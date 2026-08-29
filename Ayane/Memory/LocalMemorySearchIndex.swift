import Foundation
import SQLite3

/// A small, rebuildable SQLite FTS5 index for long-term memory assertions.
///
/// The index intentionally stores only assertion IDs and searchable text. It is a
/// derived cache, not a second source of truth: callers can delete the database and
/// reconstruct it from SwiftData at any time. Every operation is serialized by the
/// actor, and an unavailable or damaged database behaves as an empty index.
public actor LocalMemorySearchIndex {
    /// The value supplied to the index when an assertion is inserted or rebuilt.
    public struct Assertion: Hashable, Sendable {
        public let id: UUID
        public let text: String
        public let isSearchable: Bool

        public init(id: UUID, text: String, isSearchable: Bool = true) {
            self.id = id
            self.text = text
            self.isSearchable = isSearchable
        }

        public init(assertionID: UUID, text: String, isSearchable: Bool = true) {
            self.init(id: assertionID, text: text, isSearchable: isSearchable)
        }

        public var assertionID: UUID { id }
        public var assertionUUID: UUID { id }
        public var content: String { text }
    }

    /// One lightweight candidate returned by a lexical lookup.
    public struct SearchCandidate: Hashable, Identifiable, Sendable {
        public let assertionID: UUID
        public let score: Double

        public init(assertionID: UUID, score: Double) {
            self.assertionID = assertionID
            self.score = score
        }

        public init(id: UUID, score: Double) {
            self.init(assertionID: id, score: score)
        }

        public var id: UUID { assertionID }
        public var assertionUUID: UUID { assertionID }
        public var uuid: UUID { assertionID }
        public var relevanceScore: Double { score }
        public var floatScore: Float { Float(score) }
    }

    // Common spellings make the small API convenient at call sites without exposing
    // SQLite implementation details.
    public typealias Candidate = SearchCandidate
    public typealias Result = SearchCandidate
    public typealias Entry = Assertion

    /// The URL used to open this derived cache.
    public let databaseURL: URL

    private static let schemaVersion = 2
    private static let assertionTable = "ayane_memory_index_assertions"
    private static let ftsTable = "ayane_memory_index_fts"
    private static let stagingAssertionTable = "ayane_memory_index_staging_assertions"
    private static let stagingFTSTable = "ayane_memory_index_staging_fts"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// SQLite's C pointer is kept behind a checked ownership object so the actor can
    /// satisfy Swift 6's nonisolated-deinit rules without leaking the handle.
    private final class SQLiteHandle: @unchecked Sendable {
        let pointer: OpaquePointer

        init(_ pointer: OpaquePointer) {
            self.pointer = pointer
        }

        deinit {
            sqlite3_close(pointer)
        }
    }

    private var database: SQLiteHandle?
    private var stagedRebuildActive = false

    /// Opens (or creates) a durable cache at `databaseURL`.
    ///
    /// Parent directories are created when possible. Opening or initializing SQLite
    /// is deliberately best effort; `search` then returns `[]` and mutations become
    /// no-ops if the path is unavailable.
    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
        self.database = Self.openDatabase(at: databaseURL).map(SQLiteHandle.init)
    }

    public init(url: URL) {
        self.init(databaseURL: url)
    }

    public init(path: URL) {
        self.init(databaseURL: path)
    }

    public init(databasePath: URL) {
        self.init(databaseURL: databasePath)
    }

    public init(path: String) {
        self.init(databaseURL: URL(fileURLWithPath: path))
    }

    public init(databasePath: String) {
        self.init(databaseURL: URL(fileURLWithPath: databasePath))
    }

    /// Uses an app-support location suitable for the standalone app.
    public init() {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.init(databaseURL: directory.appendingPathComponent("Ayane", isDirectory: true)
            .appendingPathComponent("local-memory-index.sqlite", isDirectory: false))
    }

    /// Creates an in-memory SQLite cache. This is useful for callers that do not need
    /// persistence and for tests that want to avoid filesystem state.
    public init(inMemory: Bool) {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("Ayane", isDirectory: true)
            .appendingPathComponent("local-memory-index.sqlite", isDirectory: false)
        self.databaseURL = inMemory ? URL(fileURLWithPath: ":memory:") : url
        self.database = inMemory
            ? Self.openDatabase(path: ":memory:").map(SQLiteHandle.init)
            : Self.openDatabase(at: url).map(SQLiteHandle.init)
    }

    /// Inserts or replaces one searchable assertion.
    public func upsert(_ assertion: Assertion) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else {
            disableDatabase()
            return
        }

        let success = writeUpsert(assertion, database: database)
        if success && Self.commitTransaction(database) {
            return
        }

        _ = Self.rollbackTransaction(database)
        disableDatabase()
    }

    public func upsert(assertionID: UUID, text: String, isSearchable: Bool = true) {
        upsert(Assertion(id: assertionID, text: text, isSearchable: isSearchable))
    }

    public func upsert(id: UUID, text: String, isSearchable: Bool = true) {
        upsert(assertionID: id, text: text, isSearchable: isSearchable)
    }

    /// Removes an assertion from this derived cache.
    public func delete(_ assertionID: UUID) {
        delete(assertionID: assertionID)
    }

    public func delete(assertionID: UUID) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else {
            disableDatabase()
            return
        }

        let key = assertionID.uuidString.lowercased()
        let success = Self.execute(
            database,
            sql: "DELETE FROM \(Self.ftsTable) WHERE assertion_id = ?1;"
        ) { statement in
            Self.bindText(statement, index: 1, value: key)
        } && Self.execute(
            database,
            sql: "DELETE FROM \(Self.assertionTable) WHERE assertion_id = ?1;"
        ) { statement in
            Self.bindText(statement, index: 1, value: key)
        }

        if success && Self.commitTransaction(database) {
            return
        }

        _ = Self.rollbackTransaction(database)
        disableDatabase()
    }

    /// Atomically replaces the entire derived cache with `assertions`.
    public func rebuild(_ assertions: [Assertion]) {
        guard beginStagedRebuild() else { return }
        guard appendStagedBatch(assertions) else {
            _ = cancelStagedRebuild()
            return
        }
        _ = commitStagedRebuild()
    }

    public func rebuild(assertions: [Assertion]) {
        rebuild(assertions)
    }

    // MARK: - Staged rebuild

    /// Starts a rebuild in tables which are intentionally invisible to `search`.
    ///
    /// The staging tables are cleared in their own transaction. The current live
    /// index is not touched until `commitStagedRebuild()` succeeds, so callers can
    /// append arbitrarily many batches without first materializing one large array.
    /// Calling this while another staged rebuild is active discards that staged
    /// attempt and starts a fresh one; the live index is never affected.
    @discardableResult
    public func beginStagedRebuild() -> Bool {
        stagedRebuildActive = false
        guard let databaseHandle = database else { return false }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else { return false }

        let success = Self.clearStagingTables(database)
        if success && Self.commitTransaction(database) {
            stagedRebuildActive = true
            return true
        }

        let rolledBack = Self.rollbackTransaction(database)
        if !rolledBack {
            disableDatabase()
        }
        return false
    }

    /// Appends one batch to the currently active staged rebuild.
    ///
    /// Each batch is committed to staging independently. A failed batch rolls
    /// back only that batch; previously appended staged rows and the live index
    /// remain intact so the caller may retry or cancel.
    @discardableResult
    public func appendStagedBatch(_ assertions: [Assertion]) -> Bool {
        guard stagedRebuildActive,
              let databaseHandle = database else {
            return false
        }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else { return false }

        var success = true
        for assertion in assertions {
            guard writeUpsert(
                assertion,
                database: database,
                assertionTable: Self.stagingAssertionTable,
                ftsTable: Self.stagingFTSTable
            ) else {
                success = false
                break
            }
        }

        if success && Self.commitTransaction(database) {
            return true
        }

        let rolledBack = Self.rollbackTransaction(database)
        if !rolledBack {
            stagedRebuildActive = false
            disableDatabase()
        }
        return false
    }

    /// Labelled spelling for call sites that prefer an explicit argument name.
    @discardableResult
    public func appendStagedBatch(assertions: [Assertion]) -> Bool {
        appendStagedBatch(assertions)
    }

    /// Atomically publishes the staged rebuild as the new live index.
    ///
    /// The live tables are copied from staging in one SQLite transaction. If any
    /// delete, copy, staging cleanup, or commit operation fails, rollback leaves
    /// the prior live index queryable and the staged attempt available for cancel
    /// or retry. Searches from this actor are serialized around this operation;
    /// other SQLite connections likewise see either the old or the new snapshot.
    @discardableResult
    public func commitStagedRebuild() -> Bool {
        guard stagedRebuildActive,
              let databaseHandle = database else {
            return false
        }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else { return false }

        var success = Self.execute(database, sql: "DELETE FROM \(Self.ftsTable);")
        success = success && Self.execute(database, sql: "DELETE FROM \(Self.assertionTable);")
        if success {
            success = Self.execute(
                database,
                sql: """
                INSERT INTO \(Self.assertionTable)
                    (assertion_id, source_text, token_text, is_searchable, updated_at)
                SELECT assertion_id, source_text, token_text, is_searchable, updated_at
                FROM \(Self.stagingAssertionTable);
                """
            )
        }
        if success {
            success = Self.execute(
                database,
                sql: """
                INSERT INTO \(Self.ftsTable) (assertion_id, token_text)
                SELECT assertion_id, token_text
                FROM \(Self.stagingFTSTable);
                """
            )
        }
        if success {
            success = Self.clearStagingTables(database)
        }

        if success && Self.commitTransaction(database) {
            stagedRebuildActive = false
            return true
        }

        let rolledBack = Self.rollbackTransaction(database)
        if !rolledBack {
            stagedRebuildActive = false
            disableDatabase()
        }
        return false
    }

    /// Cancels the active staged rebuild without changing the live index.
    ///
    /// Cancellation is idempotent. Staging cleanup is transactional and does not
    /// involve the live tables, so even a cleanup failure cannot clear live data.
    @discardableResult
    public func cancelStagedRebuild() -> Bool {
        guard stagedRebuildActive else { return true }
        guard let databaseHandle = database else { return false }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else { return false }

        if Self.clearStagingTables(database) && Self.commitTransaction(database) {
            stagedRebuildActive = false
            return true
        }

        let rolledBack = Self.rollbackTransaction(database)
        if !rolledBack {
            stagedRebuildActive = false
            disableDatabase()
        }
        // A successful rollback keeps the staged attempt active so a caller can
        // retry cleanup instead of silently abandoning residual private rows.
        return false
    }

    /// Returns at most `limit` matching assertion IDs, ranked by lexical overlap.
    ///
    /// FTS5 performs the candidate lookup. A deterministic, bounded score is then
    /// computed from the same normalized terms so Chinese, Japanese, and Korean
    /// character/bigram matches rank consistently across SQLite builds. Empty
    /// queries, invalid limits, and any SQLite failure return an empty array.
    public func search(_ query: String, limit: Int = 20) -> [SearchCandidate] {
        let resultLimit = max(0, limit)
        guard resultLimit > 0,
              let databaseHandle = database,
              let terms = Self.uniqueTokens(from: query),
              !terms.isEmpty else {
            return []
        }
        let database = databaseHandle.pointer

        let matchExpression = terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
        let sql = """
        SELECT assertion_id, token_text, bm25(\(Self.ftsTable)) AS rank
        FROM \(Self.ftsTable)
        WHERE \(Self.ftsTable) MATCH ?1
        ORDER BY rank ASC, assertion_id ASC
        LIMIT ?2;
        """
        // Keep the multiplier below the overflow boundary before scaling. The
        // SQLite fetch is capped anyway, so a larger caller limit cannot make
        // this query return more rows; clamping first preserves that bound for
        // Int.max as well as ordinary limits.
        let safeResultLimitForFetch = min(resultLimit, 2_000 / 8)
        let fetchLimit = min(max(safeResultLimitForFetch * 8, 64), 2_000)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            disableDatabase()
            return []
        }
        defer { sqlite3_finalize(statement) }

        guard Self.bindText(statement, index: 1, value: matchExpression),
              sqlite3_bind_int(statement, 2, Int32(fetchLimit)) == SQLITE_OK else {
            disableDatabase()
            return []
        }

        let querySet = Set(terms)
        var candidates: [SearchCandidate] = []
        candidates.reserveCapacity(min(resultLimit, fetchLimit))
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idCString = sqlite3_column_text(statement, 0),
                  let tokenCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            let idString = String(cString: idCString)
            guard let assertionID = UUID(uuidString: idString) else { continue }
            let documentTerms = Set(String(cString: tokenCString).split(separator: " ").map(String.init))
            let matchedCount = querySet.intersection(documentTerms).count
            guard matchedCount > 0 else { continue }

            let queryCoverage = Double(matchedCount) / Double(querySet.count)
            let documentCoverage = Double(matchedCount) / Double(max(1, documentTerms.count))
            let rank = sqlite3_column_double(statement, 2)
            // SQLite's bm25 is normally negative (more negative is better). It is
            // only a small tie-break signal here; overlap remains the primary score.
            let rankSignal: Double
            if rank.isFinite {
                rankSignal = rank < 0 ? min(1, abs(rank) / (1 + abs(rank))) : 1 / (1 + rank)
            } else {
                rankSignal = 0
            }
            let score = min(1, max(0,
                queryCoverage * 0.75 + documentCoverage * 0.20 + rankSignal * 0.05
            ))
            guard score.isFinite else { continue }
            candidates.append(SearchCandidate(assertionID: assertionID, score: score))
        }

        let stepResult = sqlite3_errcode(database)
        guard stepResult == SQLITE_OK || stepResult == SQLITE_DONE else {
            disableDatabase()
            return []
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.assertionID.uuidString < $1.assertionID.uuidString
        }
        return Array(candidates.prefix(resultLimit))
    }

    public func search(query: String, limit: Int = 20) -> [SearchCandidate] {
        search(query, limit: limit)
    }

    /// A diagnostic count of indexed assertion rows. This is still only cache state.
    public func count() -> Int {
        guard let databaseHandle = database else { return 0 }
        let database = databaseHandle.pointer
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(Self.assertionTable);"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            disableDatabase()
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            disableDatabase()
            return 0
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: - SQLite setup and writes

    private static func openDatabase(at url: URL) -> OpaquePointer? {
        let path = url.isFileURL ? url.path : ""
        return openDatabase(path: path)
    }

    private static func openDatabase(path: String) -> OpaquePointer? {
        guard !path.isEmpty else { return nil }

        if path != ":memory:" {
            let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                return nil
            }
        }

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = path.withCString {
            sqlite3_open_v2($0, &database, flags, nil)
        }
        guard openResult == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }

        let initialized = sqlite3_busy_timeout(database, 2_000) == SQLITE_OK
            && execute(database, sql: "PRAGMA foreign_keys = ON;")
            && createSchema(database)
        guard initialized else {
            sqlite3_close(database)
            return nil
        }
        return database
    }

    private static func createSchema(_ database: OpaquePointer) -> Bool {
        let ordinaryColumns: Set<String> = [
            "assertion_id", "source_text", "token_text", "is_searchable", "updated_at"
        ]
        let ftsColumns: Set<String> = ["assertion_id", "token_text"]
        let existingSchemaIsCompatible = schemaCompatibility(
            table: assertionTable,
            requiredColumns: ordinaryColumns,
            expectsFTS5: false,
            database: database
        ) && schemaCompatibility(
            table: ftsTable,
            requiredColumns: ftsColumns,
            expectsFTS5: true,
            database: database
        ) && schemaCompatibility(
            table: stagingAssertionTable,
            requiredColumns: ordinaryColumns,
            expectsFTS5: false,
            database: database
        ) && schemaCompatibility(
            table: stagingFTSTable,
            requiredColumns: ftsColumns,
            expectsFTS5: true,
            database: database
        )
        if !existingSchemaIsCompatible,
           !resetDerivedSchema(database) {
            return false
        }

        let tableSQL = """
        CREATE TABLE IF NOT EXISTS \(assertionTable) (
            assertion_id TEXT PRIMARY KEY NOT NULL,
            source_text TEXT NOT NULL,
            token_text TEXT NOT NULL,
            is_searchable INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        );
        """
        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(ftsTable) USING fts5(
            assertion_id UNINDEXED,
            token_text,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        let stagingTableSQL = """
        CREATE TABLE IF NOT EXISTS \(stagingAssertionTable) (
            assertion_id TEXT PRIMARY KEY NOT NULL,
            source_text TEXT NOT NULL,
            token_text TEXT NOT NULL,
            is_searchable INTEGER NOT NULL DEFAULT 1,
            updated_at REAL NOT NULL
        );
        """
        let stagingFTSSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(stagingFTSTable) USING fts5(
            assertion_id UNINDEXED,
            token_text,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        return execute(database, sql: tableSQL)
            && execute(database, sql: ftsSQL)
            && execute(database, sql: stagingTableSQL)
            && execute(database, sql: stagingFTSSQL)
            && execute(database, sql: "PRAGMA user_version = \(schemaVersion);")
    }

    /// Checks the object kind and definition in addition to its columns. A
    /// normal table can expose the same two FTS columns, and `PRAGMA table_info`
    /// reports those columns for an FTS virtual table as well, so columns alone
    /// cannot establish that MATCH/bm25 and the expected tokenizer are usable.
    private static func schemaCompatibility(
        table: String,
        requiredColumns: Set<String>,
        expectsFTS5: Bool,
        database: OpaquePointer
    ) -> Bool {
        guard let object = schemaObject(table, database: database) else {
            // A missing object is compatible with the CREATE statements below.
            return true
        }
        guard object.type == "table",
              let columns = tableColumns(table, database: database),
              requiredColumns.isSubset(of: columns),
              let sql = object.sql else {
            return false
        }

        if expectsFTS5 {
            return canonicalSchemaSQL(sql) == canonicalSchemaSQL(expectedFTS5SQL(for: table))
        }

        // `sqlite_master` reports virtual tables as type `table`; reject one in
        // an ordinary-table slot rather than accepting an unrelated FTS schema.
        return !canonicalSchemaSQL(sql).contains("createvirtualtable")
            && hasUniqueAssertionID(table: table, database: database)
    }

    private static func expectedFTS5SQL(for table: String) -> String {
        "CREATE VIRTUAL TABLE \(table) USING fts5(assertion_id UNINDEXED, token_text, tokenize = 'unicode61 remove_diacritics 2')"
    }

    /// SQLite preserves the CREATE statement in `sqlite_master` but allows
    /// harmless quoting and whitespace differences. Removing only those
    /// presentation differences keeps the column modifiers and tokenizer
    /// arguments part of the compatibility check.
    private static func canonicalSchemaSQL(_ sql: String) -> String {
        sql.lowercased()
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "'", with: "")
            .filter { !$0.isWhitespace }
            .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
    }

    /// The SQLite file is only a rebuildable cache. If a previous app version
    /// left incompatible columns, recreating these private tables is safer than
    /// permanently disabling search or attempting to migrate source data here.
    private static func resetDerivedSchema(_ database: OpaquePointer) -> Bool {
        dropSchemaObject(stagingFTSTable, database: database)
            && dropSchemaObject(stagingAssertionTable, database: database)
            && dropSchemaObject(ftsTable, database: database)
            && dropSchemaObject(assertionTable, database: database)
    }

    /// A malformed cache slot may be left behind as a view, trigger, index, or
    /// virtual table. DROP TABLE IF EXISTS is not safe for those names: SQLite
    /// reports an error when the object kind does not match. Consult
    /// sqlite_master first and issue the matching DROP statement. Virtual
    /// tables are reported as table and are therefore correctly removed by
    /// DROP TABLE.
    private static func dropSchemaObject(
        _ table: String,
        database: OpaquePointer
    ) -> Bool {
        guard let object = schemaObject(table, database: database) else {
            return true
        }
        let identifier = quotedIdentifier(table)
        switch object.type.lowercased() {
        case "table":
            return execute(database, sql: "DROP TABLE IF EXISTS \(identifier);")
        case "view":
            return execute(database, sql: "DROP VIEW IF EXISTS \(identifier);")
        case "trigger":
            return execute(database, sql: "DROP TRIGGER IF EXISTS \(identifier);")
        case "index":
            return execute(database, sql: "DROP INDEX IF EXISTS \(identifier);")
        default:
            // Do not guess a DROP statement for an unknown sqlite_master type.
            return false
        }
    }

    private static func schemaObject(
        _ table: String,
        database: OpaquePointer
    ) -> (type: String, sql: String?)? {
        var statement: OpaquePointer?
        let sql = "SELECT type, sql FROM sqlite_master WHERE name = ?1 LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard bindText(statement, index: 1, value: table),
              sqlite3_step(statement) == SQLITE_ROW,
              let typeCString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        let type = String(cString: typeCString)
        let createSQL = sqlite3_column_text(statement, 1).map(String.init(cString:))
        return (type, createSQL)
    }

    private static func tableColumns(
        _ table: String,
        database: OpaquePointer
    ) -> Set<String>? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(quotedIdentifier(table)));",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else { return nil }
        return columns
    }

    /// ON CONFLICT(assertion_id) is used by both the live and staging writes.
    /// SQLite only accepts that clause when the column is itself a single-column
    /// primary key or has a single-column UNIQUE constraint/index. A required
    /// column set alone is insufficient, because a legacy ordinary table can
    /// otherwise look valid until the first write reaches statement preparation.
    private static func hasUniqueAssertionID(
        table: String,
        database: OpaquePointer
    ) -> Bool {
        var tableInfoStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(quotedIdentifier(table)));",
            -1,
            &tableInfoStatement,
            nil
        ) == SQLITE_OK,
              let tableInfoStatement else {
            return false
        }
        defer { sqlite3_finalize(tableInfoStatement) }

        var primaryKeyColumnCount = 0
        var assertionIDIsPrimaryKey = false
        var stepResult = sqlite3_step(tableInfoStatement)
        while stepResult == SQLITE_ROW {
            if let name = sqlite3_column_text(tableInfoStatement, 1) {
                let columnName = String(cString: name)
                let isPrimaryKey = sqlite3_column_int(tableInfoStatement, 5) > 0
                if isPrimaryKey {
                    primaryKeyColumnCount += 1
                    if columnName == "assertion_id" {
                        assertionIDIsPrimaryKey = true
                    }
                }
            }
            stepResult = sqlite3_step(tableInfoStatement)
        }
        guard stepResult == SQLITE_DONE else { return false }
        if assertionIDIsPrimaryKey && primaryKeyColumnCount == 1 {
            return true
        }

        // A UNIQUE constraint is exposed through index_list as an autoindex;
        // explicitly created UNIQUE indexes are valid too. Composite and
        // partial indexes are deliberately rejected because they do not make
        // ON CONFLICT(assertion_id) universally applicable.
        var indexListStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA index_list(\(quotedIdentifier(table)));",
            -1,
            &indexListStatement,
            nil
        ) == SQLITE_OK,
              let indexListStatement else {
            return false
        }
        defer { sqlite3_finalize(indexListStatement) }

        stepResult = sqlite3_step(indexListStatement)
        while stepResult == SQLITE_ROW {
            let isUnique = sqlite3_column_int(indexListStatement, 2) != 0
            let isPartial = sqlite3_column_int(indexListStatement, 4) != 0
            if isUnique && !isPartial,
               let indexName = sqlite3_column_text(indexListStatement, 1) {
                let index = String(cString: indexName)
                if isSingleAssertionIDIndex(index, database: database) {
                    return true
                }
            }
            stepResult = sqlite3_step(indexListStatement)
        }
        return false
    }

    private static func isSingleAssertionIDIndex(
        _ index: String,
        database: OpaquePointer
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA index_info(\(quotedIdentifier(index)));",
            -1,
            &statement,
            nil
        ) == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        var columnCount = 0
        var assertionIDIsOnlyColumn = false
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            columnCount += 1
            // cid < 0 denotes an expression index, which is not a direct
            // uniqueness constraint on assertion_id.
            let columnID = sqlite3_column_int(statement, 1)
            if columnID >= 0,
               let name = sqlite3_column_text(statement, 2),
               String(cString: name) == "assertion_id" {
                assertionIDIsOnlyColumn = true
            } else {
                assertionIDIsOnlyColumn = false
            }
            stepResult = sqlite3_step(statement)
        }
        return stepResult == SQLITE_DONE
            && columnCount == 1
            && assertionIDIsOnlyColumn
    }

    private static func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func writeUpsert(_ assertion: Assertion, database: OpaquePointer) -> Bool {
        writeUpsert(
            assertion,
            database: database,
            assertionTable: Self.assertionTable,
            ftsTable: Self.ftsTable
        )
    }

    private func writeUpsert(
        _ assertion: Assertion,
        database: OpaquePointer,
        assertionTable: String,
        ftsTable: String
    ) -> Bool {
        let key = assertion.id.uuidString.lowercased()
        let tokens = MemoryTokenizer.tokens(from: assertion.text)
        let tokenText = tokens.joined(separator: " ")
        let searchable = assertion.isSearchable && !tokens.isEmpty
        let timestamp = Date().timeIntervalSince1970

        let deleteFTS = Self.execute(
            database,
            sql: "DELETE FROM \(ftsTable) WHERE assertion_id = ?1;"
        ) { statement in
            Self.bindText(statement, index: 1, value: key)
        }
        guard deleteFTS else { return false }

        let upsertRow = Self.execute(
            database,
            sql: """
            INSERT INTO \(assertionTable)
                (assertion_id, source_text, token_text, is_searchable, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5)
            ON CONFLICT(assertion_id) DO UPDATE SET
                source_text = excluded.source_text,
                token_text = excluded.token_text,
                is_searchable = excluded.is_searchable,
                updated_at = excluded.updated_at;
            """
        ) { statement in
            Self.bindText(statement, index: 1, value: key)
                && Self.bindText(statement, index: 2, value: assertion.text)
                && Self.bindText(statement, index: 3, value: tokenText)
                && sqlite3_bind_int(statement, 4, searchable ? 1 : 0) == SQLITE_OK
                && sqlite3_bind_double(statement, 5, timestamp) == SQLITE_OK
        }
        guard upsertRow else { return false }

        guard searchable else { return true }
        return Self.execute(
            database,
            sql: "INSERT INTO \(ftsTable) (assertion_id, token_text) VALUES (?1, ?2);"
        ) { statement in
            Self.bindText(statement, index: 1, value: key)
                && Self.bindText(statement, index: 2, value: tokenText)
        }
    }

    private static func clearStagingTables(_ database: OpaquePointer) -> Bool {
        execute(database, sql: "DELETE FROM \(stagingFTSTable);")
            && execute(database, sql: "DELETE FROM \(stagingAssertionTable);")
    }

    private static func execute(
        _ database: OpaquePointer,
        sql: String,
        bind: ((OpaquePointer) -> Bool)? = nil
    ) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        guard bind?(statement) ?? true else { return false }
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private static func bindText(_ statement: OpaquePointer, index: Int32, value: String) -> Bool {
        value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, sqliteTransient) == SQLITE_OK
        }
    }

    private static func beginTransaction(_ database: OpaquePointer) -> Bool {
        execute(database, sql: "BEGIN IMMEDIATE;")
    }

    private static func commitTransaction(_ database: OpaquePointer) -> Bool {
        execute(database, sql: "COMMIT;")
    }

    private static func rollbackTransaction(_ database: OpaquePointer) -> Bool {
        execute(database, sql: "ROLLBACK;")
    }

    private static func uniqueTokens(from text: String) -> [String]? {
        let tokens = MemoryTokenizer.tokens(from: text)
        guard !tokens.isEmpty else { return nil }
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }

    private func disableDatabase() {
        guard database != nil else { return }
        self.database = nil
    }
}
