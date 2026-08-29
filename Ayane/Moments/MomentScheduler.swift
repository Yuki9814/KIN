import Foundation

/// The value boundary used by the Moments scheduler.
///
/// SwiftData records are reference types and may be refreshed by another
/// context while a generation is in flight.  The scheduler therefore only
/// reads and returns this value; persistence code can apply `after` in one
/// context-local write.
struct MomentTaskSnapshot: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var roleID: UUID
    var instruction: String
    var scheduledAt: Date
    var seriesID: UUID?
    var occurrenceKey: String
    var recurrenceRaw: String
    var recurrenceInterval: Int
    var recurrenceWeekday: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceHour: Int
    var recurrenceMinute: Int
    var timezoneIdentifier: String
    var nextAttemptAt: Date?
    var state: MomentTaskState
    var resultText: String
    var publishedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var attemptCount: Int
    var lastError: String
    var leaseOwner: String
    var leaseExpiresAt: Date?
    var deviceID: String
    var revision: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case roleID
        case instruction
        case scheduledAt
        case seriesID
        case occurrenceKey
        case recurrenceRaw
        case recurrenceInterval
        case recurrenceWeekday
        case recurrenceDayOfMonth
        case recurrenceHour
        case recurrenceMinute
        case timezoneIdentifier
        case nextAttemptAt
        case state
        case resultText
        case publishedAt
        case createdAt
        case updatedAt
        case attemptCount
        case lastError
        case leaseOwner
        case leaseExpiresAt
        case deviceID
        case revision
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        instruction: String = "",
        scheduledAt: Date = Date(),
        seriesID: UUID? = nil,
        occurrenceKey: String = "",
        recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        nextAttemptAt: Date? = nil,
        state: MomentTaskState = .scheduled,
        resultText: String = "",
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String = "",
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        deviceID: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.instruction = instruction
        self.scheduledAt = scheduledAt
        self.seriesID = seriesID
        self.occurrenceKey = occurrenceKey
        self.recurrenceRaw = recurrenceRaw
        self.recurrenceInterval = max(1, recurrenceInterval)
        self.recurrenceWeekday = recurrenceWeekday
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceHour = recurrenceHour
        self.recurrenceMinute = recurrenceMinute
        self.timezoneIdentifier = timezoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : timezoneIdentifier
        self.nextAttemptAt = nextAttemptAt
        self.state = state
        self.resultText = resultText
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = max(0, attemptCount)
        self.lastError = lastError
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.deviceID = deviceID
        self.revision = max(0, revision)
    }

    /// Keeps scheduler payloads produced before recurring tasks were added
    /// readable. Those snapshots are treated as one-shot tasks.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            roleID: try container.decode(UUID.self, forKey: .roleID),
            instruction: try container.decode(String.self, forKey: .instruction),
            scheduledAt: try container.decode(Date.self, forKey: .scheduledAt),
            seriesID: try container.decodeIfPresent(UUID.self, forKey: .seriesID),
            occurrenceKey: try container.decodeIfPresent(String.self, forKey: .occurrenceKey) ?? "",
            recurrenceRaw: try container.decodeIfPresent(String.self, forKey: .recurrenceRaw)
                ?? MomentTaskRecurrenceFrequency.once.rawValue,
            recurrenceInterval: try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval) ?? 1,
            recurrenceWeekday: try container.decodeIfPresent(Int.self, forKey: .recurrenceWeekday),
            recurrenceDayOfMonth: try container.decodeIfPresent(Int.self, forKey: .recurrenceDayOfMonth),
            recurrenceHour: try container.decodeIfPresent(Int.self, forKey: .recurrenceHour) ?? 0,
            recurrenceMinute: try container.decodeIfPresent(Int.self, forKey: .recurrenceMinute) ?? 0,
            timezoneIdentifier: try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
                ?? TimeZone.current.identifier,
            nextAttemptAt: try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt),
            state: try container.decode(MomentTaskState.self, forKey: .state),
            resultText: try container.decode(String.self, forKey: .resultText),
            publishedAt: try container.decodeIfPresent(Date.self, forKey: .publishedAt),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            attemptCount: try container.decode(Int.self, forKey: .attemptCount),
            lastError: try container.decode(String.self, forKey: .lastError),
            leaseOwner: try container.decode(String.self, forKey: .leaseOwner),
            leaseExpiresAt: try container.decodeIfPresent(Date.self, forKey: .leaseExpiresAt),
            deviceID: try container.decode(String.self, forKey: .deviceID),
            revision: try container.decode(Int.self, forKey: .revision)
        )
    }
}

