import Foundation

/// The supported wall-clock recurrence frequencies for a Moments task.
enum MomentTaskRecurrenceFrequency: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case once
    case hourly
    case daily
    case weekly
    case monthly

    var title: String {
        switch self {
        case .once: "仅一次"
        case .hourly: "每小时"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        }
    }

    var chineseTitle: String { title }

    var isRecurring: Bool { self != .once }
}

/// A value-only recurrence rule. Calendar math is deliberately performed in
/// the persisted IANA time zone instead of by adding a fixed number of
/// seconds; this keeps daily/weekly/monthly schedules correct across DST.
struct MomentTaskRecurrenceRule: Codable, Equatable, Hashable, Sendable {
    let frequency: MomentTaskRecurrenceFrequency
    let interval: Int
    let weekday: Int?
    let dayOfMonth: Int?
    let hour: Int
    let minute: Int
    let timezoneIdentifier: String
    let anchorDate: Date
    let seriesID: UUID?

    init(
        frequency: MomentTaskRecurrenceFrequency,
        interval: Int = 1,
        weekday: Int? = nil,
        dayOfMonth: Int? = nil,
        hour: Int = 0,
        minute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        scheduledAt: Date = Date(),
        seriesID: UUID? = nil
    ) {
        self.frequency = frequency
        self.interval = interval
        self.weekday = weekday
        self.dayOfMonth = dayOfMonth
        self.hour = hour
        self.minute = minute
        self.timezoneIdentifier = timezoneIdentifier
        self.anchorDate = scheduledAt
        self.seriesID = seriesID
    }

    /// Alternate spelling for callers which treat the first scheduled date as
    /// an anchor rather than as the task's `scheduledAt` field.
    init(
        frequency: MomentTaskRecurrenceFrequency,
        interval: Int = 1,
        weekday: Int? = nil,
        dayOfMonth: Int? = nil,
        hour: Int = 0,
        minute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        anchorDate: Date,
        seriesID: UUID? = nil
    ) {
        self.init(
            frequency: frequency,
            interval: interval,
            weekday: weekday,
            dayOfMonth: dayOfMonth,
            hour: hour,
            minute: minute,
            timezoneIdentifier: timezoneIdentifier,
            scheduledAt: anchorDate,
            seriesID: seriesID
        )
    }

    init(
        recurrenceRaw: String,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        scheduledAt: Date = Date(),
        seriesID: UUID? = nil
    ) {
        self.init(
            frequency: MomentTaskRecurrenceFrequency(rawValue: recurrenceRaw) ?? .once,
            interval: recurrenceInterval,
            weekday: recurrenceWeekday,
            dayOfMonth: recurrenceDayOfMonth,
            hour: recurrenceHour,
            minute: recurrenceMinute,
            timezoneIdentifier: timezoneIdentifier,
            scheduledAt: scheduledAt,
            seriesID: seriesID
        )
    }

    init(_ task: CompanionMomentTaskRecord) {
        self.init(
            recurrenceRaw: task.recurrenceRaw,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceWeekday: task.recurrenceWeekday,
            recurrenceDayOfMonth: task.recurrenceDayOfMonth,
            recurrenceHour: task.recurrenceHour,
            recurrenceMinute: task.recurrenceMinute,
            timezoneIdentifier: task.timezoneIdentifier,
            scheduledAt: task.scheduledAt,
            seriesID: task.seriesID
        )
    }

    init(task: CompanionMomentTaskRecord) {
        self.init(task)
    }

    static func from(task: CompanionMomentTaskRecord) -> Self { Self(task) }

    var recurrenceRaw: String { frequency.rawValue }
    var recurrenceInterval: Int { interval }
    var recurrenceWeekday: Int? { weekday }
    var recurrenceDayOfMonth: Int? { dayOfMonth }
    var recurrenceHour: Int { hour }
    var recurrenceMinute: Int { minute }
    var scheduledAt: Date { anchorDate }
    var title: String { frequency.title }
    var chineseTitle: String { frequency.title }

    /// Whether all scalar values can safely be used to schedule a task.
    var isValid: Bool {
        guard interval >= 1,
              (0...23).contains(hour),
              (0...59).contains(minute),
              !timezoneIdentifier.isEmpty,
              TimeZone(identifier: timezoneIdentifier) != nil else {
            return false
        }
        if let weekday, !(1...7).contains(weekday) { return false }
        if let dayOfMonth, !(1...31).contains(dayOfMonth) { return false }
        switch frequency {
        case .weekly:
            return weekday.map { (1...7).contains($0) } ?? false
        case .monthly:
            return dayOfMonth.map { (1...31).contains($0) } ?? false
        case .once, .hourly, .daily:
            return true
        }
    }

    /// A stable local-time key for deduplicating one occurrence. It uses local
    /// components rather than a formatted absolute date, so two devices with
    /// the same IANA zone converge on the same key across DST transitions.
    var occurrenceKey: String { occurrenceKey(for: anchorDate) }

