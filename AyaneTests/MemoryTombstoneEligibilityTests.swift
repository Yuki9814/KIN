import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryTombstoneEligibilityTests: XCTestCase {
    func testUserEditedRejectsForgottenReference() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        let content = "我喜欢咖啡"
        _ = try MemoryRepository.apply(
            [candidate(eventID: eventID, value: "咖啡", quote: content)],
            eventContents: [eventID: content],
            context: context,
            deviceID: "tombstone-test",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        try MemoryRepository.forget(memory, context: context, deviceID: "tombstone-test")

        XCTAssertThrowsError(
            try MemoryRepository.userEdited(memory, value: "茶", context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryRepositoryError, .forgottenMemoryCannotBeChanged)
        }
        XCTAssertEqual(memory.state, .forgotten)
        XCTAssertTrue(memory.value.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryTombstoneRecord>()), 1)
    }

    func testStaleActiveSameKeyIsSuppressedButPostTombstoneVersionIsEligibleForPrompt() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let old = makeStoredMemory(value: "咖啡")
        let fresh = makeStoredMemory(value: "乌龙茶")
        let deletionDate = Date(timeIntervalSince1970: 200)
        old.createdAt = Date(timeIntervalSince1970: 100)
        fresh.createdAt = Date(timeIntervalSince1970: 300)
        let tombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            deviceID: "remote-device"
        )
        tombstone.deletedAt = deletionDate
        context.insert(old)
        context.insert(fresh)
        context.insert(tombstone)
        try context.save()

        let eligible = MemoryRepository.eligibleMemories(
            from: [old, fresh],
            tombstones: [tombstone]
        )
        XCTAssertEqual(eligible.map(\.id), [fresh.id])
        let snapshots = PromptAssembler.snapshots(
            from: [old, fresh],
            tombstones: [tombstone]
        )
        XCTAssertEqual(snapshots.map(\.id), [fresh.id.uuidString])
        XCTAssertTrue(snapshots.first?.text.contains("乌龙茶") == true)
        XCTAssertFalse(snapshots.first?.text.contains("咖啡") == true)
    }

    func testConversationRetractionRejectsOldReplayAndAllowsLaterExplicitRestatement() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let originalEvent = UUID()
        let originalText = "我喜欢咖啡"
        _ = try MemoryRepository.apply(
            [candidate(eventID: originalEvent, value: "咖啡", quote: originalText)],
            eventContents: [originalEvent: originalText],
            eventDates: [originalEvent: Date(timeIntervalSince1970: 100)],
            context: context,
            deviceID: "tombstone-test",
            extractorID: "fixture"
        )

        let retractionEvent = UUID()
        let retractionText = "请撤回我喜欢咖啡这件事"
        _ = try MemoryRepository.apply(
            [candidate(
                eventID: retractionEvent,
                operation: .retract,
                value: "",
                quote: retractionText
            )],
            eventContents: [retractionEvent: retractionText],
            eventDates: [retractionEvent: Date(timeIntervalSince1970: 200)],
            context: context,
            deviceID: "tombstone-test",
            extractorID: "fixture"
        )
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first)
        XCTAssertEqual(tombstone.reason, "conversation_retraction")
        tombstone.deletedAt = Date(timeIntervalSince1970: 200)
        try context.save()

        let replayEvent = UUID()
        let replayCount = try MemoryRepository.apply(
            [candidate(eventID: replayEvent, value: "咖啡", quote: originalText)],
            eventContents: [replayEvent: originalText],
            eventDates: [replayEvent: Date(timeIntervalSince1970: 150)],
            context: context,
            deviceID: "tombstone-test",
            extractorID: "fixture"
        )
        XCTAssertEqual(replayCount, 0)

        let restatementEvent = UUID()
        let restatementText = "现在请重新记住，我喜欢乌龙茶"
        let restatementCount = try MemoryRepository.apply(
            [candidate(eventID: restatementEvent, value: "乌龙茶", quote: restatementText)],
            eventContents: [restatementEvent: restatementText],
            eventDates: [restatementEvent: Date(timeIntervalSince1970: 300)],
            context: context,
            deviceID: "tombstone-test",
            extractorID: "fixture"
        )
        XCTAssertEqual(restatementCount, 1)
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.filter { $0.state == .active }.map(\.value), ["乌龙茶"])
    }

    private func makeStoredMemory(value: String) -> MemoryAssertionRecord {
        MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: value,
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 1,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "fixture-device"
        )
    }

    private func candidate(
        eventID: UUID,
        operation: ExtractionOperation = .upsert,
        value: String,
        quote: String
    ) -> ExtractedMemoryCandidate {
        ExtractedMemoryCandidate(
            operation: operation,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: value,
            canonicalKey: "user.favorite_drink",
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
}