/// Stable operation outcomes returned by `MomentScheduler`.
enum MomentSchedulerAction: String, Codable, CaseIterable, Sendable {
    case available
    case notDue
    case claimed
    case leaseHeld
    case published
    case alreadyPublished
    case released
    case cancelled
    case rejected
}

/// Stable, local reason codes for scheduler decisions.
enum MomentSchedulerReason: String, Codable, CaseIterable, Sendable {
    case due
    case notDue
    case leaseClaimed
    case leaseAlreadyHeld
    case leaseHeldByAnotherOwner
    case leaseReclaimed
    case published
    case alreadyPublished
    case retryScheduled
    case cancelled
    case invalidOwner
    case invalidResult
    case notClaimed
    case leaseLost

    var title: String {
        switch self {
        case .due: "任务已到期"
        case .notDue: "任务尚未到期"
        case .leaseClaimed: "已取得生成租约"
        case .leaseAlreadyHeld: "当前执行者已持有租约"
        case .leaseHeldByAnotherOwner: "其他执行者持有租约"
        case .leaseReclaimed: "已回收过期租约并重试"
        case .published: "朋友圈动态已发布"
        case .alreadyPublished: "任务已经发布，保持幂等"
        case .retryScheduled: "失败已释放，等待重试"
        case .cancelled: "任务已取消"
        case .invalidOwner: "执行者标识为空"
        case .invalidResult: "发布文本为空"
        case .notClaimed: "任务尚未取得租约"
        case .leaseLost: "租约已失效或不属于当前执行者"
        }
    }
}

/// A pure value result from one scheduler operation.
struct MomentSchedulerDecision: Codable, Equatable, Sendable {
    let before: MomentTaskSnapshot
    let after: MomentTaskSnapshot
    let action: MomentSchedulerAction
    let reasonCode: MomentSchedulerReason

    var from: MomentTaskState { before.state }
    var to: MomentTaskState { after.state }
    var state: MomentTaskState { after.state }
    var task: MomentTaskSnapshot { after }
    var reason: String { reasonCode.title }
    var didTransition: Bool { before != after }
    var accepted: Bool {
        switch action {
        case .claimed, .published, .alreadyPublished, .released, .cancelled:
            true
        case .available, .notDue, .leaseHeld, .rejected:
            false
        }
    }
    var isAccepted: Bool { accepted }
    var shouldPublish: Bool { action == .published }
    var shouldRetry: Bool { action == .released }
}

/// Deterministic, local lease state machine for text-only Moments tasks.
///
/// It never performs I/O, starts a background task, or calls a model/API.  A
/// caller claims a value, generates text elsewhere, then feeds the value back
/// to `publish` or `release`.  Publishing is accepted only for the active
/// owner lease; once `published`, every later operation is a no-op.
struct MomentScheduler: Sendable {
    static let defaultLeaseDuration: TimeInterval = 120

    typealias State = MomentTaskSnapshot
    typealias Decision = MomentSchedulerDecision

    let leaseDuration: TimeInterval

    init(leaseDuration: TimeInterval = MomentScheduler.defaultLeaseDuration) {
        self.leaseDuration = Self.validLeaseDuration(leaseDuration)
    }

    /// Returns whether the task may be claimed at `now`.
    ///
    /// A scheduled task is due at its exact scheduled timestamp.  A running
    /// task is due again only when its lease is missing or expired, allowing a
    /// crashed worker to be retried without another scheduler service.
    func isDue(_ task: State, now: Date) -> Bool {
        switch task.state {
        case .scheduled:
            task.scheduledAt <= now
        case .running:
            !hasActiveLease(task, now: now)
        case .published, .cancelled:
            false
        }
    }

    /// Compatibility spelling for callers that use a property-like verb.
    func due(_ task: State, now: Date) -> Bool {
        isDue(task, now: now)
    }

    static func isDue(_ task: State, now: Date) -> Bool {
        MomentScheduler().isDue(task, now: now)
    }

