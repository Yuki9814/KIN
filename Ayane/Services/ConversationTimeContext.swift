import Foundation

/// A value-only event used to derive the temporal context for a chat prompt.
/// SwiftData model objects stay outside this type so it can be shared by iOS,
/// macOS, and unit tests without a persistence dependency.
struct ConversationTimeMessage: Equatable, Hashable, Sendable {
    let occurredAt: Date
    let role: EventRole
    let deliveryState: EventDeliveryState

    init(
        occurredAt: Date,
        role: EventRole = .user,
        deliveryState: EventDeliveryState = .complete
    ) {
        self.occurredAt = occurredAt
        self.role = role
        self.deliveryState = deliveryState
    }
}

/// Compatibility spelling for callers that model the input as an event.
typealias ConversationTimeEvent = ConversationTimeMessage

/// The only interval labels emitted to the prompt.
enum ConversationTimeGap: String, Codable, CaseIterable, Sendable {
    case lessThanOneHour = "<1h"
    case oneToTwentyFourHours = "1-24h"
    case oneToThreeDays = "1-3d"
    case threeToFiveDays = "3-5d"
    case fiveToTenDays = "5-10d"
    case tenDaysPlus = "10d+"

    var label: String { rawValue }
}

/// Current local date/time plus the gap from the latest valid user turn.
///
/// Only a `.user` event in `.complete` state is eligible. Failed, cancelled,
/// streaming, and undelivered events are deliberately ignored.
struct ConversationTimeContext: Equatable, Sendable {
    let now: Date
    let timeZoneIdentifier: String
    let localDateText: String
    let localTimeText: String
    /// Timestamp of the user event currently being answered. It can be older
    /// than `now` when a suspended or retried generation resumes later.
    let currentTurnOccurredAt: Date
    let currentTurnLocalDateText: String
    let currentLocalDayStart: Date
    let lastValidUserMessageAt: Date?
    let intervalSinceLastValidUserMessage: TimeInterval?
    let localCalendarDayDistance: Int?
    let crossesLocalCalendarDay: Bool
    let gap: ConversationTimeGap
    let promptLine: String
    let turnBoundaryInstruction: String

    /// Whether a valid previous user event was found. The `gap` is still
    /// conservative (`10d+`) when no such event exists, while this flag keeps
    /// that distinction available to a caller that wants to explain it.
    var hasLastValidUserMessage: Bool { lastValidUserMessageAt != nil }

    /// Short aliases used by prompt assembly code.
    var systemPrompt: String { promptLine }
    var intervalLabel: String { gap.rawValue }
    var timeZone: String { timeZoneIdentifier }

    init(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        messages: [ConversationTimeMessage] = [],
        currentTurnOccurredAt: Date? = nil
    ) {
        self.now = now
        self.timeZoneIdentifier = timeZone.identifier
        let resolvedTurnOccurredAt = currentTurnOccurredAt ?? now
        self.currentTurnOccurredAt = resolvedTurnOccurredAt

        let dateFormatter = Self.makeFormatter(timeZone: timeZone)
        dateFormatter.dateFormat = "yyyy年M月d日"
        let timeFormatter = Self.makeFormatter(timeZone: timeZone)
        timeFormatter.dateFormat = "HH:mm:ss"
        self.localDateText = dateFormatter.string(from: now)
        self.localTimeText = timeFormatter.string(from: now)
        self.currentTurnLocalDateText = dateFormatter.string(from: resolvedTurnOccurredAt)
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = timeZone
        self.currentLocalDayStart = localCalendar.startOfDay(for: resolvedTurnOccurredAt)

        let lastValid = messages
            .filter {
                $0.role == .user
                    && $0.deliveryState == .complete
                    && $0.occurredAt <= resolvedTurnOccurredAt
            }
            .max { lhs, rhs in lhs.occurredAt < rhs.occurredAt }?
            .occurredAt
        self.lastValidUserMessageAt = lastValid

        let interval = lastValid.map { max(0, resolvedTurnOccurredAt.timeIntervalSince($0)) }
        self.intervalSinceLastValidUserMessage = interval
        let dayDistance = lastValid.map {
            Self.calendarDayDistance(from: $0, to: resolvedTurnOccurredAt, timeZone: timeZone)
        }
        self.localCalendarDayDistance = dayDistance
        self.crossesLocalCalendarDay = (dayDistance ?? 0) > 0
        let gap = Self.classify(interval)
        self.gap = gap

        let timeZoneOffset = Self.offsetText(for: timeZone, at: now)
        let previousText: String
        if let lastValid {
            previousText = "上一次已成功发送的用户消息发生于 \(Self.localDateTimeText(for: lastValid, timeZone: timeZone))（\(Self.relativeTimeText(from: lastValid, to: resolvedTurnOccurredAt, timeZone: timeZone))；间隔分类 \(gap.rawValue)）"
        } else {
            previousText = "暂无上次有效消息，这是首次有效对话"
        }
        self.promptLine = "时间上下文：当前日期 \(localDateText)，时间 \(localTimeText)，时区 \(timeZoneIdentifier)（\(timeZoneOffset)）；\(previousText)。"
        if let dayDistance, dayDistance > 0 {
            self.turnBoundaryInstruction = "跨日轮次边界：当前输入与上一条有效用户消息之间已经跨过 \(dayDistance) 个本地自然日，因此当前输入是一个新的会话阶段。除非当前用户消息明确要求‘继续’、明确引用旧内容或重新点名旧话题，否则严禁续写上一日的回答、句子、清单或未完思路。即使当前消息只有‘？’、‘嗯’、‘在吗’等短内容，也不得凭相邻历史自动承接昨天；应只回应当前消息，必要时简短询问用户现在想表达什么。昨天及更早的消息和摘要只能作为历史背景。"
        } else {
            self.turnBoundaryInstruction = ""
        }
    }

