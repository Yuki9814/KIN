import Foundation

enum LorebookStoreError: LocalizedError, Equatable {
    case invalidArchive
    case unsupportedArchive
    case emptyDocumentName

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "世界书文件不是有效的 JSON。"
        case .unsupportedArchive:
            return "无法识别这份世界书格式；支持 KIN 世界书、世界书数组与常见 World Info JSON。"
        case .emptyDocumentName:
            return "世界书名称不能为空。"
        }
    }
}

struct LorebookArchive: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var documents: [LorebookDocument]

    init(
        schemaVersion: Int = currentSchemaVersion,
        exportedAt: Date = Date(),
        documents: [LorebookDocument]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.documents = documents
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case documents
    }
}

/// Lightweight durable storage for authored lore. It intentionally does not
/// share the evidence-memory tables: worldbook entries are user-authored prompt
/// context, while long-term memory remains conversation-derived evidence.
enum LorebookStore {
    static let defaultsKey = "worldbook.documents.v1"
    static let maximumDocumentCount = 100
    static let maximumEntriesPerDocument = 2_000

    static func load(defaults: UserDefaults = .standard) -> [LorebookDocument] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        do {
            return try decode(data: data)
        } catch {
            return []
        }
    }

    static func save(
        _ documents: [LorebookDocument],
        defaults: UserDefaults = .standard
    ) throws {
        let normalized = try normalize(documents)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        defaults.set(try encoder.encode(LorebookArchive(documents: normalized)), forKey: defaultsKey)
    }

    static func exportData(
        _ documents: [LorebookDocument],
        prettyPrinted: Bool = true
    ) throws -> Data {
        let normalized = try normalize(documents)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(LorebookArchive(documents: normalized))
    }

    static func decode(data: Data) throws -> [LorebookDocument] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(LorebookArchive.self, from: data) {
            return try normalize(archive.documents)
        }
        if let documents = try? decoder.decode([LorebookDocument].self, from: data) {
            return try normalize(documents)
        }
        if let document = try? decoder.decode(LorebookDocument.self, from: data) {
            return try normalize([document])
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LorebookStoreError.invalidArchive
        }
        guard let imported = importWorldInfo(object), !imported.isEmpty else {
            throw LorebookStoreError.unsupportedArchive
        }
        return try normalize(imported)
    }

    static func merged(
        existing: [LorebookDocument],
        imported: [LorebookDocument]
    ) throws -> [LorebookDocument] {
        var winners: [UUID: LorebookDocument] = [:]
        for document in existing {
            winners[document.id] = document
        }
        for document in imported {
            winners[document.id] = document
        }
        return try normalize(Array(winners.values))
    }

    private static func normalize(_ documents: [LorebookDocument]) throws -> [LorebookDocument] {
        var winners: [UUID: LorebookDocument] = [:]
        for raw in documents.prefix(maximumDocumentCount) {
            var document = raw
            document.name = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !document.name.isEmpty else { throw LorebookStoreError.emptyDocumentName }
            document.description = String(
                document.description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(2_000)
            )
            document.scanDepth = max(0, min(100, document.scanDepth))
            document.tokenBudget = max(0, min(50_000, document.tokenBudget))
            document.maxRecursionSteps = max(1, min(8, document.maxRecursionSteps))
            document.entries = normalizedEntries(document.entries)
            winners[document.id] = document
        }
        return winners.values.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func normalizedEntries(_ entries: [LorebookEntry]) -> [LorebookEntry] {
        var winners: [UUID: LorebookEntry] = [:]
        for raw in entries.prefix(maximumEntriesPerDocument) {
            var entry = raw
            entry.name = String(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            entry.content = String(entry.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30_000))
            entry.primaryKeys = normalizedStrings(entry.primaryKeys, limit: 100, itemLimit: 200)
            entry.secondaryKeys = normalizedStrings(entry.secondaryKeys, limit: 100, itemLimit: 200)
            entry.inclusionGroups = normalizedStrings(entry.inclusionGroups, limit: 30, itemLimit: 120)
            entry.probabilityPercent = min(100, max(0, entry.probabilityPercent))
            entry.tokenBudget = entry.tokenBudget.map { max(1, min(50_000, $0)) }
            entry.recursionLevel = max(1, min(8, entry.recursionLevel))
            entry.delayMessages = max(0, min(10_000, entry.delayMessages))
            winners[entry.id] = entry
        }
        return winners.values.sorted { lhs, rhs in
            if lhs.insertionPosition.stableOrder != rhs.insertionPosition.stableOrder {
                return lhs.insertionPosition.stableOrder < rhs.insertionPosition.stableOrder
            }
            if lhs.insertionOrder != rhs.insertionOrder {
                return lhs.insertionOrder < rhs.insertionOrder
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func normalizedStrings(
        _ values: [String],
        limit: Int,
        itemLimit: Int
    ) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = String(
                raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(itemLimit)
            )
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }.prefix(limit).map { $0 }
    }

    private static func importWorldInfo(_ object: Any) -> [LorebookDocument]? {
        guard let root = object as? [String: Any] else { return nil }
        let rawEntries: [[String: Any]]
        if let entries = root["entries"] as? [[String: Any]] {
            rawEntries = entries
        } else if let entries = root["entries"] as? [String: Any] {
            rawEntries = entries
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .compactMap { key, value in
                    guard var row = value as? [String: Any] else { return nil }
                    if row["uid"] == nil { row["uid"] = key }
                    return row
                }
        } else {
            return nil
        }

        let fallbackName = string(root["name"])
            ?? string(root["display_name"])
            ?? "导入的世界书"
        let documentID = stableUUID("world-info|\(fallbackName)|\(rawEntries.count)")
        let entries = rawEntries.enumerated().compactMap { index, row in
            importedEntry(row, documentID: documentID, index: index)
        }
        let scanDepth = integer(root["scanDepth"] ?? root["scan_depth"]) ?? 2
        let tokenBudget = integer(root["tokenBudget"] ?? root["token_budget"]) ?? 1_024
        return [LorebookDocument(
            id: documentID,
            name: fallbackName,
            description: string(root["description"]) ?? "从 World Info JSON 导入",
            scope: .global,
            scanDepth: scanDepth,
            tokenBudget: tokenBudget,
            recursiveScanning: boolean(root["recursiveScanning"] ?? root["recursive_scanning"]) ?? true,
            maxRecursionSteps: integer(root["maxRecursionSteps"] ?? root["max_recursion_steps"]) ?? 3,
            entries: entries,
            extensions: portableObject(root["extensions"])
        )]
    }

    private static func importedEntry(
        _ row: [String: Any],
        documentID: UUID,
        index: Int
    ) -> LorebookEntry? {
        let content = string(row["content"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { return nil }
        let rawID = string(row["uid"] ?? row["id"]) ?? String(index)
        let keys = stringArray(row["key"] ?? row["keys"] ?? row["primary_keys"])
        let secondaryKeys = stringArray(row["keysecondary"] ?? row["secondary_keys"])
        let constant = boolean(row["constant"]) ?? false
        let disabled = boolean(row["disable"] ?? row["disabled"]) ?? false
        let selectiveLogic = integer(row["selectiveLogic"] ?? row["selective_logic"]) ?? 0
        let position = integer(row["position"]) ?? 1
        let probability = boolean(row["useProbability"] ?? row["use_probability"]) == false
            ? 100
            : (integer(row["probability"]) ?? 100)
        let group = string(row["group"])
        let insertionOrder = integer(row["order"] ?? row["insertion_order"]) ?? 100
        return LorebookEntry(
            id: stableUUID("world-info-entry|\(documentID.uuidString)|\(rawID)"),
            name: string(row["comment"] ?? row["name"]) ?? "条目 \(index + 1)",
            content: content,
            primaryKeys: keys,
            secondaryKeys: secondaryKeys,
            enabled: !disabled,
            strategy: constant ? .constant : .keyword,
            secondaryLogic: secondaryLogic(selectiveLogic),
            insertionPosition: insertionPosition(position),
            insertionOrder: insertionOrder,
            priority: integer(row["priority"]) ?? insertionOrder,
            caseSensitive: boolean(row["caseSensitive"] ?? row["case_sensitive"]) ?? false,
            matchWholeWords: boolean(row["matchWholeWords"] ?? row["match_whole_words"]) ?? false,
            probabilityPercent: probability,
            tokenBudget: integer(row["tokenBudget"] ?? row["token_budget"]),
            inclusionGroups: group.map { [$0] } ?? [],
            groupWeight: integer(row["groupWeight"] ?? row["group_weight"]) ?? 100,
            nonRecursable: boolean(row["nonRecursable"] ?? row["non_recursable"]) ?? false,
            preventFurtherRecursion: boolean(row["preventRecursion"] ?? row["prevent_recursion"]) ?? false,
            delayUntilRecursion: boolean(row["delayUntilRecursion"] ?? row["delay_until_recursion"]) ?? false,
            recursionLevel: integer(row["recursionLevel"] ?? row["recursion_level"]) ?? 1,
            delayMessages: integer(row["delay"] ?? row["delay_messages"]) ?? 0,
            extensions: portableObject(row["extensions"])
        )
    }

    private static func secondaryLogic(_ value: Int) -> LorebookSecondaryLogic {
        switch value {
        case 1: .notAll
        case 2: .notAny
        case 3: .andAll
        default: .andAny
        }
    }

    private static func insertionPosition(_ value: Int) -> LorebookInsertionPosition {
        switch value {
        case 0: .beforeCharacter
        case 2: .beforeExamples
        case 3: .afterExamples
        case 4: .depthSystem
        case 5: .depthUser
        case 6: .depthAssistant
        default: .afterCharacter
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap(string) }
        if let value = value as? String {
            return value.split(separator: ",").map(String.init)
        }
        return []
    }

    private static func portableObject(_ value: Any?) -> [String: PortableJSONValue] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        return dictionary.compactMapValues(portableValue)
    }

    private static func portableValue(_ value: Any) -> PortableJSONValue? {
        if value is NSNull { return .null }
        if let value = value as? Bool { return .bool(value) }
        if let value = value as? NSNumber { return .number(value.decimalValue) }
        if let value = value as? String { return .string(value) }
        if let value = value as? [Any] {
            return .array(value.compactMap(portableValue))
        }
        if let value = value as? [String: Any] {
            return .object(value.compactMapValues(portableValue))
        }
        return nil
    }

    private static func stableUUID(_ value: String) -> UUID {
        var left: UInt64 = 14_695_981_039_346_656_037
        var right: UInt64 = 10_995_116_282_11
        for byte in value.utf8 {
            left ^= UInt64(byte)
            left &*= 1_099_511_628_211
            right &+= UInt64(byte)
            right ^= right << 13
            right ^= right >> 7
            right ^= right << 17
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8((left >> UInt64((7 - index) * 8)) & 0xff)
            bytes[index + 8] = UInt8((right >> UInt64((7 - index) * 8)) & 0xff)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