    /// Describes availability without mutating the task.
    func decision(for task: State, now: Date) -> Decision {
        switch task.state {
        case .scheduled:
            return makeDecision(
                before: task,
                after: task,
                action: isDue(task, now: now) ? .available : .notDue,
                reasonCode: isDue(task, now: now) ? .due : .notDue
            )
        case .running:
            if hasActiveLease(task, now: now) {
                return makeDecision(
                    before: task,
                    after: task,
                    action: .leaseHeld,
                    reasonCode: .leaseAlreadyHeld
                )
            }
            return makeDecision(
                before: task,
                after: task,
                action: .available,
                reasonCode: .leaseReclaimed
            )
        case .published:
            return makeDecision(
                before: task,
                after: task,
                action: .alreadyPublished,
                reasonCode: .alreadyPublished
            )
        case .cancelled:
            return makeDecision(
                before: task,
                after: task,
                action: .cancelled,
                reasonCode: .cancelled
            )
        }
    }

    /// Claims a due task for one owner and creates a finite lease.
    func claim(
        _ task: State,
        owner: String,
        now: Date,
        leaseDuration: TimeInterval? = nil
    ) -> Decision {
        let normalizedOwner = Self.normalizedOwner(owner)

        // Terminal states are idempotent even when a stale caller no longer
        // has an owner token.  This is the key duplicate-publication guard.
        switch task.state {
        case .published:
            return makeDecision(
                before: task,
                after: task,
                action: .alreadyPublished,
                reasonCode: .alreadyPublished
            )
        case .cancelled:
            return makeDecision(
                before: task,
                after: task,
                action: .cancelled,
                reasonCode: .cancelled
            )
        case .scheduled, .running:
            break
        }

        guard !normalizedOwner.isEmpty else {
            return rejected(task, reasonCode: .invalidOwner)
        }

        if task.state == .scheduled, !isDue(task, now: now) {
            return makeDecision(
                before: task,
                after: task,
                action: .notDue,
                reasonCode: .notDue
            )
        }

        if task.state == .running, hasActiveLease(task, now: now) {
            let currentOwner = Self.normalizedOwner(task.leaseOwner)
            return makeDecision(
                before: task,
                after: task,
                action: .leaseHeld,
                reasonCode: currentOwner == normalizedOwner
                    ? .leaseAlreadyHeld
                    : .leaseHeldByAnotherOwner
            )
        }

        var next = task
        next.state = .running
        next.attemptCount = max(0, task.attemptCount) + 1
        next.lastError = ""
        next.leaseOwner = normalizedOwner
        next.leaseExpiresAt = now.addingTimeInterval(
            Self.validLeaseDuration(leaseDuration ?? self.leaseDuration)
        )
        next.updatedAt = now
        next.revision = max(0, task.revision) + 1
        return makeDecision(
            before: task,
            after: next,
            action: .claimed,
            reasonCode: task.state == .running ? .leaseReclaimed : .leaseClaimed
        )
    }

    /// Marks a task as published only while the caller owns a live lease.
    func publish(
        _ task: State,
        owner: String,
        resultText: String,
        now: Date
    ) -> Decision {
        terminalDecision(for: task) ?? publishRunning(
            task,
            owner: owner,
            resultText: resultText,
            now: now
        )
    }

    /// Convenience form for a caller that keeps the owner on the snapshot.
    func publish(
        _ task: State,
        resultText: String,
        now: Date
    ) -> Decision {
        publish(task, owner: task.leaseOwner, resultText: resultText, now: now)
    }

    /// Alias that reads naturally at a generation completion boundary.
    func succeed(
        _ task: State,
        owner: String,
        resultText: String,
        now: Date
    ) -> Decision {
        publish(task, owner: owner, resultText: resultText, now: now)
    }

    /// Releases a live lease after generation failure.  The resulting
    /// scheduled state is immediately retryable once its original due time
    /// has passed (which is true for a task already being attempted).
    func release(
        _ task: State,
        owner: String,
        error: String = "",
        now: Date
    ) -> Decision {
        terminalDecision(for: task) ?? releaseRunning(
            task,
            owner: owner,
            error: error,
            now: now
        )
    }

    /// Alias for callers that use failure terminology.
    func fail(
        _ task: State,
        owner: String,
        error: String = "",
        now: Date
    ) -> Decision {
        release(task, owner: owner, error: error, now: now)
    }

    /// Convenience form for a caller that keeps the owner on the snapshot.
    func fail(
        _ task: State,
        error: String = "",
        now: Date
    ) -> Decision {
        fail(task, owner: task.leaseOwner, error: error, now: now)
    }

