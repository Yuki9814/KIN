import Foundation

/// A narrow, deterministic bridge from a chat instruction to the existing
/// durable Moments scheduler and local Moments actions. It recognizes only
/// explicit imperative requests; ordinary discussion about Moments must never
/// create side effects.
struct LocalMomentCommand: Equatable, Sendable {
    let instruction: String
    let scheduledAt: Date

    func confirmationText(now: Date, calendar: Calendar) -> String {
        if scheduledAt.timeIntervalSince(now) <= 2 {
            return "已创建朋友圈任务，将立即发布。"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(scheduledAt, inSameDayAs: now)
            ? "HH:mm"
            : "M月d日 HH:mm"
        return "已创建朋友圈任务，将在\(formatter.string(from: scheduledAt))发布。"
    }
}

enum LocalMomentDeletionTarget: Equatable, Sendable {
    case latest
    case content(String)
    case unspecified
}

struct LocalMomentDeletionCommand: Equatable, Sendable {
    typealias Target = LocalMomentDeletionTarget

    let target: LocalMomentDeletionTarget
}

enum LocalMomentCommandParser {
    static func parse(
        _ rawText: String,
        now: Date = Date(),
        calendar sourceCalendar: Calendar = .autoupdatingCurrent
    ) -> LocalMomentCommand? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              isExplicitPublishRequest(text),
              !isNegatedOrInformational(text) else {
            return nil
        }

        var calendar = sourceCalendar
        if calendar.timeZone.identifier.isEmpty {
            calendar.timeZone = .autoupdatingCurrent
        }
        // Only timing words before the publish object are scheduling syntax.
        // Content such as “写写今天吹到的风” must publish immediately rather
        // than being mistaken for “今天 09:00”.
        let schedulingText: String
        if let momentRange = text.range(of: "朋友圈") {
            schedulingText = String(text[..<momentRange.lowerBound])
        } else {
            schedulingText = text
        }
        let scheduledAt = resolvedDate(in: schedulingText, now: now, calendar: calendar)
        return LocalMomentCommand(
            instruction: String(text.prefix(2_000)),
            scheduledAt: max(now, scheduledAt)
        )
    }

    static func parseDeletion(_ rawText: String) -> LocalMomentDeletionCommand? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isDeletionNegatedOrInformational(text),
              isExplicitDeletionRequest(text) else {
            return nil
        }

