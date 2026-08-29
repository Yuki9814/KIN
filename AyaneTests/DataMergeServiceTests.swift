import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class DataMergeServiceTests: XCTestCase {
    func testSmallPayloadDoesNotMaterializeOrRewriteUnrelatedLargeMemoryRows() throws {
        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: 1_000)
        let payload = try makePayload(from: sourceContext)

        let destinationContext = makeContext()
        let unrelatedCount = 256
        for index in 0..<unrelatedCount {
            let memory = makeMemory(
                id: uuid(10_000 + index),
                canonicalKey: "unrelated.large_fixture.\(index)",
                value: "不应被小 payload 触碰 \(index)",
                createdOffset: 20 + TimeInterval(index),
                updatedOffset: 30 + TimeInterval(index),
                observedOffset: 25 + TimeInterval(index),
                sourceRank: 100
            )
            // An invalid blob in an unrelated row is an observable guard
            // against broad target materialization: final validation must not
            // inspect or decode it while merging the disjoint payload.
            memory.embeddingData = index == 0
                ? Data([0xFF])
                : Data(repeating: 0xA5, count: 4 * 1024)
            destinationContext.insert(memory)
        }
        try destinationContext.save()

        let report = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(report.inserted, 8)
        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, unrelatedCount + 1)
        let unrelated = memories.filter { $0.canonicalKey.hasPrefix("unrelated.large_fixture.") }
        XCTAssertEqual(unrelated.count, unrelatedCount)
        XCTAssertEqual(
            unrelated.first(where: { $0.id == uuid(10_000) })?.embeddingData,
            Data([0xFF])
        )
        XCTAssertEqual(
            unrelated.first(where: { $0.id == uuid(10_001) })?.embeddingData?.count,
            4 * 1024
        )
        XCTAssertTrue(unrelated.allSatisfy { $0.state == .active })
    }

    func testSmallPayloadDoesNotMaterializeSameKeySupersededEmbeddingHistory() throws {
        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: 2_000)
        let payload = try makePayload(from: sourceContext)
        let incomingKey = try XCTUnwrap(payload.memories.first?.canonicalKey)

        let destinationContext = makeContext()
        let historyCount = 600
        for index in 0..<historyCount {
            let memory = makeMemory(
                id: uuid(20_000 + index),
                canonicalKey: incomingKey,
                value: "已归档历史 \(index)",
                createdOffset: TimeInterval(index),
                updatedOffset: TimeInterval(index + 1),
                observedOffset: TimeInterval(index),
                sourceRank: 100,
                state: .superseded
            )
            // Invalid and large blobs make accidental history materialization
            // observable: scoped final validation must never decode them.
            memory.embeddingData = index == 0
                ? Data([0xFF])
                : Data(repeating: 0x5A, count: 4 * 1024)
            destinationContext.insert(memory)
        }
        try destinationContext.save()

        let report = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(report.inserted, 8)
        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, historyCount + 1)
        XCTAssertEqual(
            memories.first(where: { $0.id == uuid(20_000) })?.embeddingData,
            Data([0xFF])
        )
        XCTAssertEqual(
            memories.filter { $0.state == .superseded && $0.canonicalKey == incomingKey }.count,
            historyCount
        )
    }

    func testDisjointUnionPreservesEveryExistingRecord() throws {
        let sourceContext = makeContext()
        let source = try insertCompleteFixture(into: sourceContext, base: 1)

        let destinationContext = makeContext()
        let target = try insertCompleteFixture(into: destinationContext, base: 100)

        let report = try DataMergeService.merge(from: sourceContext, into: destinationContext)

        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.conversations, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.events, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.memories, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.evidence, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.summaries, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.tombstones, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(report.inserted, 8)

        XCTAssertEqual(
            try Set(destinationContext.fetch(FetchDescriptor<ConversationRecord>()).map(\.id)),
            Set([source.conversationID, target.conversationID])
        )
        XCTAssertEqual(
            try Set(destinationContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.id)),
            Set([source.eventID, target.eventID])
        )
        XCTAssertEqual(
            try Set(destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>()).map(\.id)),
            Set([source.memoryID, target.memoryID])
        )
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>()).count, 2)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemorySummaryRecord>()).count, 2)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count, 2)
    }

    func testRepeatedMergeIsIdempotent() throws {
        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: 10)
        let payload = try makePayload(from: sourceContext)
        let destinationContext = makeContext()

        let first = try DataMergeService.merge(payload, into: destinationContext)
        let second = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(first.profiles, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(first.inserted, 8)
        XCTAssertEqual(second.profiles, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.conversations, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.events, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.memories, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.evidence, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.summaries, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.tombstones, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.updated, 0)
        XCTAssertEqual(second.unchanged, 8)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>()).count, 1)
    }

    func testReadStateMergeIsIdempotentAndPreservesTheCursor() throws {
        let sourceContext = makeContext()
        let fixture = try insertCompleteFixture(into: sourceContext, base: 20_000)
        sourceContext.insert(ConversationReadStateRecord(
            id: fixture.conversationID,
            roleID: RoleScope.legacyRoleID,
            conversationID: fixture.conversationID,
            lastReadOccurredAt: date(2),
            lastReadLogicalTimestamp: "1-fixture-1",
            lastReadEventID: fixture.eventID,
            updatedAt: date(3),
            revision: 1,
            deviceID: "read-state-source"
        ))
        try sourceContext.save()
        let payload = try makePayload(from: sourceContext)

        let destinationContext = makeContext()
        let first = try DataMergeService.merge(payload, into: destinationContext)
        let second = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(first.conversationReadStates, .init(inserted: 1, updated: 0, unchanged: 0))
        XCTAssertEqual(second.conversationReadStates, .init(inserted: 0, updated: 0, unchanged: 1))
        let marker = try XCTUnwrap(
            try destinationContext.fetch(FetchDescriptor<ConversationReadStateRecord>()).first
        )
        XCTAssertEqual(marker.conversationID, fixture.conversationID)
        XCTAssertEqual(marker.lastReadOccurredAt, date(2))
        XCTAssertEqual(marker.lastReadEventID, fixture.eventID)
    }

    func testReadStateMergeChoosesMaximumCursorRegardlessOfOrder() throws {
        let lowContext = makeContext()
        let fixture = try insertCompleteFixture(into: lowContext, base: 20_100)
        lowContext.insert(ConversationReadStateRecord(
            id: fixture.conversationID,
            roleID: RoleScope.legacyRoleID,
            conversationID: fixture.conversationID,
            lastReadOccurredAt: date(2),
            lastReadLogicalTimestamp: "1-fixture-1",
            lastReadEventID: fixture.eventID,
            updatedAt: date(3),
            revision: 1,
            deviceID: "low"
        ))
        try lowContext.save()

        let highContext = makeContext()
        let highFixture = try insertCompleteFixture(into: highContext, base: 20_100)
        highContext.insert(ConversationReadStateRecord(
            id: highFixture.conversationID,
            roleID: RoleScope.legacyRoleID,
            conversationID: highFixture.conversationID,
            lastReadOccurredAt: date(9),
            lastReadLogicalTimestamp: "1-fixture-1",
            lastReadEventID: highFixture.eventID,
            updatedAt: date(4),
            revision: 1,
            deviceID: "high"
        ))
        try highContext.save()

        let lowPayload = try makePayload(from: lowContext)
        let highPayload = try makePayload(from: highContext)
        let firstTarget = makeContext()
        _ = try DataMergeService.merge(lowPayload, into: firstTarget)
        let forward = try DataMergeService.merge(highPayload, into: firstTarget)

        let reverseTarget = makeContext()
        _ = try DataMergeService.merge(highPayload, into: reverseTarget)
        let reverse = try DataMergeService.merge(lowPayload, into: reverseTarget)

        XCTAssertEqual(forward.conversationReadStates, .init(inserted: 0, updated: 1, unchanged: 0))
        XCTAssertEqual(reverse.conversationReadStates, .init(inserted: 0, updated: 0, unchanged: 1))
        let forwardMarker = try XCTUnwrap(
            try firstTarget.fetch(FetchDescriptor<ConversationReadStateRecord>()).first
        )
        let reverseMarker = try XCTUnwrap(
            try reverseTarget.fetch(FetchDescriptor<ConversationReadStateRecord>()).first
        )
        XCTAssertEqual(forwardMarker.lastReadOccurredAt, date(9))
        XCTAssertEqual(reverseMarker.lastReadOccurredAt, date(9))
        XCTAssertEqual(forwardMarker.lastReadEventID, fixture.eventID)
        XCTAssertEqual(reverseMarker.lastReadEventID, fixture.eventID)
    }

    func testReadStateIdentityConflictFailsClosedBeforeDestinationWrites() throws {
        let sourceContext = makeContext()
        let fixture = try insertCompleteFixture(into: sourceContext, base: 20_200)
        sourceContext.insert(ConversationReadStateRecord(
            id: fixture.conversationID,
            roleID: RoleScope.legacyRoleID,
            conversationID: fixture.conversationID,
            lastReadOccurredAt: date(2),
            lastReadLogicalTimestamp: "1-fixture-1",
            lastReadEventID: fixture.eventID,
            updatedAt: date(3),
            revision: 1,
            deviceID: "source"
        ))
        try sourceContext.save()
        let payload = try makePayload(from: sourceContext)

        let destinationContext = makeContext()
        let conflicting = ConversationReadStateRecord(
            id: fixture.conversationID,
            roleID: RoleScope.legacyRoleID,
            conversationID: uuid(20_299),
            lastReadOccurredAt: date(1),
            lastReadLogicalTimestamp: "old",
            updatedAt: date(1),
            revision: 0,
            deviceID: "destination"
        )
        destinationContext.insert(conflicting)
        try destinationContext.save()

        XCTAssertThrowsError(try DataMergeService.merge(payload, into: destinationContext)) { error in
            XCTAssertEqual(
                error as? DataMergeError,
                .identityConflict(entity: .conversationReadState, id: fixture.conversationID)
            )
        }
        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationReadStateRecord>()).count,
            1
        )
        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationReadStateRecord>()).first?.conversationID,
            uuid(20_299)
        )
    }

    func testMissingTargetProfileIsInsertedAndPreservesMetadata() throws {
        let sourceContext = makeContext()
        let profile = makeProfile(
            name: "绫音测试",
            userName: "测试者",
            prompt: "保持清醒",
            createdAt: date(10),
            updatedAt: date(20),
            revision: 3,
            deviceID: "source-device"
        )
        sourceContext.insert(makeConversation(id: uuid(120), title: "Persona"))
        sourceContext.insert(profile)
        try sourceContext.save()

        let payload = try makePayload(from: sourceContext)
        let destinationContext = makeContext()
        let report = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
        let restored = try XCTUnwrap(
            try destinationContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first
        )
        XCTAssertEqual(restored.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(restored.name, "绫音测试")
        XCTAssertEqual(restored.userName, "测试者")
        XCTAssertEqual(restored.prompt, "保持清醒")
        XCTAssertEqual(restored.createdAt, date(10))
        XCTAssertEqual(restored.updatedAt, date(20))
        XCTAssertEqual(restored.revision, 3)
        XCTAssertEqual(restored.deviceID, "source-device")
    }

    func testProfileLWWUsesRevisionThenTimestampDeviceAndContentFingerprint() throws {
        let targetContext = makeContext()
        targetContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        targetContext.insert(makeProfile(
            name: "目标",
            createdAt: date(0),
            updatedAt: date(100),
            revision: 1,
            deviceID: "z-device"
        ))
        try targetContext.save()

        let sourceContext = makeContext()
        sourceContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        sourceContext.insert(makeProfile(
            name: "版本较新",
            createdAt: date(0),
            updatedAt: date(1),
            revision: 2,
            deviceID: "a-device"
        ))
        try sourceContext.save()

        var report = try DataMergeService.merge(
            try makePayload(from: sourceContext),
            into: targetContext
        )
        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 0, updated: 1, unchanged: 0))
        XCTAssertEqual(try XCTUnwrap(try targetContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first).name, "版本较新")

        // Same revision: the newer update timestamp wins even from a device
        // which sorts lower lexicographically.
        let newerTimestampContext = makeContext()
        newerTimestampContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        newerTimestampContext.insert(makeProfile(
            name: "时间较新",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "a-device"
        ))
        try newerTimestampContext.save()
        report = try DataMergeService.merge(
            try makePayload(from: newerTimestampContext),
            into: targetContext
        )
        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 0, updated: 1, unchanged: 0))
        XCTAssertEqual(try XCTUnwrap(try targetContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first).name, "时间较新")

        let newerDeviceContext = makeContext()
        newerDeviceContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        newerDeviceContext.insert(makeProfile(
            name: "设备较新",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "z-device"
        ))
        try newerDeviceContext.save()
        report = try DataMergeService.merge(
            try makePayload(from: newerDeviceContext),
            into: targetContext
        )
        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 0, updated: 1, unchanged: 0))
        XCTAssertEqual(try XCTUnwrap(try targetContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first).name, "设备较新")

        // Same ordering metadata: merging either content first must converge
        // to the same canonical content fingerprint winner.
        let lowContentContext = makeContext()
        lowContentContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        lowContentContext.insert(makeProfile(
            name: "内容 A",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "z-device"
        ))
        try lowContentContext.save()
        let highContentContext = makeContext()
        highContentContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        highContentContext.insert(makeProfile(
            name: "内容 B",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "z-device"
        ))
        try highContentContext.save()

        let contentTargetContext = makeContext()
        contentTargetContext.insert(makeConversation(id: uuid(121), title: "Persona"))
        contentTargetContext.insert(makeProfile(
            name: "基线",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "z-device"
        ))
        try contentTargetContext.save()

        let firstPayload = try makePayload(from: lowContentContext)
        let secondPayload = try makePayload(from: highContentContext)
        let firstOrder = try DataMergeService.merge(firstPayload, into: contentTargetContext)
        _ = try DataMergeService.merge(secondPayload, into: contentTargetContext)

        let reverseTarget = makeContext()
        reverseTarget.insert(makeConversation(id: uuid(121), title: "Persona"))
        reverseTarget.insert(makeProfile(
            name: "基线",
            createdAt: date(0),
            updatedAt: date(200),
            revision: 2,
            deviceID: "z-device"
        ))
        try reverseTarget.save()
        _ = try DataMergeService.merge(secondPayload, into: reverseTarget)
        _ = try DataMergeService.merge(firstPayload, into: reverseTarget)

        let firstProfile = try XCTUnwrap(try contentTargetContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first)
        let reverseProfile = try XCTUnwrap(try reverseTarget.fetch(FetchDescriptor<CompanionProfileRecord>()).first)
        XCTAssertEqual(firstProfile.name, reverseProfile.name)
        XCTAssertEqual(firstOrder.profiles.inserted, 0)
        XCTAssertEqual(firstOrder.profiles.updated + firstOrder.profiles.unchanged, 1)
    }

    func testInvalidProfileIDIsTypedAndLeavesDestinationUntouched() throws {
        let sourceContext = makeContext()
        let invalidID = uuid(122)
        sourceContext.insert(makeConversation(id: uuid(123), title: "Persona"))
        try sourceContext.save()
        let base = try makePayload(from: sourceContext)
        let payload = AyaneDataExport(
            exportedAt: base.exportedAt,
            conversations: base.conversations,
            events: base.events,
            memories: base.memories,
            evidence: base.evidence,
            summaries: base.summaries,
            tombstones: base.tombstones,
            persona: AyanePersonaExport(
                name: "无效角色",
                userName: "你",
                prompt: "无效固定 ID",
                id: invalidID
            ),
            settings: base.settings
        )

        let destinationContext = makeContext()
        let preserved = makeConversation(id: uuid(124), title: "保留")
        destinationContext.insert(preserved)
        try destinationContext.save()

        XCTAssertThrowsError(try DataMergeService.merge(payload, into: destinationContext)) { error in
            guard case .identityConflict(entity: .profile, id: invalidID) = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).map(\.id), [preserved.id])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<CompanionProfileRecord>()).count, 0)
    }

    func testLegacyV4ProfilePayloadIsAccepted() throws {
        let sourceContext = makeContext()
        sourceContext.insert(makeConversation(id: uuid(125), title: "Persona"))
        sourceContext.insert(makeProfile(revision: 1, deviceID: "legacy-device"))
        try sourceContext.save()
        let current = try makePayload(from: sourceContext)
        let legacy = AyaneDataExport(
            schemaVersion: 4,
            exportedAt: current.exportedAt,
            conversations: current.conversations,
            events: current.events,
            memories: current.memories,
            evidence: current.evidence,
            summaries: current.summaries,
            tombstones: current.tombstones,
            persona: current.persona,
            settings: current.settings
        )

        let destinationContext = makeContext()
        let report = try DataMergeService.merge(legacy, into: destinationContext)
        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 1, updated: 0, unchanged: 0))
    }

    func testV6MergesProfilesAndRoleScopedRecordsWithoutCrossRoleConvergence() throws {
        let sourceContext = makeContext()
        let roleA = uuid(1_001)
        let roleB = uuid(1_002)
        let profiles = [
            makeProfile(id: roleA, name: "角色 A"),
            makeProfile(id: roleB, name: "角色 B")
        ]

        for (index, roleID) in [roleA, roleB].enumerated() {
            let base = 1_010 + index * 10
            let conversation = makeConversation(id: uuid(base), title: "角色会话 \(index)")
            conversation.roleID = roleID
            let content = "角色 \(index) 的原文"
            let event = makeEvent(
                id: uuid(base + 1),
                conversationID: conversation.id,
                content: content,
                deviceID: "role-\(index)",
                sequence: 1,
                occurredOffset: 1,
                recordedOffset: 2
            )
            event.roleID = roleID
            let memory = makeMemory(
                id: uuid(base + 2),
                canonicalKey: "user.favorite_drink",
                value: index == 0 ? "咖啡" : "茶",
                createdOffset: 3,
                updatedOffset: 4,
                observedOffset: 3,
                sourceRank: 100
            )
            memory.roleID = roleID
            let evidence = MemoryEvidenceRecord(
                id: uuid(base + 3),
                memoryID: memory.id,
                eventID: event.id,
                startUTF16: 0,
                endUTF16: content.utf16.count,
                relation: .supports,
                quoteHash: ContentHasher.sha256(content),
                confidence: 0.9,
                roleID: roleID
            )
            let summary = makeSummary(
                id: uuid(base + 4),
                conversationID: conversation.id,
                content: "摘要 \(index)",
                firstEventID: event.id,
                lastEventID: event.id
            )
            summary.roleID = roleID
            let tombstone = makeTombstone(
                id: uuid(base + 5),
                entityID: uuid(base + 500),
                canonicalKey: "obsolete.\(index)",
                sourceEventIDs: [event.id],
                deletedOffset: 6,
                deviceID: "role-\(index)",
                reason: "fixture"
            )
            tombstone.roleID = roleID

            sourceContext.insert(conversation)
            sourceContext.insert(event)
            sourceContext.insert(memory)
            sourceContext.insert(evidence)
            sourceContext.insert(summary)
            sourceContext.insert(tombstone)
        }
        for profile in profiles { sourceContext.insert(profile) }
        try sourceContext.save()

        let payload = try makePayload(from: sourceContext)
        XCTAssertEqual(payload.schemaVersion, AyaneDataExport.currentSchemaVersion)
        XCTAssertEqual(Set(payload.profiles.compactMap(\.roleID)), Set([roleA, roleB]))

        let destinationContext = makeContext()
        let report = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(report.profiles, DataMergeEntityReport(inserted: 2, updated: 0, unchanged: 0))
        XCTAssertEqual(report.conversations.inserted, 2)
        XCTAssertEqual(report.events.inserted, 2)
        XCTAssertEqual(report.memories.inserted, 2)
        XCTAssertEqual(report.evidence.inserted, 2)
        XCTAssertEqual(report.summaries.inserted, 2)
        XCTAssertEqual(report.tombstones.inserted, 2)
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<CompanionProfileRecord>()).map(\.id)),
            Set([roleA, roleB])
        )
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).map(\.resolvedRoleID)),
            Set([roleA, roleB])
        )
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.resolvedRoleID)),
            Set([roleA, roleB])
        )
        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(Set(memories.map(\.resolvedRoleID)), Set([roleA, roleB]))
        XCTAssertEqual(memories.filter { $0.state == .active }.count, 2)
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>()).map(\.resolvedRoleID)),
            Set([roleA, roleB])
        )
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<MemorySummaryRecord>()).map(\.resolvedRoleID)),
            Set([roleA, roleB])
        )
        XCTAssertEqual(
            Set(try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>()).map(\.resolvedRoleID)),
            Set([roleA, roleB])
        )
    }

    func testLegacyV5PayloadMapsEveryRoleOwnedRecordToLegacyRole() throws {
        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: 1_050)
        let current = try makePayload(from: sourceContext)
        let legacy = try mutateJSON(current) { root in
            root["schema_version"] = 5
            root.removeValue(forKey: "profiles")
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona.removeValue(forKey: "role_id")
            root["persona"] = persona
            for key in ["conversations", "events", "memories", "evidence", "summaries", "tombstones"] {
                var records = try XCTUnwrap(root[key] as? [[String: Any]])
                records = records.map { record in
                    var copy = record
                    copy.removeValue(forKey: "role_id")
                    return copy
                }
                root[key] = records
            }
        }

        let destinationContext = makeContext()
        _ = try DataMergeService.merge(legacy, into: destinationContext)
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<ConversationRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemorySummaryRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
    }

    func testPreflightConflictRollsBackStagedDestinationCanonicalization() throws {
        let conversationID = uuid(150)
        let eventID = uuid(151)
        let destinationContext = makeContext()
        destinationContext.insert(makeConversation(id: conversationID, title: "目标"))
        destinationContext.insert(makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "目标原文",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        ))
        destinationContext.insert(makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "目标原文",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 3
        ))
        try destinationContext.save()

        _ = try StoreDuplicateReconciler.stage(context: destinationContext)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).count, 1)

        let sourceContext = makeContext()
        sourceContext.insert(makeConversation(id: conversationID, title: "目标"))
        sourceContext.insert(makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "冲突原文",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        ))
        try sourceContext.save()

        XCTAssertThrowsError(
            try DataMergeService.merge(try makePayload(from: sourceContext), into: destinationContext)
        ) { error in
            guard case .identityConflict(entity: .event, id: eventID) = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).count,
            2,
            "A merge preflight failure must roll back staged duplicate deletions."
        )
    }

    func testConflictingEventIDIsRejectedBeforeAnyDestinationChange() throws {
        let conversationID = uuid(200)
        let eventID = uuid(201)
        let destinationContext = makeContext()
        let destinationConversation = makeConversation(
            id: conversationID,
            title: "共享会话",
            createdOffset: 0,
            updatedOffset: 10
        )
        let destinationEvent = makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "目标原文",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        )
        destinationContext.insert(destinationConversation)
        destinationContext.insert(destinationEvent)
        try destinationContext.save()

        let sourceContext = makeContext()
        let sourceConversation = makeConversation(
            id: conversationID,
            title: "共享会话",
            createdOffset: 0,
            updatedOffset: 10
        )
        let conflictingEvent = makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "源端冲突原文",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        )
        let extraEvent = makeEvent(
            id: uuid(202),
            conversationID: conversationID,
            content: "冲突之后不应写入",
            deviceID: "device",
            sequence: 2,
            occurredOffset: 3,
            recordedOffset: 4
        )
        sourceContext.insert(sourceConversation)
        sourceContext.insert(conflictingEvent)
        sourceContext.insert(extraEvent)
        try sourceContext.save()

        let payload = try makePayload(from: sourceContext)
        XCTAssertThrowsError(try DataMergeService.merge(payload, into: destinationContext)) { error in
            guard case .identityConflict(entity: .event, id: eventID) = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let events = try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.content, "目标原文")
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
    }

    func testConflictingEvidenceIDRejectsWholeMergeAtomically() throws {
        let base = 240
        let destinationContext = makeContext()
        _ = try insertCompleteFixture(into: destinationContext, base: base)

        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: base)
        let evidenceID = uuid(base + 3)
        let evidence = try XCTUnwrap(
            try sourceContext.fetch(FetchDescriptor<MemoryEvidenceRecord>())
                .first(where: { $0.id == evidenceID })
        )
        evidence.relationRaw = EvidenceRelation.contradicts.rawValue
        sourceContext.insert(makeConversation(id: uuid(249), title: "不应部分插入"))
        try sourceContext.save()

        XCTAssertThrowsError(
            try DataMergeService.merge(try makePayload(from: sourceContext), into: destinationContext)
        ) { error in
            guard case .identityConflict(entity: .evidence, id: evidenceID) = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>()).count, 1)
    }

    func testConflictingTombstoneIDRejectsWholeMergeAtomically() throws {
        let base = 250
        let destinationContext = makeContext()
        _ = try insertCompleteFixture(into: destinationContext, base: base)

        let sourceContext = makeContext()
        _ = try insertCompleteFixture(into: sourceContext, base: base)
        let tombstoneID = uuid(base + 5)
        let tombstone = try XCTUnwrap(
            try sourceContext.fetch(FetchDescriptor<MemoryTombstoneRecord>())
                .first(where: { $0.id == tombstoneID })
        )
        tombstone.reason = "conflicting-reason"
        sourceContext.insert(makeConversation(id: uuid(259), title: "不应部分插入"))
        try sourceContext.save()

        XCTAssertThrowsError(
            try DataMergeService.merge(try makePayload(from: sourceContext), into: destinationContext)
        ) { error in
            guard case .identityConflict(entity: .tombstone, id: tombstoneID) = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count, 1)
    }

    func testNewerMemoryWinsAndDifferentIDsWithSameCanonicalKeyRemain() throws {
        let memoryID = uuid(300)
        let targetContext = makeContext()
        let oldMemory = makeMemory(
            id: memoryID,
            canonicalKey: "user.favorite_drink",
            value: "旧值",
            createdOffset: 1,
            updatedOffset: 3,
            observedOffset: 2,
            sourceRank: 100
        )
        targetContext.insert(oldMemory)
        try targetContext.save()

        let sourceContext = makeContext()
        let conversation = makeConversation(id: uuid(301), title: "记忆合并")
        let newer = makeMemory(
            id: memoryID,
            canonicalKey: "user.favorite_drink",
            value: "新值",
            createdOffset: 1,
            updatedOffset: 101,
            observedOffset: 100,
            sourceRank: 100
        )
        let differentID = makeMemory(
            id: uuid(302),
            canonicalKey: "user.favorite_drink",
            value: "另一种值",
            createdOffset: 4,
            updatedOffset: 5,
            observedOffset: 4,
            sourceRank: 100
        )
        sourceContext.insert(conversation)
        sourceContext.insert(newer)
        sourceContext.insert(differentID)
        try sourceContext.save()

        let report = try DataMergeService.merge(
            try makePayload(from: sourceContext),
            into: targetContext
        )

        XCTAssertEqual(report.memories.inserted, 1)
        XCTAssertEqual(report.memories.updated, 1)
        let memories = try targetContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(memories.first(where: { $0.id == memoryID })?.value, "新值")
        XCTAssertEqual(memories.first(where: { $0.id == memoryID })?.state, .active)
        XCTAssertEqual(memories.first(where: { $0.id == differentID.id })?.state, .superseded)
        XCTAssertEqual(memories.filter { $0.state == .active }.count, 1)
    }

    func testForgottenMemoryWinsAcrossMergeOrderAndStaysErased() throws {
        let memoryID = uuid(350)
        let conversationID = uuid(351)

        func makeMemoryPayload(state: MemoryState, value: String) throws -> AyaneDataExport {
            let sourceContext = makeContext()
            sourceContext.insert(makeConversation(id: conversationID, title: "遗忘优先"))
            let memory = makeMemory(
                id: memoryID,
                canonicalKey: "user.favorite_drink",
                value: value,
                createdOffset: state == .forgotten ? 1 : 100,
                updatedOffset: state == .forgotten ? 2 : 200,
                observedOffset: state == .forgotten ? 1 : 199,
                sourceRank: state == .forgotten ? 1 : 999,
                state: state,
                userVerified: true
            )
            memory.isPinned = true
            memory.embeddingData = MemoryEmbeddingCodec.encode(
                state == .forgotten ? [0.1, 0.2] : [0.9, 0.8]
            )
            memory.embeddingModelID = state == .forgotten
                ? "forgotten-embedding"
                : "active-embedding"
            sourceContext.insert(memory)
            try sourceContext.save()
            return try makePayload(from: sourceContext)
        }

        let activePayload = try makeMemoryPayload(state: .active, value: "较新的活动值")
        let forgottenPayload = try makeMemoryPayload(state: .forgotten, value: "不应恢复的旧值")

        let activeThenForgotten = makeContext()
        _ = try DataMergeService.merge(activePayload, into: activeThenForgotten)
        _ = try DataMergeService.merge(forgottenPayload, into: activeThenForgotten)

        let forgottenThenActive = makeContext()
        _ = try DataMergeService.merge(forgottenPayload, into: forgottenThenActive)
        _ = try DataMergeService.merge(activePayload, into: forgottenThenActive)

        for context in [activeThenForgotten, forgottenThenActive] {
            let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
            let winner = try XCTUnwrap(memories.first { $0.id == memoryID })
            XCTAssertEqual(memories.count, 1)
            XCTAssertEqual(winner.state, .forgotten)
            XCTAssertEqual(winner.value, "")
            XCTAssertNil(winner.embeddingData)
            XCTAssertNil(winner.embeddingModelID)
            XCTAssertFalse(winner.isPinned)
            XCTAssertFalse(winner.userVerified)
        }
    }

    func testCanonicalSameValueKeepsOneStrongestActiveVersion() throws {
        let sourceContext = makeContext()
        let conversation = makeConversation(id: uuid(400), title: "同值收敛")
        let weaker = makeMemory(
            id: uuid(401),
            canonicalKey: " User.Favorite ",
            value: "  乌龙茶 ",
            createdOffset: 1,
            updatedOffset: 2,
            observedOffset: 2,
            sourceRank: 100
        )
        let stronger = makeMemory(
            id: uuid(402),
            canonicalKey: "user.favorite",
            value: "乌龙茶",
            createdOffset: 3,
            updatedOffset: 4,
            observedOffset: 4,
            sourceRank: 200
        )
        sourceContext.insert(conversation)
        sourceContext.insert(weaker)
        sourceContext.insert(stronger)
        try sourceContext.save()

        let destinationContext = makeContext()
        _ = try DataMergeService.merge(try makePayload(from: sourceContext), into: destinationContext)

        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(memories.first(where: { $0.id == stronger.id })?.state, .active)
        XCTAssertEqual(memories.first(where: { $0.id == weaker.id })?.state, .superseded)
        XCTAssertEqual(memories.filter { $0.state == .active }.count, 1)
    }

    func testCanonicalMergeFindsLegacyRawTargetVariantWithinBoundedScope() throws {
        let sourceContext = makeContext()
        let sourceConversation = makeConversation(id: uuid(450), title: "旧键收敛")
        let incoming = makeMemory(
            id: uuid(451),
            canonicalKey: "user.favorite",
            value: "新值",
            createdOffset: 3,
            updatedOffset: 4,
            observedOffset: 4,
            sourceRank: 200
        )
        sourceContext.insert(sourceConversation)
        sourceContext.insert(incoming)
        try sourceContext.save()

        let destinationContext = makeContext()
        let legacy = makeMemory(
            id: uuid(452),
            canonicalKey: "\u{FEFF} User.Favorite \u{FEFF}",
            value: "旧值",
            createdOffset: 1,
            updatedOffset: 2,
            observedOffset: 2,
            sourceRank: 100
        )
        legacy.embeddingData = MemoryEmbeddingCodec.encode([0.1, 0.2, 0.3])
        destinationContext.insert(legacy)

        let unrelatedCount = 256
        for index in 0..<unrelatedCount {
            let unrelated = makeMemory(
                id: uuid(5_000 + index),
                canonicalKey: "unrelated.canonical.\(index)",
                value: "不应被候选查询触碰 \(index)",
                createdOffset: 10 + TimeInterval(index),
                updatedOffset: 11 + TimeInterval(index),
                observedOffset: 10 + TimeInterval(index),
                sourceRank: 100
            )
            // An invalid blob makes an accidental broad materialization
            // observable during scoped final validation.
            unrelated.embeddingData = index == 0
                ? Data([0xFF])
                : Data(repeating: 0xA5, count: 4 * 1024)
            destinationContext.insert(unrelated)
        }
        try destinationContext.save()

        let report = try DataMergeService.merge(
            try makePayload(from: sourceContext),
            into: destinationContext
        )

        XCTAssertEqual(report.memories, DataMergeEntityReport(inserted: 1, updated: 1, unchanged: 0))
        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, unrelatedCount + 2)
        let logical = memories.filter {
            MemoryTombstoneRecord.normalizedCanonicalKey($0.canonicalKey) == "user.favorite"
        }
        XCTAssertEqual(logical.count, 2)
        XCTAssertEqual(logical.filter { $0.state == .active }.count, 1)
        XCTAssertEqual(logical.first(where: { $0.id == incoming.id })?.state, .active)
        XCTAssertEqual(logical.first(where: { $0.id == legacy.id })?.state, .superseded)
        XCTAssertTrue(memories.allSatisfy {
            $0.canonicalKey != "unrelated.canonical.0" || $0.embeddingData == Data([0xFF])
        })
    }

    func testDifferentUserVerifiedValuesBecomeContested() throws {
        let sourceContext = makeContext()
        let conversation = makeConversation(id: uuid(500), title: "冲突收敛")
        let first = makeMemory(
            id: uuid(501),
            canonicalKey: "user.boundary",
            value: "方案一",
            createdOffset: 1,
            updatedOffset: 2,
            observedOffset: 2,
            sourceRank: 300,
            userVerified: true
        )
        let second = makeMemory(
            id: uuid(502),
            canonicalKey: "user.boundary",
            value: "方案二",
            createdOffset: 3,
            updatedOffset: 4,
            observedOffset: 4,
            sourceRank: 300,
            userVerified: true
        )
        sourceContext.insert(conversation)
        sourceContext.insert(first)
        sourceContext.insert(second)
        try sourceContext.save()

        let destinationContext = makeContext()
        _ = try DataMergeService.merge(try makePayload(from: sourceContext), into: destinationContext)

        let memories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        XCTAssertTrue(memories.allSatisfy { $0.state == .contested })
        XCTAssertTrue(memories.allSatisfy { !($0.state == .active) })
    }

    func testTombstoneMergesSourceEventsAndSuppressesOldMemory() throws {
        let conversationID = uuid(600)
        let firstEventID = uuid(601)
        let memoryID = uuid(602)
        let tombstoneID = uuid(603)

        let targetContext = makeContext()
        let targetConversation = makeConversation(id: conversationID, title: "墓碑")
        let firstEvent = makeEvent(
            id: firstEventID,
            conversationID: conversationID,
            content: "旧来源",
            deviceID: "device",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        )
        let memory = makeMemory(
            id: memoryID,
            canonicalKey: "user.deleted_fact",
            value: "旧事实",
            createdOffset: 3,
            updatedOffset: 4,
            observedOffset: 3,
            sourceRank: 100
        )
        let oldTombstone = makeTombstone(
            id: tombstoneID,
            entityID: memoryID,
            canonicalKey: "user.deleted_fact",
            sourceEventIDs: [firstEventID],
            deletedOffset: 20,
            deviceID: "device",
            reason: "user_requested"
        )
        targetContext.insert(targetConversation)
        targetContext.insert(firstEvent)
        targetContext.insert(memory)
        targetContext.insert(oldTombstone)
        try targetContext.save()

        let sourceContext = makeContext()
        let sourceConversation = makeConversation(id: conversationID, title: "墓碑")
        let secondEventID = uuid(604)
        let secondEvent = makeEvent(
            id: secondEventID,
            conversationID: conversationID,
            content: "新来源",
            deviceID: "device",
            sequence: 2,
            occurredOffset: 5,
            recordedOffset: 6
        )
        let newerTombstone = makeTombstone(
            id: tombstoneID,
            entityID: memoryID,
            canonicalKey: "user.deleted_fact",
            sourceEventIDs: [secondEventID],
            deletedOffset: 30,
            deviceID: "device",
            reason: "user_requested"
        )
        sourceContext.insert(sourceConversation)
        sourceContext.insert(secondEvent)
        sourceContext.insert(newerTombstone)
        try sourceContext.save()

        let report = try DataMergeService.merge(
            try makePayload(from: sourceContext),
            into: targetContext
        )

        XCTAssertEqual(report.events.inserted, 1)
        XCTAssertEqual(report.tombstones.updated, 1)
        let tombstone = try XCTUnwrap(
            try targetContext.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first { $0.id == tombstoneID }
        )
        XCTAssertEqual(Set(tombstone.sourceEventIDs), Set([firstEventID, secondEventID]))
        XCTAssertEqual(tombstone.deletedAt, date(30))
        let storedMemory = try XCTUnwrap(
            try targetContext.fetch(FetchDescriptor<MemoryAssertionRecord>()).first { $0.id == memoryID }
        )
        XCTAssertTrue(MemoryRepository.isSuppressedByTombstone(storedMemory, tombstones: [tombstone]))
    }

    func testLegacyBlankKeyTombstoneSuppressesPreDeletionUUIDButAllowsLaterExplicitMemory() throws {
        let sourceContext = makeContext()
        let conversation = makeConversation(id: uuid(678), title: "旧版删除标记")
        let oldMemory = makeMemory(
            id: uuid(680),
            canonicalKey: "user.legacy_fact",
            value: "删除前的旧值",
            createdOffset: 10,
            updatedOffset: 11,
            observedOffset: 10,
            sourceRank: 300,
            userVerified: true
        )
        let newMemory = makeMemory(
            id: uuid(681),
            canonicalKey: "user.legacy_fact",
            value: "删除后明确重新告知的新值",
            createdOffset: 30,
            updatedOffset: 31,
            observedOffset: 30,
            sourceRank: 300,
            userVerified: true
        )
        let legacyTombstone = makeTombstone(
            id: uuid(682),
            entityID: uuid(679),
            canonicalKey: "",
            sourceEventIDs: [],
            deletedOffset: 20,
            deviceID: "legacy-device",
            reason: "legacy_user_requested"
        )
        sourceContext.insert(conversation)
        sourceContext.insert(oldMemory)
        sourceContext.insert(newMemory)
        sourceContext.insert(legacyTombstone)
        try sourceContext.save()

        let payload: AyaneDataExport
        do {
            payload = try makePayload(from: sourceContext)
        } catch {
            XCTFail("Legacy tombstone fixture export failed: \(error)")
            return
        }

        let destinationContext = makeContext()
        do {
            _ = try DataMergeService.merge(payload, into: destinationContext)
        } catch {
            XCTFail("Legacy tombstone merge failed: \(error)")
            return
        }

        let storedMemories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let storedTombstones = try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(storedMemories.count, 2)
        XCTAssertEqual(storedTombstones.count, 1)
        XCTAssertEqual(storedTombstones.first?.canonicalKey, "")

        let eligible = MemoryRepository.eligibleMemories(
            from: storedMemories,
            tombstones: storedTombstones
        )
        XCTAssertEqual(eligible.map(\.id), [newMemory.id])
        XCTAssertTrue(storedMemories.allSatisfy { $0.state == .active })
    }

    func testEvidenceRangeAndReferenceValidationLeaveDestinationUntouched() throws {
        let sourceContext = makeContext()
        let source = try insertCompleteFixture(into: sourceContext, base: 700)
        let payload = try makePayload(from: sourceContext)

        let rangeDestination = makeContext()
        let preservedConversation = makeConversation(id: uuid(800), title: "保留")
        rangeDestination.insert(preservedConversation)
        try rangeDestination.save()
        let invalidRange = try mutateJSON(payload) { root in
            var evidence = try XCTUnwrap(root["evidence"] as? [[String: Any]])
            evidence[0]["end_utf16"] = 999_999
            root["evidence"] = evidence
        }
        XCTAssertThrowsError(try DataMergeService.merge(invalidRange, into: rangeDestination))
        XCTAssertEqual(try rangeDestination.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
        XCTAssertFalse(
            try rangeDestination.fetch(FetchDescriptor<ConversationRecord>()).contains { $0.id == source.conversationID }
        )

        let referenceDestination = makeContext()
        let referencePreserved = makeConversation(id: uuid(801), title: "保留")
        referenceDestination.insert(referencePreserved)
        try referenceDestination.save()
        let invalidReference = try mutateJSON(payload) { root in
            var evidence = try XCTUnwrap(root["evidence"] as? [[String: Any]])
            evidence[0]["event_id"] = uuid(899).uuidString
            root["evidence"] = evidence
        }
        XCTAssertThrowsError(try DataMergeService.merge(invalidReference, into: referenceDestination)) { error in
            guard case .invalidReference = error as? DataMergeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try referenceDestination.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
    }

    func testEventRoundTripDateDifferencesDoNotCreateIdentityConflict() throws {
        let conversationID = uuid(900)
        let eventID = uuid(901)
        let targetContext = makeContext()
        let targetConversation = makeConversation(id: conversationID, title: "亚秒")
        let targetEvent = makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "相同正文",
            deviceID: "roundtrip-device",
            sequence: 1,
            occurredOffset: 1.123,
            recordedOffset: 2.234
        )
        targetContext.insert(targetConversation)
        targetContext.insert(targetEvent)
        try targetContext.save()

        let sourceContext = makeContext()
        let sourceConversation = makeConversation(id: conversationID, title: "亚秒")
        let sourceEvent = makeEvent(
            id: eventID,
            conversationID: conversationID,
            content: "相同正文",
            deviceID: "roundtrip-device",
            sequence: 1,
            occurredOffset: 1.987,
            recordedOffset: 2.876
        )
        sourceContext.insert(sourceConversation)
        sourceContext.insert(sourceEvent)
        try sourceContext.save()

        let report = try DataMergeService.merge(
            try makePayload(from: sourceContext),
            into: targetContext
        )

        XCTAssertEqual(report.events, DataMergeEntityReport(inserted: 0, updated: 0, unchanged: 1))
        let storedEvent = try XCTUnwrap(
            try targetContext.fetch(FetchDescriptor<ConversationEvent>()).first { $0.id == eventID }
        )
        XCTAssertEqual(storedEvent.occurredAt, targetEvent.occurredAt)
        XCTAssertEqual(storedEvent.recordedAt, targetEvent.recordedAt)
    }

    private struct CompleteFixture {
        let conversationID: UUID
        let eventID: UUID
        let memoryID: UUID
    }

    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true, preferCloud: false).container)
    }

    private func makePayload(from context: ModelContext) throws -> AyaneDataExport {
        let suiteName = "AyaneTests.DataMerge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try DataExportService.makePayload(
            context: context,
            defaults: defaults,
            now: date(10_000)
        )
    }

    private func insertCompleteFixture(into context: ModelContext, base: Int) throws -> CompleteFixture {
        let conversation = makeConversation(
            id: uuid(base),
            title: "完整 fixture \(base)",
            createdOffset: 0,
            updatedOffset: 10
        )
        let content = "我喜欢乌龙茶"
        let event = makeEvent(
            id: uuid(base + 1),
            conversationID: conversation.id,
            content: content,
            deviceID: "fixture-\(base)",
            sequence: 1,
            occurredOffset: 1,
            recordedOffset: 2
        )
        let memory = makeMemory(
            id: uuid(base + 2),
            canonicalKey: "user.favorite_drink.\(base)",
            value: "乌龙茶",
            createdOffset: 3,
            updatedOffset: 4,
            observedOffset: 1,
            sourceRank: 300
        )
        memory.embeddingData = MemoryEmbeddingCodec.encode([0.1, 0.2, 0.3])
        memory.embeddingModelID = "fixture-embedding"
        let evidence = MemoryEvidenceRecord(
            id: uuid(base + 3),
            memoryID: memory.id,
            eventID: event.id,
            startUTF16: 0,
            endUTF16: content.utf16.count,
            relation: .supports,
            quoteHash: ContentHasher.sha256(content),
            confidence: 0.9
        )
        evidence.createdAt = date(5)
        let summary = makeSummary(
            id: uuid(base + 4),
            conversationID: conversation.id,
            content: "用户喜欢乌龙茶。",
            firstEventID: event.id,
            lastEventID: event.id
        )
        let tombstone = makeTombstone(
            id: uuid(base + 5),
            entityID: uuid(base + 500),
            canonicalKey: "obsolete.\(base)",
            sourceEventIDs: [event.id],
            deletedOffset: 6,
            deviceID: "fixture-\(base)",
            reason: "fixture"
        )

        context.insert(conversation)
        context.insert(event)
        context.insert(memory)
        context.insert(evidence)
        context.insert(summary)
        context.insert(tombstone)
        try context.save()
        return CompleteFixture(conversationID: conversation.id, eventID: event.id, memoryID: memory.id)
    }

    private func makeConversation(
        id: UUID,
        title: String,
        createdOffset: TimeInterval = 0,
        updatedOffset: TimeInterval? = nil
    ) -> ConversationRecord {
        let record = ConversationRecord(id: id, title: title, createdAt: date(createdOffset))
        record.updatedAt = date(updatedOffset ?? createdOffset)
        return record
    }

    private func makeProfile(
        id: UUID = CompanionProfileRecord.singletonID,
        name: String = "绫音",
        userName: String = "你",
        prompt: String = "保持坦诚",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        revision: Int = 0,
        deviceID: String = "fixture-device"
    ) -> CompanionProfileRecord {
        CompanionProfileRecord(
            id: id,
            name: name,
            userName: userName,
            prompt: prompt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision,
            deviceID: deviceID
        )
    }

    private func makeEvent(
        id: UUID,
        conversationID: UUID,
        content: String,
        deviceID: String,
        sequence: Int,
        occurredOffset: TimeInterval,
        recordedOffset: TimeInterval,
        deliveryState: EventDeliveryState = .complete
    ) -> ConversationEvent {
        let record = ConversationEvent(
            id: id,
            conversationID: conversationID,
            deviceID: deviceID,
            deviceSequence: sequence,
            logicalTimestamp: "\(sequence)-\(deviceID)-\(sequence)",
            occurredAt: date(occurredOffset),
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: deliveryState
        )
        record.recordedAt = date(recordedOffset)
        return record
    }

    private func makeMemory(
        id: UUID,
        canonicalKey: String,
        value: String,
        createdOffset: TimeInterval,
        updatedOffset: TimeInterval,
        observedOffset: TimeInterval,
        sourceRank: Int,
        state: MemoryState = .active,
        userVerified: Bool = false
    ) -> MemoryAssertionRecord {
        let record = MemoryAssertionRecord(
            id: id,
            kind: .preference,
            subject: "user",
            predicate: "preference",
            value: value,
            canonicalKey: canonicalKey,
            state: state,
            confidence: 0.8,
            importance: 0.7,
            sensitive: false,
            sourceRank: sourceRank,
            observedAt: date(observedOffset),
            extractorID: "fixture",
            deviceID: "fixture-device"
        )
        record.createdAt = date(createdOffset)
        record.updatedAt = date(updatedOffset)
        record.userVerified = userVerified
        return record
    }

    private func makeSummary(
        id: UUID,
        conversationID: UUID,
        content: String,
        firstEventID: UUID?,
        lastEventID: UUID?
    ) -> MemorySummaryRecord {
        let record = MemorySummaryRecord(
            conversationID: conversationID,
            scope: "session",
            content: content,
            firstEventID: firstEventID,
            lastEventID: lastEventID,
            coveredEventCount: firstEventID == nil ? 0 : 1,
            extractorID: "fixture"
        )
        record.id = id
        record.createdAt = date(7)
        record.updatedAt = date(8)
        return record
    }

    private func makeTombstone(
        id: UUID,
        entityID: UUID,
        canonicalKey: String,
        sourceEventIDs: [UUID],
        deletedOffset: TimeInterval,
        deviceID: String,
        reason: String
    ) -> MemoryTombstoneRecord {
        let record = MemoryTombstoneRecord(
            entityID: entityID,
            entityType: "memory",
            canonicalKey: canonicalKey,
            sourceEventIDs: sourceEventIDs,
            deviceID: deviceID,
            reason: reason
        )
        record.id = id
        record.deletedAt = date(deletedOffset)
        return record
    }

    private func mutateJSON(
        _ payload: AyaneDataExport,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> AyaneDataExport {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(payload)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        try mutate(&root)
        let modified = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AyaneDataExport.self, from: modified)
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", value))")!
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}