    /// Cancels a scheduled or running task.  A published task remains
    /// published, preserving the one-publication invariant.
    func cancel(_ task: State, now: Date) -> Decision {
        terminalDecision(for: task) ?? cancelActive(task, now: now)
    }

    /// Owner-aware cancellation for a running task.
    func cancel(_ task: State, owner: String, now: Date) -> Decision {
        guard task.state == .running else {
            return cancel(task, now: now)
        }
        let normalizedOwner = Self.normalizedOwner(owner)
        guard !normalizedOwner.isEmpty,
              normalizedOwner == Self.normalizedOwner(task.leaseOwner),
              hasActiveLease(task, now: now) else {
            return rejected(task, reasonCode: .leaseLost)
        }
        return cancelActive(task, now: now)
    }

    private func publishRunning(
        _ task: State,
        owner: String,
        resultText: String,
        now: Date
    ) -> Decision {
        guard task.state == .running else {
            return rejected(task, reasonCode: .notClaimed)
        }

        let normalizedOwner = Self.normalizedOwner(owner)
        guard !normalizedOwner.isEmpty else {
            return rejected(task, reasonCode: .invalidOwner)
        }
        guard normalizedOwner == Self.normalizedOwner(task.leaseOwner),
              hasActiveLease(task, now: now) else {
            return rejected(task, reasonCode: .leaseLost)
        }

        let normalizedResult = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedResult.isEmpty else {
            return rejected(task, reasonCode: .invalidResult)
        }

        var next = task
        next.state = .published
        next.resultText = normalizedResult
        next.publishedAt = now
        next.updatedAt = now
        next.leaseOwner = ""
        next.leaseExpiresAt = nil
        next.revision = max(0, task.revision) + 1
        return makeDecision(
            before: task,
            after: next,
            action: .published,
            reasonCode: .published
        )
    }

    private func releaseRunning(
        _ task: State,
        owner: String,
        error: String,
        now: Date
    ) -> Decision {
        guard task.state == .running else {
            return rejected(task, reasonCode: .notClaimed)
        }

        let normalizedOwner = Self.normalizedOwner(owner)
        guard !normalizedOwner.isEmpty else {
            return rejected(task, reasonCode: .invalidOwner)
        }
        guard normalizedOwner == Self.normalizedOwner(task.leaseOwner),
              hasActiveLease(task, now: now) else {
            return rejected(task, reasonCode: .leaseLost)
        }

        var next = task
        next.state = .scheduled
        next.lastError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        next.updatedAt = now
        next.leaseOwner = ""
        next.leaseExpiresAt = nil
        next.revision = max(0, task.revision) + 1
        return makeDecision(
            before: task,
            after: next,
            action: .released,
            reasonCode: .retryScheduled
        )
    }

    private func cancelActive(_ task: State, now: Date) -> Decision {
        var next = task
        next.state = .cancelled
        next.updatedAt = now
        next.leaseOwner = ""
        next.leaseExpiresAt = nil
        next.revision = max(0, task.revision) + 1
        return makeDecision(
            before: task,
            after: next,
            action: .cancelled,
            reasonCode: .cancelled
        )
    }

    private func terminalDecision(for task: State) -> Decision? {
        switch task.state {
        case .published:
            makeDecision(
                before: task,
                after: task,
                action: .alreadyPublished,
                reasonCode: .alreadyPublished
            )
        case .cancelled:
            makeDecision(
                before: task,
                after: task,
                action: .cancelled,
                reasonCode: .cancelled
            )
        case .scheduled, .running:
            nil
        }
    }

    private func rejected(_ task: State, reasonCode: MomentSchedulerReason) -> Decision {
        makeDecision(
            before: task,
            after: task,
            action: .rejected,
            reasonCode: reasonCode
        )
    }

    private func makeDecision(
        before: State,
        after: State,
        action: MomentSchedulerAction,
        reasonCode: MomentSchedulerReason
    ) -> Decision {
        Decision(
            before: before,
            after: after,
            action: action,
            reasonCode: reasonCode
        )
    }

    private func hasActiveLease(_ task: State, now: Date) -> Bool {
        guard !Self.normalizedOwner(task.leaseOwner).isEmpty,
              let expiresAt = task.leaseExpiresAt else {
            return false
        }
        return expiresAt > now
    }

    private static func normalizedOwner(_ owner: String) -> String {
        owner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validLeaseDuration(_ value: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : defaultLeaseDuration
    }
}
