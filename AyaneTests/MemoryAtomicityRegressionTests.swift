import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryAtomicityRegressionTests: XCTestCase {
    func testSameBatchSameCanonicalKeyAndValueCreatesOneActiveMemory() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstEventID = UUID()
        let secondEventID = UUID()
        let firstContent = "我喜欢乌龙茶"
        let secondContent = "请记住我最喜欢乌龙茶"
        let first = makeCandidate(
            eventID: firstEventID,
            value: "乌龙茶",
            quote: firstContent
        )
        let second = makeCandidate(
            eventID: secondEventID,
            value: "乌龙茶",
            quote: secondContent
        )

        _ = try MemoryRepository.apply(
            [first, second],
            eventContents: [
                firstEventID: firstContent,
                secondEventID: secondContent
            ],
            context: context,
            deviceID: "atomicity-test-device",
            extractorID: "atomicity-fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.filter { $0.state == .active }.count, 1)
        XCTAssertEqual(memories.first?.canonicalKey, "user.favorite_drink")
        XCTAssertEqual(memories.first?.value, "乌龙茶")

        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(Set(evidence.map(\.memoryID)).count, 1)
        XCTAssertEqual(Set(evidence.map(\.eventID)), Set([firstEventID, secondEventID]))
    }

    func testReapplyingSameCandidateBatchDoesNotAddMemoryOrEvidence() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        let content = "我最喜欢乌龙茶"
        let candidate = makeCandidate(eventID: eventID, value: "乌龙茶", quote: content)
        let input = [candidate]
        let contents = [eventID: content]

        _ = try MemoryRepository.apply(
            input,
            eventContents: contents,
            context: context,
            deviceID: "atomicity-test-device",
            extractorID: "atomicity-fixture"
        )
        let initialMemories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let initialEvidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        let initialMemoryIDs = Set(initialMemories.map(\.id))
        let initialEvidenceIDs = Set(initialEvidence.map(\.id))

        _ = try MemoryRepository.apply(
            input,
            eventContents: contents,
            context: context,
            deviceID: "atomicity-test-device",
            extractorID: "atomicity-fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(memories.count, initialMemories.count)
        XCTAssertEqual(evidence.count, initialEvidence.count)
        XCTAssertEqual(Set(memories.map(\.id)), initialMemoryIDs)
        XCTAssertEqual(Set(evidence.map(\.id)), initialEvidenceIDs)
    }

    func testSameBatchDifferentValuesUseObservedDateForOneActiveSupersessionChain() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let olderEventID = UUID()
        let newerEventID = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_700_000_100)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_200)
        let olderContent = "我以前喜欢咖啡"
        let newerContent = "我现在喜欢乌龙茶"
        let older = makeCandidate(
            eventID: olderEventID,
            value: "咖啡",
            quote: olderContent,
            validFrom: olderDate
        )
        let newer = makeCandidate(
            eventID: newerEventID,
            value: "乌龙茶",
            quote: newerContent,
            validFrom: newerDate
        )

        // Deliberately reverse model output order; eventDates is the chronology
        // source and should decide which assertion remains active.
        _ = try MemoryRepository.apply(
            [newer, older],
            eventContents: [
                olderEventID: olderContent,
                newerEventID: newerContent
            ],
            eventDates: [
                olderEventID: olderDate,
                newerEventID: newerDate
            ],
            context: context,
            deviceID: "atomicity-test-device",
            extractorID: "atomicity-fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.count, 2)
        let active = try XCTUnwrap(memories.first { $0.state == .active })
        let superseded = try XCTUnwrap(memories.first { $0.state == .superseded })
        XCTAssertEqual(active.value, "乌龙茶")
        XCTAssertEqual(active.observedAt, newerDate)
        XCTAssertEqual(superseded.value, "咖啡")
        XCTAssertEqual(superseded.observedAt, olderDate)
        XCTAssertEqual(active.supersedesID, superseded.id)
        XCTAssertEqual(superseded.validTo, newerDate)
    }

    func testEvidenceIdentityIncludesMemoryEventRangeAndQuoteHash() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstEventID = UUID()
        let secondEventID = UUID()
        let firstContent = "我喜欢咖啡，也喜欢茶"
        let secondContent = "我喜欢咖啡，也喜欢茶"
        let firstQuote = "咖啡"
        let secondQuote = "茶"
        let first = makeCandidate(
            eventID: firstEventID,
            value: "咖啡",
            quote: firstQuote
        )
        let second = makeCandidate(
            eventID: secondEventID,
            value: "茶",
            quote: secondQuote
        )

        _ = try MemoryRepository.apply(
            [first, second],
            eventContents: [
                firstEventID: firstContent,
                secondEventID: secondContent
            ],
            eventDates: [
                firstEventID: Date(timeIntervalSince1970: 1_700_000_300),
                secondEventID: Date(timeIntervalSince1970: 1_700_000_400)
            ],
            context: context,
            deviceID: "atomicity-test-device",
            extractorID: "atomicity-fixture"
        )

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(
            Set(evidence.map(EvidenceIdentity.init)).count,
            evidence.count
        )
        let coffeeMemory = try XCTUnwrap(memories.first { $0.value == "咖啡" })
        let teaMemory = try XCTUnwrap(memories.first { $0.value == "茶" })
        XCTAssertTrue(evidence.contains {
            $0.memoryID == coffeeMemory.id
                && $0.eventID == firstEventID
                && $0.startUTF16 == 3
                && $0.endUTF16 == 5
                && $0.quoteHash == ContentHasher.sha256(firstQuote)
        })
        XCTAssertTrue(evidence.contains {
            $0.memoryID == teaMemory.id
                && $0.eventID == secondEventID
                && $0.startUTF16 == 9
                && $0.endUTF16 == 10
                && $0.quoteHash == ContentHasher.sha256(secondQuote)
        })
        for item in evidence {
            XCTAssertEqual(item.quoteHash.count, 64)
            XCTAssertTrue(memories.contains { $0.id == item.memoryID })
            XCTAssertTrue(item.endUTF16 > item.startUTF16)
        }
    }

    private struct EvidenceIdentity: Hashable {
        let memoryID: UUID
        let eventID: UUID
        let startUTF16: Int
        let endUTF16: Int
        let quoteHash: String

        init(_ record: MemoryEvidenceRecord) {
            memoryID = record.memoryID
            eventID = record.eventID
            startUTF16 = record.startUTF16
            endUTF16 = record.endUTF16
            quoteHash = record.quoteHash
        }
    }

    private func makeCandidate(
        eventID: UUID,
        value: String,
        quote: String,
        validFrom: Date? = nil
    ) -> ExtractedMemoryCandidate {
        ExtractedMemoryCandidate(
            operation: .upsert,
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
            startUTF16: nil,
            endUTF16: nil,
            validFrom: validFrom,
            validTo: nil
        )
    }
}
