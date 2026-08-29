import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryRepositoryTests: XCTestCase {
    func testLaterDirectEvidencePromotesExistingCandidateToActive() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstEvent = UUID()
        let secondEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(
                eventID: firstEvent,
                value: "上海",
                quote: "我可能住在上海",
                explicit: false
            )],
            eventContents: [firstEvent: "我可能住在上海"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first?.state,
            .candidate
        )

        _ = try MemoryRepository.apply(
            [makeCandidate(
                eventID: secondEvent,
                value: "上海",
                quote: "我住在上海",
                explicit: true
            )],
            eventContents: [secondEvent: "我住在上海"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first?.state,
            .active
        )
    }

    func testOlderCandidatePromotionCannotSupersedeNewerActiveFact() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let oldCandidateEvent = UUID()
        let newerActiveEvent = UUID()
        let oldConfirmationEvent = UUID()

        _ = try MemoryRepository.apply(
            [makeCandidate(
                eventID: oldCandidateEvent,
                value: "咖啡",
                quote: "我可能喜欢咖啡",
                explicit: false
            )],
            eventContents: [oldCandidateEvent: "我可能喜欢咖啡"],
            eventDates: [oldCandidateEvent: Date(timeIntervalSince1970: 100)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: newerActiveEvent, value: "茶", quote: "我现在喜欢茶")],
            eventContents: [newerActiveEvent: "我现在喜欢茶"],
            eventDates: [newerActiveEvent: Date(timeIntervalSince1970: 200)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        _ = try MemoryRepository.apply(
            [makeCandidate(
                eventID: oldConfirmationEvent,
                value: "咖啡",
                quote: "我喜欢咖啡",
                explicit: true
            )],
            eventContents: [oldConfirmationEvent: "我喜欢咖啡"],
            eventDates: [oldConfirmationEvent: Date(timeIntervalSince1970: 150)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.first(where: { $0.value == "茶" })?.state, .active)
        XCTAssertEqual(memories.first(where: { $0.value == "咖啡" })?.state, .contested)
    }

    func testExplicitMemoryIsStoredWithEvidence() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        let content = "我最喜欢乌龙茶"
        let candidate = makeCandidate(eventID: eventID, value: "乌龙茶", quote: content)

        let count = try MemoryRepository.apply(
            [candidate],
            eventContents: [eventID: content],
            context: context,
            deviceID: "test-device",
            extractorID: "fixture"
        )

        XCTAssertEqual(count, 1)
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].state, .active)
        XCTAssertEqual(memories[0].value, "乌龙茶")
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).first?.eventID,
            eventID
        )
    }

    func testNewExplicitValueSupersedesUnverifiedValue() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstEvent = UUID()
        let secondEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: firstEvent, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [firstEvent: "我喜欢咖啡"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: secondEvent, value: "茶", quote: "我现在喜欢茶")],
            eventContents: [secondEvent: "我现在喜欢茶"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.filter { $0.state == .active }.map(\.value), ["茶"])
        XCTAssertEqual(memories.filter { $0.state == .superseded }.map(\.value), ["咖啡"])
    }

    func testVerifiedMemoryCannotBeSilentlyOverwritten() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: firstEvent, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [firstEvent: "我喜欢咖啡"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        try MemoryRepository.userEdited(original, value: "手冲咖啡", context: context)

        let secondEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: secondEvent, value: "茶", quote: "我现在喜欢茶")],
            eventContents: [secondEvent: "我现在喜欢茶"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.first(where: { $0.userVerified })?.value, "手冲咖啡")
        XCTAssertEqual(memories.first(where: { $0.state == .contested })?.value, "茶")
    }

    func testForgetClearsDerivedContentAndCreatesTombstone() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: eventID, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [eventID: "我喜欢咖啡"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        try MemoryRepository.forget(memory, context: context, deviceID: "d")

        XCTAssertEqual(memory.state, .forgotten)
        XCTAssertTrue(memory.value.isEmpty)
        let tombstones = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.canonicalKey, "user.favorite_drink")
        XCTAssertEqual(tombstones.first?.sourceEventIDs, [eventID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)
    }

    func testForgottenKeyRejectsOldHistoryAndInferenceButAllowsLaterExplicitRestatement() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let originalEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: originalEvent, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [originalEvent: "我喜欢咖啡"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        try MemoryRepository.forget(memory, context: context, deviceID: "d")
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first)
        tombstone.deletedAt = Date(timeIntervalSince1970: 200)
        try context.save()

        let oldEvent = UUID()
        let oldCount = try MemoryRepository.apply(
            [makeCandidate(eventID: oldEvent, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [oldEvent: "我喜欢咖啡"],
            eventDates: [oldEvent: Date(timeIntervalSince1970: 150)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        XCTAssertEqual(oldCount, 0)

        let inferredEvent = UUID()
        let inferredCount = try MemoryRepository.apply(
            [makeCandidate(
                eventID: inferredEvent,
                value: "茶",
                quote: "我好像更喜欢茶",
                explicit: false
            )],
            eventContents: [inferredEvent: "我好像更喜欢茶"],
            eventDates: [inferredEvent: Date(timeIntervalSince1970: 300)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        XCTAssertEqual(inferredCount, 0)

        let restatementEvent = UUID()
        let restatedCount = try MemoryRepository.apply(
            [makeCandidate(eventID: restatementEvent, value: "茶", quote: "请重新记住，我喜欢茶")],
            eventContents: [restatementEvent: "请重新记住，我喜欢茶"],
            eventDates: [restatementEvent: Date(timeIntervalSince1970: 300)],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        XCTAssertEqual(restatedCount, 1)
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.filter { $0.state == .active }.map(\.value), ["茶"])
    }

    func testLegacyEmptyKeyForgetCutoffRejectsOldOrInferredResurrection() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "",
            deviceID: "legacy-device"
        )
        legacy.deletedAt = Date(timeIntervalSince1970: 200)
        context.insert(legacy)
        try context.save()

        let oldEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: oldEvent, value: "咖啡", quote: "我喜欢咖啡")],
                eventContents: [oldEvent: "我喜欢咖啡"],
                eventDates: [oldEvent: Date(timeIntervalSince1970: 150)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            0
        )

        let inferredEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: inferredEvent,
                    value: "茶",
                    quote: "我好像更喜欢茶",
                    explicit: false
                )],
                eventContents: [inferredEvent: "我好像更喜欢茶"],
                eventDates: [inferredEvent: Date(timeIntervalSince1970: 300)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            0
        )

        let restatement = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: restatement, value: "茶", quote: "请重新记住，我喜欢茶")],
                eventContents: [restatement: "请重新记住，我喜欢茶"],
                eventDates: [restatement: Date(timeIntervalSince1970: 300)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).filter {
                $0.state == .active
            }.map(\.value),
            ["茶"]
        )
    }

    func testWhitespaceCanonicalKeyCandidateIsRejected() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()

        XCTAssertThrowsError(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: eventID,
                    value: "咖啡",
                    quote: "我喜欢咖啡",
                    canonicalKey: "   "
                )],
                eventContents: [eventID: "我喜欢咖啡"],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            )
        ) { error in
            XCTAssertEqual(error as? MemoryRepositoryError, .blankCanonicalKey)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()), 0)
    }

    func testWhitespaceLegacyTombstoneSuppressesOldMemoryAndNormalizesRestatementKey() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "\t \u{00A0}",
            deviceID: "legacy-device"
        )
        legacy.deletedAt = Date(timeIntervalSince1970: 200)
        context.insert(legacy)
        try context.save()

        let oldEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: oldEvent,
                    value: "咖啡",
                    quote: "我喜欢咖啡",
                    canonicalKey: " User.Favorite_Drink "
                )],
                eventContents: [oldEvent: "我喜欢咖啡"],
                eventDates: [oldEvent: Date(timeIntervalSince1970: 150)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            0
        )

        let restatementEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: restatementEvent,
                    value: "茶",
                    quote: "请重新记住，我喜欢茶",
                    canonicalKey: " User.Favorite_Drink "
                )],
                eventContents: [restatementEvent: "请重新记住，我喜欢茶"],
                eventDates: [restatementEvent: Date(timeIntervalSince1970: 300)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            1
        )
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.map(\.canonicalKey), ["user.favorite_drink"])
        XCTAssertEqual(memories.first?.value, "茶")
    }

    func testStronglyNormalizedCanonicalKeyCannotBypassTombstone() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let originalEvent = UUID()
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: originalEvent, value: "咖啡", quote: "我喜欢咖啡")],
            eventContents: [originalEvent: "我喜欢咖啡"],
            context: context,
            deviceID: "d",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        try MemoryRepository.forget(memory, context: context, deviceID: "d")
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first)
        tombstone.deletedAt = Date(timeIntervalSince1970: 200)
        try context.save()

        let hiddenCanonicalKey = "\u{FEFF} USER.\u{200B}Favorite_Drink\u{2060} "
        let oldEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: oldEvent,
                    value: "咖啡",
                    quote: "我喜欢咖啡",
                    canonicalKey: hiddenCanonicalKey
                )],
                eventContents: [oldEvent: "我喜欢咖啡"],
                eventDates: [oldEvent: Date(timeIntervalSince1970: 150)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            0
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).filter {
                $0.state == .active
            }.isEmpty
        )

        let restatementEvent = UUID()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: restatementEvent,
                    value: "茶",
                    quote: "请重新记住，我喜欢茶",
                    canonicalKey: hiddenCanonicalKey
                )],
                eventContents: [restatementEvent: "请重新记住，我喜欢茶"],
                eventDates: [restatementEvent: Date(timeIntervalSince1970: 300)],
                context: context,
                deviceID: "d",
                extractorID: "fixture"
            ),
            1
        )
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.filter { $0.state == .active }.map(\.canonicalKey), ["user.favorite_drink"])
        XCTAssertEqual(memories.first(where: { $0.state == .active })?.value, "茶")
    }

    func testSameTimestampTombstoneConflictDoesNotDropEitherCanonicalKey() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let tombstoneID = UUID()
        let deletedAt = Date(timeIntervalSince1970: 200)
        for key in ["user.first_conflict", "user.second_conflict"] {
            let tombstone = MemoryTombstoneRecord(
                entityID: UUID(),
                entityType: "memory",
                canonicalKey: key,
                deviceID: "conflict-device"
            )
            tombstone.id = tombstoneID
            tombstone.deletedAt = deletedAt
            context.insert(tombstone)
        }
        try context.save()

        let firstEventID = UUID()
        let secondEventID = UUID()
        let firstText = "旧的第一条事实"
        let secondText = "旧的第二条事实"
        let count = try MemoryRepository.apply(
            [
                makeCandidate(
                    eventID: firstEventID,
                    value: "第一条",
                    quote: firstText,
                    canonicalKey: "user.first_conflict"
                ),
                makeCandidate(
                    eventID: secondEventID,
                    value: "第二条",
                    quote: secondText,
                    canonicalKey: "user.second_conflict"
                )
            ],
            eventContents: [
                firstEventID: firstText,
                secondEventID: secondText
            ],
            eventDates: [
                firstEventID: Date(timeIntervalSince1970: 150),
                secondEventID: Date(timeIntervalSince1970: 150)
            ],
            context: context,
            deviceID: "conflict-device",
            extractorID: "fixture"
        )

        XCTAssertEqual(count, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()), 0)
    }

    func testEqualUpdatedAtMatchingUsesDeterministicPreferredRecord() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let sameUpdatedAt = Date(timeIntervalSince1970: 500)
        let lower = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "alpha",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.8,
            importance: 0.8,
            sensitive: false,
            sourceRank: 100,
            extractorID: "fixture",
            deviceID: "fixture"
        )
        let higher = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "zeta",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.8,
            importance: 0.8,
            sensitive: false,
            sourceRank: 100,
            extractorID: "fixture",
            deviceID: "fixture"
        )
        lower.updatedAt = sameUpdatedAt
        higher.updatedAt = sameUpdatedAt
        context.insert(lower)
        context.insert(higher)
        try context.save()

        let eventID = UUID()
        let content = "我现在喜欢绿茶"
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(eventID: eventID, value: "绿茶", quote: content)],
                eventContents: [eventID: content],
                context: context,
                deviceID: "fixture",
                extractorID: "fixture"
            ),
            1
        )
        let inserted = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first {
                $0.value == "绿茶"
            }
        )
        XCTAssertEqual(inserted.supersedesID, higher.id)
        XCTAssertEqual(higher.state, .superseded)
        XCTAssertEqual(lower.state, .active)
    }

    func testForgottenUUIDWinsEligibilityRegardlessOfArrivalOrder() throws {
        let memoryID = UUID(uuidString: "00000000-0000-0000-0000-000000001401")!
        let active = MemoryAssertionRecord(
            id: memoryID,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "较新的活动值",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.99,
            importance: 0.99,
            sensitive: false,
            sourceRank: 999,
            extractorID: "active",
            deviceID: "active-device"
        )
        active.createdAt = Date(timeIntervalSince1970: 100)
        active.updatedAt = Date(timeIntervalSince1970: 500)
        active.isPinned = true
        active.userVerified = true
        active.embeddingData = MemoryEmbeddingCodec.encode([0.9, 0.8])
        active.embeddingModelID = "active-embedding"

        let forgotten = MemoryAssertionRecord(
            id: memoryID,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "旧副本不应泄露",
            canonicalKey: "user.favorite_drink",
            state: .forgotten,
            confidence: 0.1,
            importance: 0.1,
            sensitive: false,
            sourceRank: 1,
            extractorID: "forgotten",
            deviceID: "forgotten-device"
        )
        forgotten.createdAt = Date(timeIntervalSince1970: 90)
        forgotten.updatedAt = Date(timeIntervalSince1970: 200)
        forgotten.isPinned = true
        forgotten.userVerified = true
        forgotten.embeddingData = MemoryEmbeddingCodec.encode([0.1, 0.2])
        forgotten.embeddingModelID = "forgotten-embedding"

        XCTAssertTrue(
            MemoryRepository.eligibleMemories(
                from: [active, forgotten],
                tombstones: []
            ).isEmpty
        )
        XCTAssertTrue(
            MemoryRepository.eligibleMemories(
                from: [forgotten, active],
                tombstones: []
            ).isEmpty
        )
    }

    private func makeCandidate(
        eventID: UUID,
        value: String,
        quote: String,
        explicit: Bool = true,
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
            explicit: explicit,
            sensitive: false,
            sourceEventID: eventID,
            sourceQuote: quote,
            startUTF16: 0,
            endUTF16: quote.utf16.count,
            validFrom: nil,
            validTo: nil
        )
    }
}
