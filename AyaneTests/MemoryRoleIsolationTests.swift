import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryRoleIsolationTests: XCTestCase {
    func testSameCanonicalKeyStaysIsolatedAndEvidenceKeepsRole() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let roleA = UUID()
        let roleB = UUID()
        let eventA = UUID()
        let eventB = UUID()
        let contentA = "A 喜欢咖啡"
        let contentB = "B 喜欢茶"
        try insertSourceEvent(
            id: eventA,
            roleID: roleA,
            content: contentA,
            context: context
        )
        try insertSourceEvent(
            id: eventB,
            roleID: roleB,
            content: contentB,
            context: context
        )

        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventA, value: "咖啡", quote: contentA)],
                eventContents: [eventA: contentA],
                context: context,
                deviceID: "role-a-device",
                extractorID: "role-fixture",
                roleID: roleA
            ),
            1
        )
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventB, value: "茶", quote: contentB)],
                eventContents: [eventB: contentB],
                context: context,
                deviceID: "role-b-device",
                extractorID: "role-fixture",
                roleID: roleB
            ),
            1
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(Set(memories.map(\.resolvedRoleID)), Set([roleA, roleB]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: memories.map {
                ($0.resolvedRoleID, $0.value)
            }),
            [roleA: "咖啡", roleB: "茶"]
        )

        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(Set(evidence.map(\.resolvedRoleID)), Set([roleA, roleB]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: evidence.map {
                ($0.resolvedRoleID, $0.eventID)
            }),
            [roleA: eventA, roleB: eventB]
        )

        let roleAPage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            roleID: roleA,
            after: nil,
            storeRevision: 0
        )
        let roleBPage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            roleID: roleB,
            after: nil,
            storeRevision: 0
        )
        XCTAssertEqual(roleAPage.items.map(\.value), ["咖啡"])
        XCTAssertEqual(roleBPage.items.map(\.value), ["茶"])
    }

    func testForgettingOneRoleDoesNotSuppressTheOtherRole() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let roleA = UUID()
        let roleB = UUID()
        let eventA = UUID()
        let eventB = UUID()
        let contentA = "A 喜欢咖啡"
        let contentB = "B 喜欢茶"
        try insertSourceEvent(
            id: eventA,
            roleID: roleA,
            content: contentA,
            context: context
        )
        try insertSourceEvent(
            id: eventB,
            roleID: roleB,
            content: contentB,
            context: context
        )

        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: eventA, value: "咖啡", quote: contentA)],
            eventContents: [eventA: contentA],
            context: context,
            deviceID: "role-a-device",
            extractorID: "role-fixture",
            roleID: roleA
        )
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: eventB, value: "茶", quote: contentB)],
            eventContents: [eventB: contentB],
            context: context,
            deviceID: "role-b-device",
            extractorID: "role-fixture",
            roleID: roleB
        )

        let roleAMemory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first {
                $0.resolvedRoleID == roleA
            }
        )
        try MemoryRepository.forget(roleAMemory, context: context, deviceID: "role-a-device")

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let roleBMemory = try XCTUnwrap(memories.first { $0.resolvedRoleID == roleB })
        XCTAssertEqual(roleBMemory.state, .active)
        XCTAssertEqual(roleBMemory.value, "茶")
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).filter {
                $0.resolvedRoleID == roleB
            }.count,
            1
        )

        let tombstones = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones[0].resolvedRoleID, roleA)
        XCTAssertFalse(
            MemoryRepository.isSuppressedByTombstone(
                roleBMemory,
                tombstones: tombstones
            )
        )
        XCTAssertEqual(
            MemoryRepository.eligibleMemories(
                from: memories,
                tombstones: tombstones,
                roleID: roleB
            ).map(\.value),
            ["茶"]
        )
    }

    func testLegacyNilRowsRemainReadableOnlyInLegacyScope() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let legacyMemory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "咖啡",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.9,
            importance: 0.8,
            sensitive: false,
            sourceRank: 100,
            extractorID: "legacy-fixture",
            deviceID: "legacy-device",
            roleID: nil
        )
        context.insert(legacyMemory)
        try context.save()

        let eventID = UUID()
        let content = "我喜欢咖啡"
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventID, value: "咖啡", quote: content)],
                eventContents: [eventID: content],
                context: context,
                deviceID: "legacy-device",
                extractorID: "legacy-fixture"
            ),
            1
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].id, legacyMemory.id)
        XCTAssertEqual(memories[0].resolvedRoleID, RoleScope.legacyRoleID)

        let nonLegacyRole = UUID()
        XCTAssertTrue(
            MemoryRepository.eligibleMemories(
                from: memories,
                tombstones: [],
                roleID: nonLegacyRole
            ).isEmpty
        )
        XCTAssertEqual(
            MemoryRepository.eligibleMemories(
                from: memories,
                tombstones: [],
                roleID: RoleScope.legacyRoleID
            ).map(\.id),
            [legacyMemory.id]
        )
    }

    func testCrossRoleSourceEventFailsClosedWithoutWritingMemory() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let roleA = UUID()
        let roleB = UUID()
        let eventA = UUID()
        let contentA = "A 喜欢咖啡"
        try insertSourceEvent(
            id: eventA,
            roleID: roleA,
            content: contentA,
            context: context
        )

        XCTAssertThrowsError(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventA, value: "咖啡", quote: contentA)],
                eventContents: [eventA: contentA],
                context: context,
                deviceID: "role-b-device",
                extractorID: "role-fixture",
                roleID: roleB
            )
        ) { error in
            guard case let .sourceEventRoleMismatch(sourceEventID, expectedRoleID, actualRoleID) =
                error as? MemoryRepositoryError else {
                return XCTFail("expected a source-event role mismatch, got \(error)")
            }
            XCTAssertEqual(sourceEventID, eventA)
            XCTAssertEqual(expectedRoleID, roleB)
            XCTAssertEqual(actualRoleID, roleA)
        }

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()),
            0
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()),
            0
        )
    }

    func testMissingExplicitSourceEventFailsClosed() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let role = UUID()
        let missingEvent = UUID()
        let content = "我喜欢咖啡"

        XCTAssertThrowsError(
            try MemoryRepository.apply(
                [makeCandidate(eventID: missingEvent, value: "咖啡", quote: content)],
                eventContents: [missingEvent: content],
                context: context,
                deviceID: "role-device",
                extractorID: "role-fixture",
                roleID: role
            )
        ) { error in
            guard case let .sourceEventNotFound(sourceEventID) = error as? MemoryRepositoryError else {
                return XCTFail("expected a missing source-event error, got \(error)")
            }
            XCTAssertEqual(sourceEventID, missingEvent)
        }
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()),
            0
        )
    }

    func testGroupUserSourceRemainsUsableForTargetRole() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let role = UUID()
        let conversationID = UUID()
        let eventID = UUID()
        let content = "我在群里喜欢咖啡"
        context.insert(GroupConversationRecord(
            conversationID: conversationID,
            groupName: "角色群聊"
        ))
        context.insert(ConversationEvent(
            id: eventID,
            conversationID: conversationID,
            deviceID: "group-device",
            deviceSequence: 1,
            logicalTimestamp: "1-group-device-1",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: .complete,
            roleID: nil,
            senderRoleID: nil
        ))
        try context.save()

        XCTAssertThrowsError(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventID, value: "咖啡", quote: content)],
                eventContents: [eventID: content],
                context: context,
                deviceID: "role-device",
                extractorID: "role-fixture",
                roleID: role
            )
        )

        context.insert(GroupParticipantRecord(
            conversationID: conversationID,
            participantRoleID: role,
            participantKind: .companion,
            displayName: "角色"
        ))
        try context.save()

        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventID, value: "咖啡", quote: content)],
                eventContents: [eventID: content],
                context: context,
                deviceID: "role-device",
                extractorID: "role-fixture",
                roleID: role
            ),
            1
        )
        let memory = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first
        )
        XCTAssertEqual(memory.resolvedRoleID, role)
    }

    private func makeCandidate(
        eventID: UUID,
        value: String,
        quote: String,
        canonicalKey: String = "user.favorite_drink"
    ) -> ExtractedMemoryCandidate {
        ExtractedMemoryCandidate(
            operation: .upsert,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: value,
            canonicalKey: canonicalKey,
            confidence: 0.98,
            importance: 0.8,
            explicit: true,
            sensitive: false,
            sourceEventID: eventID,
            sourceQuote: quote,
            startUTF16: 0,
            endUTF16: quote.utf16.count,
            validFrom: nil,
            validTo: nil
        )
    }

    private func insertSourceEvent(
        id: UUID,
        roleID: UUID,
        content: String,
        context: ModelContext
    ) throws {
        context.insert(ConversationEvent(
            id: id,
            conversationID: UUID(),
            deviceID: "role-fixture",
            deviceSequence: 1,
            logicalTimestamp: "1-role-fixture-1",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: .complete,
            roleID: roleID
        ))
        try context.save()
    }
}
