import Foundation

/// The small value-only input needed by the continuous-conversation policy.
///
/// Validity, delivery state, role ownership, and conversation filtering belong
/// to the caller. This type deliberately contains only the evidence needed by
/// the policy so it can be used without SwiftData or SwiftUI.
struct ConversationCareEvent: Equatable, Hashable, Sendable {
    let id: UUID
    let occurredAt: Date
    let isUser: Bool

    init(id: UUID = UUID(), occurredAt: Date, isUser: Bool) {
        self.id = id
        self.occurredAt = occurredAt
        self.isUser = isUser
    }
}

/// The elapsed milestones used by a care schedule.
///
/// The first reminder is user-configurable in the 60...180 minute range. The
/// 180-minute milestone is always present. The policy does not impose a UI
/// step size; a slider or picker can choose its own increments.
struct ConversationCareMilestones: Equatable, Sendable {
    static let minimumFirstReminderMinutes = 60
    static let maximumFirstReminderMinutes = 180
    static let finalReminderMinutes = 180

    let firstReminderMinutes: Int
    let minutes: [Int]

    init(firstReminderMinutes: Int = 90) {
        let normalized = Self.clamp(firstReminderMinutes)
        self.firstReminderMinutes = normalized
        self.minutes = Array(Set([normalized, Self.finalReminderMinutes])).sorted()
    }

    /// A short alias for callers that describe the setting as a delay.
    var firstDelayMinutes: Int { firstReminderMinutes }

    /// The unique, ascending reminder values.
    var values: [Int] { minutes }

    var isSingleReminder: Bool { minutes.count == 1 }

    func contains(_ value: Int) -> Bool {
        minutes.contains(value)
    }

    func minutes(for stage: ConversationCareStage) -> Int {
        switch stage {
        case .first:
            return firstReminderMinutes
        case .final:
            return Self.finalReminderMinutes
        }
    }

    func dueDate(for stage: ConversationCareStage, from startDate: Date) -> Date {
        startDate.addingTimeInterval(TimeInterval(minutes(for: stage)) * 60)
    }

    func isDue(
        stage: ConversationCareStage,
        elapsed: TimeInterval
    ) -> Bool {
        elapsed >= TimeInterval(minutes(for: stage)) * 60
    }

    func isDue(
        stage: ConversationCareStage,
        at date: Date,
        from startDate: Date
    ) -> Bool {
        isDue(stage: stage, elapsed: date.timeIntervalSince(startDate))
    }

    /// Clamps a setting without imposing any step size.
    static func clamp(_ minutes: Int) -> Int {
        min(
            maximumFirstReminderMinutes,
            max(minimumFirstReminderMinutes, minutes)
        )
    }
}

/// The two semantic stages of the schedule. Their elapsed values can
/// coincide when the first reminder is configured to 180 minutes.
enum ConversationCareStage: String, CaseIterable, Codable, Sendable {
    case first
    case final

    /// Compatibility spellings for call sites that use initial/follow-up
    /// terminology. They do not add another reminder stage.
    static let initial = Self.first
    static let followUp = Self.final
}

/// A deterministic, contiguous run of conversation activity.
struct ConversationCareSession: Equatable, Sendable {
    /// Events are retained in the policy's stable chronological order.
    let events: [ConversationCareEvent]
    let startEvent: ConversationCareEvent
    let lastEvent: ConversationCareEvent
    let lastUserEvent: ConversationCareEvent?
    let userTurnCount: Int

    init?(events: [ConversationCareEvent]) {
        guard !events.isEmpty else { return nil }
        let ordered = ConversationCarePolicy.sortedEvents(events)
        guard let first = ordered.first, let last = ordered.last else {
            return nil
        }
        self.events = ordered
        self.startEvent = first
        self.lastEvent = last
        self.lastUserEvent = ordered.last(where: \.isUser)
        self.userTurnCount = ordered.reduce(into: 0) { count, event in
            if event.isUser { count += 1 }
        }
    }

    init?(_ events: [ConversationCareEvent]) {
        self.init(events: events)
    }

    var startDate: Date { startEvent.occurredAt }
    var lastEventDate: Date { lastEvent.occurredAt }
    var lastActivityDate: Date { lastEventDate }
    var lastUserEventDate: Date? { lastUserEvent?.occurredAt }
    var lastUserDate: Date? { lastUserEventDate }

    /// Four user turns are the minimum evidence for care eligibility.
    var isEligible: Bool {
        userTurnCount >= ConversationCarePolicy.minimumEligibleUserTurns
    }

    /// A session stays active only while both the latest activity and the
    /// latest user message are no more than 20 minutes old. Exactly 20 minutes
    /// remains active; only a greater interval closes it.
    func isActive(at now: Date) -> Bool {
        guard let lastUserEventDate else { return false }
        return ConversationCarePolicy.isWithinActiveWindow(
            now: now,
            eventDate: lastEventDate
        ) && ConversationCarePolicy.isWithinActiveWindow(
            now: now,
            eventDate: lastUserEventDate
        )
    }

    func isActive(now: Date) -> Bool {
        isActive(at: now)
    }

    func isEligible(at now: Date) -> Bool {
        isEligible && isActive(at: now)
    }

    func elapsed(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startDate))
    }

    func elapsedMinutes(at now: Date) -> Int {
        Int(elapsed(at: now) / 60)
    }
}