    /// High-salience metadata placed immediately before the current user body.
    /// This counteracts a model's adjacency bias after a local calendar-day
    /// change without mutating the persisted event.
    var currentTurnBoundaryMetadataLine: String? {
        guard crossesLocalCalendarDay else { return nil }
        return "【跨日新轮次：这是 \(currentTurnLocalDateText) 的新输入。除非本条明确要求继续或引用旧话题，否则不要续写上一日回答；‘？’等短消息不得自动承接昨天内容。】"
    }

    /// Metadata prepended to a recent provider message. The stored event body is
    /// never mutated; this line exists only at the prompt boundary.
    func messageTimestampLine(for occurredAt: Date) -> String {
        let resolvedTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return "【本地消息时间：\(Self.localDateTimeText(for: occurredAt, timeZone: resolvedTimeZone))；\(Self.relativeTimeText(from: occurredAt, to: now, timeZone: resolvedTimeZone))】"
    }

    /// Factory spelling that reads naturally at call sites.
    static func make(
        now: Date = Date(),
        timeZone: TimeZone = .current,
        messages: [ConversationTimeMessage] = [],
        currentTurnOccurredAt: Date? = nil
    ) -> Self {
        Self(
            now: now,
            timeZone: timeZone,
            messages: messages,
            currentTurnOccurredAt: currentTurnOccurredAt
        )
    }

    static func classify(_ interval: TimeInterval?) -> ConversationTimeGap {
        guard let interval else { return .tenDaysPlus }
        let seconds = max(0, interval)
        switch seconds {
        case ..<3_600:
            return .lessThanOneHour
        case ..<86_400:
            return .oneToTwentyFourHours
        case ..<259_200:
            return .oneToThreeDays
        case ..<432_000:
            return .threeToFiveDays
        case ..<864_000:
            return .fiveToTenDays
        default:
            return .tenDaysPlus
        }
    }

    private static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        return formatter
    }

    private static func localDateTimeText(for date: Date, timeZone: TimeZone) -> String {
        let formatter = makeFormatter(timeZone: timeZone)
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func relativeTimeText(
        from occurredAt: Date,
        to now: Date,
        timeZone: TimeZone
    ) -> String {
        let signedInterval = now.timeIntervalSince(occurredAt)
        guard signedInterval.isFinite else { return "时间间隔异常" }
        if signedInterval < -1 {
            return "时间异常：晚于当前时间"
        }

        let interval = max(0, signedInterval)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let occurredDay = calendar.startOfDay(for: occurredAt)
        let currentDay = calendar.startOfDay(for: now)
        let dayDistance = max(
            0,
            calendar.dateComponents([.day], from: occurredDay, to: currentDay).day ?? 0
        )
        let calendarText: String
        switch dayDistance {
        case 0:
            calendarText = "今天"
        case 1:
            calendarText = "昨天"
        default:
            calendarText = "\(dayDistance)天前"
        }
        if interval < 60 {
            return "\(calendarText)，距当前不足1分钟"
        }
        return "\(calendarText)，距当前约\(elapsedText(interval))"
    }

    private static func calendarDayDistance(
        from occurredAt: Date,
        to now: Date,
        timeZone: TimeZone
    ) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let occurredDay = calendar.startOfDay(for: occurredAt)
        let currentDay = calendar.startOfDay(for: now)
        return max(
            0,
            calendar.dateComponents([.day], from: occurredDay, to: currentDay).day ?? 0
        )
    }

    private static func elapsedText(_ interval: TimeInterval) -> String {
        guard interval < Double(Int.max / 120) * 60 else {
            return "很久以前"
        }
        let totalMinutes = Int(max(0, interval) / 60)
        if totalMinutes < 1 { return "不足1分钟" }
        if totalMinutes < 60 { return "\(totalMinutes)分钟" }

        let totalHours = totalMinutes / 60
        let remainingMinutes = totalMinutes % 60
        if totalHours < 24 {
            return remainingMinutes == 0
                ? "\(totalHours)小时"
                : "\(totalHours)小时\(remainingMinutes)分钟"
        }

        let days = totalHours / 24
        let remainingHours = totalHours % 24
        return remainingHours == 0
            ? "\(days)天"
            : "\(days)天\(remainingHours)小时"
    }

    private static func offsetText(for timeZone: TimeZone, at date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let absolute = abs(seconds)
        return String(format: "UTC%@%02d:%02d", sign, absolute / 3_600, (absolute % 3_600) / 60)
    }
}
