import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class StoreDuplicateReconcilerTests: XCTestCase {
    private struct FixtureIDs {
        let conversation: UUID
        let event: UUID
        let memory: UUID
        let evidence: UUID
        let summary: UUID
        let tombstone: UUID
        let uniqueConversation: UUID
        let uniqueEvent: UUID
        let uniqueMemory: UUID
        let uniqueEvidence: UUID
        let uniqueSummary: UUID
        let uniqueTombstone: UUID
    }

    private func makeContext() -> ModelContext {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        return ModelContext(bootstrap.container)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func id(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }

    private func makeProfile(
        id profileID: UUID = CompanionProfileRecord.singletonID,
        name: String = "绫音",
        userName: String = "你",
        prompt: String = "保持坦诚",
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 1),
        revision: Int = 0,
        deviceID: String = "fixture-device"
    ) -> CompanionProfileRecord {
        CompanionProfileRecord(
            id: profileID,
            name: name,
            userName: userName,
            prompt: prompt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision,
            deviceID: deviceID
        )
    }

    private func makeRelationship(
        id relationshipID: UUID,
        roleID: UUID,
        affinityScore: Double,
        manualAffinityScore: Double?,
        manualAffinityUpdatedAt: Date?,
        updatedAt: Date,
        revision: Int,
        deviceID: String
    ) -> CompanionRelationshipRecord {
        CompanionRelationshipRecord(
            id: relationshipID,
            roleID: roleID,
            state: .accepted,
            affinityScore: affinityScore,
            affinityTier: 1,
            manualAffinityScore: manualAffinityScore,
            manualAffinityUpdatedAt: manualAffinityUpdatedAt,
            createdAt: date(0),
            updatedAt: updatedAt,
            revision: revision,
            deviceID: deviceID
        )
    }

    private func makeEvent(
        id eventID: UUID,
        conversationID: UUID,
        content: String = "原始事件",
        contentHash: String? = nil,
        deliveryState: EventDeliveryState = .streaming
    ) -> ConversationEvent {
        ConversationEvent(
            id: eventID,
            conversationID: conversationID,
            deviceID: "fixture-device",
            deviceSequence: 7,
            logicalTimestamp: "7-fixture-device-7",
            occurredAt: date(100),
            role: .user,
            content: content,
            contentHash: contentHash ?? ContentHasher.sha256(content),
            deliveryState: deliveryState
        )
    }

    private func makeMemory(
        id memoryID: UUID,
        value: String,
        state: MemoryState = .active,
        sourceRank: Int = 10,
        confidence: Double = 0.5,
        importance: Double = 0.5
    ) -> MemoryAssertionRecord {
        MemoryAssertionRecord(
            id: memoryID,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: value,
            canonicalKey: "user.favorite_drink",
            state: state,
            confidence: confidence,
            importance: importance,
            sensitive: false,
            sourceRank: sourceRank,
            extractorID: "fixture",
            deviceID: "fixture-device"
        )
    }

    private func insertCompleteFixture(in context: ModelContext) throws -> FixtureIDs {
        let ids = FixtureIDs(
            conversation: id("00000000-0000-0000-0000-000000000101"),
            event: id("00000000-0000-0000-0000-000000000102"),
            memory: id("00000000-0000-0000-0000-000000000103"),
            evidence: id("00000000-0000-0000-0000-000000000104"),
            summary: id("00000000-0000-0000-0000-000000000105"),
            tombstone: id("00000000-0000-0000-0000-000000000106"),
            uniqueConversation: id("00000000-0000-0000-0000-000000000201"),
            uniqueEvent: id("00000000-0000-0000-0000-000000000202"),
            uniqueMemory: id("00000000-0000-0000-0000-000000000203"),
            uniqueEvidence: id("00000000-0000-0000-0000-000000000204"),
            uniqueSummary: id("00000000-0000-0000-0000-000000000205"),
            uniqueTombstone: id("00000000-0000-0000-0000-000000000206")
        )

        let oldConversation = ConversationRecord(
            id: ids.conversation,
            title: "旧标题",
            createdAt: date(100)
        )
        oldConversation.updatedAt = date(200)
        let newConversation = ConversationRecord(
            id: ids.conversation,
            title: "新标题",
            createdAt: date(150)
        )
        newConversation.updatedAt = date(300)
        newConversation.archived = true

        let oldEvent = makeEvent(id: ids.event, conversationID: ids.conversation)
        oldEvent.recordedAt = date(110)
        oldEvent.redacted = false
        oldEvent.memoryProcessedAt = date(120)
        oldEvent.memoryProcessingVersion = 1

        let newEvent = makeEvent(
            id: ids.event,
            conversationID: ids.conversation,
            deliveryState: .complete
        )
        // A JSON round-trip can quantize this timestamp without changing the
        // event's immutable identity or body.
        newEvent.occurredAt = date(100.000001)
        newEvent.recordedAt = date(130)
        newEvent.redacted = true
        newEvent.memoryProcessedAt = date(140)
        newEvent.memoryProcessingVersion = 2

        let oldMemory = makeMemory(
            id: ids.memory,
            value: "咖啡",
            sourceRank: 10,
            confidence: 0.70,
            importance: 0.40
        )
        oldMemory.createdAt = date(100)
        oldMemory.updatedAt = date(200)
        oldMemory.sensitive = true
        oldMemory.isPinned = true
        let fixtureEmbedding = MemoryEmbeddingCodec.encode([0.1, 0.2, 0.3])
        oldMemory.embeddingData = fixtureEmbedding
        oldMemory.embeddingModelID = "fixture-embedding"

        let newMemory = makeMemory(
            id: ids.memory,
            value: "乌龙茶",
            sourceRank: 20,
            confidence: 0.90,
            importance: 0.80
        )
        newMemory.createdAt = date(150)
        newMemory.updatedAt = date(300)
        newMemory.userVerified = true

        let oldEvidence = MemoryEvidenceRecord(
            id: ids.evidence,
            memoryID: ids.memory,
            eventID: ids.event,
            startUTF16: 0,
            endUTF16: 3,
            relation: .supports,
            quoteHash: ContentHasher.sha256("原始事"),
            confidence: 0.40
        )
        oldEvidence.createdAt = date(210)
        let newEvidence = MemoryEvidenceRecord(
            id: ids.evidence,
            memoryID: ids.memory,
            eventID: ids.event,
            startUTF16: 0,
            endUTF16: 3,
            relation: .supports,
            quoteHash: ContentHasher.sha256("原始事"),
            confidence: 0.90
        )
        newEvidence.createdAt = date(220)

        let oldSummary = MemorySummaryRecord(
            conversationID: ids.conversation,
            scope: "session",
            content: "旧摘要",
            firstEventID: ids.event,
            lastEventID: ids.event,
            coveredEventCount: 1,
            extractorID: "fixture"
        )
        oldSummary.id = ids.summary
        oldSummary.createdAt = date(210)
        oldSummary.updatedAt = date(220)
        let newSummary = MemorySummaryRecord(
            conversationID: ids.conversation,
            scope: "session",
            content: "新摘要",
            firstEventID: ids.event,
            lastEventID: ids.event,
            coveredEventCount: 2,
            extractorID: "fixture"
        )
        newSummary.id = ids.summary
        newSummary.createdAt = date(230)
        newSummary.updatedAt = date(320)

        let oldTombstone = MemoryTombstoneRecord(
            entityID: ids.memory,
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            sourceEventIDs: [ids.event],
            deviceID: "fixture-device",
            reason: "fixture"
        )
        oldTombstone.id = ids.tombstone
        oldTombstone.deletedAt = date(400)
        let newTombstone = MemoryTombstoneRecord(
            entityID: ids.memory,
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            sourceEventIDs: [ids.uniqueEvent],
            deviceID: "fixture-device",
            reason: "fixture"
        )
        newTombstone.id = ids.tombstone
        newTombstone.deletedAt = date(500)

        let uniqueConversation = ConversationRecord(
            id: ids.uniqueConversation,
            title: "独立会话",
            createdAt: date(10)
        )
        let uniqueEvent = makeEvent(
            id: ids.uniqueEvent,
            conversationID: ids.uniqueConversation,
            content: "独立事件",
            deliveryState: .complete
        )
        uniqueEvent.recordedAt = date(11)
        let uniqueMemory = makeMemory(id: ids.uniqueMemory, value: "独立记忆")
        // Keep the independent fixture logically independent as well. Import
        // validation rejects two active memories with one canonical key.
        uniqueMemory.canonicalKey = "user.independent"
        let uniqueEvidence = MemoryEvidenceRecord(
            id: ids.uniqueEvidence,
            memoryID: ids.uniqueMemory,
            eventID: ids.uniqueEvent,
            startUTF16: 0,
            endUTF16: 1,
            relation: .supports,
            quoteHash: ContentHasher.sha256("独"),
            confidence: 0.5
        )
        let uniqueSummary = MemorySummaryRecord(
            conversationID: ids.uniqueConversation,
            scope: "session",
            content: "独立摘要",
            firstEventID: ids.uniqueEvent,
            lastEventID: ids.uniqueEvent,
            coveredEventCount: 1,
            extractorID: "fixture"
        )
        uniqueSummary.id = ids.uniqueSummary
        let uniqueTombstone = MemoryTombstoneRecord(
            entityID: ids.uniqueMemory,
            entityType: "memory",
            canonicalKey: "user.independent",
            deviceID: "fixture-device",
            reason: "fixture"
        )
        uniqueTombstone.id = ids.uniqueTombstone

        for model in [oldConversation, newConversation, uniqueConversation] {
            context.insert(model)
        }
        for model in [oldEvent, newEvent, uniqueEvent] {
            context.insert(model)
        }
        for model in [oldMemory, newMemory, uniqueMemory] {
            context.insert(model)
        }
        for model in [oldEvidence, newEvidence, uniqueEvidence] {
            context.insert(model)
        }
        for model in [oldSummary, newSummary, uniqueSummary] {
            context.insert(model)
        }
        for model in [oldTombstone, newTombstone, uniqueTombstone] {
            context.insert(model)
        }
        try context.save()
        return ids
    }

    func testReconcilesEveryEntityAndLeavesIndependentIDsUntouched() throws {
        let context = makeContext()
        let ids = try insertCompleteFixture(in: context)

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.total, 11)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).count, 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationEvent>()).count, 3)

        let result = try StoreDuplicateReconciler.reconcile(context: context)

        XCTAssertEqual(result, preflight)
        XCTAssertEqual(result.conversations, .init(removed: 1, updated: 1))
        XCTAssertEqual(result.events, .init(removed: 1, updated: 1))
        XCTAssertEqual(result.memories, .init(removed: 1, updated: 1))
        XCTAssertEqual(result.evidence, .init(removed: 1, updated: 1))
        XCTAssertEqual(result.summaries, .init(removed: 1, updated: 0))
        XCTAssertEqual(result.tombstones, .init(removed: 1, updated: 1))
        XCTAssertEqual(result.totalRemoved, 6)
        XCTAssertEqual(result.totalUpdated, 5)
        XCTAssertEqual(result.total, 11)

        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        XCTAssertEqual(conversations.count, 2)
        let conversation = try XCTUnwrap(conversations.first { $0.id == ids.conversation })
        XCTAssertEqual(conversation.title, "新标题")
        XCTAssertEqual(conversation.createdAt, date(100))
        XCTAssertEqual(conversation.updatedAt, date(300))
        XCTAssertTrue(conversation.archived)
        XCTAssertEqual(conversations.first { $0.id == ids.uniqueConversation }?.title, "独立会话")

        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertEqual(events.count, 2)
        let event = try XCTUnwrap(events.first { $0.id == ids.event })
        XCTAssertEqual(event.occurredAt, date(100))
        XCTAssertEqual(event.recordedAt, date(110))
        XCTAssertTrue(event.redacted)
        XCTAssertEqual(event.memoryProcessedAt, date(140))
        XCTAssertEqual(event.memoryProcessingVersion, 2)
        XCTAssertEqual(event.deliveryState, .complete)
        XCTAssertEqual(events.first { $0.id == ids.uniqueEvent }?.content, "独立事件")

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        let memory = try XCTUnwrap(memories.first { $0.id == ids.memory })
        XCTAssertEqual(memory.value, "乌龙茶")
        XCTAssertEqual(memory.createdAt, date(100))
        XCTAssertEqual(memory.updatedAt, date(300))
        XCTAssertEqual(memory.confidence, 0.90)
        XCTAssertEqual(memory.importance, 0.80)
        XCTAssertTrue(memory.sensitive)
        XCTAssertTrue(memory.isPinned)
        XCTAssertTrue(memory.userVerified)
        XCTAssertEqual(memory.embeddingData, MemoryEmbeddingCodec.encode([0.1, 0.2, 0.3]))
        XCTAssertEqual(memory.embeddingModelID, "fixture-embedding")
        XCTAssertEqual(memories.first { $0.id == ids.uniqueMemory }?.value, "独立记忆")

        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(evidence.first { $0.id == ids.evidence }?.confidence, 0.90)
        XCTAssertEqual(
            evidence.first { $0.id == ids.uniqueEvidence }?.quoteHash,
            ContentHasher.sha256("独")
        )

        let summaries = try context.fetch(FetchDescriptor<MemorySummaryRecord>())
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.first { $0.id == ids.summary }?.content, "新摘要")
        XCTAssertEqual(summaries.first { $0.id == ids.uniqueSummary }?.content, "独立摘要")

        let tombstones = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(tombstones.count, 2)
        let tombstone = try XCTUnwrap(tombstones.first { $0.id == ids.tombstone })
        XCTAssertEqual(tombstone.deletedAt, date(500))
        XCTAssertEqual(
            Set(tombstone.sourceEventIDs),
            Set([
                ids.event,
                ids.uniqueEvent
            ])
        )
        XCTAssertEqual(tombstones.first { $0.id == ids.uniqueTombstone }?.canonicalKey, "user.independent")
    }

    func testSecondReconcileIsIdempotent() throws {
        let context = makeContext()
        _ = try insertCompleteFixture(in: context)

        _ = try StoreDuplicateReconciler.reconcile(context: context)
        let second = try StoreDuplicateReconciler.reconcile(context: context)

        XCTAssertEqual(second, StoreDuplicateReconcileSummary())
        XCTAssertTrue(second.isNoOp)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationEvent>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemorySummaryRecord>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count, 2)
    }

    func testCanonicalPayloadExportsWithoutChangingSource() throws {
        let context = makeContext()
        _ = try insertCompleteFixture(in: context)

        let beforeEvents = try context.fetch(FetchDescriptor<ConversationEvent>()).count
        let payload = try StoreDuplicateReconciler.makeCanonicalPayload(context: context)
        try DataImportService.validate(payload)
        XCTAssertLessThan(payload.events.count, beforeEvents)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationEvent>()).count,
            beforeEvents,
            "Source canonicalization must remain read-only after rollback."
        )
    }

    func testProfilePhysicalDuplicatesConvergeByLogicalVersion() throws {
        let context = makeContext()
        let older = makeProfile(
            name: "旧 Persona",
            updatedAt: date(200),
            revision: 1,
            deviceID: "z-device"
        )
        let newer = makeProfile(
            name: "新 Persona",
            updatedAt: date(100),
            revision: 2,
            deviceID: "a-device"
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.profiles, .init(removed: 1, updated: 0))
        let result = try StoreDuplicateReconciler.reconcile(context: context)
        XCTAssertEqual(result.profiles, .init(removed: 1, updated: 0))

        let remaining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>()).first
        )
        XCTAssertEqual(remaining.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(remaining.name, "新 Persona")
        XCTAssertEqual(remaining.revision, 2)
        XCTAssertEqual(remaining.deviceID, "a-device")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CompanionProfileRecord>()).count, 1)
        XCTAssertTrue(try StoreDuplicateReconciler.reconcile(context: context).isNoOp)
    }

    func testProfileEqualMetadataUsesContentFingerprintIndependentlyOfFetchOrder() throws {
        let context = makeContext()
        let first = makeProfile(
            name: "内容 A",
            updatedAt: date(200),
            revision: 3,
            deviceID: "same-device"
        )
        let second = makeProfile(
            name: "内容 B",
            updatedAt: date(200),
            revision: 3,
            deviceID: "same-device"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let expectedName = CompanionProfileService.canonicalContentFingerprint(first)
            > CompanionProfileService.canonicalContentFingerprint(second)
            ? first.name
            : second.name
        _ = try StoreDuplicateReconciler.reconcile(context: context)
        let remaining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>()).first
        )
        XCTAssertEqual(remaining.name, expectedName)
        XCTAssertEqual(try StoreDuplicateReconciler.reconcile(context: context), StoreDuplicateReconcileSummary())
    }

    func testIndependentRoleProfileIDIsValidAndPreserved() throws {
        let context = makeContext()
        let roleID = id("00000000-0000-0000-0000-000000001301")
        context.insert(makeProfile(id: roleID, name: "独立角色"))
        try context.save()

        XCTAssertTrue(try StoreDuplicateReconciler.reconcile(context: context).isNoOp)
        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, roleID)
        XCTAssertEqual(profiles.first?.name, "独立角色")
    }

    func testRelationshipDuplicatesKeepLatestManualAffinityStreamIndependentOfRowWinner() throws {
        let context = makeContext()
        let roleID = id("00000000-0000-0000-0000-000000001331")
        let rowWinner = makeRelationship(
            id: id("00000000-0000-0000-0000-000000001332"),
            roleID: roleID,
            affinityScore: 12,
            manualAffinityScore: 42,
            manualAffinityUpdatedAt: date(100),
            updatedAt: date(300),
            revision: 9,
            deviceID: "row-winner"
        )
        let manualWinner = makeRelationship(
            id: id("00000000-0000-0000-0000-000000001333"),
            roleID: roleID,
            affinityScore: 98,
            manualAffinityScore: 88,
            manualAffinityUpdatedAt: date(400),
            updatedAt: date(100),
            revision: 1,
            deviceID: "manual-winner"
        )
        let clearWinner = makeRelationship(
            id: id("00000000-0000-0000-0000-000000001334"),
            roleID: roleID,
            affinityScore: 50,
            manualAffinityScore: nil,
            manualAffinityUpdatedAt: date(500),
            updatedAt: date(50),
            revision: 0,
            deviceID: "clear-winner"
        )
        context.insert(makeProfile(id: roleID))
        context.insert(rowWinner)
        context.insert(manualWinner)
        context.insert(clearWinner)
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.relationships.removed, 2)

        let projected = try StoreDuplicateReconciler.makeCanonicalPayload(
            context: context,
            now: date(500)
        )
        let projectedRelationship = try XCTUnwrap(
            projected.relationships.first { $0.roleID == roleID }
        )
        XCTAssertEqual(projectedRelationship.affinityScore, 12)
        XCTAssertEqual(projectedRelationship.revision, 9)
        XCTAssertEqual(projectedRelationship.deviceID, "row-winner")
        XCTAssertNil(projectedRelationship.manualAffinityScore)
        XCTAssertEqual(projectedRelationship.manualAffinityUpdatedAt, date(500))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).count,
            3,
            "Canonical projection must remain read-only."
        )

        let result = try StoreDuplicateReconciler.reconcile(context: context)
        XCTAssertEqual(result.relationships.removed, 2)
        let remaining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first
        )
        XCTAssertEqual(remaining.id, rowWinner.id)
        XCTAssertEqual(remaining.affinityScore, 12)
        XCTAssertEqual(remaining.revision, 9)
        XCTAssertNil(remaining.manualAffinityScore)
        XCTAssertEqual(remaining.manualAffinityUpdatedAt, date(500))
    }

    func testCanonicalProfileProjectionIsReadOnlyAndContainsOneWinner() throws {
        let context = makeContext()
        let conversation = ConversationRecord(
            id: id("00000000-0000-0000-0000-000000001302"),
            title: "Persona",
            createdAt: date(1)
        )
        context.insert(conversation)
        context.insert(makeProfile(
            name: "内容 A",
            updatedAt: date(200),
            revision: 4,
            deviceID: "same-device"
        ))
        context.insert(makeProfile(
            name: "内容 B",
            updatedAt: date(200),
            revision: 4,
            deviceID: "same-device"
        ))
        try context.save()

        let sourceProfiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        let expectedProfile = sourceProfiles.reduce(
            Optional<CompanionProfileRecord>.none
        ) { current, candidate in
            guard let current else { return candidate }
            return CompanionProfileService.isPreferred(candidate, over: current)
                ? candidate
                : current
        }
        let payload = try StoreDuplicateReconciler.makeCanonicalPayload(
            context: context,
            now: date(500)
        )
        XCTAssertEqual(payload.persona.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(payload.persona.name, expectedProfile?.name)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>()).count,
            2,
            "Canonical source projection must not delete or save source duplicates."
        )
    }

    func testEventConflictIsRejectedAtomicallyBeforeAnyDeletion() throws {
        let context = makeContext()
        let eventID = id("00000000-0000-0000-0000-000000001001")
        let conversationID = id("00000000-0000-0000-0000-000000001002")
        let first = makeEvent(id: eventID, conversationID: conversationID, content: "原文一")
        let second = makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "原文二",
            contentHash: "different-hash"
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertThrowsError(try StoreDuplicateReconciler.reconcile(context: context)) { error in
            XCTAssertEqual(error as? StoreDuplicateReconcileError, .eventConflict(eventID))
            XCTAssertTrue(error.localizedDescription.contains(eventID.uuidString))
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationEvent>()).count, 2)
        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<ConversationEvent>()).map(\.content)),
            Set(["原文一", "原文二"])
        )
    }

    func testEventRoundTripDateDifferencesAreNotIdentityConflicts() throws {
        let context = makeContext()
        let eventID = id("00000000-0000-0000-0000-000000001051")
        let conversationID = id("00000000-0000-0000-0000-000000001052")
        let first = makeEvent(id: eventID, conversationID: conversationID)
        first.occurredAt = date(10.001)
        first.recordedAt = date(20.001)
        let second = makeEvent(id: eventID, conversationID: conversationID)
        second.occurredAt = date(10.002)
        second.recordedAt = date(20.002)
        context.insert(first)
        context.insert(second)
        try context.save()

        let result = try StoreDuplicateReconciler.reconcile(context: context)

        XCTAssertEqual(result.events, .init(removed: 1, updated: 0))
        let remaining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>()).first { $0.id == eventID }
        )
        XCTAssertEqual(remaining.occurredAt, date(10.001))
        XCTAssertEqual(remaining.recordedAt, date(20.001))
    }

    func testEvidenceConflictIsRejectedAtomicallyBeforeAnyDeletion() throws {
        let context = makeContext()
        let evidenceID = id("00000000-0000-0000-0000-000000001101")
        let memoryID = id("00000000-0000-0000-0000-000000001102")
        let first = MemoryEvidenceRecord(
            id: evidenceID,
            memoryID: memoryID,
            eventID: id("00000000-0000-0000-0000-000000001103"),
            startUTF16: 0,
            endUTF16: 2,
            relation: .supports,
            quoteHash: "quote",
            confidence: 0.4
        )
        let second = MemoryEvidenceRecord(
            id: evidenceID,
            memoryID: memoryID,
            eventID: id("00000000-0000-0000-0000-000000001104"),
            startUTF16: 0,
            endUTF16: 2,
            relation: .supports,
            quoteHash: "quote",
            confidence: 0.9
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertThrowsError(try StoreDuplicateReconciler.reconcile(context: context)) { error in
            XCTAssertEqual(error as? StoreDuplicateReconcileError, .evidenceConflict(evidenceID))
            XCTAssertTrue(error.localizedDescription.contains(evidenceID.uuidString))
        }
        let records = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.eventID)).count, 2)
    }

    func testEvidenceCreatedAtDifferencesAreNotIdentityConflicts() throws {
        let context = makeContext()
        let evidenceID = id("00000000-0000-0000-0000-000000001151")
        let memoryID = id("00000000-0000-0000-0000-000000001152")
        let eventID = id("00000000-0000-0000-0000-000000001153")
        let first = MemoryEvidenceRecord(
            id: evidenceID,
            memoryID: memoryID,
            eventID: eventID,
            startUTF16: 0,
            endUTF16: 2,
            relation: .supports,
            quoteHash: "quote",
            confidence: 0.9
        )
        first.createdAt = date(30.001)
        let second = MemoryEvidenceRecord(
            id: evidenceID,
            memoryID: memoryID,
            eventID: eventID,
            startUTF16: 0,
            endUTF16: 2,
            relation: .supports,
            quoteHash: "quote",
            confidence: 0.9
        )
        second.createdAt = date(30.002)
        context.insert(first)
        context.insert(second)
        try context.save()

        let result = try StoreDuplicateReconciler.reconcile(context: context)

        XCTAssertEqual(result.evidence, .init(removed: 1, updated: 0))
        let remaining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).first { $0.id == evidenceID }
        )
        XCTAssertEqual(remaining.createdAt, date(30.001))
    }

    func testTombstoneConflictIsRejectedAtomicallyBeforeAnyDeletion() throws {
        let context = makeContext()
        let tombstoneID = id("00000000-0000-0000-0000-000000001201")
        let entityID = id("00000000-0000-0000-0000-000000001202")
        let first = MemoryTombstoneRecord(
            entityID: entityID,
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            deviceID: "device",
            reason: "fixture"
        )
        first.id = tombstoneID
        let second = MemoryTombstoneRecord(
            entityID: entityID,
            entityType: "memory",
            canonicalKey: "user.other_fact",
            deviceID: "device",
            reason: "fixture"
        )
        second.id = tombstoneID
        context.insert(first)
        context.insert(second)
        try context.save()

        XCTAssertThrowsError(try StoreDuplicateReconciler.reconcile(context: context)) { error in
            XCTAssertEqual(error as? StoreDuplicateReconcileError, .tombstoneConflict(tombstoneID))
            XCTAssertTrue(error.localizedDescription.contains(tombstoneID.uuidString))
        }
        let records = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.canonicalKey)), Set(["user.favorite_drink", "user.other_fact"]))
    }

    func testTombstoneRemainsTheFinalEligibilityBarrierAfterMemoryReconcile() throws {
        let context = makeContext()
        let ids = try insertCompleteFixture(in: context)
        _ = try StoreDuplicateReconciler.reconcile(context: context)

        let memory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first { $0.id == ids.memory }
        )
        let tombstone = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first { $0.id == ids.tombstone }
        )
        XCTAssertEqual(memory.id, tombstone.entityID)
        XCTAssertTrue(MemoryRepository.isSuppressedByTombstone(memory, tombstones: [tombstone]))
        XCTAssertTrue(MemoryRepository.eligibleMemories(from: [memory], tombstones: [tombstone]).isEmpty)
        XCTAssertTrue(PromptAssembler.snapshots(from: [memory], tombstones: [tombstone]).isEmpty)
    }

    func testForgottenPhysicalCopyWinsMixedStateAndScrubsContent() throws {
        let context = makeContext()
        let memoryID = id("00000000-0000-0000-0000-000000001351")
        let active = makeMemory(
            id: memoryID,
            value: "这段内容必须被擦除",
            state: .active,
            sourceRank: 999,
            confidence: 0.99,
            importance: 0.99
        )
        active.createdAt = date(100)
        active.updatedAt = date(500)
        active.isPinned = true
        active.userVerified = true
        active.embeddingData = MemoryEmbeddingCodec.encode([1, 0, 0])
        active.embeddingModelID = "fixture-embedding"

        let forgotten = makeMemory(
            id: memoryID,
            value: "遗忘副本也不能泄露",
            state: .forgotten,
            sourceRank: 1,
            confidence: 0.10,
            importance: 0.10
        )
        forgotten.createdAt = date(90)
        forgotten.updatedAt = date(200)
        forgotten.isPinned = true
        forgotten.userVerified = true
        forgotten.embeddingData = MemoryEmbeddingCodec.encode([0, 1, 0])
        forgotten.embeddingModelID = "old-embedding"

        context.insert(active)
        context.insert(forgotten)
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.memories, .init(removed: 1, updated: 1))
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count,
            0,
            "Reconciliation must not fabricate a user tombstone."
        )
        let canonicalPayload = try StoreDuplicateReconciler.makeCanonicalPayload(context: context)
        let projectedMemory = try XCTUnwrap(
            canonicalPayload.memories.first { $0.id == memoryID }
        )
        XCTAssertEqual(projectedMemory.stateRaw, MemoryState.forgotten.rawValue)
        XCTAssertEqual(projectedMemory.value, "")

        let result = try StoreDuplicateReconciler.reconcile(context: context)
        XCTAssertEqual(result.memories, .init(removed: 1, updated: 1))

        let records = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let winner = try XCTUnwrap(records.first { $0.id == memoryID })
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(winner.state, .forgotten)
        XCTAssertEqual(winner.value, "")
        XCTAssertNil(winner.embeddingData)
        XCTAssertNil(winner.embeddingModelID)
        XCTAssertFalse(winner.userVerified)
        XCTAssertFalse(winner.isPinned)
        XCTAssertEqual(winner.updatedAt, date(500))
        XCTAssertTrue(PromptAssembler.snapshots(from: records).isEmpty)
    }

    func testPagedDuplicateScanReconcilesGroupAcrossBatchBoundary() throws {
        let context = makeContext()

        // A four-row test page keeps the test fast while putting the first
        // physical copy of duplicateID at the end of page one and its second
        // copy at the beginning of page two.
        for index in 1...3 {
            let memoryID = id(String(format: "00000000-0000-0000-0000-%012X", index))
            let memory = makeMemory(id: memoryID, value: "独立记忆 \(index)")
            memory.canonicalKey = "user.scale.\(index)"
            context.insert(memory)
        }

        let duplicateID = id("00000000-0000-0000-0000-000000000004")
        let older = makeMemory(id: duplicateID, value: "旧值")
        older.canonicalKey = "user.scale.boundary"
        older.updatedAt = date(100)
        let newer = makeMemory(id: duplicateID, value: "新值")
        newer.canonicalKey = "user.scale.boundary"
        newer.updatedAt = date(200)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(
            context: context,
            scanBatchSize: 4
        )
        XCTAssertEqual(preflight.memories, .init(removed: 1, updated: 1))

        let result = try StoreDuplicateReconciler.reconcile(
            context: context,
            scanBatchSize: 4
        )
        XCTAssertEqual(result.memories, .init(removed: 1, updated: 1))
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()),
            4
        )
        let surviving = try context.fetch(
            FetchDescriptor<MemoryAssertionRecord>(
                predicate: #Predicate { $0.id == duplicateID }
            )
        )
        XCTAssertEqual(surviving.count, 1)
        XCTAssertEqual(surviving.first?.value, "新值")
    }

    func testReadStateDuplicatesKeepMaximumCursorAndRemovePhysicalCopies() throws {
        let context = makeContext()
        let conversationID = id("00000000-0000-0000-0000-000000001401")
        let postID = id("00000000-0000-0000-0000-000000001402")
        let olderConversationMarker = ConversationReadStateRecord(
            id: id("00000000-0000-0000-0000-000000001403"),
            roleID: RoleScope.legacyRoleID,
            conversationID: conversationID,
            lastReadOccurredAt: date(10),
            lastReadLogicalTimestamp: "10-old",
            lastReadEventID: id("00000000-0000-0000-0000-000000001405"),
            updatedAt: date(10),
            revision: 1,
            deviceID: "old"
        )
        let newerConversationMarker = ConversationReadStateRecord(
            id: id("00000000-0000-0000-0000-000000001404"),
            roleID: RoleScope.legacyRoleID,
            conversationID: conversationID,
            lastReadOccurredAt: date(20),
            lastReadLogicalTimestamp: "20-new",
            lastReadEventID: id("00000000-0000-0000-0000-000000001406"),
            updatedAt: date(11),
            revision: 1,
            deviceID: "new"
        )
        let olderMomentMarker = MomentReadStateRecord(
            id: id("00000000-0000-0000-0000-000000001407"),
            postID: postID,
            lastReadCreatedAt: date(30),
            lastReadInteractionID: id("00000000-0000-0000-0000-000000001409"),
            updatedAt: date(30),
            revision: 1,
            deviceID: "old"
        )
        let newerMomentMarker = MomentReadStateRecord(
            id: id("00000000-0000-0000-0000-000000001408"),
            postID: postID,
            lastReadCreatedAt: date(40),
            lastReadInteractionID: id("00000000-0000-0000-0000-000000001410"),
            updatedAt: date(31),
            revision: 1,
            deviceID: "new"
        )
        for marker in [olderConversationMarker, newerConversationMarker] {
            context.insert(marker)
        }
        for marker in [olderMomentMarker, newerMomentMarker] {
            context.insert(marker)
        }
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.conversationReadStates, .init(removed: 1, updated: 0))
        XCTAssertEqual(preflight.momentReadStates, .init(removed: 1, updated: 0))

        let result = try StoreDuplicateReconciler.reconcile(context: context)
        XCTAssertEqual(result, preflight)
        let conversationMarkers = try context.fetch(
            FetchDescriptor<ConversationReadStateRecord>()
        )
        let momentMarkers = try context.fetch(FetchDescriptor<MomentReadStateRecord>())
        XCTAssertEqual(conversationMarkers.count, 1)
        XCTAssertEqual(momentMarkers.count, 1)
        XCTAssertEqual(conversationMarkers.first?.lastReadOccurredAt, date(20))
        XCTAssertEqual(momentMarkers.first?.lastReadCreatedAt, date(40))
        XCTAssertTrue(try StoreDuplicateReconciler.reconcile(context: context).isNoOp)
    }
}