/// Pure policy for detecting continuous conversation sessions and their care
/// milestones. Inputs must already be filtered to valid conversation events.
enum ConversationCarePolicy {
    typealias Event = ConversationCareEvent
    typealias Session = ConversationCareSession
    typealias Milestones = ConversationCareMilestones
    typealias Stage = ConversationCareStage

    static let sessionBreakInterval: TimeInterval = 20 * 60
    static let activeWindow: TimeInterval = sessionBreakInterval
    static let minimumEligibleUserTurns = 4
    static let defaultFirstReminderMinutes = 90
    static let minimumFirstReminderMinutes = ConversationCareMilestones.minimumFirstReminderMinutes
    static let maximumFirstReminderMinutes = ConversationCareMilestones.maximumFirstReminderMinutes
    static let fixedFinalReminderMinutes = ConversationCareMilestones.finalReminderMinutes

    static var defaultMilestones: ConversationCareMilestones {
        ConversationCareMilestones(firstReminderMinutes: defaultFirstReminderMinutes)
    }

    static func milestones(
        firstReminderMinutes: Int = defaultFirstReminderMinutes
    ) -> ConversationCareMilestones {
        ConversationCareMilestones(firstReminderMinutes: firstReminderMinutes)
    }

    static func normalizedFirstReminderMinutes(_ minutes: Int) -> Int {
        ConversationCareMilestones.clamp(minutes)
    }

    /// Sorts by activity time and then UUID so the same events produce the
    /// same session boundaries regardless of input order.
    static func sortedEvents(_ events: [ConversationCareEvent]) -> [ConversationCareEvent] {
        events.sorted(by: areOrderedBefore)
    }

    /// Splits ordered activity into sessions. A gap strictly greater than 20
    /// minutes starts a new session; a gap of exactly 20 minutes is contiguous.
    static func sessions(from events: [ConversationCareEvent]) -> [ConversationCareSession] {
        let ordered = sortedEvents(events)
        guard var current = ordered.first.map({ [$0] }) else { return [] }
        var result: [ConversationCareSession] = []

        for event in ordered.dropFirst() {
            guard let previous = current.last else { continue }
            if event.occurredAt.timeIntervalSince(previous.occurredAt) > sessionBreakInterval {
                if let session = ConversationCareSession(events: current) {
                    result.append(session)
                }
                current = [event]
            } else {
                current.append(event)
            }
        }

        if let session = ConversationCareSession(events: current) {
            result.append(session)
        }
        return result
    }

    static func latestSession(
        from events: [ConversationCareEvent]
    ) -> ConversationCareSession? {
        sessions(from: events).last
    }

    /// Returns the latest session only while it satisfies the active-window
    /// rule. It does not apply validity filtering to the input.
    static func activeSession(
        from events: [ConversationCareEvent],
        now: Date
    ) -> ConversationCareSession? {
        guard let session = latestSession(from: events), session.isActive(at: now) else {
            return nil
        }
        return session
    }

    static func isWithinActiveWindow(now: Date, eventDate: Date) -> Bool {
        now.timeIntervalSince(eventDate) <= activeWindow
    }

    static func elapsed(
        for session: ConversationCareSession,
        at now: Date
    ) -> TimeInterval {
        session.elapsed(at: now)
    }

    static func elapsedMinutes(
        for session: ConversationCareSession,
        at now: Date
    ) -> Int {
        session.elapsedMinutes(at: now)
    }

    static func scheduleDate(
        for session: ConversationCareSession,
        stage: ConversationCareStage,
        firstReminderMinutes: Int = defaultFirstReminderMinutes
    ) -> Date {
        milestones(firstReminderMinutes: firstReminderMinutes)
            .dueDate(for: stage, from: session.startDate)
    }

    static func scheduleDates(
        for session: ConversationCareSession,
        firstReminderMinutes: Int = defaultFirstReminderMinutes
    ) -> [Date] {
        milestones(firstReminderMinutes: firstReminderMinutes).minutes.map {
            session.startDate.addingTimeInterval(TimeInterval($0) * 60)
        }
    }

    static func isDue(
        stage: ConversationCareStage,
        for session: ConversationCareSession,
        at now: Date,
        firstReminderMinutes: Int = defaultFirstReminderMinutes
    ) -> Bool {
        milestones(firstReminderMinutes: firstReminderMinutes).isDue(
            stage: stage,
            elapsed: session.elapsed(at: now)
        )
    }

    static func isDue(
        stage: ConversationCareStage,
        elapsed: TimeInterval,
        firstReminderMinutes: Int = defaultFirstReminderMinutes
    ) -> Bool {
        milestones(firstReminderMinutes: firstReminderMinutes).isDue(
            stage: stage,
            elapsed: elapsed
        )
    }

    private static func areOrderedBefore(
        _ lhs: ConversationCareEvent,
        _ rhs: ConversationCareEvent
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt < rhs.occurredAt
        }

        let leftID = lhs.id.uuidString.lowercased()
        let rightID = rhs.id.uuidString.lowercased()
        if leftID != rightID {
            return leftID < rightID
        }

        // UUID is the requested tie-break. This final field only makes the
        // comparator total for malformed duplicate-ID inputs.
        return (!lhs.isUser && rhs.isUser)
    }
}

// Short spellings are useful at integration boundaries while the descriptive
// names remain the canonical API.
typealias CareEvent = ConversationCareEvent
typealias CareSession = ConversationCareSession
typealias CareMilestones = ConversationCareMilestones
typealias CareStage = ConversationCareStage
