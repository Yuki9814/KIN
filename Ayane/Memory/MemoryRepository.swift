import Foundation
import SwiftData

enum MemoryRepositoryError: LocalizedError, Equatable {
    case forgottenMemoryCannotBeChanged
    case blankMemoryValue
    case blankCanonicalKey
    case sourceEventNotFound(UUID)
    case sourceEventRedacted(UUID)
    case sourceEventRoleMismatch(
        sourceEventID: UUID,
        expectedRoleID: UUID,
        actualRoleID: UUID
    )

    var errorDescription: String? {
        switch self {
        case .forgottenMemoryCannotBeChanged:
            return "这条记忆已有遗忘标记，不能从旧副本恢复；请在这个角色的新对话中重新明确说明。"
        case .blankMemoryValue:
            return "记忆内容不能为空。"
        case .blankCanonicalKey:
            return "记忆的规范键不能为空。"
        case let .sourceEventNotFound(sourceEventID):
            return "记忆来源事件不存在，已拒绝写入：\(sourceEventID.uuidString)。"
        case let .sourceEventRedacted(sourceEventID):
            return "记忆来源事件已被撤回或删除，已拒绝写入：\(sourceEventID.uuidString)。"
        case let .sourceEventRoleMismatch(sourceEventID, expectedRoleID, actualRoleID):
            return "记忆来源事件与目标角色不一致，已拒绝写入：\(sourceEventID.uuidString)（目标 \(expectedRoleID.uuidString)，来源 \(actualRoleID.uuidString)）。"
        }
    }
}

@MainActor
enum MemoryRepository {
    private static let maximumLiveVersionsPerCanonicalKey = 512
    private static let maximumEvidencePerMemoryOperation = 1_024
    /// A role-wide privacy reset suppresses source material at or before its
    /// cutoff, while still allowing genuinely new conversations to establish
    /// memories automatically afterwards.
    static let roleResetReason = "user_requested_all_memory"

