import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MemoryLibraryTests: XCTestCase {
    func testFirstPageRemainsBoundedForLargeLibrary() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let recordCount = 10_001
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<recordCount {
            let record = makeRecord(
                id: testUUID(index),
                value: "bulk-\(index)",
                canonicalKey: "bulk.\(index)",
                updatedAt: timestamp
            )
            context.insert(record)
        }
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 1,
            limit: MemoryLibrary.defaultPageSize
        )

        XCTAssertEqual(page.items.count, MemoryLibrary.defaultPageSize)
        XCTAssertTrue(page.hasMore)
        XCTAssertNotNil(page.nextCursor)
        XCTAssertLessThanOrEqual(
            page.sourceRecordsScanned,
            MemoryLibrary.defaultPageSize * 2,
            "the first screen must not scan the whole durable library"
        )
        XCTAssertLessThan(page.sourceRecordsScanned, recordCount / 10)
    }

    func testApplicationUUIDIsDeduplicatedAcrossPages() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let duplicateID = testUUID(1_000)

        // The older physical copy is deliberately placed after the first
        // page. This models a CloudKit merge that materialized two rows for
        // one application UUID.
        context.insert(makeRecord(
            id: duplicateID,
            value: "new copy",
            canonicalKey: "duplicate.new",
            createdAt: Date(timeIntervalSince1970: 10_000),
            updatedAt: Date(timeIntervalSince1970: 10_000)
        ))
        for index in 0..<80 {
            let timestamp = Date(timeIntervalSince1970: 9_000 + Double(80 - index))
            context.insert(makeRecord(
                id: testUUID(2_000 + index),
                value: "unique-\(index)",
                canonicalKey: "unique.\(index)",
                createdAt: timestamp,
                updatedAt: timestamp
            ))
        }
        context.insert(makeRecord(
            id: duplicateID,
            value: "old copy",
            canonicalKey: "duplicate.old",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        try context.save()

        let ids = try readAllPages(
            context: context,
            query: "",
            state: nil,
            storeRevision: 1,
            limit: 10
        )

        XCTAssertEqual(ids.count, 81)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.filter { $0 == duplicateID }.count, 1)
    }

    func testEqualSortKeyPhysicalCopiesResolveBoundaryWinnerBeforeQuery() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let duplicateID = testUUID(1_500)

        // limit=1 uses a 32-row source chunk. Thirty-one newer rows place the
        // equal-key duplicate group exactly on that physical boundary.
        for index in 0..<31 {
            let timestamp = Date(timeIntervalSince1970: 6_000 + Double(31 - index))
            context.insert(makeRecord(
                id: testUUID(20_000 + index),
                value: "unrelated-\(index)",
                updatedAt: timestamp
            ))
        }
        let timestamp = Date(timeIntervalSince1970: 5_000)
        let stale = makeRecord(
            id: duplicateID,
            value: "stale-copy",
            canonicalKey: "duplicate.equal",
            updatedAt: timestamp
        )
        let verified = makeRecord(
            id: duplicateID,
            value: "verified-boundary-token",
            canonicalKey: "duplicate.equal",
            updatedAt: timestamp
        )
        verified.userVerified = true
        context.insert(stale)
        context.insert(verified)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "verified-boundary-token",
            state: nil,
            after: nil,
            storeRevision: 2,
            limit: 1
        )
        XCTAssertEqual(page.items.map(\.id), [duplicateID])
        XCTAssertEqual(page.items.first?.value, "verified-boundary-token")

        let stalePage = try MemoryLibrary.fetchPage(
            context: context,
            query: "stale-copy",
            state: nil,
            after: nil,
            storeRevision: 2,
            limit: 1
        )
        XCTAssertTrue(stalePage.items.isEmpty)
    }

    func testOlderPhysicalCopyCannotMakeStaleTextSearchable() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let duplicateID = testUUID(1_600)

        context.insert(makeRecord(
            id: duplicateID,
            value: "current-copy",
            canonicalKey: "duplicate.search",
            updatedAt: Date(timeIntervalSince1970: 10_000)
        ))
        for index in 0..<80 {
            context.insert(makeRecord(
                id: testUUID(30_000 + index),
                value: "unrelated-\(index)",
                updatedAt: Date(timeIntervalSince1970: 9_000 - Double(index))
            ))
        }
        context.insert(makeRecord(
            id: duplicateID,
            value: "stale-search-token",
            canonicalKey: "duplicate.search",
            updatedAt: Date(timeIntervalSince1970: 1)
        ))
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "stale-search-token",
            state: nil,
            after: nil,
            storeRevision: 3,
            limit: 10
        )
        XCTAssertTrue(page.items.isEmpty)
    }

    func testForgottenPhysicalCopyBlocksActiveDuplicateWithoutTombstone() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let duplicateID = testUUID(1_700)

        // The active copy sorts first, so filtering forgotten rows before
        // completing the UUID group would incorrectly expose it.
        context.insert(makeRecord(
            id: duplicateID,
            value: "active copy must remain hidden",
            canonicalKey: "duplicate.integrity",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ))
        context.insert(makeRecord(
            id: duplicateID,
            state: .forgotten,
            value: "forgotten physical copy",
            canonicalKey: "duplicate.integrity",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "active copy must remain hidden",
            state: nil,
            after: nil,
            storeRevision: 5,
            limit: 10
        )
        XCTAssertTrue(page.items.isEmpty)

        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: duplicateID, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
    }

    func testEqualTimeConflictingTombstoneKeysSuppressBothOldMemories() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let tombstoneID = testUUID(1_800)
        let firstMemoryID = testUUID(1_801)
        let secondMemoryID = testUUID(1_802)
        let deletionDate = Date(timeIntervalSince1970: 5_000)

        context.insert(makeRecord(
            id: firstMemoryID,
            value: "old first key",
            canonicalKey: "user.first_old_key",
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_100)
        ))
        context.insert(makeRecord(
            id: secondMemoryID,
            value: "old second key",
            canonicalKey: "user.second_old_key",
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        ))

        let firstTombstone = MemoryTombstoneRecord(
            entityID: firstMemoryID,
            entityType: "memory",
            canonicalKey: "user.first_old_key",
            deviceID: "conflicting-device"
        )
        firstTombstone.id = tombstoneID
        firstTombstone.deletedAt = deletionDate
        let secondTombstone = MemoryTombstoneRecord(
            entityID: firstMemoryID,
            entityType: "memory",
            canonicalKey: "user.second_old_key",
            deviceID: "conflicting-device"
        )
        secondTombstone.id = tombstoneID
        secondTombstone.deletedAt = deletionDate
        context.insert(firstTombstone)
        context.insert(secondTombstone)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 6,
            limit: 80
        )
        XCTAssertFalse(page.items.contains { $0.id == firstMemoryID })
        XCTAssertFalse(page.items.contains { $0.id == secondMemoryID })

        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: firstMemoryID, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: secondMemoryID, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
    }

    func testDifferentTimeConflictingTombstoneKeysSuppressBothOldMemories() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let tombstoneID = testUUID(1_900)
        let firstMemoryID = testUUID(1_901)
        let secondMemoryID = testUUID(1_902)

        context.insert(makeRecord(
            id: firstMemoryID,
            value: "old first key at different time",
            canonicalKey: "user.first_different_time",
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_100)
        ))
        context.insert(makeRecord(
            id: secondMemoryID,
            value: "old second key at different time",
            canonicalKey: "user.second_different_time",
            createdAt: Date(timeIntervalSince1970: 4_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        ))

        let olderKeyCopy = MemoryTombstoneRecord(
            entityID: firstMemoryID,
            entityType: "memory",
            canonicalKey: "user.first_different_time",
            deviceID: "conflicting-device"
        )
        olderKeyCopy.id = tombstoneID
        olderKeyCopy.deletedAt = Date(timeIntervalSince1970: 5_000)
        let newerKeyCopy = MemoryTombstoneRecord(
            entityID: firstMemoryID,
            entityType: "memory",
            canonicalKey: "user.second_different_time",
            deviceID: "conflicting-device"
        )
        newerKeyCopy.id = tombstoneID
        newerKeyCopy.deletedAt = Date(timeIntervalSince1970: 5_001)
        context.insert(olderKeyCopy)
        context.insert(newerKeyCopy)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 7,
            limit: 80
        )
        XCTAssertFalse(page.items.contains { $0.id == firstMemoryID })
        XCTAssertFalse(page.items.contains { $0.id == secondMemoryID })

        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: firstMemoryID, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: secondMemoryID, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
    }

    func testSnapshotUpperBoundKeepsLaterPageStableWhenNewerRecordArrives() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstID = testUUID(3_000)
        let secondID = testUUID(3_001)
        let firstDate = Date(timeIntervalSince1970: 10_000)
        let secondDate = Date(timeIntervalSince1970: 9_000)

        context.insert(makeRecord(
            id: firstID,
            value: "first",
            createdAt: firstDate,
            updatedAt: firstDate
        ))
        context.insert(makeRecord(
            id: secondID,
            value: "second",
            createdAt: secondDate,
            updatedAt: secondDate
        ))
        try context.save()

        let firstPage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 1,
            limit: 1
        )
        let cursor = try XCTUnwrap(firstPage.nextCursor)
        XCTAssertEqual(firstPage.items.map(\.id), [firstID])

        let insertedID = testUUID(3_002)
        let insertedDate = Date(timeIntervalSince1970: 20_000)
        context.insert(makeRecord(
            id: insertedID,
            value: "arrived after snapshot",
            createdAt: insertedDate,
            updatedAt: insertedDate
        ))
        let lateLegacyTombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "",
            deviceID: "late-legacy-device"
        )
        lateLegacyTombstone.deletedAt = Date(timeIntervalSince1970: 9_500)
        context.insert(lateLegacyTombstone)
        try context.save()

        let secondPage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: cursor,
            storeRevision: 1,
            limit: 1
        )
        XCTAssertEqual(secondPage.items.map(\.id), [secondID])
        XCTAssertFalse(secondPage.items.contains { $0.id == insertedID })
    }

    func testLegacyWhitespaceTombstoneKeepsTenThousandSuppressedRowsOutOfFirstScan() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let suppressedCount = 10_000
        let deletionDate = Date(timeIntervalSince1970: 5_000)

        for index in 0..<suppressedCount {
            let createdAt = Date(timeIntervalSince1970: 100)
            let updatedAt = Date(timeIntervalSince1970: 10_000 + Double(index))
            context.insert(makeRecord(
                id: testUUID(4_000 + index),
                value: "suppressed-\(index)",
                canonicalKey: "legacy.\(index)",
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        let freshID = testUUID(15_000)
        let freshDate = Date(timeIntervalSince1970: 6_000)
        context.insert(makeRecord(
            id: freshID,
            value: "fresh restatement",
            canonicalKey: "legacy.fresh",
            createdAt: freshDate,
            updatedAt: freshDate
        ))
        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "   ",
            deviceID: "legacy-device"
        )
        legacy.deletedAt = deletionDate
        context.insert(legacy)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 1,
            limit: MemoryLibrary.defaultPageSize
        )

        XCTAssertEqual(page.items.map(\.id), [freshID])
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.sourceRecordsScanned, 1)
        XCTAssertLessThanOrEqual(page.sourceRecordsScanned, MemoryLibrary.defaultPageSize * 2)
    }

    func testEqualUpdatedAtCursorReadsEveryRecordExactlyOnceInStableOrder() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let recordCount = 257
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let expectedIDs = (0..<recordCount).reversed().map(testUUID)

        for index in 0..<recordCount {
            context.insert(
                makeRecord(
                    id: testUUID(index),
                    value: "same-time-\(index)",
                    canonicalKey: "same-time.\(index)",
                    updatedAt: timestamp
                )
            )
        }
        try context.save()

        let firstPass = try readAllPages(
            context: context,
            query: "",
            state: nil,
            storeRevision: 4,
            limit: 37
        )
        let secondPass = try readAllPages(
            context: context,
            query: "",
            state: nil,
            storeRevision: 4,
            limit: 37
        )

        XCTAssertEqual(firstPass, expectedIDs)
        XCTAssertEqual(secondPass, expectedIDs)
        XCTAssertEqual(Set(firstPass).count, recordCount)
    }

    func testStateFilterKindTitleSearchAndForgottenExclusion() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let candidatePreferenceID = testUUID(1)
        let activePreferenceID = testUUID(2)
        let candidateBoundaryID = testUUID(3)
        let activeProfileID = testUUID(4)
        let forgottenPreferenceID = testUUID(5)

        let records = [
            makeRecord(
                id: candidatePreferenceID,
                kind: .preference,
                state: .candidate,
                value: "候选咖啡"
            ),
            makeRecord(
                id: activePreferenceID,
                kind: .preference,
                state: .active,
                value: "有效乌龙茶"
            ),
            makeRecord(
                id: candidateBoundaryID,
                kind: .boundary,
                state: .candidate,
                value: "候选边界"
            ),
            makeRecord(
                id: activeProfileID,
                kind: .profile,
                state: .active,
                value: "有效资料"
            ),
            makeRecord(
                id: forgottenPreferenceID,
                kind: .preference,
                state: .forgotten,
                value: "不应显示的偏好"
            )
        ]
        records.forEach(context.insert)
        try context.save()

        let candidatePage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: .candidate,
            after: nil,
            storeRevision: 2,
            limit: 80
        )
        XCTAssertEqual(
            Set(candidatePage.items.map(\.id)),
            Set([candidatePreferenceID, candidateBoundaryID])
        )
        XCTAssertFalse(candidatePage.items.contains { $0.state == .forgotten })

        let preferencePage = try MemoryLibrary.fetchPage(
            context: context,
            query: MemoryKind.preference.title,
            state: nil,
            after: nil,
            storeRevision: 2,
            limit: 80
        )
        XCTAssertEqual(
            Set(preferencePage.items.map(\.id)),
            Set([candidatePreferenceID, activePreferenceID])
        )
        XCTAssertFalse(preferencePage.items.contains { $0.id == forgottenPreferenceID })
    }

    func testExactIDAndCanonicalKeyTombstonesSuppressOldVersionsButAllowNewVersion() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let deletionDate = Date(timeIntervalSince1970: 2_000)

        let exactID = testUUID(10)
        let oldKeyID = testUUID(11)
        let freshKeyID = testUUID(12)
        let unrelatedID = testUUID(13)
        let exact = makeRecord(
            id: exactID,
            value: "exactly deleted",
            canonicalKey: "user.exact_fact",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100)
        )
        let oldKey = makeRecord(
            id: oldKeyID,
            value: "old canonical version",
            canonicalKey: "user.favorite_drink",
            createdAt: Date(timeIntervalSince1970: 1_500),
            updatedAt: Date(timeIntervalSince1970: 1_600)
        )
        let freshKey = makeRecord(
            id: freshKeyID,
            value: "new canonical version",
            canonicalKey: "user.favorite_drink",
            createdAt: Date(timeIntervalSince1970: 2_100),
            updatedAt: Date(timeIntervalSince1970: 2_200)
        )
        let unrelated = makeRecord(
            id: unrelatedID,
            value: "unrelated visible fact",
            canonicalKey: "user.other_fact",
            createdAt: Date(timeIntervalSince1970: 1_700),
            updatedAt: Date(timeIntervalSince1970: 1_800)
        )

        let exactTombstone = MemoryTombstoneRecord(
            entityID: exactID,
            entityType: "memory",
            canonicalKey: "user.exact_fact",
            deviceID: "library-test"
        )
        exactTombstone.deletedAt = deletionDate
        let keyTombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            deviceID: "library-test"
        )
        keyTombstone.deletedAt = deletionDate

        [exact, oldKey, freshKey, unrelated].forEach(context.insert)
        [exactTombstone, keyTombstone].forEach(context.insert)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 9,
            limit: 80
        )

        XCTAssertEqual(Set(page.items.map(\.id)), Set([freshKeyID, unrelatedID]))
        XCTAssertFalse(page.items.contains { $0.id == exactID })
        XCTAssertFalse(page.items.contains { $0.id == oldKeyID })
        XCTAssertTrue(page.items.contains { $0.id == freshKeyID })
    }

    func testCursorRejectsQueryOrStoreRevisionChanges() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        context.insert(makeRecord(id: testUUID(20), value: "第一条"))
        context.insert(makeRecord(id: testUUID(21), value: "第二条"))
        try context.save()

        let firstPage = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 11,
            limit: 1
        )
        let cursor = try XCTUnwrap(firstPage.nextCursor)

        XCTAssertThrowsError(
            try MemoryLibrary.fetchPage(
                context: context,
                query: "第一",
                state: nil,
                after: cursor,
                storeRevision: 11,
                limit: 1
            )
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .staleCursor)
        }

        XCTAssertThrowsError(
            try MemoryLibrary.fetchPage(
                context: context,
                query: "",
                state: nil,
                after: cursor,
                storeRevision: 12,
                limit: 1
            )
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .staleCursor)
        }
    }

    func testFetchLatestVisibleRecordRejectsTombstonedObject() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let id = testUUID(30)
        let record = makeRecord(
            id: id,
            value: "已撤回的事实",
            canonicalKey: "user.retracted_fact"
        )
        let tombstone = MemoryTombstoneRecord(
            entityID: id,
            entityType: "memory",
            canonicalKey: "user.retracted_fact",
            deviceID: "library-test"
        )
        context.insert(record)
        context.insert(tombstone)
        try context.save()

        XCTAssertThrowsError(
            try MemoryLibrary.fetchLatestVisibleRecord(id: id, context: context)
        ) { error in
            XCTAssertEqual(error as? MemoryLibraryError, .unavailable)
        }
    }

    func testLegacyEmptyKeyTombstoneSuppressesOlderDifferentUUIDButAllowsLaterRestatement() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let deletionDate = Date(timeIntervalSince1970: 5_000)
        let oldID = testUUID(31)
        let newID = testUUID(32)
        let oldRecord = makeRecord(
            id: oldID,
            value: "旧设备带回的事实",
            canonicalKey: "user.legacy_fact",
            createdAt: Date(timeIntervalSince1970: 4_000)
        )
        let newRecord = makeRecord(
            id: newID,
            value: "遗忘后用户重新明确表述",
            canonicalKey: "user.legacy_fact",
            createdAt: Date(timeIntervalSince1970: 6_000)
        )
        let legacy = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "",
            deviceID: "legacy-device"
        )
        legacy.deletedAt = deletionDate
        context.insert(oldRecord)
        context.insert(newRecord)
        context.insert(legacy)
        try context.save()

        let page = try MemoryLibrary.fetchPage(
            context: context,
            query: "",
            state: nil,
            after: nil,
            storeRevision: 1,
            limit: 80
        )

        XCTAssertFalse(page.items.contains { $0.id == oldID })
        XCTAssertTrue(page.items.contains { $0.id == newID })
    }

    private func readAllPages(
        context: ModelContext,
        query: String,
        state: MemoryState?,
        storeRevision: Int,
        limit: Int
    ) throws -> [UUID] {
        var cursor: MemoryLibraryCursor?
        var ids: [UUID] = []
        while true {
            let page = try MemoryLibrary.fetchPage(
                context: context,
                query: query,
                state: state,
                after: cursor,
                storeRevision: storeRevision,
                limit: limit
            )
            ids.append(contentsOf: page.items.map(\.id))
            guard page.hasMore else {
                XCTAssertNil(page.nextCursor)
                break
            }
            cursor = try XCTUnwrap(page.nextCursor)
        }
        return ids
    }

    private func makeRecord(
        id: UUID = UUID(),
        kind: MemoryKind = .profile,
        state: MemoryState = .active,
        subject: String = "user",
        predicate: String = "remembered_fact",
        value: String = "visible fact",
        canonicalKey: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) -> MemoryAssertionRecord {
        let record = MemoryAssertionRecord(
            id: id,
            kind: kind,
            subject: subject,
            predicate: predicate,
            value: value,
            canonicalKey: canonicalKey ?? "user.fact.\(id.uuidString)",
            state: state,
            confidence: 0.95,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "memory-library-tests",
            deviceID: "memory-library-tests"
        )
        if let createdAt {
            record.createdAt = createdAt
        }
        if let updatedAt {
            record.updatedAt = updatedAt
        } else if let createdAt {
            record.updatedAt = createdAt
        }
        return record
    }

    private func testUUID(_ index: Int) -> UUID {
        let hex = String(index, radix: 16)
        let suffix = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }
}
