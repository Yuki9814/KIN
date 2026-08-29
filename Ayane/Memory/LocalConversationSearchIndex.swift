import Foundation
import SQLite3

/// A rebuildable, lexical index for the original conversation events.
///
/// This is deliberately a derived cache. The SwiftData conversation events remain
/// the source of truth, so an unavailable, corrupt, or deleted SQLite file simply
/// makes this index empty until the caller rebuilds it.
public actor LocalConversationSearchIndex {
    /// The small value object accepted by the index. Keeping the value independent
    /// from SwiftData's `ConversationEvent` also makes it safe to send into this
    /// actor under Swift 6 concurrency checking.
    public struct Event: Hashable, Sendable {
        public let id: UUID
        public let role: String
        public let body: String
        public let occurredAt: Date
        public let isSearchable: Bool

        public init(
            id: UUID,
            role: String,
            body: String,
            occurredAt: Date = Date(),
            isSearchable: Bool = true
        ) {
            self.id = id
            self.role = role
            self.body = body
            self.occurredAt = occurredAt
            self.isSearchable = isSearchable
        }

        /// Accepts raw-value roles such as the app's `EventRole` without making
        /// that model type part of this public cache API.
        public init<Role: RawRepresentable & Sendable>(
            id: UUID,
            role: Role,
            body: String,
            occurredAt: Date = Date(),
            isSearchable: Bool = true
        ) where Role.RawValue == String {
            self.init(
                id: id,
                role: role.rawValue,
                body: body,
                occurredAt: occurredAt,
                isSearchable: isSearchable
            )
        }

        public init(
            eventID: UUID,
            role: String,
            content: String,
            occurredAt: Date = Date(),
            isSearchable: Bool = true
        ) {
            self.init(
                id: eventID,
                role: role,
                body: content,
                occurredAt: occurredAt,
                isSearchable: isSearchable
            )
        }

        public init<Role: RawRepresentable & Sendable>(
            eventID: UUID,
            role: Role,
            content: String,
            occurredAt: Date = Date(),
            isSearchable: Bool = true
        ) where Role.RawValue == String {
            self.init(
                id: eventID,
                role: role,
                body: content,
                occurredAt: occurredAt,
                isSearchable: isSearchable
            )
        }

        public init(
            eventID: UUID,
            role: String,
            text: String,
            timestamp: Date = Date(),
            isSearchable: Bool = true
        ) {
            self.init(
                id: eventID,
                role: role,
                body: text,
                occurredAt: timestamp,
                isSearchable: isSearchable
            )
        }

        public init(
            id: UUID,
            role: String,
            text: String,
            timestamp: Date = Date(),
            isSearchable: Bool = true
        ) {
            self.init(
                id: id,
                role: role,
                body: text,
                occurredAt: timestamp,
                isSearchable: isSearchable
            )
        }

        public var eventID: UUID { id }
        public var eventUUID: UUID { id }
        public var uuid: UUID { id }
        public var content: String { body }
        public var text: String { body }
        public var timestamp: Date { occurredAt }
        public var date: Date { occurredAt }
        public var time: Date { occurredAt }
        public var searchable: Bool { isSearchable }
    }

    /// A lexical match containing only derived ranking data and the event identity.
    public struct SearchCandidate: Hashable, Identifiable, Sendable {
        public let eventID: UUID
        public let score: Double

        public init(eventID: UUID, score: Double) {
            self.eventID = eventID
            self.score = score
        }

        public init(id: UUID, score: Double) {
            self.init(eventID: id, score: score)
        }

        public var id: UUID { eventID }
        public var eventUUID: UUID { eventID }
        public var uuid: UUID { eventID }
        public var relevanceScore: Double { score }
        public var floatScore: Float { Float(score) }
    }

    public typealias Entry = Event
    public typealias Record = Event
    public typealias EventRecord = Event
    public typealias ConversationEventInput = Event
    public typealias IndexedEvent = Event
    public typealias ConversationEvent = Event
    public typealias SearchEvent = Event
    public typealias Candidate = SearchCandidate
    public typealias Result = SearchCandidate
    public typealias Match = SearchCandidate
    public typealias SearchResult = SearchCandidate

    /// The configured URL. For `init(inMemory: true)` this is a descriptive
    /// `:memory:` URL; the actual SQLite handle is opened with SQLite's memory path.
    public let databaseURL: URL

    private static let schemaVersion = 2
    private static let eventTable = "ayane_conversation_index_events"
    private static let ftsTable = "ayane_conversation_index_fts"
    private static let metadataTable = "ayane_conversation_index_metadata"
    private static let sourceMarkerKey = "source_marker"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Keeps the C handle owned by a reference type so actor teardown can close it
    /// without exposing an unsafe pointer in the public API.
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

    /// Opens or creates a durable cache at a caller-supplied URL.
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

    /// Uses an app-support location independent from `LocalMemorySearchIndex`.
    public init() {
        let url = Self.defaultDatabaseURL()
        self.databaseURL = url
        self.database = Self.openDatabase(at: url).map(SQLiteHandle.init)
    }

    /// Creates an in-memory cache when `true`; `false` is equivalent to the default
    /// durable initializer and is useful for configuration-driven call sites.
    public init(inMemory: Bool) {
        if inMemory {
            self.databaseURL = URL(fileURLWithPath: ":memory:")
            self.database = Self.openDatabase(path: ":memory:").map(SQLiteHandle.init)
        } else {
            let url = Self.defaultDatabaseURL()
            self.databaseURL = url
            self.database = Self.openDatabase(at: url).map(SQLiteHandle.init)
        }
    }

    public init(memory: Bool) {
        self.init(inMemory: memory)
    }

    /// Inserts or replaces one searchable event. Non-searchable and blank events
    /// are removed from the derived cache, which prevents redacted content from
    /// lingering after an event is edited.
    public func upsert(_ event: Event) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else {
            disableDatabase()
            return
        }

        let success = Self.writeUpsert(event, database: database)
            && Self.deleteMetadata(Self.sourceMarkerKey, database: database)
        if success && Self.commitTransaction(database) {
            return
        }

        _ = Self.rollbackTransaction(database)
        disableDatabase()
    }

    public func upsert(event: Event) {
        upsert(event)
    }

    public func upsert(eventID: UUID, role: String, body: String, occurredAt: Date = Date(), isSearchable: Bool = true) {
        upsert(Event(id: eventID, role: role, body: body, occurredAt: occurredAt, isSearchable: isSearchable))
    }

    public func upsert<Role: RawRepresentable & Sendable>(
        eventID: UUID,
        role: Role,
        body: String,
        occurredAt: Date = Date(),
        isSearchable: Bool = true
    ) where Role.RawValue == String {
        upsert(Event(id: eventID, role: role, body: body, occurredAt: occurredAt, isSearchable: isSearchable))
    }

    public func upsert(id: UUID, role: String, body: String, occurredAt: Date = Date(), isSearchable: Bool = true) {
        upsert(eventID: id, role: role, body: body, occurredAt: occurredAt, isSearchable: isSearchable)
    }

    public func upsert(eventID: UUID, role: String, content: String, timestamp: Date = Date(), isSearchable: Bool = true) {
        upsert(eventID: eventID, role: role, body: content, occurredAt: timestamp, isSearchable: isSearchable)
    }

    public func upsert<Role: RawRepresentable & Sendable>(
        eventID: UUID,
        role: Role,
        content: String,
        timestamp: Date = Date(),
        isSearchable: Bool = true
    ) where Role.RawValue == String {
        upsert(eventID: eventID, role: role, body: content, occurredAt: timestamp, isSearchable: isSearchable)
    }

    public func upsert(eventID: UUID, role: String, text: String, timestamp: Date = Date(), isSearchable: Bool = true) {
        upsert(eventID: eventID, role: role, body: text, occurredAt: timestamp, isSearchable: isSearchable)
    }

    public func upsert(id: UUID, role: String, text: String, timestamp: Date = Date(), isSearchable: Bool = true) {
        upsert(eventID: id, role: role, body: text, occurredAt: timestamp, isSearchable: isSearchable)
    }

    /// Removes an event from the derived cache.
    public func delete(_ eventID: UUID) {
        delete(eventID: eventID)
    }

    public func delete(eventID: UUID) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else {
            disableDatabase()
            return
        }

        let key = eventID.uuidString.lowercased()
        let success = Self.deleteExisting(key: key, database: database)
            && Self.deleteMetadata(Self.sourceMarkerKey, database: database)

        if success && Self.commitTransaction(database) {
            return
        }

        _ = Self.rollbackTransaction(database)
        disableDatabase()
    }

    public func delete(id: UUID) {
        delete(eventID: id)
    }

    /// Atomically replaces this cache with the supplied event snapshot.
    public func rebuild(_ events: [Event], sourceMarker: String? = nil) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        guard Self.beginTransaction(database) else {
            disableDatabase()
            return
        }

        var success = Self.execute(database, sql: "DELETE FROM \(Self.ftsTable);")
        success = success && Self.execute(database, sql: "DELETE FROM \(Self.eventTable);")
        success = success && Self.deleteMetadata(Self.sourceMarkerKey, database: database)
        if success {
            for event in events {
                guard Self.writeUpsert(event, database: database, removeExisting: false) else {
                    success = false
                    break
                }
            }
        }
        if success, let sourceMarker {
            success = Self.writeMetadata(
                key: Self.sourceMarkerKey,
                value: sourceMarker,
                database: database
            )
        }

        if success && Self.commitTransaction(database) {
            return
        }

        _ = Self.rollbackTransaction(database)
        disableDatabase()
    }

    public func rebuild(events: [Event]) {
        rebuild(events)
    }

    /// Marker for the SwiftData snapshot represented by this derived cache.
    /// A missing marker means the caller must reconcile before trusting results.
    public func sourceMarker() -> String? {
        guard let databaseHandle = database else { return nil }
        let database = databaseHandle.pointer
        var statement: OpaquePointer?
        let sql = "SELECT value FROM \(Self.metadataTable) WHERE key = ?1 LIMIT 1;"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            disableDatabase()
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard Self.bindText(statement, index: 1, value: Self.sourceMarkerKey) else {
            disableDatabase()
            return nil
        }
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let value = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: value)
        case SQLITE_DONE:
            return nil
        default:
            disableDatabase()
            return nil
        }
    }

    public func setSourceMarker(_ marker: String?) {
        guard let databaseHandle = database else { return }
        let database = databaseHandle.pointer
        let success: Bool
        if let marker {
            success = Self.writeMetadata(
                key: Self.sourceMarkerKey,
                value: marker,
                database: database
            )
        } else {
            success = Self.deleteMetadata(Self.sourceMarkerKey, database: database)
        }
        if !success { disableDatabase() }
    }

    /// Returns up to `limit` event IDs with a bounded lexical relevance score.
    ///
    /// FTS5 finds candidates; the final score is calculated from the same
    /// normalized token sets so CJK and Latin matches remain deterministic across
    /// SQLite builds. Empty queries, non-positive limits, and SQLite failures are
    /// safe and return an empty array.
    public func search(_ query: String, limit: Int = 20) -> [SearchCandidate] {
        let resultLimit = max(0, limit)
        guard resultLimit > 0,
              let databaseHandle = database,
              let terms = Self.uniqueQueryTokens(from: query),
              !terms.isEmpty else {
            return []
        }

        let database = databaseHandle.pointer
        let matchExpression = terms
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
        let scaledLimit = resultLimit > 625 ? Int.max : resultLimit * 16
        let fetchLimit = min(max(scaledLimit, 64), 10_000)
        let sql = """
        SELECT event_id, token_text, bm25(\(Self.ftsTable)) AS rank
        FROM \(Self.ftsTable)
        WHERE \(Self.ftsTable) MATCH ?1
        ORDER BY rank ASC, event_id ASC
        LIMIT ?2;
        """

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
        var stepResult = SQLITE_ROW
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(statement)
            guard stepResult == SQLITE_ROW else { break }
            guard let idCString = sqlite3_column_text(statement, 0),
                  let tokenCString = sqlite3_column_text(statement, 1) else {
                continue
            }
            let idString = String(cString: idCString)
            guard let eventID = UUID(uuidString: idString) else { continue }
            let documentTerms = Set(String(cString: tokenCString).split(separator: " ").map(String.init))
            let matchedCount = querySet.intersection(documentTerms).count
            guard matchedCount > 0 else { continue }

            let queryCoverage = Double(matchedCount) / Double(querySet.count)
            let documentCoverage = Double(matchedCount) / Double(max(1, documentTerms.count))
            let rank = sqlite3_column_double(statement, 2)
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
            candidates.append(SearchCandidate(eventID: eventID, score: score))
        }

        guard stepResult == SQLITE_DONE else {
            disableDatabase()
            return []
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.eventID.uuidString < $1.eventID.uuidString
        }
        return Array(candidates.prefix(resultLimit))
    }

    public func search(query: String, limit: Int = 20) -> [SearchCandidate] {
        search(query, limit: limit)
    }

    /// Number of currently indexed (searchable and non-blank) events.
    public func count() -> Int {
        guard let databaseHandle = database else { return 0 }
        let database = databaseHandle.pointer
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM \(Self.eventTable);"
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

    private static func defaultDatabaseURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return directory
            .appendingPathComponent("Ayane", isDirectory: true)
            .appendingPathComponent("local-conversation-index.sqlite", isDirectory: false)
    }

    private static func openDatabase(at url: URL) -> OpaquePointer? {
        guard url.isFileURL, !url.path.isEmpty else { return nil }
        return openDatabase(path: url.path)
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
        guard currentSchemaVersion(database) == schemaVersion || resetSchema(database) else {
            return false
        }
        let tableSQL = """
        CREATE TABLE IF NOT EXISTS \(eventTable) (
            event_id TEXT PRIMARY KEY NOT NULL,
            role TEXT NOT NULL,
            occurred_at REAL NOT NULL,
            token_text TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        """
        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS \(ftsTable) USING fts5(
            event_id UNINDEXED,
            token_text,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """
        let metadataSQL = """
        CREATE TABLE IF NOT EXISTS \(metadataTable) (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );
        """
        return execute(database, sql: tableSQL)
            && execute(database, sql: ftsSQL)
            && execute(database, sql: metadataSQL)
            && execute(database, sql: "PRAGMA user_version = \(schemaVersion);")
    }

    private static func writeUpsert(
        _ event: Event,
        database: OpaquePointer,
        removeExisting: Bool = true
    ) -> Bool {
        let key = event.id.uuidString.lowercased()
        let hasBody = !event.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // FTS5 cannot index an UNINDEXED UUID column for deletion. Resolve the
        // event-table rowid through its primary-key index, then delete FTS by
        // rowid. This keeps incremental replacement O(log N), not O(N).
        if removeExisting, !deleteExisting(key: key, database: database) {
            return false
        }

        guard event.isSearchable && hasBody else { return true }

        let tokenText = indexTokens(for: event).joined(separator: " ")
        guard !tokenText.isEmpty else { return true }

        let occurredAt = event.occurredAt.timeIntervalSince1970.isFinite
            ? event.occurredAt.timeIntervalSince1970
            : 0
        let upsertRow = execute(
            database,
            sql: """
            INSERT INTO \(Self.eventTable)
                (event_id, role, occurred_at, token_text, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5);
            """
        ) { statement in
            bindText(statement, index: 1, value: key)
                && bindText(statement, index: 2, value: event.role)
                && sqlite3_bind_double(statement, 3, occurredAt) == SQLITE_OK
                && bindText(statement, index: 4, value: tokenText)
                && sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970) == SQLITE_OK
        }
        guard upsertRow else { return false }
        let rowID = sqlite3_last_insert_rowid(database)

        return execute(
            database,
            sql: "INSERT INTO \(Self.ftsTable) (rowid, event_id, token_text) VALUES (?1, ?2, ?3);"
        ) { statement in
            sqlite3_bind_int64(statement, 1, rowID) == SQLITE_OK
                && bindText(statement, index: 2, value: key)
                && bindText(statement, index: 3, value: tokenText)
        }
    }

    private static func deleteExisting(key: String, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        let selectSQL = "SELECT rowid FROM \(eventTable) WHERE event_id = ?1 LIMIT 1;"
        guard sqlite3_prepare_v2(database, selectSQL, -1, &statement, nil) == SQLITE_OK,
              let statement,
              bindText(statement, index: 1, value: key) else {
            if let statement { sqlite3_finalize(statement) }
            return false
        }
        let step = sqlite3_step(statement)
        let rowID = step == SQLITE_ROW ? sqlite3_column_int64(statement, 0) : nil
        sqlite3_finalize(statement)
        guard step == SQLITE_ROW || step == SQLITE_DONE else { return false }

        if let rowID {
            guard execute(
                database,
                sql: "DELETE FROM \(ftsTable) WHERE rowid = ?1;",
                bind: { statement in
                sqlite3_bind_int64(statement, 1, rowID) == SQLITE_OK
                }
            ) else {
                return false
            }
        }
        return execute(
            database,
            sql: "DELETE FROM \(eventTable) WHERE event_id = ?1;"
        ) { statement in
            bindText(statement, index: 1, value: key)
        }
    }

    private static func currentSchemaVersion(_ database: OpaquePointer) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return -1
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func resetSchema(_ database: OpaquePointer) -> Bool {
        guard beginTransaction(database) else { return false }
        let success = execute(database, sql: "DROP TABLE IF EXISTS \(ftsTable);")
            && execute(database, sql: "DROP TABLE IF EXISTS \(eventTable);")
            && execute(database, sql: "DROP TABLE IF EXISTS \(metadataTable);")
        if success && commitTransaction(database) { return true }
        _ = rollbackTransaction(database)
        return false
    }

    private static func writeMetadata(
        key: String,
        value: String,
        database: OpaquePointer
    ) -> Bool {
        execute(
            database,
            sql: """
            INSERT INTO \(metadataTable) (key, value) VALUES (?1, ?2)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """
        ) { statement in
            bindText(statement, index: 1, value: key)
                && bindText(statement, index: 2, value: value)
        }
    }

    private static func deleteMetadata(_ key: String, database: OpaquePointer) -> Bool {
        execute(
            database,
            sql: "DELETE FROM \(metadataTable) WHERE key = ?1;"
        ) { statement in
            bindText(statement, index: 1, value: key)
        }
    }

    private static func indexTokens(for event: Event) -> [String] {
        var tokens = ConversationSearchTokenizer.tokens(from: event.role)
        tokens.append(contentsOf: ConversationSearchTokenizer.tokens(from: event.body))

        let idString = event.id.uuidString.lowercased()
        tokens.append(contentsOf: ConversationSearchTokenizer.tokens(from: idString))
        tokens.append("eventid" + idString.replacingOccurrences(of: "-", with: ""))
        tokens.append(contentsOf: timeTokens(for: event.occurredAt))
        return unique(tokens)
    }

    private static func uniqueQueryTokens(from query: String) -> [String]? {
        var tokens = ConversationSearchTokenizer.tokens(from: query)
        let queryRange = NSRange(query.startIndex..<query.endIndex, in: query)
        for match in uuidRegex.matches(in: query, options: [], range: queryRange) {
            guard let range = Range(match.range, in: query) else { continue }
            let uuidString = String(query[range]).lowercased()
            tokens.append("eventid" + uuidString.replacingOccurrences(of: "-", with: ""))
        }
        let result = unique(tokens)
        return result.isEmpty ? nil : result
    }

    private static func timeTokens(for date: Date) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return []
        }
        let monthText = String(format: "%02d", month)
        let dayText = String(format: "%02d", day)
        return [
            String(year),
            monthText,
            dayText,
            "date\(year)\(monthText)\(dayText)",
            "year\(year)",
            "month\(year)\(monthText)"
        ]
    }

    // This expression only adds an exact ID token; the ordinary tokenizer still
    // contributes UUID segments for partial ID searches.
    private static let uuidRegex = try! NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )

    private static func unique(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.filter { !$0.isEmpty && seen.insert($0).inserted }
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

    private func disableDatabase() {
        database = nil
    }
}

/// Tokenization used only by the conversation cache. Latin and number runs remain
/// words; Han, Hiragana, Katakana, Bopomofo, and Hangul runs contribute characters
/// plus overlapping bigrams so unspaced CJK searches work in system SQLite FTS5.
private enum ConversationSearchTokenizer {
    static func tokens(from text: String) -> [String] {
        var result: [String] = []
        var wordBuffer = ""
        var cjkRun: [String] = []

        func flushWord() {
            guard !wordBuffer.isEmpty else { return }
            result.append(wordBuffer)
            wordBuffer.removeAll(keepingCapacity: true)
        }

        func flushCJK() {
            guard !cjkRun.isEmpty else { return }
            result.append(contentsOf: cjkRun)
            if cjkRun.count > 1 {
                for index in 0..<(cjkRun.count - 1) {
                    result.append(cjkRun[index] + cjkRun[index + 1])
                }
            }
            cjkRun.removeAll(keepingCapacity: true)
        }

        for scalar in text.lowercased().unicodeScalars {
            if isCJKScript(scalar) {
                flushWord()
                cjkRun.append(String(scalar))
            } else if Character(String(scalar)).isLetter || Character(String(scalar)).isNumber {
                flushCJK()
                wordBuffer.append(contentsOf: String(scalar))
            } else {
                flushWord()
                flushCJK()
            }
        }

        flushWord()
        flushCJK()
        return result
    }

    private static func isCJKScript(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF, // Hangul Jamo
             0x3040...0x30FF, // Hiragana and Katakana
             0x3100...0x312F, // Bopomofo
             0x3130...0x318F, // Hangul compatibility jamo
             0x31A0...0x31BF, // Bopomofo extended
             0x31F0...0x31FF, // Katakana phonetic extensions
             0x3400...0x4DBF, // CJK Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xA960...0xA97F, // Hangul Jamo Extended A
             0xAC00...0xD7FF, // Hangul syllables and Jamo Extended B
             0xF900...0xFAFF, // CJK compatibility ideographs
             0xFF66...0xFF9D, // Halfwidth Katakana
             0x20000...0x2FA1F: // Supplementary ideographs
            return true
        default:
            return false
        }
    }
}

extension LocalConversationSearchIndex.Event {
    /// Convenience adapter for the app's SwiftData model. It intentionally copies
    /// values before the actor call and excludes redacted or blank source content.
    @MainActor init(_ event: ConversationEvent) {
        let role = event.role
        self.init(
            id: event.id,
            role: event.roleRaw,
            body: event.content,
            occurredAt: event.occurredAt,
            isSearchable: !event.redacted
                && event.deliveryState == .complete
                && (role == .user || role == .assistant)
                && !event.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }
}