    static func apply(
        _ candidates: [ExtractedMemoryCandidate],
        eventContents: [UUID: String],
        eventDates: [UUID: Date] = [:],
        context: ModelContext,
        deviceID: String,
        extractorID: String,
        roleID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> Int {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let currentRoleID = RoleScope.resolve(roleID)
        guard candidates.allSatisfy({
            !normalizeKey($0.canonicalKey).isEmpty
        }) else {
            throw MemoryRepositoryError.blankCanonicalKey
        }

        // A caller-provided `eventContents` dictionary is only an extraction
        // payload; it is not authority for ownership.  When a role is
        // explicitly supplied, every source ID must resolve to a persisted
        // event in that same role before any memory/evidence mutation starts.
        // Calls that omit roleID are the pre-multi-role legacy API.  Their
        // in-memory fixtures may not have a ConversationEvent row yet, so a
        // missing row remains compatible there; any row that does exist is
        // still checked and cannot cross a role boundary.
        let persistedEventDates = try validateSourceEvents(
            for: candidates,
            requestedRoleID: roleID,
            targetRoleID: currentRoleID,
            context: context
        )
        var authoritativeEventDates = eventDates
        for (eventID, persistedDate) in persistedEventDates {
            authoritativeEventDates[eventID] = persistedDate
        }
        let orderedCandidates = candidates.enumerated().sorted { lhs, rhs in
            let lhsDate = authoritativeEventDates[lhs.element.sourceEventID] ?? .distantPast
            let rhsDate = authoritativeEventDates[rhs.element.sourceEventID] ?? .distantPast
            return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
        }.map { $0.element }

        // Scope every initial read to the keys represented by this batch. The
        // old implementation loaded the whole memory, evidence, and tombstone
        // tables before doing any work, which made a small extraction scan grow
        // linearly with the user's complete history.
        var allMemories = try fetchMemories(
            forCanonicalKeys: orderedCandidates.map(\.canonicalKey),
            roleID: currentRoleID,
            context: context
        )
        // A CloudKit merge can briefly expose an active physical copy beside
        // a forgotten copy with the same application UUID.  Scrub the
        // forgotten winner before any later path can inspect or persist it;
        // this also repairs legacy rows which were marked forgotten before
        // erasure was made part of the write contract.
        var didScrubForgottenMemory = false
        for memory in allMemories where memory.state == .forgotten {
            didScrubForgottenMemory = scrubForgottenMemory(memory)
                || didScrubForgottenMemory
        }
        var tombstones = try fetchTombstones(
            forCanonicalKeys: orderedCandidates.map(\.canonicalKey),
            memoryIDs: allMemories.map(\.id),
            roleID: currentRoleID,
            context: context
        )
        // Retractions delete evidence through the paged helper below. Avoid
        // materializing even the hot evidence window when this batch contains
        // no upserts; mixed batches still keep the bounded cache for their
        // upsert candidates.
        var allEvidence: [MemoryEvidenceRecord] = []
        if orderedCandidates.contains(where: { $0.operation != .retract }) {
            allEvidence = try fetchEvidence(
                forMemoryIDs: allMemories.map(\.id),
                roleID: currentRoleID,
                context: context
            )
        }
        let userForgetDates = userForgetDatesByCanonicalKey(
            tombstones: tombstones,
            memories: allMemories
        )
        let roleResetCutoff = tombstones
            .filter {
                $0.entityType == "memory"
                    && normalizeKey($0.canonicalKey).isEmpty
                    && $0.reason == roleResetReason
            }
            .map(\.deletedAt)
            .max()
        let legacyForgetCutoff = tombstones
            .filter {
                $0.entityType == "memory"
                    && normalizeKey($0.canonicalKey).isEmpty
                    && $0.reason != roleResetReason
            }
            .map(\.deletedAt)
            .max()
        var applied = 0

        // Model output order is not a trustworthy chronology. Applying older
        // evidence first makes the newest source event deterministically win,
        // while preserving the original order when dates are unavailable.
        for candidate in orderedCandidates {
            guard let eventContent = eventContents[candidate.sourceEventID],
                  let quoteRange = eventContent.range(of: candidate.sourceQuote) else {
                continue
            }
            if candidate.operation != .retract,
               let roleResetCutoff {
                guard let sourceDate = authoritativeEventDates[candidate.sourceEventID]
                        ?? candidate.validFrom,
                      sourceDate > roleResetCutoff else {
                    continue
                }
            }
            if candidate.operation != .retract,
               let forgottenAt = maxDate(
                    userForgetDates[normalizeKey(candidate.canonicalKey)],
                    legacyForgetCutoff
               ) {
                // Old history and inferred facts must not resurrect a user-forgotten
                // memory. A later, explicit user statement may establish it again.
                guard candidate.explicit,
                      let sourceDate = authoritativeEventDates[candidate.sourceEventID],
                      sourceDate > forgottenAt else {
                    continue
                }
            }
            let normalizedCandidateKey = normalizeKey(candidate.canonicalKey)
            let matching = allMemories
                .filter {
                    normalizeKey($0.canonicalKey) == normalizedCandidateKey
                        && $0.resolvedRoleID == currentRoleID
                        && $0.state != .forgotten
                        && !isSuppressedByTombstone($0, tombstones: tombstones)
                }
                .sorted(by: memoryRecordIsPreferred)

            if candidate.operation == .retract {
                for existing in matching {
                    existing.stateRaw = MemoryState.forgotten.rawValue
                    existing.value = ""
                    existing.embeddingData = nil
                    existing.embeddingModelID = nil
                    existing.userVerified = false
                    existing.isPinned = false
                    existing.updatedAt = Date()
                    let sourceEventIDs = try deleteEvidenceAndCollectSourceEventIDs(
                        memoryID: existing.id,
                        roleID: currentRoleID,
                        context: context
                    )
                    let tombstone = MemoryTombstoneRecord(
                        entityID: existing.id,
                        entityType: "memory",
                        canonicalKey: normalizeKey(existing.canonicalKey),
                        sourceEventIDs: sourceEventIDs,
                        deviceID: deviceID,
                        reason: "conversation_retraction",
                        roleID: currentRoleID
                    )
                    context.insert(tombstone)
                    appendUnique(tombstone, to: &tombstones)
                    applied += 1
                }
                continue
            }

            let sourceRank = sourceRank(for: candidate)
            // Callers that do not have a persisted source timestamp still
            // submit candidates in chronological apply order. Treat those as
            // observed now, matching the record's historical initialization
            // behavior, while explicit event dates continue to protect a
            // newer active fact from stale imported evidence.
            let candidateObservedAt = authoritativeEventDates[candidate.sourceEventID]
                ?? candidate.validFrom
                ?? Date()
            if let identical = matching.first(where: {
                normalize($0.value) == normalize(candidate.value)
            }) {
                var changed = false
                if candidate.explicit, identical.state == .candidate {
                    let current = matching.first(where: { $0.state == .active })
                    if let current,
                       current.id != identical.id,
                       (current.userVerified
                        || current.sourceRank > sourceRank
                        || current.observedAt > candidateObservedAt) {
                        identical.stateRaw = MemoryState.contested.rawValue
                    } else {
                        identical.stateRaw = MemoryState.active.rawValue
                        identical.supersedesID = current?.id
                        if let current, current.id != identical.id {
                            current.stateRaw = MemoryState.superseded.rawValue
                            current.validTo = candidate.validFrom
                                ?? authoritativeEventDates[candidate.sourceEventID]
                                ?? Date()
                            current.updatedAt = Date()
                        }
                    }
                    identical.sourceRank = max(identical.sourceRank, sourceRank)
                    changed = true
                }
                if candidate.confidence > identical.confidence {
                    identical.confidence = candidate.confidence
                    changed = true
                }
                if candidate.importance > identical.importance {
                    identical.importance = candidate.importance
                    changed = true
                }
                if insertEvidenceIfNeeded(
                    memoryID: identical.id,
                    candidate: candidate,
                    eventContent: eventContent,
                    quoteRange: quoteRange,
                    roleID: currentRoleID,
                    evidence: &allEvidence,
                    context: context
                ) {
                    changed = true
                }
                if changed {
                    identical.updatedAt = Date()
                    applied += 1
                }
                continue
            }

            let current = matching.first(where: { $0.state == .active })
            let proposedState: MemoryState
            if let current,
               current.userVerified
                || current.sourceRank > sourceRank
                || current.observedAt > candidateObservedAt {
                proposedState = .contested
            } else {
                proposedState = candidate.explicit ? .active : .candidate
            }

            let record = MemoryAssertionRecord(
                kind: candidate.kind,
                subject: candidate.subject,
                predicate: candidate.predicate,
                value: candidate.value,
                canonicalKey: normalizedCandidateKey,
                state: proposedState,
                confidence: candidate.confidence,
                importance: candidate.importance,
                sensitive: candidate.sensitive,
                sourceRank: sourceRank,
                validFrom: candidate.validFrom,
                validTo: candidate.validTo,
                observedAt: candidateObservedAt,
                supersedesID: proposedState == .active ? current?.id : nil,
                extractorID: extractorID,
                deviceID: deviceID,
                roleID: currentRoleID
            )
            context.insert(record)
            allMemories.append(record)
            _ = insertEvidenceIfNeeded(
                memoryID: record.id,
                candidate: candidate,
                eventContent: eventContent,
                quoteRange: quoteRange,
                roleID: currentRoleID,
                evidence: &allEvidence,
                context: context
            )

            if proposedState == .active, let current, sourceRank >= current.sourceRank {
                current.stateRaw = MemoryState.superseded.rawValue
                current.validTo = candidate.validFrom
                    ?? authoritativeEventDates[candidate.sourceEventID]
                    ?? Date()
                current.updatedAt = Date()
            }
            applied += 1
        }

        if (applied > 0 || didScrubForgottenMemory), saveChanges {
            try context.save()
        }
        return applied
    }

    static func userEdited(
        _ memory: MemoryAssertionRecord,
        value: String,
        context: ModelContext
    ) throws {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let currentRoleID = memory.resolvedRoleID
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw MemoryRepositoryError.blankMemoryValue
        }
        let tombstones = try fetchTombstones(
            forCanonicalKeys: [memory.canonicalKey],
            memoryIDs: [memory.id],
            roleID: currentRoleID,
            context: context
        )
        guard memory.state != .forgotten,
              memory.resolvedRoleID == currentRoleID,
              !isSuppressedByTombstone(memory, tombstones: tombstones) else {
            throw MemoryRepositoryError.forgottenMemoryCannotBeChanged
        }
        memory.value = trimmedValue
        memory.stateRaw = MemoryState.active.rawValue
        memory.userVerified = true
        memory.sourceRank = 1_000
        memory.confidence = 1
        memory.updatedAt = Date()
        try context.save()
    }

