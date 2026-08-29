import Foundation
import SQLite3
import XCTest
@testable import Ayane

final class LocalMemorySearchIndexTests: XCTestCase {
    func testUpsertAndQueryReturnAssertionIDAndScore() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let favorite = UUID()
        await index.upsert(assertionID: favorite, text: "My favorite color is blue")

        let results = await index.search("favorite blue", limit: 4)
        XCTAssertEqual(results.first?.assertionID, favorite)
        XCTAssertGreaterThan(results.first?.score ?? 0, 0)
        let count = await index.count()
        XCTAssertEqual(count, 1)
    }

    func testChineseCharactersAndBigramsMatchWithoutSpaces() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let hotpot = UUID()
        let tea = UUID()
        await index.rebuild([
            .init(id: hotpot, text: "今晚一起吃火锅"),
            .init(id: tea, text: "我喜欢乌龙茶")
        ])

        let count = await index.count()
        XCTAssertEqual(count, 2)
        let results = await index.search("火锅")
        XCTAssertEqual(results.first?.assertionID, hotpot)
        XCTAssertFalse(results.contains { $0.assertionID == tea })
    }

    func testJapaneseAndKoreanUnspacedTextUsesCharacterBigrams() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let japanese = UUID()
        let korean = UUID()
        await index.rebuild([
            .init(id: japanese, text: "日本語を勉強しています"),
            .init(id: korean, text: "한국어를 공부합니다")
        ])

        let japaneseResults = await index.search("日本語")
        let koreanResults = await index.search("한국어")
        XCTAssertEqual(japaneseResults.first?.assertionID, japanese)
        XCTAssertEqual(koreanResults.first?.assertionID, korean)
    }

    func testUpsertReplacesOldTextAndDeleteRemovesAssertion() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let assertionID = UUID()
        await index.upsert(assertionID: assertionID, text: "喜欢咖啡")
        await index.upsert(assertionID: assertionID, text: "喜欢乌龙茶")

        let newResults = await index.search("乌龙茶")
        let oldResults = await index.search("咖啡")
        XCTAssertTrue(newResults.contains { $0.assertionID == assertionID })
        XCTAssertFalse(oldResults.contains { $0.assertionID == assertionID })

        await index.delete(assertionID: assertionID)
        let afterDelete = await index.search("乌龙茶")
        let count = await index.count()
        XCTAssertTrue(afterDelete.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testRebuildIsAtomicFromCallerPerspectiveAndPersistsAcrossInstances() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let firstID = UUID()
        let secondID = UUID()
        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        await index.rebuild([.init(id: firstID, text: "春天去杭州")])

        let reopened = LocalMemorySearchIndex(databaseURL: databaseURL)
        let persisted = await reopened.search("杭州")
        XCTAssertEqual(persisted.first?.assertionID, firstID)

        await reopened.rebuild([.init(id: secondID, text: "秋天去巴黎")])
        let rebuiltOld = await reopened.search("杭州")
        let rebuiltNew = await reopened.search("巴黎")
        XCTAssertTrue(rebuiltOld.isEmpty)
        XCTAssertEqual(rebuiltNew.first?.assertionID, secondID)
    }

    func testStagedRebuildKeepsOldResultsVisibleUntilTenThousandBatchCommit() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let oldID = UUID()
        await index.upsert(assertionID: oldID, text: "staged old snapshot")

        let targetID = UUID()
        let began = await index.beginStagedRebuild()
        XCTAssertTrue(began)

        let total = 10_000
        let batchSize = 1_000
        for start in stride(from: 0, to: total, by: batchSize) {
            let end = min(start + batchSize, total)
            let batch = (start..<end).map { offset in
                LocalMemorySearchIndex.Assertion(
                    id: offset == total - 1 ? targetID : UUID(),
                    text: offset == total - 1
                        ? "staged ten thousand target"
                        : "staged batch assertion \(offset)"
                )
            }
            let appended = await index.appendStagedBatch(batch)
            XCTAssertTrue(appended)
        }

        let beforeCommitOld = await index.search("snapshot")
        let beforeCommitNew = await index.search("ten thousand target")
        XCTAssertEqual(beforeCommitOld.first?.assertionID, oldID)
        XCTAssertTrue(beforeCommitNew.isEmpty)

        let committed = await index.commitStagedRebuild()
        XCTAssertTrue(committed)
        let committedCount = await index.count()
        XCTAssertEqual(committedCount, total)

        let afterCommit = await index.search("ten thousand target", limit: 4)
        XCTAssertEqual(afterCommit.first?.assertionID, targetID)
        XCTAssertLessThanOrEqual(afterCommit.count, 4)
        let afterCommitOld = await index.search("snapshot")
        XCTAssertTrue(afterCommitOld.isEmpty)
    }

    func testStagedRebuildFiftyThousandRowsCommitIsCompleteAndLimitBounded() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let targetID = UUID()
        let total = 50_000
        let batchSize = 5_000

        let began = await index.beginStagedRebuild()
        XCTAssertTrue(began)
        for start in stride(from: 0, to: total, by: batchSize) {
            let end = min(start + batchSize, total)
            let batch = (start..<end).map { offset in
                LocalMemorySearchIndex.Assertion(
                    id: offset == total - 1 ? targetID : UUID(),
                    text: offset == total - 1
                        ? "staged fifty thousand unique target"
                        : "staged fifty thousand common \(offset)"
                )
            }
            let appended = await index.appendStagedBatch(batch)
            XCTAssertTrue(appended)
        }

        let committed = await index.commitStagedRebuild()
        XCTAssertTrue(committed)
        let committedCount = await index.count()
        XCTAssertEqual(committedCount, total)

        let uniqueResults = await index.search("unique target", limit: 1)
        XCTAssertEqual(uniqueResults.first?.assertionID, targetID)
        let boundedResults = await index.search("staged fifty thousand", limit: 7)
        XCTAssertLessThanOrEqual(boundedResults.count, 7)
    }

    func testIntMaxLimitDoesNotOverflowAndFetchRemainsBounded() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let total = 2_100
        await index.rebuild((0..<total).map { offset in
            .init(
                id: UUID(),
                text: "intmax overflow candidate \(offset)"
            )
        })

        let results = await index.search("intmax overflow", limit: Int.max)

        XCTAssertFalse(results.isEmpty)
        XCTAssertLessThanOrEqual(results.count, 2_000)
        XCTAssertEqual(Set(results.map(\.assertionID)).count, results.count)
    }

    func testCancelStagedRebuildRetainsOldLiveResults() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let oldID = UUID()
        await index.upsert(assertionID: oldID, text: "cancel keeps this result")

        let began = await index.beginStagedRebuild()
        XCTAssertTrue(began)
        let appended = await index.appendStagedBatch([
            .init(id: UUID(), text: "cancelled replacement result")
        ])
        XCTAssertTrue(appended)

        let beforeCancel = await index.search("cancelled replacement")
        XCTAssertTrue(beforeCancel.isEmpty)
        let cancelled = await index.cancelStagedRebuild()
        XCTAssertTrue(cancelled)

        let oldResults = await index.search("keeps this result")
        let replacementResults = await index.search("cancelled replacement")
        XCTAssertEqual(oldResults.first?.assertionID, oldID)
        XCTAssertTrue(replacementResults.isEmpty)
        let retainedCount = await index.count()
        XCTAssertEqual(retainedCount, 1)
    }

    func testNonSearchableAndEmptyQueryAreSafe() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let hiddenID = UUID()
        await index.upsert(assertionID: hiddenID, text: "不可检索的记忆", isSearchable: false)
        let hiddenResults = await index.search("记忆")
        let emptyResults = await index.search("   ")
        let zeroLimitResults = await index.search("记忆", limit: 0)
        let count = await index.count()
        XCTAssertTrue(hiddenResults.isEmpty)
        XCTAssertTrue(emptyResults.isEmpty)
        XCTAssertTrue(zeroLimitResults.isEmpty)
        XCTAssertEqual(count, 1)
    }

    func testUnavailablePathDegradesToEmptyResults() async throws {
        let index = LocalMemorySearchIndex(databaseURL: URL(fileURLWithPath: "/dev/null/ayane-index.sqlite"))
        await index.upsert(assertionID: UUID(), text: "blue")
        let results = await index.search("blue")
        let count = await index.count()
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(count, 0)
    }

    func testIncompatibleLegacyCacheSchemaIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE TABLE ayane_memory_index_assertions (
            assertion_id TEXT PRIMARY KEY NOT NULL,
            old_text TEXT NOT NULL
        );
        PRAGMA user_version = 1;
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "迁移后可以检索")

        let count = await index.count()
        let results = await index.search("迁移 检索")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testSameColumnsOrdinaryTableInFTSSlotIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE TABLE ayane_memory_index_fts (
            assertion_id TEXT NOT NULL,
            token_text TEXT NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "普通表不能执行 FTS 搜索")

        let count = await index.count()
        let results = await index.search("FTS 搜索")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testSameColumnsOrdinaryAssertionTableWithoutPrimaryKeyIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE TABLE ayane_memory_index_assertions (
            assertion_id TEXT NOT NULL,
            source_text TEXT NOT NULL,
            token_text TEXT NOT NULL,
            is_searchable INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "无主键普通表必须重建")

        let count = await index.count()
        let results = await index.search("无主键 重建")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testSameColumnsStagingAssertionTableWithoutPrimaryKeyIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE TABLE ayane_memory_index_staging_assertions (
            assertion_id TEXT NOT NULL,
            source_text TEXT NOT NULL,
            token_text TEXT NOT NULL,
            is_searchable INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        );
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        let began = await index.beginStagedRebuild()
        XCTAssertTrue(began)
        let appended = await index.appendStagedBatch([
            .init(id: targetID, text: "无主键 staging 表必须重建")
        ])
        XCTAssertTrue(appended)
        let committed = await index.commitStagedRebuild()
        XCTAssertTrue(committed)

        let count = await index.count()
        let results = await index.search("无主键 staging")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testViewPlaceholderInFTSSlotIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE VIEW ayane_memory_index_fts AS
        SELECT 'legacy' AS assertion_id, 'legacy' AS token_text;
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "view 占位必须安全删除")

        let count = await index.count()
        let results = await index.search("view 占位")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testTriggerPlaceholderInFTSSlotIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE TABLE legacy_trigger_source (value TEXT);
        CREATE TRIGGER ayane_memory_index_fts
        AFTER INSERT ON legacy_trigger_source
        BEGIN
            SELECT 1;
        END;
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "trigger 占位必须安全删除")

        let count = await index.count()
        let results = await index.search("trigger 占位")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
    }

    func testWrongFTS5TokenizerIsSafelyRecreated() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let incompatibleSQL = """
        CREATE VIRTUAL TABLE ayane_memory_index_fts USING fts5(
            assertion_id UNINDEXED,
            token_text,
            tokenize = 'unicode61'
        );
        """
        XCTAssertEqual(sqlite3_exec(database, incompatibleSQL, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let index = LocalMemorySearchIndex(databaseURL: databaseURL)
        let targetID = UUID()
        await index.upsert(assertionID: targetID, text: "重建后使用预期 tokenizer")

        let count = await index.count()
        let results = await index.search("预期 tokenizer")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(results.first?.assertionID, targetID)
        let schemaSQL = try XCTUnwrap(readSchemaSQL(for: "ayane_memory_index_fts", at: databaseURL))
        XCTAssertTrue(schemaSQL.lowercased().contains("unicode61 remove_diacritics 2"))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AyaneLocalMemorySearchIndexTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
    }

    private func readSchemaSQL(for table: String, at url: URL) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK,
        let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT sql FROM sqlite_master WHERE name = ?1 LIMIT 1;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
        let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard table.withCString({ pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }) == SQLITE_OK,
        sqlite3_step(statement) == SQLITE_ROW,
        let sql = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: sql)
    }

    private func removeDatabase(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }
}
