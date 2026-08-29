import Foundation

/// A month and day that can be used as a recurring birthday.
///
/// The value is validated against a leap year so that February 29 remains a
/// valid birthday even though it does not occur in every Gregorian year.
struct BirthdayMonthDay: Codable, Hashable, Sendable {
    let month: Int
    let day: Int

    init?(month: Int, day: Int) {
        guard Self.isValid(month: month, day: day) else { return nil }
        self.month = month
        self.day = day
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let month = try values.decode(Int.self, forKey: .month)
        let day = try values.decode(Int.self, forKey: .day)
        guard let value = Self(month: month, day: day) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: values,
                debugDescription: "Invalid Gregorian birthday month/day"
            )
        }
        self = value
    }

    private enum CodingKeys: String, CodingKey {
        case month
        case day
    }

    /// Returns whether the month/day is valid in at least one Gregorian year.
    /// The year 2000 is used because it is a leap year, allowing 02-29.
    static func isValid(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day > 0 else { return false }
        let daysInMonth = [
            31, 29, 31, 30, 31, 30,
            31, 31, 30, 31, 30, 31
        ]
        return day <= daysInMonth[month - 1]
    }

    /// Compatibility spelling for callers that use a property-like verb.
    var isValid: Bool { Self.isValid(month: month, day: day) }

    var monthDayString: String {
        "\(twoDigit(month))-\(twoDigit(day))"
    }

    private func twoDigit(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}

/// The two recurring birthday automations owned by a role.
enum BirthdayAutomationKind: String, Codable, CaseIterable, Hashable, Sendable {
    case userBirthdayGreeting
    case roleBirthdayCheckIn
}

/// The minimal event evidence needed to decide whether a role birthday
/// check-in has already been answered by the user.
///
/// This value type intentionally has no SwiftData or SwiftUI dependency.  A
/// caller can map its persisted conversation event into this shape before
/// asking the policy for a cancellation decision.
struct BirthdayAutomationEvent: Codable, Equatable, Hashable, Sendable {
    let roleID: UUID
    let conversationID: UUID
    let occurredAt: Date
    let isUser: Bool
    let isComplete: Bool
    let isRetracted: Bool
    let isGroup: Bool

    init(
        roleID: UUID,
        conversationID: UUID,
        occurredAt: Date,
        isUser: Bool,
        isComplete: Bool = true,
        isRetracted: Bool = false,
        isGroup: Bool = false
    ) {
        self.roleID = roleID
        self.conversationID = conversationID
        self.occurredAt = occurredAt
        self.isUser = isUser
        self.isComplete = isComplete
        self.isRetracted = isRetracted
        self.isGroup = isGroup
    }
}

/// A scheduled birthday occurrence and its idempotency key.
struct BirthdayAutomationOccurrence: Codable, Equatable, Hashable, Sendable {
    let kind: BirthdayAutomationKind
    let roleID: UUID
    let birthday: BirthdayMonthDay
    let localYear: Int
    let scheduledAt: Date
    let occurrenceKey: String

    var date: Date { scheduledAt }
    var scheduledDate: Date { scheduledAt }
    var key: String { occurrenceKey }
    var year: Int { localYear }
    var monthDay: BirthdayMonthDay { birthday }
}

/// Deterministic local-calendar rules for birthday automations.
///
/// Only `timeZoneIdentifier` is persisted.  `calendar` is reconstructed as a
/// Gregorian calendar from that IANA identifier on every value boundary, so
/// devices agree on the local birthday even when their system time zones
/// differ.
struct BirthdayAutomationPolicy: Codable, Equatable, Hashable, Sendable {
    typealias Event = BirthdayAutomationEvent
    typealias Occurrence = BirthdayAutomationOccurrence

    static let defaultGreetingHour = 9
    static let defaultGreetingMinute = 0
    static let roleCheckInHours = [0, 1, 2]
    static let fallbackTimeZoneIdentifier = "UTC"

