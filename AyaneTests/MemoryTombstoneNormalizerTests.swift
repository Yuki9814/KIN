import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryTombstoneNormalizerTests: XCTestCase {
    func testNewTombstoneNormalizesCanonicalKeyAndMarksCurrentVersion() {
        let tombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "  User.Favorite_Drink\n",
            deviceID: "new-device"
        )

        XCTAssertEqual(tombstone.canonicalKey, "user.favorite_drink")
        XCTAssertEqual(
            tombstone.canonicalKeyNormalizationVersion,
            MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        )
    }

    func testNormalizationRemovesBOMZeroWidthAndUnicodeBoundaryNoise() {
        let raw = "\u{FEFF}\u{200B}\u{2060}\u{0009} User.Favorite_Drink \u{000A}\u{200D}\u{FEFF}"

        XCTAssertEqual(
            MemoryTombstoneRecord.normalizedCanonicalKey(raw),
            "user.favorite_drink"
        )
    }

    func testFEFFLegacyGlobalForgetCannotReviveOldMemory() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let oldID = UUID()
        let freshID = UUID()

        context.insert(makeMemory(
            id: oldID,
            key: "user.private_fact",
            value: "old fact must stay forgotten",
            createdAt: date(100),
            updatedAt: date(100)
        ))
        context.insert(makeMemory(
            id: freshID,
            key: "user.private_fact",
            value: "later explicit restatement",
            createdAt: date(300),
            updatedAt: date(300)
        ))

        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "temporary",
            deviceID: "legacy-device"
        )
        // Version 1 rows could look trimmed while retaining invisible
        // boundary scalars. Version 2 must migrate this to the empty global
        // key before any memory read is allowed.
        legacy.canonicalKey = "\u{FEFF}\u{200B}\u{2060}\n\u{FEFF}"
        legacy.canonicalKeyNormalizationVersion = 1
        legacy.deletedAt = date(200)
        context.insert(legacy)
        try context.save()

        XCTAssertThrowsError(
            try MemoryLibrary.fetchPage(
                context: context,
                query: "",
                state: nil,
                after: nil,
                storeRevision: 1
            )
        ) { error in
            XCTAssertEqual(error as? MemoryTombstoneNormalizationError, .incomplete)
        }

        XCTAssertEqual(
            try MemoryTombstoneNormalizer.normalizePending(context: context),
            1
        )
        XCTAssertEqual(legacy.canonicalKey, "")
        XCTAssertEqual(
            legacy.canonicalKeyNormalizationVersion,
            MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        )

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 2
        )
        XCTAssertFalse(page.items.contains { $0.id == oldID })
        XCTAssertTrue(page.items.contains { $0.id == freshID })
    }

    func testArbitraryLegacyWhitespaceBehindNewerRowsCannotReviveOldMemory() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let oldID = UUID()
        let freshID = UUID()

        context.insert(makeMemory(
            id: oldID,
            key: "user.private_fact",
            value: "old fact must stay forgotten",
            createdAt: date(100),
            updatedAt: date(10_000)
        ))
        context.insert(makeMemory(
            id: freshID,
            key: "user.private_fact",
            value: "later explicit restatement",
            createdAt: date(300),
            updatedAt: date(300)
        ))

        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "temporary",
            deviceID: "legacy-device"
        )
        legacy.canonicalKey = "\t\u{2003}\n\u{00A0}"
        legacy.canonicalKeyNormalizationVersion = 1
        legacy.deletedAt = date(200)
        context.insert(legacy)

        // More than the old 256-row fallback window, all newer than the
        // legacy global marker. A recent-slice approximation would miss it.
        for index in 0..<300 {
            let marker = MemoryTombstoneRecord(
                entityID: UUID(),
                entityType: "memory",
                canonicalKey: "ordinary.\(index)",
                deviceID: "new-device"
            )
            marker.deletedAt = date(1_000 + index)
            context.insert(marker)
        }
        try context.save()

        XCTAssertThrowsError(
            try MemoryLibrary.fetchPage(
                context: context,
                query: "",
                state: nil,
                after: nil,
                storeRevision: 1
            )
        ) { error in
            XCTAssertEqual(error as? MemoryTombstoneNormalizationError, .incomplete)
        }

        XCTAssertEqual(
            try MemoryTombstoneNormalizer.normalizePending(context: context),
            1
        )
        XCTAssertEqual(legacy.canonicalKey, "")

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 2
        )
        XCTAssertFalse(page.items.contains { $0.id == oldID })
        XCTAssertTrue(page.items.contains { $0.id == freshID })
    }

    func testNormalizerPersistsAcrossMultipleBoundedBatches() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let total = MemoryTombstoneNormalizer.batchSize * 2 + 19

        for index in 0..<total {
            let tombstone = MemoryTombstoneRecord(
                entityID: UUID(),
                entityType: "memory",
                canonicalKey: "temporary",
                deviceID: "legacy-device"
            )
            tombstone.canonicalKey = index.isMultiple(of: 2) ? " \t\n " : " USER.KEY.\(index) "
            tombstone.canonicalKeyNormalizationVersion = 0
            tombstone.deletedAt = date(index)
            context.insert(tombstone)
        }
        try context.save()

        XCTAssertEqual(
            try MemoryTombstoneNormalizer.normalizePending(context: context),
            total
        )
        XCTAssertFalse(try MemoryTombstoneNormalizer.hasPending(context: context))

        let records = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        XCTAssertEqual(records.count, total)
        XCTAssertTrue(records.allSatisfy {
            $0.canonicalKeyNormalizationVersion
                == MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        })
        XCTAssertTrue(records.allSatisfy {
            $0.canonicalKey == MemoryTombstoneRecord.normalizedCanonicalKey($0.canonicalKey)
        })
    }

    private func makeMemory(
        id: UUID,
        key: String,
        value: String,
        createdAt: Date,
        updatedAt: Date
    ) -> MemoryAssertionRecord {
        let record = MemoryAssertionRecord(
            id: id,
            kind: .profile,
            subject: "user",
            predicate: "fact",
            value: value,
            canonicalKey: key,
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 300,
            observedAt: createdAt,
            extractorID: "normalizer-test",
            deviceID: "test-device"
        )
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        return record
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
