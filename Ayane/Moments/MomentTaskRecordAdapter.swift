import Foundation

/// Persistence adapters kept outside the pure scheduler.  They are small
/// scalar copies so a caller can read a record, make one value decision, then
/// apply that decision in its own ModelContext.
extension MomentTaskSnapshot {
    init(_ record: CompanionMomentTaskRecord) {
        self.init(
            id: record.id,
            roleID: record.resolvedRoleID,
            instruction: record.instruction,
            scheduledAt: record.scheduledAt,
            seriesID: record.seriesID,
            occurrenceKey: record.occurrenceKey,
            recurrenceRaw: record.recurrenceRaw,
            recurrenceInterval: record.recurrenceInterval,
            recurrenceWeekday: record.recurrenceWeekday,
            recurrenceDayOfMonth: record.recurrenceDayOfMonth,
            recurrenceHour: record.recurrenceHour,
            recurrenceMinute: record.recurrenceMinute,
            timezoneIdentifier: record.timezoneIdentifier,
            nextAttemptAt: record.nextAttemptAt,
            state: record.state,
            resultText: record.resultText,
            publishedAt: record.publishedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            attemptCount: record.attemptCount,
            lastError: record.lastError,
            leaseOwner: record.leaseOwner,
            leaseExpiresAt: record.leaseExpiresAt,
            deviceID: record.deviceID,
            revision: record.revision
        )
    }

    var recurrenceRule: MomentTaskRecurrenceRule {
        MomentTaskRecurrenceRule(
            recurrenceRaw: recurrenceRaw,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            timezoneIdentifier: timezoneIdentifier,
            scheduledAt: scheduledAt,
            seriesID: seriesID
        )
    }
}

extension CompanionMomentTaskRecord {
    var snapshot: MomentTaskSnapshot { MomentTaskSnapshot(self) }

    var summary: CompanionMomentTaskSummary {
        CompanionMomentTaskSummary(
            id: id,
            resolvedRoleID: resolvedRoleID,
            instruction: instruction,
            scheduledAt: scheduledAt,
            state: state,
            resultText: resultText,
            publishedAt: publishedAt,
            lastError: lastError,
            attemptCount: attemptCount,
            seriesID: seriesID,
            occurrenceKey: occurrenceKey,
            recurrenceRaw: recurrenceRaw,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            timezoneIdentifier: timezoneIdentifier,
            nextAttemptAt: nextAttemptAt
        )
    }

    var recurrenceRule: MomentTaskRecurrenceRule { MomentTaskRecurrenceRule(self) }

    /// Applies only scalar values from a pure decision.  The identity is
    /// intentionally left untouched; callers should apply a decision to the
    /// same logical record that produced its `before` snapshot.
    func apply(_ snapshot: MomentTaskSnapshot) {
        guard id == snapshot.id else { return }
        roleID = snapshot.resolvedRoleID
        instruction = snapshot.instruction
        scheduledAt = snapshot.scheduledAt
        seriesID = snapshot.seriesID
        occurrenceKey = snapshot.occurrenceKey
        recurrenceRaw = snapshot.recurrenceRaw
        recurrenceInterval = max(1, snapshot.recurrenceInterval)
        recurrenceWeekday = snapshot.recurrenceWeekday
        recurrenceDayOfMonth = snapshot.recurrenceDayOfMonth
        recurrenceHour = snapshot.recurrenceHour
        recurrenceMinute = snapshot.recurrenceMinute
        timezoneIdentifier = snapshot.timezoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : snapshot.timezoneIdentifier
        nextAttemptAt = snapshot.nextAttemptAt
        stateRaw = snapshot.state.rawValue
        resultText = snapshot.resultText
        publishedAt = snapshot.publishedAt
        createdAt = snapshot.createdAt
        updatedAt = snapshot.updatedAt
        attemptCount = max(0, snapshot.attemptCount)
        lastError = snapshot.lastError
        leaseOwner = snapshot.leaseOwner
        leaseExpiresAt = snapshot.leaseExpiresAt
        deviceID = snapshot.deviceID
        revision = max(0, snapshot.revision)
    }

    func apply(_ decision: MomentSchedulerDecision) {
        apply(decision.after)
    }
}

/// Model overloads keep the call site concise while the returned decision
/// remains a value and does not mutate the record automatically.
extension MomentScheduler {
    func claim(
        _ task: CompanionMomentTaskRecord,
        owner: String,
        now: Date,
        leaseDuration: TimeInterval? = nil
    ) -> Decision {
        claim(task.snapshot, owner: owner, now: now, leaseDuration: leaseDuration)
    }

    func publish(
        _ task: CompanionMomentTaskRecord,
        owner: String,
        resultText: String,
        now: Date
    ) -> Decision {
        publish(task.snapshot, owner: owner, resultText: resultText, now: now)
    }

    func release(
        _ task: CompanionMomentTaskRecord,
        owner: String,
        error: String = "",
        now: Date
    ) -> Decision {
        release(task.snapshot, owner: owner, error: error, now: now)
    }

    func fail(
        _ task: CompanionMomentTaskRecord,
        owner: String,
        error: String = "",
        now: Date
    ) -> Decision {
        fail(task.snapshot, owner: owner, error: error, now: now)
    }
}
