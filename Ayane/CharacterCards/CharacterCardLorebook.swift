import Foundation

enum CharacterCardImportError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case unsupportedSpecification(String)
    case missingName
    case fileTooLarge(maximumMegabytes: Int)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "角色卡不是有效的 Character Card V1/V2 JSON。"
        case .unsupportedSpecification(let value):
            return "暂不支持角色卡格式“\(value)”，请先转换为 Character Card V1 或 V2。"
        case .missingName:
            return "角色卡缺少角色名。"
        case .fileTooLarge(let maximumMegabytes):
            return "角色卡文件过大，最大支持 \(maximumMegabytes) MB。"
        }
    }
}

struct CharacterCardBookEntry: Codable, Equatable, Sendable {
    var keys: [String]
    var content: String
    var extensions: [String: PortableJSONValue]
    var enabled: Bool
    var insertionOrder: Int
    var caseSensitive: Bool?
    var name: String?
    var priority: Int?
    var id: Int?
    var comment: String?
    var selective: Bool?
    var secondaryKeys: [String]
    var constant: Bool?
    var position: String?

    enum CodingKeys: String, CodingKey {
        case keys
        case content
        case extensions
        case enabled
        case insertionOrder = "insertion_order"
        case caseSensitive = "case_sensitive"
        case name
        case priority
        case id
        case comment
        case selective
        case secondaryKeys = "secondary_keys"
        case constant
        case position
    }

    init(
        keys: [String] = [],
        content: String,
        extensions: [String: PortableJSONValue] = [:],
        enabled: Bool = true,
        insertionOrder: Int = 100,
        caseSensitive: Bool? = nil,
        name: String? = nil,
        priority: Int? = nil,
        id: Int? = nil,
        comment: String? = nil,
        selective: Bool? = nil,
        secondaryKeys: [String] = [],
        constant: Bool? = nil,
        position: String? = nil
    ) {
        self.keys = keys
        self.content = content
        self.extensions = extensions
        self.enabled = enabled
        self.insertionOrder = insertionOrder
        self.caseSensitive = caseSensitive
        self.name = name
        self.priority = priority
        self.id = id
        self.comment = comment
        self.selective = selective
        self.secondaryKeys = secondaryKeys
        self.constant = constant
        self.position = position
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decodeIfPresent([String].self, forKey: .keys) ?? []
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        extensions = try container.decodeIfPresent(
            [String: PortableJSONValue].self,
            forKey: .extensions
        ) ?? [:]
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        insertionOrder = try container.decodeIfPresent(Int.self, forKey: .insertionOrder) ?? 100
        caseSensitive = try container.decodeIfPresent(Bool.self, forKey: .caseSensitive)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        selective = try container.decodeIfPresent(Bool.self, forKey: .selective)
        secondaryKeys = try container.decodeIfPresent([String].self, forKey: .secondaryKeys) ?? []
        constant = try container.decodeIfPresent(Bool.self, forKey: .constant)
        position = try container.decodeIfPresent(String.self, forKey: .position)
    }
}

struct CharacterCardBook: Codable, Equatable, Sendable {
    var name: String?
    var description: String?
    var scanDepth: Int?
    var tokenBudget: Int?
    var recursiveScanning: Bool?
    var extensions: [String: PortableJSONValue]
    var entries: [CharacterCardBookEntry]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case scanDepth = "scan_depth"
        case tokenBudget = "token_budget"
        case recursiveScanning = "recursive_scanning"
        case extensions
        case entries
    }

    init(
        name: String? = nil,
        description: String? = nil,
        scanDepth: Int? = nil,
        tokenBudget: Int? = nil,
        recursiveScanning: Bool? = nil,
        extensions: [String: PortableJSONValue] = [:],
        entries: [CharacterCardBookEntry] = []
    ) {
        self.name = name
        self.description = description
        self.scanDepth = scanDepth
        self.tokenBudget = tokenBudget
        self.recursiveScanning = recursiveScanning
        self.extensions = extensions
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        scanDepth = try container.decodeIfPresent(Int.self, forKey: .scanDepth)
        tokenBudget = try container.decodeIfPresent(Int.self, forKey: .tokenBudget)
        recursiveScanning = try container.decodeIfPresent(Bool.self, forKey: .recursiveScanning)
        extensions = try container.decodeIfPresent(
            [String: PortableJSONValue].self,
            forKey: .extensions
        ) ?? [:]
        entries = try container.decodeIfPresent([CharacterCardBookEntry].self, forKey: .entries) ?? []
    }

    func lorebook(
        fallbackName: String,
        scope: LorebookScope = .character,
        boundCharacterIDs: [UUID] = []
    ) -> LorebookDocument {
        let resolvedName = name?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .characterCardNonEmpty ?? "\(fallbackName)角色世界书"
        let documentID = CharacterCardDocument.stableUUID("book|\(resolvedName)|\(fallbackName)")
        let mappedEntries = entries.enumerated().map { index, value in
            let label = value.name?.characterCardNonEmpty
                ?? value.comment?.characterCardNonEmpty
                ?? value.keys.first?.characterCardNonEmpty
                ?? "条目 \(index + 1)"
            let stableEntryKey = value.id.map(String.init)
                ?? "\(index)|\(label)|\(value.content)"
            let selectiveKeys = value.selective == true ? value.secondaryKeys : []
            return LorebookEntry(
                id: CharacterCardDocument.stableUUID(
                    "entry|\(documentID.uuidString)|\(stableEntryKey)"
                ),
                name: label,
                content: value.content,
                primaryKeys: value.keys,
                secondaryKeys: selectiveKeys,
                enabled: value.enabled,
                strategy: value.constant == true ? .constant : .keyword,
                secondaryLogic: .andAny,
                insertionPosition: lorebookInsertionPosition(value.position),
                insertionOrder: value.insertionOrder,
                priority: value.priority ?? value.insertionOrder,
                caseSensitive: value.caseSensitive ?? false,
                matchWholeWords: false,
                extensions: value.extensions
            )
        }
        return LorebookDocument(
            id: documentID,
            name: resolvedName,
            description: description ?? "",
            scope: scope,
            scanDepth: scanDepth ?? 2,
            tokenBudget: tokenBudget ?? 1_024,
            recursiveScanning: recursiveScanning ?? true,
            maxRecursionSteps: 3,
            boundCharacterIDs: boundCharacterIDs,
            entries: mappedEntries,
            extensions: extensions
        )
    }

    private func lorebookInsertionPosition(
        _ rawValue: String?
    ) -> LorebookInsertionPosition {
        switch rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "before_char", "before_character":
            return .beforeCharacter
        case "before_example", "before_examples":
            return .beforeExamples
        case "after_example", "after_examples":
            return .afterExamples
        case "at_depth", "depth_system":
            return .depthSystem
        case "depth_user":
            return .depthUser
        case "depth_assistant":
            return .depthAssistant
        default:
            return .afterCharacter
        }
    }
}
