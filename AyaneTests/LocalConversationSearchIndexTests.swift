import Foundation
import SQLite3
import XCTest
@testable import Ayane

final class LocalConversationSearchIndexTests: XCTestCase {
    func testEnglishChineseRoleAndEventIDSearchReturnScoredIDs() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let userID = UUID()
        let assistantID = UUID()

        await index.rebuild([
            .init(id: userID, role: "user", body: "My favorite color is blue"),
            .init(id: assistantID, role: "assistant", body: "今晚一起吃火锅")
        ])

        let english = await index.search("FAVORITE BLUE", limit: 4)
        XCTAssertEqual(english.first?.eventID, userID)
        XCTAssertGreaterThan(english.first?.score ?? 0, 0)
        XCTAssertLessThanOrEqual(english.first?.score ?? 2, 1)

        let chinese = await index.search("火锅", limit: 4)
        XCTAssertEqual(chinese.first?.eventID, assistantID)

        let roleResults = await index.search("assistant", limit: 4)
        XCTAssertEqual(roleResults.first?.eventID, assistantID)

        let idResults = await index.search(assistantID.uuidString, limit: 4)
        XCTAssertEqual(idResults.first?.eventID, assistantID)
        let count = await index.count()
        XCTAssertEqual(count, 2)
    }

    func testUpsertReplacesTextAndDeleteRemovesEvent() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let eventID = UUID()

        await index.upsert(eventID: eventID, role: "user", body: "喜欢咖啡")
        await index.upsert(eventID: eventID, role: "user", body: "喜欢乌龙茶")

        let newResults = await index.search("乌龙茶")
        let oldResults = await index.search("咖啡")
        XCTAssertTrue(newResults.contains { $0.eventID == eventID })
        XCTAssertFalse(oldResults.contains { $0.eventID == eventID })

        await index.delete(eventID: eventID)
        let afterDelete = await index.search("乌龙茶")
        let count = await index.count()
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testDurableURLPersistsAndRebuildReplacesSnapshot() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let firstID = UUID()
        let secondID = UUID()
        let first = LocalConversationSearchIndex(databaseURL: databaseURL)
        await first.upsert(.init(id: firstID, role: "user", body: "春天去杭州"))

        let reopened = LocalConversationSearchIndex(url: databaseURL)
        let persisted = await reopened.search("杭州")
        XCTAssertEqual(persisted.first?.eventID, firstID)

        await reopened.rebuild(events: [
            .init(id: secondID, role: "assistant", body: "秋天去巴黎")
        ])
        let oldResults = await reopened.search("杭州")
        let newResults = await reopened.search("巴黎")
        let count = await reopened.count()
        XCTAssertTrue(oldResults.isEmpty)
        XCTAssertEqual(newResults.first?.eventID, secondID)
        XCTAssertEqual(count, 1)
    }

    func testSourceMarkerPersistsAcrossReopenAndCanBeCleared() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let eventID = UUID()
        let first = LocalConversationSearchIndex(databaseURL: databaseURL)
        await first.rebuild([
            .init(id: eventID, role: "user", body: "marker persistence")
        ], sourceMarker: "snapshot-001")
        let firstMarker = await first.sourceMarker()
        XCTAssertEqual(firstMarker, "snapshot-001")

        let reopened = LocalConversationSearchIndex(url: databaseURL)
        let reopenedMarker = await reopened.sourceMarker()
        let persistedResults = await reopened.search("persistence")
        XCTAssertEqual(reopenedMarker, "snapshot-001")
        XCTAssertEqual(persistedResults.first?.eventID, eventID)

        await reopened.setSourceMarker(nil)
        let clearedMarker = await reopened.sourceMarker()
        XCTAssertNil(clearedMarker)

        let cleared = LocalConversationSearchIndex(url: databaseURL)
        let reopenedClearedMarker = await cleared.sourceMarker()
        XCTAssertNil(reopenedClearedMarker)
    }

    func testUpsertAndDeleteInvalidateSourceMarker() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let eventID = UUID()

        await index.rebuild([
            .init(id: eventID, role: "user", body: "before update")
        ], sourceMarker: "snapshot-before-update")
        let initialMarker = await index.sourceMarker()
        XCTAssertEqual(initialMarker, "snapshot-before-update")

        await index.upsert(eventID: eventID, role: "user", body: "after update")
        let markerAfterUpsert = await index.sourceMarker()
        XCTAssertNil(markerAfterUpsert)

        await index.setSourceMarker("snapshot-before-delete")
        await index.delete(eventID: eventID)
        let markerAfterDelete = await index.sourceMarker()
        XCTAssertNil(markerAfterDelete)
    }

    func testRebuildStoresTheSuppliedSourceMarkerWithItsSnapshot() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let firstID = UUID()
        let secondID = UUID()

        await index.rebuild([
            .init(id: firstID, role: "user", body: "first snapshot")
        ], sourceMarker: "snapshot-first")
        let firstMarker = await index.sourceMarker()
        XCTAssertEqual(firstMarker, "snapshot-first")

        await index.rebuild([
            .init(id: secondID, role: "assistant", body: "second snapshot")
        ], sourceMarker: "snapshot-second")
        let secondMarker = await index.sourceMarker()
        let firstResults = await index.search("first")
        let secondResults = await index.search("second")
        XCTAssertEqual(secondMarker, "snapshot-second")
        XCTAssertTrue(firstResults.isEmpty)
        XCTAssertEqual(secondResults.first?.eventID, secondID)
    }

    func testNonSearchableRedactedEquivalentAndBlankBodiesAreNotIndexed() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let visibleID = UUID()
        let hiddenID = UUID()
        let blankID = UUID()

        await index.rebuild([
            .init(id: visibleID, role: "user", body: "visible text"),
            .init(id: hiddenID, role: "assistant", body: "redacted secret", isSearchable: false),
            .init(id: blankID, role: "user", body: " \n\t")
        ])

        let initialCount = await index.count()
        let visibleResults = await index.search("visible")
        let secretResults = await index.search("secret")
        let assistantResults = await index.search("assistant")
        XCTAssertEqual(initialCount, 1)
        XCTAssertEqual(visibleResults.first?.eventID, visibleID)
        XCTAssertFalse(secretResults.contains { $0.eventID == hiddenID })
        XCTAssertFalse(assistantResults.contains { $0.eventID == hiddenID })

        await index.upsert(.init(id: visibleID, role: "user", body: "now redacted", isSearchable: false))
        let redactedCount = await index.count()
        let afterRedaction = await index.search("visible")
        XCTAssertEqual(redactedCount, 0)
        XCTAssertTrue(afterRedaction.isEmpty)
    }

    func testEmptyQueriesAndUnavailablePathDegradeToEmpty() async throws {
        let badPath = URL(fileURLWithPath: "/dev/null/ayane-conversation-index.sqlite")
        let index = LocalConversationSearchIndex(databaseURL: badPath)
        await index.upsert(.init(id: UUID(), role: "user", body: "blue"))

        let blueResults = await index.search("blue")
        let emptyResults = await index.search("   ")
        let zeroLimitResults = await index.search("blue", limit: 0)
        let count = await index.count()
        XCTAssertTrue(blueResults.isEmpty)
        XCTAssertTrue(emptyResults.isEmpty)
        XCTAssertTrue(zeroLimitResults.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testCorruptSQLiteFileDegradesToEmpty() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        try Data("not a sqlite database".utf8).write(to: databaseURL)

        let index = LocalConversationSearchIndex(databaseURL: databaseURL)
        await index.upsert(.init(id: UUID(), role: "user", body: "should not surface"))

        let results = await index.search("surface")
        let count = await index.count()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testInMemoryIndexesAreIndependent() async throws {
        let first = LocalConversationSearchIndex(inMemory: true)
        let second = LocalConversationSearchIndex(inMemory: true)
        let eventID = UUID()

        await first.upsert(.init(id: eventID, role: "user", body: "only in first"))
        let firstCount = await first.count()
        let secondCount = await second.count()
        let secondResults = await second.search("first")
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)
        XCTAssertTrue(secondResults.isEmpty)
    }

    func testLegacyV1DatabaseIsMigratedToAnEmptyUsableV2Index() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let legacyID = UUID()
        try createLegacyV1Database(at: databaseURL, eventID: legacyID)

        // The v1 FTS rows do not carry the v2 event-table rowid mapping. Since
        // this is a derived cache, opening a v1 file must reset it before use.
        let migrated = LocalConversationSearchIndex(databaseURL: databaseURL)
        let migratedCount = await migrated.count()
        let legacyResults = await migrated.search("legacy-migration-token")
        let migratedMarker = await migrated.sourceMarker()
        XCTAssertEqual(migratedCount, 0)
        XCTAssertTrue(legacyResults.isEmpty)
        XCTAssertNil(migratedMarker)

        let currentID = UUID()
        await migrated.rebuild([
            .init(id: currentID, role: "assistant", body: "v2 migration works")
        ], sourceMarker: "snapshot-after-migration")
        let currentCount = await migrated.count()
        let currentResults = await migrated.search("migration")
        let currentMarker = await migrated.sourceMarker()
        XCTAssertEqual(currentCount, 1)
        XCTAssertEqual(currentResults.first?.eventID, currentID)
        XCTAssertEqual(currentMarker, "snapshot-after-migration")
    }

    func testTenThousandEventsRebuildAndSearchWithinLooseBudget() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let targetID = UUID()
        let events = (0..<10_000).map { offset in
            LocalConversationSearchIndex.Event(
                id: offset == 9_999 ? targetID : UUID(),
                role: offset.isMultiple(of: 2) ? "user" : "assistant",
                body: offset == 9_999
                    ? "scale-target CJK 火锅 and English searchable text"
                    : "bulk conversation event number \(offset)"
            )
        }

        let startedAt = Date()
        await index.rebuild(events)
        let elapsed = Date().timeIntervalSince(startedAt)

        let count = await index.count()
        let targetResults = await index.search("scale-target", limit: 1)
        XCTAssertEqual(count, 10_000)
        XCTAssertEqual(targetResults.first?.eventID, targetID)
        XCTAssertLessThan(elapsed, 30, "10,000-event rebuild took unexpectedly long")
    }

    func testOneHundredThousandEventsRebuildAndSearchWithinLooseBudget() async throws {
        let index = LocalConversationSearchIndex(inMemory: true)
        let targetID = UUID()
        let targetOffset = 99_999
        let events = (0..<100_000).map { offset in
            LocalConversationSearchIndex.Event(
                id: offset == targetOffset ? targetID : UUID(),
                role: offset.isMultiple(of: 2) ? "user" : "assistant",
                body: offset == targetOffset
                    ? "scaleuniquetarget CJK 火锅 and English searchable text"
                    : "bulk conversation event \(offset)"
            )
        }

        let startedAt = Date()
        await index.rebuild(events, sourceMarker: "scale-100k")
        let results = await index.search("scaleuniquetarget", limit: 1)
        let elapsed = Date().timeIntervalSince(startedAt)

        let count = await index.count()
        let marker = await index.sourceMarker()
        XCTAssertEqual(count, 100_000)
        XCTAssertEqual(results.first?.eventID, targetID)
        XCTAssertEqual(marker, "scale-100k")
        XCTAssertLessThan(elapsed, 180, "100,000-event rebuild and search took unexpectedly long")
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AyaneLocalConversationSearchIndexTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
    }

    private func removeDatabase(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }

    private func createLegacyV1Database(at url: URL, eventID: UUID) throws {
        var database: OpaquePointer?
        let openResult = url.path.withCString {
            sqlite3_open_v2(
                $0,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw NSError(
                domain: "LocalConversationSearchIndexTests",
                code: Int(openResult),
                userInfo: [NSLocalizedDescriptionKey: "Could not create legacy SQLite database"]
            )
        }
        defer { sqlite3_close(database) }

        let tokenText = "user legacy-migration-token"
        let eventKey = eventID.uuidString.lowercased()
        let escapedEventKey = eventKey.replacingOccurrences(of: "'", with: "''")
        let escapedTokenText = tokenText.replacingOccurrences(of: "'", with: "''")
        let statements = [
            """
            CREATE TABLE ayane_conversation_index_events (
                event_id TEXT PRIMARY KEY NOT NULL,
                role TEXT NOT NULL,
                occurred_at REAL NOT NULL,
                token_text TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            """
            CREATE VIRTUAL TABLE ayane_conversation_index_fts USING fts5(
                event_id UNINDEXED,
                token_text,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """,
            """
            INSERT INTO ayane_conversation_index_events
                (event_id, role, occurred_at, token_text, updated_at)
            VALUES ('\(escapedEventKey)', 'user', 0, '\(escapedTokenText)', 0);
            """,
            """
            INSERT INTO ayane_conversation_index_fts (event_id, token_text)
            VALUES ('\(escapedEventKey)', '\(escapedTokenText)');
            """,
            "PRAGMA user_version = 1;"
        ]

        for statement in statements {
            guard executeSQLite(statement, database: database) else {
                throw NSError(
                    domain: "LocalConversationSearchIndexTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not initialize legacy SQLite schema"]
                )
            }
        }
    }

    private func executeSQLite(_ sql: String, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let prepareResult = sql.withCString {
            sqlite3_prepare_v2(database, $0, -1, &statement, nil)
        }
        guard prepareResult == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_DONE
    }
}