    func occurrenceKey(for occurrence: Date) -> String {
        let calendar = makeCalendar()
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: occurrence
        )
        let local = String(
            format: "%04d-%02d-%02dT%02d:%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
        let series = seriesID?.uuidString.lowercased()
        return [series, local, timezoneIdentifier].compactMap { $0 }.joined(separator: "|")
    }

    func stableOccurrenceKey(for occurrence: Date) -> String {
        occurrenceKey(for: occurrence)
    }

    /// Returns the first occurrence strictly after `date`. One-shot tasks have
    /// no successor by definition.
    func nextOccurrence(after date: Date) -> Date? {
        guard frequency != .once, isValid, let first = firstOccurrence() else {
            return nil
        }

        var candidate = first
        var iterations = 0
        while candidate <= date {
            guard let next = nextCandidate(after: candidate), next > candidate else {
                return nil
            }
            candidate = next
            iterations += 1
            // A corrupt or extreme interval must never create an unbounded
            // loop in a scheduler or import validator.
            if iterations > 100_000 { return nil }
        }
        return candidate
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .gmt
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    private func firstOccurrence() -> Date? {
        let calendar = makeCalendar()
        switch frequency {
        case .once:
            return nil
        case .hourly, .daily:
            return dateAtWallClock(
                calendar: calendar,
                date: anchorDate,
                hour: hour,
                minute: minute
            )
        case .weekly:
            guard let weekday else { return nil }
            let currentWeekday = calendar.component(.weekday, from: anchorDate)
            let offset = (weekday - currentWeekday + 7) % 7
            guard let day = calendar.date(byAdding: .day, value: offset, to: anchorDate) else {
                return nil
            }
            return dateAtWallClock(calendar: calendar, date: day, hour: hour, minute: minute)
        case .monthly:
            guard let dayOfMonth else { return nil }
            let components = calendar.dateComponents([.year, .month], from: anchorDate)
            return dateAtWallClock(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: dayOfMonth,
                hour: hour,
                minute: minute
            )
        }
    }

    private func nextCandidate(after date: Date) -> Date? {
        let calendar = makeCalendar()
        switch frequency {
        case .hourly:
            return calendar.date(byAdding: .hour, value: interval, to: date)
        case .daily:
            guard let nextDay = calendar.date(byAdding: .day, value: interval, to: date) else {
                return nil
            }
            return dateAtWallClock(calendar: calendar, date: nextDay, hour: hour, minute: minute)
        case .weekly:
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: interval, to: date) else {
                return nil
            }
            return dateAtWallClock(calendar: calendar, date: nextWeek, hour: hour, minute: minute)
        case .monthly:
            guard let dayOfMonth else { return nil }
            let currentComponents = calendar.dateComponents([.year, .month], from: date)
            guard let currentMonthStart = calendar.date(
                    from: DateComponents(
                    year: currentComponents.year,
                    month: currentComponents.month,
                    day: 1
                    )
                  ),
                  let nextMonth = calendar.date(
                      byAdding: .month,
                      value: interval,
                      to: currentMonthStart
                  ) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month], from: nextMonth)
            return dateAtWallClock(
                calendar: calendar,
                year: components.year,
                month: components.month,
                day: dayOfMonth,
                hour: hour,
                minute: minute
            )
        case .once:
            return nil
        }
    }

    private func dateAtWallClock(
        calendar: Calendar,
        date: Date,
        hour: Int,
        minute: Int
    ) -> Date? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return dateAtWallClock(
            calendar: calendar,
            year: components.year,
            month: components.month,
            day: components.day,
            hour: hour,
            minute: minute
        )
    }

    private func dateAtWallClock(
        calendar: Calendar,
        year: Int?,
        month: Int?,
        day: Int?,
        hour: Int,
        minute: Int
    ) -> Date? {
        guard let year, let month, let day else { return nil }
        let dayComponents = DateComponents(year: year, month: month, day: day)
        guard let dayDate = calendar.date(from: dayComponents),
              let searchStart = calendar.date(byAdding: .day, value: -1, to: dayDate) else {
            return nil
        }

        // Preserve the requested minute when a spring-forward gap removes the
        // requested hour (02:30 becomes 03:30), and choose the first copy of a
        // repeated fall-back wall time.
        return calendar.nextDate(
            after: searchStart,
            matching: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: 0
            ),
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func dateAtWallClock(
        calendar: Calendar,
        year: Int?,
        month: Int?,
        day requestedDay: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        guard let year, let month else { return nil }
        let firstOfMonth = DateComponents(year: year, month: month, day: 1)
        guard let monthDate = calendar.date(from: firstOfMonth),
              let range = calendar.range(of: .day, in: .month, for: monthDate) else {
            return nil
        }
        let day = min(max(requestedDay, 1), range.count)
        return dateAtWallClock(
            calendar: calendar,
            year: year,
            month: month,
            day: Optional(day),
            hour: hour,
            minute: minute
        )
    }
}