    let timeZoneIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case timeZoneIdentifier
    }

    init(timeZoneIdentifier: String = TimeZone.current.identifier) {
        // TimeZone(identifier:) is the Foundation boundary for an IANA time
        // zone.  A bad imported value fails closed to UTC while preserving a
        // usable, deterministic policy instead of silently using device time.
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier
            ?? Self.fallbackTimeZoneIdentifier
    }

    init(timeZone: TimeZone) {
        self.init(timeZoneIdentifier: timeZone.identifier)
    }

    init(calendar: Calendar) {
        self.init(timeZoneIdentifier: calendar.timeZone.identifier)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(timeZoneIdentifier: try values.decode(String.self, forKey: .timeZoneIdentifier))
    }

    /// The persisted IANA identifier under a shorter name for integration
    /// boundaries that call it a time-zone ID.
    var timeZoneID: String { timeZoneIdentifier }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
    }

    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = timeZone
        result.locale = Locale(identifier: "en_US_POSIX")
        return result
    }

    /// Returns the greeting occurrence in a specific Gregorian local year.
    /// The default is the local birthday at 09:00.
    func userBirthdayGreetingOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        localYear: Int,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        occurrence(
            kind: .userBirthdayGreeting,
            roleID: roleID,
            birthday: birthday,
            localYear: localYear,
            hour: hour,
            minute: minute
        )
    }

    /// A year-label compatibility spelling for `localYear`.
    func userBirthdayGreetingOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        year: Int,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday,
            localYear: year,
            hour: hour,
            minute: minute
        )
    }

    /// A year-label compatibility spelling for callers using `inYear`.
    func userBirthdayGreetingOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        inYear year: Int,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday,
            localYear: year,
            hour: hour,
            minute: minute
        )
    }

    /// A role-owned check-in is assigned one of the three quiet early-morning
    /// hours.  The assignment is deterministic for a role/year pair.
    func roleBirthdayCheckInOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        localYear: Int
    ) -> BirthdayAutomationOccurrence? {
        occurrence(
            kind: .roleBirthdayCheckIn,
            roleID: roleID,
            birthday: birthday,
            localYear: localYear,
            hour: Self.roleBirthdayCheckInHour(roleID: roleID, localYear: localYear),
            minute: 0
        )
    }

    func roleBirthdayCheckInOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        year: Int
    ) -> BirthdayAutomationOccurrence? {
        roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday,
            localYear: year
        )
    }

    func roleBirthdayCheckInOccurrence(
        roleID: UUID,
        birthday: BirthdayMonthDay,
        inYear year: Int
    ) -> BirthdayAutomationOccurrence? {
        roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday,
            localYear: year
        )
    }

    /// Builds one explicit occurrence.  `hour` and `minute` are used for a
    /// user greeting; a role check-in always uses its deterministic slot.
    func occurrence(
        kind: BirthdayAutomationKind,
        roleID: UUID,
        birthday: BirthdayMonthDay,
        localYear: Int,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        guard localYear > 0 else { return nil }
        let resolved = resolvedBirthday(birthday, in: localYear)
        let scheduledHour: Int
        let scheduledMinute: Int
        switch kind {
        case .userBirthdayGreeting:
            scheduledHour = normalizedHour(hour)
            scheduledMinute = normalizedMinute(minute)
        case .roleBirthdayCheckIn:
            scheduledHour = Self.roleBirthdayCheckInHour(
                roleID: roleID,
                localYear: localYear
            )
            scheduledMinute = 0
        }

        guard let scheduledAt = date(
            year: localYear,
            month: resolved.month,
            day: resolved.day,
            hour: scheduledHour,
            minute: scheduledMinute
        ) else {
            return nil
        }

        return BirthdayAutomationOccurrence(
            kind: kind,
            roleID: roleID,
            birthday: birthday,
            localYear: localYear,
            scheduledAt: scheduledAt,
            occurrenceKey: Self.occurrenceKey(
                kind: kind,
                roleID: roleID,
                localYear: localYear,
                birthday: birthday
            )
        )
    }

    /// Returns the first occurrence whose scheduled timestamp is at or after
    /// `date`, using that instant's local Gregorian year as the first try.
    func nextOccurrence(
        kind: BirthdayAutomationKind,
        roleID: UUID,
        birthday: BirthdayMonthDay,
        onOrAfter date: Date,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        let startingYear = calendar.component(.year, from: date)
        guard var candidate = occurrence(
            kind: kind,
            roleID: roleID,
            birthday: birthday,
            localYear: startingYear,
            hour: hour,
            minute: minute
        ) else {
            return nil
        }

        if candidate.scheduledAt < date {
            guard let next = occurrence(
                kind: kind,
                roleID: roleID,
                birthday: birthday,
                localYear: startingYear + 1,
                hour: hour,
                minute: minute
            ) else {
                return nil
            }
            candidate = next
        }
        return candidate
    }

    func nextOccurrence(
        for kind: BirthdayAutomationKind,
        roleID: UUID,
        birthday: BirthdayMonthDay,
        onOrAfter date: Date,
        hour: Int = BirthdayAutomationPolicy.defaultGreetingHour,
        minute: Int = BirthdayAutomationPolicy.defaultGreetingMinute
    ) -> BirthdayAutomationOccurrence? {
        nextOccurrence(
            kind: kind,
            roleID: roleID,
            birthday: birthday,
            onOrAfter: date,
            hour: hour,
            minute: minute
        )
    }

    /// The local civil-day interval of the birthday in a particular year.
    /// February 29 is intentionally mapped to February 28 in a non-leap year.
    func birthdayLocalDayInterval(
        for birthday: BirthdayMonthDay,
        in localYear: Int
    ) -> DateInterval? {
        guard localYear > 0 else { return nil }
        let resolved = resolvedBirthday(birthday, in: localYear)
        guard let start = localDate(
            year: localYear,
            month: resolved.month,
            day: resolved.day,
            hour: 0,
            minute: 0
        ) else {
            return nil
        }

        // Derive the next civil date from noon rather than adding 24 hours to
        // `start`, preserving a 23/25-hour day at DST transitions.
        guard let noon = localDate(
            year: localYear,
            month: resolved.month,
            day: resolved.day,
            hour: 12,
            minute: 0
        ), let nextNoon = calendar.date(byAdding: .day, value: 1, to: noon) else {
            return nil
        }
        let nextComponents = calendar.dateComponents(
            [.year, .month, .day],
            from: nextNoon
        )
        guard let nextYear = nextComponents.year,
              let nextMonth = nextComponents.month,
              let nextDay = nextComponents.day,
              let end = localDate(
                  year: nextYear,
                  month: nextMonth,
                  day: nextDay,
                  hour: 0,
                  minute: 0
              ), end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func birthdayLocalDayInterval(
        for birthday: BirthdayMonthDay,
        inYear localYear: Int
    ) -> DateInterval? {
        birthdayLocalDayInterval(for: birthday, in: localYear)
    }

    /// Returns the birthday interval only when `date` falls in that local day.
    func birthdayLocalDayInterval(
        for birthday: BirthdayMonthDay,
        containing date: Date
    ) -> DateInterval? {
        let year = calendar.component(.year, from: date)
        guard let interval = birthdayLocalDayInterval(for: birthday, in: year),
              interval.contains(date) else {
            return nil
        }
        return interval
    }

    /// Only a complete, unretracted user message in the same role's same
    /// single conversation and birthday local day cancels the check-in.
    func shouldCancelRoleCheckIn(
        roleID: UUID,
        conversationID: UUID,
        birthday: BirthdayMonthDay,
        events: [BirthdayAutomationEvent],
        now: Date = Date(),
        conversationIsGroup: Bool = false
    ) -> Bool {
        guard !conversationIsGroup,
              let interval = birthdayLocalDayInterval(for: birthday, containing: now)
        else {
            return false
        }

        return events.contains { event in
            event.roleID == roleID
                && event.conversationID == conversationID
                && !event.isGroup
                && event.isUser
                && event.isComplete
                && !event.isRetracted
                && event.occurredAt <= now
                && interval.contains(event.occurredAt)
        }
    }

    func shouldCancelRoleCheckIn(
        _ events: [BirthdayAutomationEvent],
        roleID: UUID,
        conversationID: UUID,
        birthday: BirthdayMonthDay,
        now: Date = Date(),
        conversationIsGroup: Bool = false
    ) -> Bool {
        shouldCancelRoleCheckIn(
            roleID: roleID,
            conversationID: conversationID,
            birthday: birthday,
            events: events,
            now: now,
            conversationIsGroup: conversationIsGroup
        )
    }

    /// A due occurrence may be delivered late only during its local birthday
    /// day.  The scheduled timestamp is the lower bound, so a future task is
    /// never reported as valid for immediate catch-up.
    func isOccurrenceStillValid(
        now: Date,
        scheduledAt: Date,
        kind: BirthdayAutomationKind
    ) -> Bool {
        guard now >= scheduledAt else { return false }
        let scheduledComponents = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: scheduledAt
        )
        let nowComponents = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: now
        )
        guard scheduledComponents.era == nowComponents.era,
              scheduledComponents.year == nowComponents.year,
              scheduledComponents.month == nowComponents.month,
              scheduledComponents.day == nowComponents.day else {
            return false
        }

        // Keep the kind in the contract even though both current automation
        // kinds share the same one-local-day validity window.  This switch is
        // deliberately explicit so a future kind cannot inherit a window by
        // accident.
        switch kind {
        case .roleBirthdayCheckIn, .userBirthdayGreeting:
            return true
        }
    }

    /// Birthday-aware overload useful when the caller has not retained the
    /// occurrence's local date but still has its configured birthday.
    func isOccurrenceStillValid(
        now: Date,
        scheduledAt: Date,
        kind: BirthdayAutomationKind,
        birthday: BirthdayMonthDay
    ) -> Bool {
        guard isOccurrenceStillValid(
            now: now,
            scheduledAt: scheduledAt,
            kind: kind
        ), let interval = birthdayLocalDayInterval(for: birthday, containing: now) else {
            return false
        }
        return interval.contains(scheduledAt)
    }

    /// The stable hour selected for a role/year pair.  This is FNV-1a over a
    /// canonical UUID string and decimal local year; it intentionally does
    /// not use Swift's process-randomized `HashValue`.
    static func roleBirthdayCheckInHour(roleID: UUID, localYear: Int) -> Int {
        let seed = "\(roleID.uuidString.lowercased())|\(localYear)"
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return roleCheckInHours[Int(hash % UInt64(roleCheckInHours.count))]
    }

    func roleBirthdayCheckInHour(roleID: UUID, year: Int) -> Int {
        Self.roleBirthdayCheckInHour(roleID: roleID, localYear: year)
    }

    func roleBirthdayCheckInHour(for roleID: UUID, localYear: Int) -> Int {
        Self.roleBirthdayCheckInHour(roleID: roleID, localYear: localYear)
    }

    static func occurrenceKey(
        kind: BirthdayAutomationKind,
        roleID: UUID,
        localYear: Int,
        birthday: BirthdayMonthDay
    ) -> String {
        "\(kind.rawValue)|\(roleID.uuidString.lowercased())|\(localYear)|\(birthday.monthDayString)"
    }

    private func resolvedBirthday(
        _ birthday: BirthdayMonthDay,
        in localYear: Int
    ) -> BirthdayMonthDay {
        // Policy locked by product semantics: a February 29 birthday is
        // observed on February 28 in a non-leap Gregorian year.
        if birthday.month == 2,
           birthday.day == 29,
           !isGregorianLeapYear(localYear) {
            return BirthdayMonthDay(month: 2, day: 28)!
        }
        return birthday
    }

    private func isGregorianLeapYear(_ year: Int) -> Bool {
        year.isMultiple(of: 400)
            || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        localDate(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    }

    /// Uses local components and Calendar's explicit DST policies: a missing
    /// wall-clock time moves to the next valid time, while a repeated time
    /// chooses the first instance.
    private func localDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        guard let noon = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12,
            minute: 0,
            second: 0
        )), let before = calendar.date(byAdding: .day, value: -1, to: noon) else {
            return nil
        }

        let matching = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: 0,
            nanosecond: 0
        )
        return calendar.nextDate(
            after: before,
            matching: matching,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    private func normalizedHour(_ hour: Int) -> Int {
        min(23, max(0, hour))
    }

    private func normalizedMinute(_ minute: Int) -> Int {
        min(59, max(0, minute))
    }
}

typealias BirthdayOccurrence = BirthdayAutomationOccurrence
typealias BirthdayCheckInEvent = BirthdayAutomationEvent
typealias RoleBirthdayCheckInEvent = BirthdayAutomationEvent
