import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryRepositoryScaleTests: XCTestCase {
    private let unrelatedCount = 10_001

    func testTargetApplyAndForgetLeaveTenThousandUnrelatedRowsUnchanged() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)

        let initialEventID = UUID()
        let initialContent = "我喜欢咖啡"
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: initialEventID,
                    value: "咖啡",
                    quote: initialContent
                )],
                eventContents: [initialEventID: initialContent],
                context: context,
                deviceID: "scale-device",
                extractorID: "scale-fixture"
            ),
            1
        )

        var unrelatedMemoryIDs: [UUID] = []
        unrelatedMemoryIDs.reserveCapacity(unrelatedCount)
        for index in 0..<unrelatedCount {
            let memory = MemoryAssertionRecord(
                kind: .profile,
                subject: "user",
                predicate: "unrelated_" + String(index),
                value: "fixture-" + String(index),
                canonicalKey: "fixture.unrelated." + String(index),
                state: .active,
                confidence: 0.4,
                importance: 0.2,
                sensitive: false,
                sourceRank: 100,
                extractorID: "scale-fixture",
                deviceID: "scale-device"
            )
            context.insert(memory)
            unrelatedMemoryIDs.append(memory.id)
            context.insert(MemoryEvidenceRecord(
                memoryID: memory.id,
                eventID: UUID(),
                startUTF16: 0,
                endUTF16: 12,
                relation: .supports,
                quoteHash: "fixture-hash-" + String(index),
                confidence: 0.4
            ))
            context.insert(MemoryTombstoneRecord(
                entityID: memory.id,
                entityType: "memory",
                canonicalKey: memory.canonicalKey,
                sourceEventIDs: [],
                deviceID: "scale-device",
                reason: "scale-fixture"
            ))
        }
        try context.save()

        let unrelatedMemorySnapshot = try context
            .fetch(FetchDescriptor<MemoryAssertionRecord>())
            .filter { unrelatedMemoryIDs.contains($0.id) }
            .map(MemorySnapshot.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let unrelatedEvidenceSnapshot = try context
            .fetch(FetchDescriptor<MemoryEvidenceRecord>())
            .filter { unrelatedMemoryIDs.contains($0.memoryID) }
            .map(EvidenceSnapshot.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let unrelatedTombstoneSnapshot = try context
            .fetch(FetchDescriptor<MemoryTombstoneRecord>())
            .filter { unrelatedMemoryIDs.contains($0.entityID) }
            .map(TombstoneSnapshot.init)
            .sorted { $0.id.uuidString < $1.id.uuidString }

        let updateEventID = UUID()
        let updateContent = "我现在喜欢茶"
        let applyStartedAt = Date()
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: updateEventID,
                    value: "茶",
                    quote: updateContent
                )],
                eventContents: [updateEventID: updateContent],
                context: context,
                deviceID: "scale-device",
                extractorID: "scale-fixture"
            ),
            1
        )
        let applyElapsed = Date().timeIntervalSince(applyStartedAt)
        print("[MemoryRepositoryScaleTests] key-scoped apply with \(unrelatedCount) unrelated rows: \(applyElapsed)s")

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).filter {
                unrelatedMemoryIDs.contains($0.id)
            }.map(MemorySnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedMemorySnapshot
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).filter {
                unrelatedMemoryIDs.contains($0.memoryID)
            }.map(EvidenceSnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedEvidenceSnapshot
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).filter {
                unrelatedMemoryIDs.contains($0.entityID)
            }.map(TombstoneSnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedTombstoneSnapshot
        )

        let targetMemory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first {
                $0.canonicalKey == "user.favorite_drink" && $0.state == .active
            }
        )
        let forgetStartedAt = Date()
        try MemoryRepository.forget(targetMemory, context: context, deviceID: "scale-device")
        let forgetElapsed = Date().timeIntervalSince(forgetStartedAt)
        print("[MemoryRepositoryScaleTests] ID-scoped forget with \(unrelatedCount) unrelated rows: \(forgetElapsed)s")

        XCTAssertEqual(targetMemory.state, .forgotten)
        XCTAssertTrue(targetMemory.value.isEmpty)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).filter {
                $0.memoryID == targetMemory.id
            }.count,
            0
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).filter {
                $0.entityID == targetMemory.id
            }.count,
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).filter {
                unrelatedMemoryIDs.contains($0.id)
            }.map(MemorySnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedMemorySnapshot
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).filter {
                unrelatedMemoryIDs.contains($0.memoryID)
            }.map(EvidenceSnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedEvidenceSnapshot
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).filter {
                unrelatedMemoryIDs.contains($0.entityID)
            }.map(TombstoneSnapshot.init).sorted { $0.id.uuidString < $1.id.uuidString },
            unrelatedTombstoneSnapshot
        )

        // A second call re-resolves the current state and marker. It must not
        // create another tombstone or touch the already-deleted evidence.
        try MemoryRepository.forget(targetMemory, context: context, deviceID: "second-device")
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).filter {
                $0.entityID == targetMemory.id
            }.count,
            1
        )
    }

    func testUserEditedRejectsWhitespaceOnlyValueWithoutMutation() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        let content = "我喜欢乌龙茶"
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: eventID, value: "乌龙茶", quote: content)],
            eventContents: [eventID: content],
            context: context,
            deviceID: "test-device",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        let before = MemorySnapshot(memory)

        XCTAssertThrowsError(
            try MemoryRepository.userEdited(memory, value: " \n\t ", context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryRepositoryError, .blankMemoryValue)
        }

        XCTAssertEqual(MemorySnapshot(memory), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryTombstoneRecord>()), 0)
    }

    func testForgetRechecksCurrentStateAndDoesNotDuplicateTombstone() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let eventID = UUID()
        let content = "我喜欢咖啡"
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: eventID, value: "咖啡", quote: content)],
            eventContents: [eventID: content],
            context: context,
            deviceID: "test-device",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)

        try MemoryRepository.forget(memory, context: context, deviceID: "first-device")
        let firstTombstone = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first
        )
        XCTAssertEqual(firstTombstone.sourceEventIDs, [eventID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)

        let forgottenSnapshot = MemorySnapshot(memory)
        try MemoryRepository.forget(memory, context: context, deviceID: "second-device")

        XCTAssertEqual(MemorySnapshot(memory), forgottenSnapshot)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryTombstoneRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)
    }

    func testForgetDeletesEvidenceBeyondHotOperationWindowInBoundedPages() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let initialEventID = UUID()
        let content = "我喜欢乌龙茶"
        _ = try MemoryRepository.apply(
            [makeCandidate(eventID: initialEventID, value: "乌龙茶", quote: content)],
            eventContents: [initialEventID: content],
            context: context,
            deviceID: "evidence-scale-device",
            extractorID: "fixture"
        )
        let memory = try XCTUnwrap(context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first)
        let additionalEvidence = 1_300
        for index in 0..<additionalEvidence {
            let evidence = MemoryEvidenceRecord(
                memoryID: memory.id,
                eventID: UUID(),
                startUTF16: 0,
                endUTF16: 1,
                relation: .supports,
                quoteHash: "scale-\(index)",
                confidence: 0.5
            )
            evidence.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            context.insert(evidence)
        }
        try context.save()

        try MemoryRepository.forget(
            memory,
            context: context,
            deviceID: "evidence-scale-device"
        )

        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()),
            0
        )
        let tombstone = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first
        )
        XCTAssertEqual(
            Set(tombstone.sourceEventIDs).count,
            additionalEvidence + 1
        )
    }

    func testConversationRetractionDeletesEvidenceBeyondHotOperationWindowAndClearsDerivedContent() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let memory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "乌龙茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.98,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "retraction-scale-device"
        )
        memory.embeddingData = Data([1, 2, 3])
        memory.embeddingModelID = "fixture-embedding"
        memory.userVerified = true
        memory.isPinned = true
        context.insert(memory)

        let evidenceEventIDs = (0..<1_300).map { _ in UUID() }
        for (index, eventID) in evidenceEventIDs.enumerated() {
            let evidence = MemoryEvidenceRecord(
                memoryID: memory.id,
                eventID: eventID,
                startUTF16: 0,
                endUTF16: 1,
                relation: .supports,
                quoteHash: "retraction-scale-\(index)",
                confidence: 0.5
            )
            evidence.createdAt = Date(timeIntervalSince1970: TimeInterval(index))
            context.insert(evidence)
        }
        try context.save()

        let retractionEventID = UUID()
        let retractionContent = "请撤回我喜欢乌龙茶这件事"
        XCTAssertEqual(
            try MemoryRepository.apply(
                [makeCandidate(
                    eventID: retractionEventID,
                    operation: .retract,
                    value: "",
                    quote: retractionContent
                )],
                eventContents: [retractionEventID: retractionContent],
                eventDates: [retractionEventID: Date(timeIntervalSince1970: 2_000)],
                context: context,
                deviceID: "retraction-scale-device",
                extractorID: "fixture",
                saveChanges: false
            ),
            1
        )

        // The caller owns the transaction when saveChanges is false.
        XCTAssertEqual(memory.state, .forgotten)
        XCTAssertTrue(memory.value.isEmpty)
        XCTAssertNil(memory.embeddingData)
        XCTAssertNil(memory.embeddingModelID)
        XCTAssertFalse(memory.userVerified)
        XCTAssertFalse(memory.isPinned)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)
        let tombstone = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first
        )
        XCTAssertEqual(Set(tombstone.sourceEventIDs), Set(evidenceEventIDs))
    }

    func testForgetDeletesAllPhysicalEvidenceDuplicatesAtPageBoundary() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let memory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "duplicate_boundary",
            value: "边界证据",
            canonicalKey: "user.duplicate_boundary",
            state: .active,
            confidence: 0.98,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "duplicate-boundary-device"
        )
        context.insert(memory)

        let duplicateEvidenceID = UUID()
        let duplicateDate = Date(timeIntervalSince1970: 4_200)
        let evidenceEventIDs = (0..<256).map { _ in UUID() }
        for eventID in evidenceEventIDs {
            let evidence = MemoryEvidenceRecord(
                id: duplicateEvidenceID,
                memoryID: memory.id,
                eventID: eventID,
                startUTF16: 0,
                endUTF16: 1,
                relation: .supports,
                quoteHash: "duplicate-boundary",
                confidence: 0.5
            )
            evidence.createdAt = duplicateDate
            context.insert(evidence)
        }
        try context.save()

        try MemoryRepository.forget(
            memory,
            context: context,
            deviceID: "duplicate-boundary-device"
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)
        let tombstone = try XCTUnwrap(
            context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).first
        )
        XCTAssertEqual(Set(tombstone.sourceEventIDs), Set(evidenceEventIDs))
    }

    private func makeCandidate(
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

    private struct MemorySnapshot: Equatable {
        let id: UUID
        let canonicalKey: String
        let value: String
        let stateRaw: String
        let confidence: Double
        let importance: Double
        let updatedAt: Date
        let isPinned: Bool
        let userVerified: Bool

        init(_ record: MemoryAssertionRecord) {
            id = record.id
            canonicalKey = record.canonicalKey
            value = record.value
            stateRaw = record.stateRaw
            confidence = record.confidence
            importance = record.importance
            updatedAt = record.updatedAt
            isPinned = record.isPinned
            userVerified = record.userVerified
        }
    }

    private struct EvidenceSnapshot: Equatable {
        let id: UUID
        let memoryID: UUID
        let eventID: UUID
        let startUTF16: Int
        let endUTF16: Int
        let relationRaw: String
        let quoteHash: String
        let confidence: Double

        init(_ record: MemoryEvidenceRecord) {
            id = record.id
            memoryID = record.memoryID
            eventID = record.eventID
            startUTF16 = record.startUTF16
            endUTF16 = record.endUTF16
            relationRaw = record.relationRaw
            quoteHash = record.quoteHash
            confidence = record.confidence
        }
    }

    private struct TombstoneSnapshot: Equatable {
        let id: UUID
        let entityID: UUID
        let entityType: String
        let canonicalKey: String
        let sourceEventIDsRaw: String
        let deletedAt: Date
        let deviceID: String
        let reason: String

        init(_ record: MemoryTombstoneRecord) {
            id = record.id
            entityID = record.entityID
            entityType = record.entityType
            canonicalKey = record.canonicalKey
            sourceEventIDsRaw = record.sourceEventIDsRaw
            deletedAt = record.deletedAt
            deviceID = record.deviceID
            reason = record.reason
        }
    }
}