    static func setPinned(
        _ memory: MemoryAssertionRecord,
        pinned: Bool,
        context: ModelContext
    ) throws {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let currentRoleID = memory.resolvedRoleID
        let tombstones = try fetchTombstones(
            forCanonicalKeys: [memory.canonicalKey],
            memoryIDs: [memory.id],
            roleID: currentRoleID,
            context: context
        )
        guard memory.state != .forgotten,
              memory.resolvedRoleID == currentRoleID,
              !isSuppressedByTombstone(memory, tombstones: tombstones) else {
            throw MemoryRepositoryError.forgottenMemoryCannotBeChanged
        }
        memory.isPinned = pinned
        memory.updatedAt = Date()
        try context.save()
    }

    static func forget(
        _ memory: MemoryAssertionRecord,
        context: ModelContext,
        deviceID: String
    ) throws {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let memoryID = memory.id
        let currentRoleID = memory.resolvedRoleID
        let includesLegacyNilRows = currentRoleID == RoleScope.legacyRoleID
        var currentDescriptor = FetchDescriptor<MemoryAssertionRecord>(
            predicate: #Predicate {
                $0.id == memoryID
                    && ($0.roleID == currentRoleID
                        || (includesLegacyNilRows
                            && $0.roleID == nil))
            },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse),
                SortDescriptor(\.canonicalKey),
                SortDescriptor(\.value)
            ]
        )
        currentDescriptor.fetchLimit = 1
        guard let current = try context.fetch(currentDescriptor).first else {
            // A stale row may have been removed by a merge. Forget is
            // intentionally idempotent and has no object to mutate in this
            // case, so it must not create a marker for a missing record.
            return
        }

        let tombstones = try fetchTombstones(
            forCanonicalKeys: [current.canonicalKey],
            memoryIDs: [memoryID],
            roleID: currentRoleID,
            context: context
        )
        guard current.state != .forgotten,
              current.resolvedRoleID == currentRoleID,
              !isSuppressedByTombstone(current, tombstones: tombstones) else {
            // Re-checking the persisted state and the relevant marker closes
            // the duplicate-forget path, including stale UI references.
            return
        }

        current.stateRaw = MemoryState.forgotten.rawValue
        current.value = ""
        current.embeddingData = nil
        current.embeddingModelID = nil
        current.userVerified = false
        current.isPinned = false
        current.updatedAt = Date()
        let sourceEventIDs = try deleteEvidenceAndCollectSourceEventIDs(
            memoryID: memoryID,
            roleID: currentRoleID,
            context: context
        )
        context.insert(MemoryTombstoneRecord(
            entityID: current.id,
            entityType: "memory",
            canonicalKey: normalizeKey(current.canonicalKey),
            sourceEventIDs: sourceEventIDs,
            deviceID: deviceID,
            roleID: currentRoleID
        ))
        try context.save()
    }

    /// Atomically forgets every long-term-memory projection owned by one role.
    /// Original conversation events are preserved, and the role-wide marker
    /// prevents delayed CloudKit/import copies from resurrecting old facts.
    @discardableResult
    static func forgetAll(
        roleID: UUID,
        context: ModelContext,
        deviceID: String
    ) throws -> Int {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let resolvedRoleID = RoleScope.resolve(roleID)
        let now = Date()
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
            .filter { $0.resolvedRoleID == resolvedRoleID }
        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
            .filter { $0.resolvedRoleID == resolvedRoleID }
        let summaries = try context.fetch(FetchDescriptor<MemorySummaryRecord>())
            .filter { $0.resolvedRoleID == resolvedRoleID }

        var sourceEventIDsByMemoryID: [UUID: Set<UUID>] = [:]
        for row in evidence {
            sourceEventIDsByMemoryID[row.memoryID, default: []].insert(row.eventID)
            context.delete(row)
        }

        var canonicalKeyByMemoryID: [UUID: String] = [:]
        for memory in memories {
            let key = normalizeKey(memory.canonicalKey)
            if canonicalKeyByMemoryID[memory.id] == nil || !key.isEmpty {
                canonicalKeyByMemoryID[memory.id] = key
            }
            memory.stateRaw = MemoryState.forgotten.rawValue
            memory.value = ""
            memory.embeddingData = nil
            memory.embeddingModelID = nil
            memory.userVerified = false
            memory.isPinned = false
            memory.updatedAt = now
        }

        for (memoryID, canonicalKey) in canonicalKeyByMemoryID {
            let marker = MemoryTombstoneRecord(
                entityID: memoryID,
                entityType: "memory",
                canonicalKey: canonicalKey,
                sourceEventIDs: Array(sourceEventIDsByMemoryID[memoryID] ?? [])
                    .sorted { $0.uuidString < $1.uuidString },
                deviceID: deviceID,
                reason: roleResetReason,
                roleID: resolvedRoleID
            )
            marker.deletedAt = now
            context.insert(marker)
        }

        let roleMarker = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "",
            sourceEventIDs: [],
            deviceID: deviceID,
            reason: roleResetReason,
            roleID: resolvedRoleID
        )
        roleMarker.deletedAt = now
        context.insert(roleMarker)

        for summary in summaries {
            summary.content = ""
            summary.firstEventID = nil
            summary.lastEventID = nil
            summary.coveredEventCount = 0
            summary.extractorID = roleResetReason
            summary.updatedAt = now
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return Set(memories.map(\.id)).count
    }

    /// Validates the durable owner of every source event before `apply` can
    /// create or update a role-scoped assertion.  The extraction response is
    /// untrusted: a model (or a stale caller) can name an event belonging to a
    /// different companion while supplying perfectly valid quote text.
    private static func validateSourceEvents(
        for candidates: [ExtractedMemoryCandidate],
        requestedRoleID: UUID?,
        targetRoleID: UUID,
        context: ModelContext
    ) throws -> [UUID: Date] {
        let sourceEventIDs = Set(candidates.map(\.sourceEventID))
        guard !sourceEventIDs.isEmpty else { return [:] }

        var eventsByID: [UUID: [ConversationEvent]] = [:]
        var sourceEvents: [ConversationEvent] = []
        for sourceEventID in sourceEventIDs {
            let descriptor = FetchDescriptor<ConversationEvent>(
                predicate: #Predicate {
                    $0.id == sourceEventID
                },
                sortBy: [
                    SortDescriptor(\.recordedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            let events = try context.fetch(descriptor)
            if events.isEmpty {
                // `roleID == nil` is the compatibility form used by old
                // extraction callers and unit fixtures.  It may not have a
                // row to look up yet, but cannot opt out of validation when a
                // row is present.  All explicit role calls fail closed.
                guard requestedRoleID == nil else {
                    throw MemoryRepositoryError.sourceEventNotFound(sourceEventID)
                }
                continue
            }
            eventsByID[sourceEventID] = events
            sourceEvents.append(contentsOf: events)
        }

        guard !sourceEvents.isEmpty else { return [:] }

        // Group turns intentionally use the shared user event as context for
        // each companion.  That event has the legacy role scope, while the
        // assistant event (and therefore the companion-owned source) carries
        // the target role.  Permit only that narrow, persisted group-user
        // shape; a group assistant from another role remains a hard mismatch.
        var authorizedGroupConversationIDs = Set<UUID>()
        let potentialGroupConversationIDs = Set(
            sourceEvents
                .filter {
                    $0.role == .user
                        && $0.senderRoleID == nil
                        && $0.resolvedRoleID == RoleScope.legacyRoleID
                        && $0.resolvedRoleID != targetRoleID
                }
                .map(\.conversationID)
        )
        for conversationID in potentialGroupConversationIDs {
            let groupDescriptor = FetchDescriptor<GroupConversationRecord>(
                predicate: #Predicate {
                    $0.conversationID == conversationID
                }
            )
            guard try context.fetch(groupDescriptor).contains(where: {
                $0.lifecycleRaw == GroupConversationLifecycle.active.rawValue
            }) else { continue }

            let participantDescriptor = FetchDescriptor<GroupParticipantRecord>(
                predicate: #Predicate {
                    $0.conversationID == conversationID
                }
            )
            guard try context.fetch(participantDescriptor).contains(where: {
                $0.participantKindRaw == GroupParticipantKind.companion.rawValue
                    && $0.lifecycleRaw == GroupConversationLifecycle.active.rawValue
                    && $0.leftAt == nil
                    && $0.participantRoleID.map(RoleScope.resolve) == targetRoleID
            }) else { continue }
            authorizedGroupConversationIDs.insert(conversationID)
        }

        for sourceEventID in sourceEventIDs {
            guard let events = eventsByID[sourceEventID] else { continue }
            guard !events.contains(where: \.redacted) else {
                throw MemoryRepositoryError.sourceEventRedacted(sourceEventID)
            }
            let matchingRole = events.filter {
                $0.resolvedRoleID == targetRoleID
            }
            let allowedGroupUsers = events.filter {
                $0.resolvedRoleID != targetRoleID
                    && $0.role == .user
                    && $0.senderRoleID == nil
                    && $0.resolvedRoleID == RoleScope.legacyRoleID
                    && authorizedGroupConversationIDs.contains($0.conversationID)
            }
            let mismatches = events.filter { event in
                event.resolvedRoleID != targetRoleID
                    && !allowedGroupUsers.contains(where: { $0 === event })
            }

            // A duplicated application ID with both a target-role row and a
            // legacy group-user row is ambiguous.  Reject it instead of
            // allowing the exception to mask a conflicting physical copy.
            guard mismatches.isEmpty,
                  matchingRole.isEmpty || allowedGroupUsers.isEmpty else {
                let actualRoleID = (mismatches.first ?? allowedGroupUsers.first)?.resolvedRoleID
                    ?? events.first?.resolvedRoleID
                    ?? RoleScope.legacyRoleID
                throw MemoryRepositoryError.sourceEventRoleMismatch(
                    sourceEventID: sourceEventID,
                    expectedRoleID: targetRoleID,
                    actualRoleID: actualRoleID
                )
            }
        }
        return eventsByID.mapValues { copies in
            copies.map(\.occurredAt).min() ?? .distantPast
        }
    }

    /// Fetches only physical records whose canonical key is represented by the
    /// current extraction batch. Equality predicates are deliberately issued
    /// per key variant instead of using a collection `contains` predicate: this
    /// keeps the query valid on the app's minimum iOS 17/macOS 14 runtimes and
    /// avoids turning a small batch into an unbounded table scan.
    private static func fetchMemories(
        forCanonicalKeys canonicalKeys: [String],
        roleID: UUID,
        context: ModelContext
    ) throws -> [MemoryAssertionRecord] {
        var recordsByID: [MemoryIdentity: MemoryAssertionRecord] = [:]
        let supersededRaw = MemoryState.superseded.rawValue
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        for key in queryValues(forCanonicalKeys: canonicalKeys) {
            var descriptor = FetchDescriptor<MemoryAssertionRecord>(
                predicate: #Predicate {
                    $0.canonicalKey == key
                        && $0.stateRaw != supersededRaw
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.stateRaw),
                    SortDescriptor(\.value),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            // Only live/candidate/conflict versions can influence a new
            // extraction. Superseded history stays durable but is not
            // materialized into this hot operation. The newest bounded window
            // is sufficient for the current active winner; a retraction's
            // canonical-key tombstone also suppresses any older overflow row.
            descriptor.fetchLimit = maximumLiveVersionsPerCanonicalKey
            for record in try context.fetch(descriptor) {
                let identity = MemoryIdentity(record)
                guard let existing = recordsByID[identity] else {
                    recordsByID[identity] = record
                    continue
                }
                // CloudKit can temporarily materialize duplicate physical
                // objects for one application UUID. Keep the newest object for
                // repository decisions while avoiding duplicate work when a
                // key variant matched the same object more than once.
                if memoryRecordIsPreferred(record, over: existing) {
                    recordsByID[identity] = record
                }
            }
        }
        return Array(recordsByID.values)
    }

    /// Fetches only tombstones that can suppress this batch. A key lookup
    /// covers normal records; an ID lookup also covers legacy markers that did
    /// not persist their canonical key.
    private static func fetchTombstones(
        forCanonicalKeys canonicalKeys: [String],
        memoryIDs: [UUID],
        roleID: UUID,
        context: ModelContext
    ) throws -> [MemoryTombstoneRecord] {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        var tombstonesByIdentity: [TombstoneIdentity: [MemoryTombstoneRecord]] = [:]
        let entityType = "memory"
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID

        for key in queryValues(forCanonicalKeys: canonicalKeys) {
            var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.entityType == entityType
                        && $0.canonicalKey == key
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\.deletedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            descriptor.fetchLimit = 1
            guard let newest = try context.fetch(descriptor).first else {
                continue
            }
            let newestDate = newest.deletedAt
            var tieDescriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.entityType == entityType
                        && $0.canonicalKey == key
                        && $0.deletedAt == newestDate
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\.deletedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            tieDescriptor.propertiesToFetch = [
                \MemoryTombstoneRecord.id,
                \MemoryTombstoneRecord.entityID,
                \MemoryTombstoneRecord.entityType,
                \MemoryTombstoneRecord.canonicalKey,
                \MemoryTombstoneRecord.canonicalKeyNormalizationVersion,
                \MemoryTombstoneRecord.roleID,
                \MemoryTombstoneRecord.sourceEventIDsRaw,
                \MemoryTombstoneRecord.deletedAt,
                \MemoryTombstoneRecord.deviceID,
                \MemoryTombstoneRecord.reason
            ]
            for tombstone in try context.fetch(tieDescriptor) {
                appendNewest(tombstone, to: &tombstonesByIdentity)
            }
        }

        for memoryID in Set(memoryIDs) {
            let descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.entityType == entityType
                        && $0.entityID == memoryID
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\.deletedAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            // A memory ID can have physically conflicting copies with
            // different canonical keys. Read this narrow identity scope in
            // full so an older key is not discarded merely because another
            // conflicting copy has a newer timestamp.
            for tombstone in try context.fetch(descriptor) {
                appendNewest(tombstone, to: &tombstonesByIdentity)
            }
        }
        for legacy in try fetchLegacyGlobalTombstones(
            roleID: roleID,
            context: context
        ) {
            appendNewest(legacy, to: &tombstonesByIdentity)
        }
        return tombstonesByIdentity.values
            .flatMap { $0 }
            .sorted {
                if $0.deletedAt != $1.deletedAt {
                    return $0.deletedAt > $1.deletedAt
                }
                if $0.id != $1.id {
                    return $0.id.uuidString < $1.id.uuidString
                }
                let lhsKey = normalizeKey($0.canonicalKey)
                let rhsKey = normalizeKey($1.canonicalKey)
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                return $0.entityID.uuidString < $1.entityID.uuidString
            }
    }

    /// The durable normalizer has converted every legacy whitespace spelling
    /// to the empty key before repository work begins. This exact newest-row
    /// query is therefore complete and remains constant-memory.
    private static func fetchLegacyGlobalTombstones(
        roleID: UUID,
        context: ModelContext
    ) throws -> [MemoryTombstoneRecord] {
        try MemoryTombstoneNormalizer.requireComplete(context: context)
        let entityType = "memory"
        let emptyKey = ""
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && $0.canonicalKey == emptyKey
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
            },
            sortBy: [
                SortDescriptor(\.deletedAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        guard let newest = try context.fetch(descriptor).first else {
            return []
        }
        let newestDate = newest.deletedAt
        var tieDescriptor = FetchDescriptor<MemoryTombstoneRecord>(
            predicate: #Predicate {
                $0.entityType == entityType
                    && $0.canonicalKey == emptyKey
                    && $0.deletedAt == newestDate
                    && ($0.roleID == roleID
                        || (includesLegacyNilRows && $0.roleID == nil))
            },
            sortBy: [
                SortDescriptor(\.deletedAt, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        tieDescriptor.propertiesToFetch = [
            \MemoryTombstoneRecord.id,
            \MemoryTombstoneRecord.entityID,
            \MemoryTombstoneRecord.entityType,
            \MemoryTombstoneRecord.canonicalKey,
            \MemoryTombstoneRecord.canonicalKeyNormalizationVersion,
            \MemoryTombstoneRecord.roleID,
            \MemoryTombstoneRecord.sourceEventIDsRaw,
            \MemoryTombstoneRecord.deletedAt,
            \MemoryTombstoneRecord.deviceID,
            \MemoryTombstoneRecord.reason
        ]
        return try context.fetch(tieDescriptor)
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): return max(lhs, rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }

    /// Evidence is keyed by application-level memory ID, so each query stays
    /// bounded to the records that the current batch may update or retract.
    private static func fetchEvidence(
        forMemoryIDs memoryIDs: [UUID],
        roleID: UUID,
        context: ModelContext
    ) throws -> [MemoryEvidenceRecord] {
        var evidenceByID: [UUID: MemoryEvidenceRecord] = [:]
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
        for memoryID in Set(memoryIDs) {
            var descriptor = FetchDescriptor<MemoryEvidenceRecord>(
                predicate: #Predicate {
                    $0.memoryID == memoryID
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .reverse),
                    SortDescriptor(\.id, order: .reverse)
                ]
            )
            descriptor.fetchLimit = maximumEvidencePerMemoryOperation
            for evidence in try context.fetch(descriptor) {
                evidenceByID[evidence.id] = evidence
            }
        }
        return Array(evidenceByID.values)
    }

    /// Forget must remove every derived evidence row, not merely the hot
    /// operation window used while applying candidates. Delete in keyset pages
    /// so a heavily corroborated fact does not materialize its entire evidence
    /// history at once; only the compact source-event UUID set is retained for
    /// the durable tombstone audit trail.
    private static func deleteEvidenceAndCollectSourceEventIDs(
        memoryID: UUID,
        roleID: UUID,
        context: ModelContext
    ) throws -> [UUID] {
        let pageSize = 128
        var cursorDate: Date?
        var cursorID: UUID?
        var sourceEventIDs = Set<UUID>()
        let includesLegacyNilRows = roleID == RoleScope.legacyRoleID

        while true {
            let sortBy = [
                SortDescriptor(\MemoryEvidenceRecord.createdAt, order: .reverse),
                SortDescriptor(\MemoryEvidenceRecord.id, order: .reverse)
            ]
            var descriptor: FetchDescriptor<MemoryEvidenceRecord>
            if let cursorDate, let cursorID {
                descriptor = FetchDescriptor(
                    predicate: #Predicate {
                        $0.memoryID == memoryID
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                            && ($0.createdAt < cursorDate
                                || ($0.createdAt == cursorDate && $0.id < cursorID))
                    },
                    sortBy: sortBy
                )
            } else {
                descriptor = FetchDescriptor(
                    predicate: #Predicate {
                        $0.memoryID == memoryID
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                    },
                    sortBy: sortBy
                )
            }
            descriptor.fetchLimit = pageSize
            descriptor.propertiesToFetch = [
                \MemoryEvidenceRecord.id,
                \MemoryEvidenceRecord.memoryID,
                \MemoryEvidenceRecord.eventID,
                \MemoryEvidenceRecord.createdAt
            ]
            let page = try context.fetch(descriptor)
            guard !page.isEmpty else { break }

            // If the page ends at a physical duplicate key, consume the
            // complete boundary group before advancing the cursor. Otherwise
            // the strict keyset predicate would exclude all remaining copies
            // of that same `(createdAt,id)` pair.
            var boundaryGroup: [MemoryEvidenceRecord] = []
            if page.count == pageSize, let last = page.last {
                let boundaryDate = last.createdAt
                let boundaryID = last.id
                var boundaryDescriptor = FetchDescriptor<MemoryEvidenceRecord>(
                    predicate: #Predicate {
                        $0.memoryID == memoryID
                            && $0.createdAt == boundaryDate
                            && $0.id == boundaryID
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                    },
                    sortBy: sortBy
                )
                boundaryDescriptor.propertiesToFetch = [
                    \MemoryEvidenceRecord.id,
                    \MemoryEvidenceRecord.memoryID,
                    \MemoryEvidenceRecord.eventID,
                    \MemoryEvidenceRecord.createdAt
                ]
                boundaryGroup = try context.fetch(boundaryDescriptor)
            }

            var deletedObjects = Set<ObjectIdentifier>()
            for evidence in page + boundaryGroup {
                guard deletedObjects.insert(ObjectIdentifier(evidence)).inserted else {
                    continue
                }
                sourceEventIDs.insert(evidence.eventID)
                context.delete(evidence)
            }
            guard let last = page.last else { break }
            cursorDate = last.createdAt
            cursorID = last.id
            if page.count < pageSize { break }
        }

        return sourceEventIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private static func queryValues(forCanonicalKeys canonicalKeys: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for key in canonicalKeys {
            for variant in canonicalKeyVariants(key) where seen.insert(variant).inserted {
                result.append(variant)
            }
        }
        return result
    }

    private static func canonicalKeyVariants(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = MemoryTombstoneRecord.normalizedCanonicalKey(value)
        // The raw spellings keep already-persisted legacy rows discoverable,
        // while the strong normalized spelling is mandatory for current rows.
        // In particular, a candidate containing FEFF/ZWSP/format/control
        // scalars must still query a normalized tombstone before suppression
        // is evaluated.
        return [normalized, value, trimmed, trimmed.lowercased(), trimmed.uppercased()]
            .reduce(into: [String]()) { result, candidate in
                if !result.contains(candidate) {
                    result.append(candidate)
                }
            }
    }

    private static func appendNewest(
        _ tombstone: MemoryTombstoneRecord,
        to tombstonesByIdentity: inout [TombstoneIdentity: [MemoryTombstoneRecord]]
    ) {
        let identity = TombstoneIdentity(tombstone)
        var records = tombstonesByIdentity[identity] ?? []
        guard !records.contains(where: { $0 === tombstone }) else {
            return
        }

        if let newestDate = records.map(\.deletedAt).max() {
            if tombstone.deletedAt < newestDate {
                return
            }
            if tombstone.deletedAt > newestDate {
                records.removeAll(keepingCapacity: true)
            }
        }
        // Equal-time physical copies are retained rather than first-wins:
        // their source-event and suppression metadata may differ.
        records.append(tombstone)
        tombstonesByIdentity[identity] = records
    }

    private struct MemoryIdentity: Hashable {
        let id: UUID
        let roleID: UUID

        init(_ memory: MemoryAssertionRecord) {
            id = memory.id
            roleID = memory.resolvedRoleID
        }
    }

    private struct TombstoneIdentity: Hashable {
        let id: UUID
        let entityID: UUID
        let entityType: String
        let canonicalKey: String
        let roleID: UUID

        init(_ tombstone: MemoryTombstoneRecord) {
            id = tombstone.id
            entityID = tombstone.entityID
            entityType = tombstone.entityType
            canonicalKey = MemoryTombstoneRecord.normalizedCanonicalKey(
                tombstone.canonicalKey
            )
            roleID = tombstone.resolvedRoleID
        }
    }

    private static func memoryRecordIsPreferred(
        _ candidate: MemoryAssertionRecord,
        over current: MemoryAssertionRecord
    ) -> Bool {
        let candidateForgotten = candidate.state == .forgotten
        let currentForgotten = current.state == .forgotten
        if candidateForgotten != currentForgotten {
            // Forgetting is a durable privacy decision.  It dominates every
            // wall-clock/version signal so a newer active copy cannot revive
            // the same application UUID.
            return candidateForgotten
        }
        if candidate.updatedAt != current.updatedAt {
            return candidate.updatedAt > current.updatedAt
        }
        if candidate.userVerified != current.userVerified {
            return candidate.userVerified
        }
        if candidate.sourceRank != current.sourceRank {
            return candidate.sourceRank > current.sourceRank
        }
        return memoryRecordStableKey(candidate) > memoryRecordStableKey(current)
    }

    private static func memoryRecordStableKey(_ record: MemoryAssertionRecord) -> String {
        [
            stableString(record.kindRaw),
            stableString(record.subject),
            stableString(record.predicate),
            stableString(record.value),
            stableString(normalizeKey(record.canonicalKey)),
            stableString(record.stateRaw),
            String(record.confidence.bitPattern, radix: 16),
            String(record.importance.bitPattern, radix: 16),
            record.sensitive ? "1" : "0",
            String(record.sourceRank),
            record.validFrom.map(stableDate) ?? "-",
            record.validTo.map(stableDate) ?? "-",
            String(record.observedAt.timeIntervalSince1970.bitPattern, radix: 16),
            record.supersedesID?.uuidString.lowercased() ?? "-",
            stableString(record.extractorID),
            String(record.schemaVersion),
            String(record.createdAt.timeIntervalSince1970.bitPattern, radix: 16),
            String(record.updatedAt.timeIntervalSince1970.bitPattern, radix: 16),
            record.isPinned ? "1" : "0",
            record.userVerified ? "1" : "0",
            record.embeddingData?.base64EncodedString() ?? "",
            record.embeddingModelID ?? "",
            stableString(record.deviceID),
            record.id.uuidString.lowercased()
        ].joined(separator: "|")
    }

    private static func stableString(_ value: String) -> String {
        // Fixed-width UTF-8 hex is both unambiguous and lexicographically
        // ordered by content. Prefixing the byte count made shorter strings
        // sort below longer ones before their actual value was considered,
        // contradicting the deterministic tie-break contract.
        value.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private static func stableDate(_ value: Date) -> String {
        String(value.timeIntervalSince1970.bitPattern, radix: 16)
    }

    private static func appendUnique(
        _ tombstone: MemoryTombstoneRecord,
        to tombstones: inout [MemoryTombstoneRecord]
    ) {
        guard !tombstones.contains(where: {
            $0.id == tombstone.id
                && $0.resolvedRoleID == tombstone.resolvedRoleID
        }) else { return }
        tombstones.append(tombstone)
    }

    private static func sourceRank(for candidate: ExtractedMemoryCandidate) -> Int {
        if candidate.explicit && candidate.subject == "user" { return 300 }
        if candidate.subject == "companion" && candidate.kind == .commitment { return 240 }
        return 100
    }

    private static func userForgetDatesByCanonicalKey(
        tombstones: [MemoryTombstoneRecord],
        memories: [MemoryAssertionRecord]
    ) -> [String: Date] {
        // `id` is an application-level sync identifier, not SwiftData's backing
        // identity. A malformed or concurrently merged store must not trap here.
        var memoriesByID: [UUID: MemoryAssertionRecord] = [:]
        for memory in memories {
            if let existing = memoriesByID[memory.id] {
                guard memoryRecordIsPreferred(memory, over: existing) else { continue }
            }
            memoriesByID[memory.id] = memory
        }
        var result: [String: Date] = [:]
        for tombstone in tombstones
        where tombstone.entityType == "memory"
            && tombstone.reason != roleResetReason {
            let storedKey = normalizeKey(tombstone.canonicalKey)
            let legacyKey = memoriesByID[tombstone.entityID].map { normalizeKey($0.canonicalKey) } ?? ""
            let key = storedKey.isEmpty ? legacyKey : storedKey
            guard !key.isEmpty else { continue }
            result[key] = max(result[key] ?? .distantPast, tombstone.deletedAt)
        }
        return result
    }

    private static func normalizeKey(_ value: String) -> String {
        MemoryTombstoneRecord.normalizedCanonicalKey(value)
    }

    /// Tombstones are the final privacy barrier for stale CloudKit objects. An
    /// exact deleted version is always suppressed; older versions of the same
    /// logical fact are suppressed until a genuinely new post-tombstone record
    /// is created from a later explicit user statement.
    static func isSuppressedByTombstone(
        _ memory: MemoryAssertionRecord,
        tombstones: [MemoryTombstoneRecord]
    ) -> Bool {
        let key = normalizeKey(memory.canonicalKey)
        return tombstones.contains { tombstone in
            guard tombstone.entityType == "memory" else { return false }
            guard memory.resolvedRoleID == tombstone.resolvedRoleID else {
                return false
            }
            if tombstone.entityID == memory.id { return true }
            let tombstoneKey = normalizeKey(tombstone.canonicalKey)
            if tombstoneKey.isEmpty {
                return memory.createdAt <= tombstone.deletedAt
            }
            return !key.isEmpty
                && !tombstoneKey.isEmpty
                && key == tombstoneKey
                && memory.createdAt <= tombstone.deletedAt
        }
    }

    static func eligibleMemories(
        from records: [MemoryAssertionRecord],
        tombstones: [MemoryTombstoneRecord],
        roleID: UUID? = nil
    ) -> [MemoryAssertionRecord] {
        let resolvedRoleID = roleID.map { RoleScope.resolve($0) }
        var winners: [MemoryIdentity: MemoryAssertionRecord] = [:]
        for memory in records where resolvedRoleID == nil || memory.resolvedRoleID == resolvedRoleID {
            let identity = MemoryIdentity(memory)
            if let current = winners[identity] {
                if memoryRecordIsPreferred(memory, over: current) {
                    winners[identity] = memory
                }
            } else {
                winners[identity] = memory
            }
        }
        return winners.values.filter { memory in
            memory.state != .forgotten
                && !isSuppressedByTombstone(memory, tombstones: tombstones)
        }.sorted { memoryRecordStableKey($0) < memoryRecordStableKey($1) }
    }

    /// Keep the persisted representation of a forgotten assertion empty even
    /// when an old physical copy still carries derived or user-visible data.
    @discardableResult
    private static func scrubForgottenMemory(
        _ memory: MemoryAssertionRecord
    ) -> Bool {
        guard memory.state == .forgotten else { return false }
        var changed = false
        if !memory.value.isEmpty {
            memory.value = ""
            changed = true
        }
        if memory.embeddingData != nil {
            memory.embeddingData = nil
            changed = true
        }
        if memory.embeddingModelID != nil {
            memory.embeddingModelID = nil
            changed = true
        }
        if memory.userVerified {
            memory.userVerified = false
            changed = true
        }
        if memory.isPinned {
            memory.isPinned = false
            changed = true
        }
        return changed
    }

    @discardableResult
    private static func insertEvidenceIfNeeded(
        memoryID: UUID,
        candidate: ExtractedMemoryCandidate,
        eventContent: String,
        quoteRange: Range<String.Index>,
        roleID: UUID,
        evidence: inout [MemoryEvidenceRecord],
        context: ModelContext
    ) -> Bool {
        let utf16 = eventContent.utf16
        let start = quoteRange.lowerBound.samePosition(in: utf16).map {
            utf16.distance(from: utf16.startIndex, to: $0)
        } ?? 0
        let end = quoteRange.upperBound.samePosition(in: utf16).map {
            utf16.distance(from: utf16.startIndex, to: $0)
        } ?? start
        let relation: EvidenceRelation = candidate.operation == .retract ? .contradicts : .supports
        let quoteHash = ContentHasher.sha256(candidate.sourceQuote)
        if let existing = evidence.first(where: {
            $0.memoryID == memoryID
                && $0.resolvedRoleID == roleID
                && $0.eventID == candidate.sourceEventID
                && $0.startUTF16 == start
                && $0.endUTF16 == end
                && $0.relationRaw == relation.rawValue
                && $0.quoteHash == quoteHash
        }) {
            guard candidate.confidence > existing.confidence else { return false }
            existing.confidence = candidate.confidence
            return true
        }

        let record = MemoryEvidenceRecord(
            memoryID: memoryID,
            eventID: candidate.sourceEventID,
            startUTF16: start,
            endUTF16: end,
            relation: relation,
            quoteHash: quoteHash,
            confidence: candidate.confidence,
            roleID: roleID
        )
        context.insert(record)
        evidence.append(record)
        return true
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined()
    }
}