        if let quotedTarget = quotedDeletionTarget(in: text) {
            return LocalMomentDeletionCommand(target: .content(quotedTarget))
        }
        if let describedTarget = describedDeletionTarget(in: text) {
            return LocalMomentDeletionCommand(target: .content(describedTarget))
        }
        return LocalMomentDeletionCommand(
            target: isLatestDeletionTarget(in: text) ? .latest : .unspecified
        )
    }

    private static func isExplicitPublishRequest(_ text: String) -> Bool {
        let timePrefix = #"(?:(?:现在|马上|立刻|待会儿?|一会儿|过会儿|今天|今晚|今早|明天|明早|明晚|后天|早上|上午|中午|下午|晚上|凌晨|傍晚)|(?:[0-9一二两三四五六七八九十百半]+\s*(?:分钟|小时)后)|(?:[0-2]?[0-9]\s*[:：]\s*[0-5]?[0-9])|(?:[0-9一二两三四五六七八九十]{1,3}\s*(?:点|时)(?:\s*(?:[0-9一二两三四五六七八九十]{1,3}\s*分?|半))?))"#
        let lead = #"^(?:请|麻烦)?\s*(?:你|绫音)?\s*(?:在\s*)?(?:"#
            + timePrefix
            + #"\s*)*(?:你|绫音)?\s*(?:(?:去|来|帮我|替我|给我|记得|安排)\s*){0,2}"#
        return firstMatch(
            lead + #"(?:发|发布|更新|晒)(?:\s|一下|一个|一条|个|条|一篇)*朋友圈"#,
            in: text
        ) != nil
            || firstMatch(
                lead + #"朋友圈\s*(?:发|发布|更新)(?:一下|一个|一条|个|条)?"#,
                in: text
            ) != nil
    }

    private static func isExplicitDeletionRequest(_ text: String) -> Bool {
        let moment = #"(?:朋友圈|动态)"#
        let deletion = #"(?:删除|删掉|移除|删)"#
        let leadingVerb = #"^(?:(?:请|麻烦|我要求你|我想让你|我希望你|我准备让你|我打算让你))?\s*(?:(?:你|绫音)\s*)?(?:(?:帮我|替我|给我|把|将)\s*)*"#
            + deletion
            + #"(?:一下)?[\s\S]{0,100}"#
            + moment
            + #"(?:[。！!？?])?$"#
        let trailingVerb = #"^(?:(?:请|麻烦|我要求你|我想让你|我希望你|我准备让你|我打算让你))?\s*(?:(?:帮我|替我|给我)\s*)?(?:(?:你|绫音)\s*)?(?:把|将)\s*[\s\S]{1,100}"#
            + moment
            + #"(?:一下)?"#
            + deletion
            + #"(?:吧|一下)?[。！!？?]?$"#
        return firstMatch(leadingVerb, in: text) != nil
            || firstMatch(trailingVerb, in: text) != nil
    }

    private static func isDeletionNegatedOrInformational(_ text: String) -> Bool {
        let patterns = [
            #"(?:我(?:刚刚?|之前|昨天|今天)?(?:发|发布|更新|晒)(?:的)?|我的)(?:朋友圈|动态)"#,
            #"^(?:别|不要|不用|不必|禁止|不准).{0,30}(?:删除|删掉|移除|删)"#,
            #"^(?:怎么|如何|能不能|可不可以|可以不可以|是否).{0,30}(?:删除|删掉|移除|删)"#,
            #"^(?:如果|假如|要是|除非).{0,30}(?:删除|删掉|移除|删)"#,
            #"^(?:你|绫音).{0,12}(?:删除|删掉|移除|删)(?:过|了|[吗么嘛？?])"#,
            #"^(?:我|本人).{0,12}(?:已经|刚刚?|之前|早就|已).{0,12}(?:删除|删掉|移除|删)"#,
            #"^(?:我|本人).{0,12}(?:删除|删掉|移除|删)(?:过|了|[吗么嘛？?])"#,
            #"^(?:我想|我希望|我准备|我打算)(?!让你|要你|你).{0,20}(?:删除|删掉|移除|删)"#
        ]
        return patterns.contains { firstMatch($0, in: text) != nil }
    }

    private static func isLatestDeletionTarget(in text: String) -> Bool {
        firstMatch(
            #"(?:刚才|刚刚|方才|最新|最近)(?:发(?:布)?的?)?|(?:上一|上一个|上一条|最后一条)"#,
            in: text
        ) != nil
    }

    private static func quotedDeletionTarget(in text: String) -> String? {
        let quotePairs: [(Character, Character)] = [
            ("“", "”"),
            ("‘", "’"),
            ("\"", "\""),
            ("'", "'")
        ]
        for (opening, closing) in quotePairs {
            guard let start = text.firstIndex(of: opening),
                  let contentStart = text.index(start, offsetBy: 1, limitedBy: text.endIndex),
                  let end = text[contentStart...].firstIndex(of: closing),
                  end > contentStart else {
                continue
            }
            let value = text[contentStart..<end]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func describedDeletionTarget(in text: String) -> String? {
        let patterns = [
            #"关于(.{1,80}?)(?:的)?(?:朋友圈|动态)"#,
            #"(?:写着|提到|说到|包含|含有)(.{1,80}?)(?:的)?(?:朋友圈|动态)"#
        ]
        for pattern in patterns {
            guard let match = firstMatch(pattern, in: text, captureCount: 1),
                  let value = match.first else {
                continue
            }
            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines.union(.punctuationCharacters)
            )
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func isNegatedOrInformational(_ text: String) -> Bool {
        let negativePatterns = [
            #"(?:不要|别|不用|不必|禁止|不准).{0,8}(?:发|发布|更新|晒).{0,4}朋友圈"#,
            #"(?:不想|不希望|没想过).{0,12}(?:发|发布|更新|晒).{0,4}朋友圈"#,
            #"取消.{0,8}朋友圈"#,
            #"(?:如果|假如|要是|除非).{0,16}(?:发|发布|更新|晒).{0,4}朋友圈"#,
            #"(?:关于|讨论|聊聊|解释).{0,10}(?:发|发布|更新|晒).{0,4}朋友圈"#,
            #"(?:怎么|如何).{0,8}(?:发|发布|更新).{0,4}朋友圈"#,
            #"为什么.{0,12}(?:发|发布|更新).{0,4}朋友圈"#,
            #"(?:会不会|会).{0,6}(?:发|发布).{0,4}朋友圈[吗么嘛？?]"#,
            #"(?:我|他|她).{0,4}(?:刚刚?|已经|昨天|前天|上次).{0,5}(?:发|发布|更新|晒).{0,4}朋友圈"#,
            #"(?:我|他|她).{0,3}(?:发|发布|更新|晒)(?:了|过).{0,4}朋友圈"#,
            #"(?:我|他|她).{0,6}(?:发|发布|更新|晒).{0,4}朋友圈(?:了|过)?[吗么嘛？?]"#,
            #"朋友圈.{0,4}(?:发|发布|更新)(?:过|完|好)?了"#,
            #"朋友圈.{0,4}(?:发|发布|更新).{0,3}(?:了吗|过吗|没有|没)[？?]?"#,
            #"(?:发|发布|更新|晒).{0,4}朋友圈.{0,8}(?:了吗|过吗|没有|吗|么|嘛)[？?]?$"#
        ]
        return negativePatterns.contains { firstMatch($0, in: text) != nil }
    }

    private static func resolvedDate(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> Date {
        if let relative = relativeDelay(in: text) {
            return now.addingTimeInterval(relative)
        }
        if text.contains("待会") || text.contains("一会儿") || text.contains("过会儿") {
            return now.addingTimeInterval(10 * 60)
        }
        if text.contains("马上") || text.contains("现在") || text.contains("立刻") {
            return now
        }

        let dayOffset: Int?
        if text.contains("后天") {
            dayOffset = 2
        } else if text.contains("明天") || text.contains("明早") || text.contains("明晚") {
            dayOffset = 1
        } else if text.contains("今天") || text.contains("今晚") || text.contains("今早") {
            dayOffset = 0
        } else {
            dayOffset = nil
        }

        if let clock = clockTime(in: text) {
            let offset = dayOffset ?? 0
            let base = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            var components = calendar.dateComponents([.year, .month, .day], from: base)
            components.hour = adjustedHour(clock.hour, periodText: text)
            components.minute = clock.minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { return now }
            if candidate >= now { return candidate }
            // An explicitly named current day is overdue and should catch up
            // now. A bare clock time means the next occurrence of that time.
            if dayOffset == 0 { return now }
            if dayOffset == nil {
                return calendar.date(byAdding: .day, value: 1, to: candidate) ?? now
            }
            return now
        }

        guard let dayOffset else { return now }
        let base = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        if text.contains("凌晨") {
            components.hour = 1
        } else if text.contains("早上") || text.contains("上午") || text.contains("明早") {
            components.hour = 9
        } else if text.contains("中午") {
            components.hour = 12
        } else if text.contains("下午") {
            components.hour = 15
        } else if text.contains("晚上") || text.contains("今晚") || text.contains("明晚") {
            components.hour = 20
        } else {
            components.hour = 9
        }
        components.minute = 0
        components.second = 0
        return calendar.date(from: components).map { max(now, $0) } ?? now
    }

    private static func relativeDelay(in text: String) -> TimeInterval? {
        guard let match = firstMatch(
            #"([0-9一二两三四五六七八九十百半]+)\s*(分钟|小时)后"#,
            in: text,
            captureCount: 2
        ), match.count == 2,
        let value = chineseNumber(match[0]) else {
            return nil
        }
        let seconds = match[1] == "小时" ? value * 60 * 60 : value * 60
        return TimeInterval(seconds)
    }

    private static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        if let match = firstMatch(
            #"([0-2]?[0-9])\s*[:：]\s*([0-5]?[0-9])"#,
            in: text,
            captureCount: 2
        ), match.count == 2,
        let hour = Int(match[0]), let minute = Int(match[1]), hour < 24, minute < 60 {
            return (hour, minute)
        }

        guard let match = firstMatch(
            #"([0-9一二两三四五六七八九十两]{1,3})\s*(?:点|时)(?:\s*([0-9一二两三四五六七八九十两]{1,3})\s*分?|\s*(半))?"#,
            in: text,
            captureCount: 3
        ), !match.isEmpty,
        let hourValue = chineseNumber(match[0]), hourValue >= 0, hourValue < 24 else {
            return nil
        }
        let minute: Int
        if match.indices.contains(2), match[2] == "半" {
            minute = 30
        } else if match.indices.contains(1), !match[1].isEmpty {
            minute = Int(chineseNumber(match[1]) ?? 0)
        } else {
            minute = 0
        }
        guard minute < 60 else { return nil }
        return (Int(hourValue), minute)
    }

    private static func adjustedHour(_ rawHour: Int, periodText: String) -> Int {
        var hour = rawHour
        if periodText.contains("凌晨") {
            if hour == 12 { hour = 0 }
        } else if periodText.contains("下午")
                    || periodText.contains("晚上")
                    || periodText.contains("今晚")
                    || periodText.contains("明晚")
                    || periodText.contains("傍晚") {
            if hour < 12 { hour += 12 }
        } else if periodText.contains("中午"), hour < 11 {
            hour += 12
        }
        return min(23, max(0, hour))
    }

    private static func chineseNumber(_ text: String) -> Double? {
        if text == "半" { return 0.5 }
        if let value = Double(text) { return value }
        let values: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if text == "十" { return 10 }
        if text == "百" { return 100 }
        var total = 0
        var current = 0
        for character in text {
            if let digit = values[character] {
                current = digit
            } else if character == "十" {
                total += max(1, current) * 10
                current = 0
            } else if character == "百" {
                total += max(1, current) * 100
                current = 0
            } else {
                return nil
            }
        }
        return Double(total + current)
    }

    private static func firstMatch(
        _ pattern: String,
        in text: String,
        captureCount: Int = 0
    ) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..<text.endIndex, in: text)
              ) else {
            return nil
        }
        if captureCount == 0 { return [] }
        return (1...captureCount).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let swiftRange = Range(range, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }
}
