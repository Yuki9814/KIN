import Foundation

enum LorebookScope: String, Codable, CaseIterable, Sendable {
    case global
    case persona
    case character
    case conversation
}

enum LorebookEntryStrategy: String, Codable, CaseIterable, Sendable {
    case constant
    case keyword
}

enum LorebookSecondaryLogic: String, Codable, CaseIterable, Sendable {
    case andAny = "and_any"
    case andAll = "and_all"
    case notAny = "not_any"
    case notAll = "not_all"
}

enum LorebookInsertionPosition: String, Codable, CaseIterable, Sendable {
    case beforeCharacter = "before_character"
    case afterCharacter = "after_character"
    case beforeExamples = "before_examples"
    case afterExamples = "after_examples"
    case depthSystem = "depth_system"
    case depthUser = "depth_user"
    case depthAssistant = "depth_assistant"

    var stableOrder: Int {
        switch self {
        case .beforeCharacter: 0
        case .afterCharacter: 1
        case .beforeExamples: 2
        case .afterExamples: 3
        case .depthSystem: 4
        case .depthUser: 5
        case .depthAssistant: 6
        }
    }
}

enum LorebookMessageRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
}

struct LorebookMessage: Codable, Equatable, Sendable {
    var role: LorebookMessageRole
    var senderName: String?
    var content: String

    init(
        role: LorebookMessageRole,
        senderName: String? = nil,
        content: String
    ) {
        self.role = role
        self.senderName = senderName
        self.content = content
    }
}

/// One prompt-controlled lore entry. This is deliberately separate from
/// long-term memory: lore is authored setting/instructional context, while KIN
/// memory remains evidence-backed information extracted from conversations.
struct LorebookEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var content: String
    var primaryKeys: [String]
    var secondaryKeys: [String]
    var enabled: Bool
    var strategy: LorebookEntryStrategy
    var secondaryLogic: LorebookSecondaryLogic
    var insertionPosition: LorebookInsertionPosition
    /// Lower values render earlier; larger values sit closer to the current turn.
    var insertionOrder: Int
    /// Higher values win when the token budget cannot fit every activation.
    var priority: Int
    var caseSensitive: Bool
    var matchWholeWords: Bool
    var probabilityPercent: Int
    var tokenBudget: Int?
    var inclusionGroups: [String]
    var groupWeight: Int
    var nonRecursable: Bool
    var preventFurtherRecursion: Bool
    var delayUntilRecursion: Bool
    var recursionLevel: Int
    var delayMessages: Int
    var requiredCharacterIDs: [UUID]
    var excludedCharacterIDs: [UUID]
    var extensions: [String: PortableJSONValue]

    init(
        id: UUID = UUID(),
        name: String = "",
        content: String,
        primaryKeys: [String] = [],
        secondaryKeys: [String] = [],
        enabled: Bool = true,
        strategy: LorebookEntryStrategy = .keyword,
        secondaryLogic: LorebookSecondaryLogic = .andAny,
        insertionPosition: LorebookInsertionPosition = .afterCharacter,
        insertionOrder: Int = 100,
        priority: Int = 100,
        caseSensitive: Bool = false,
        matchWholeWords: Bool = true,
        probabilityPercent: Int = 100,
        tokenBudget: Int? = nil,
        inclusionGroups: [String] = [],
        groupWeight: Int = 100,
        nonRecursable: Bool = false,
        preventFurtherRecursion: Bool = false,
        delayUntilRecursion: Bool = false,
        recursionLevel: Int = 1,
        delayMessages: Int = 0,
        requiredCharacterIDs: [UUID] = [],
        excludedCharacterIDs: [UUID] = [],
        extensions: [String: PortableJSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.primaryKeys = Self.normalizedStrings(primaryKeys)
        self.secondaryKeys = Self.normalizedStrings(secondaryKeys)
        self.enabled = enabled
        self.strategy = strategy
        self.secondaryLogic = secondaryLogic
        self.insertionPosition = insertionPosition
        self.insertionOrder = insertionOrder
        self.priority = priority
        self.caseSensitive = caseSensitive
        self.matchWholeWords = matchWholeWords
        self.probabilityPercent = min(100, max(0, probabilityPercent))
        self.tokenBudget = tokenBudget.map { max(1, $0) }
        self.inclusionGroups = Self.normalizedStrings(inclusionGroups)
        self.groupWeight = max(0, groupWeight)
        self.nonRecursable = nonRecursable
        self.preventFurtherRecursion = preventFurtherRecursion
        self.delayUntilRecursion = delayUntilRecursion
        self.recursionLevel = max(1, recursionLevel)
        self.delayMessages = max(0, delayMessages)
        self.requiredCharacterIDs = Array(Set(requiredCharacterIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        self.excludedCharacterIDs = Array(Set(excludedCharacterIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        self.extensions = extensions
    }

    private static func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}

struct LorebookDocument: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var description: String
    var scope: LorebookScope
    var scanDepth: Int
    var tokenBudget: Int
    var recursiveScanning: Bool
    var maxRecursionSteps: Int
    var includeParticipantNames: Bool
    var boundPersonaIDs: [UUID]
    var boundCharacterIDs: [UUID]
    var boundConversationIDs: [UUID]
    var entries: [LorebookEntry]
    var extensions: [String: PortableJSONValue]

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        scope: LorebookScope = .global,
        scanDepth: Int = 2,
        tokenBudget: Int = 1_024,
        recursiveScanning: Bool = true,
        maxRecursionSteps: Int = 3,
        includeParticipantNames: Bool = true,
        boundPersonaIDs: [UUID] = [],
        boundCharacterIDs: [UUID] = [],
        boundConversationIDs: [UUID] = [],
        entries: [LorebookEntry] = [],
        extensions: [String: PortableJSONValue] = [:]
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.scanDepth = max(0, scanDepth)
        self.tokenBudget = max(0, tokenBudget)
        self.recursiveScanning = recursiveScanning
        self.maxRecursionSteps = max(1, min(8, maxRecursionSteps))
        self.includeParticipantNames = includeParticipantNames
        self.boundPersonaIDs = Self.stableUnique(boundPersonaIDs)
        self.boundCharacterIDs = Self.stableUnique(boundCharacterIDs)
        self.boundConversationIDs = Self.stableUnique(boundConversationIDs)
        self.entries = entries
        self.extensions = extensions
    }

    private static func stableUnique(_ values: [UUID]) -> [UUID] {
        Array(Set(values)).sorted { $0.uuidString < $1.uuidString }
    }
}

struct LorebookActivationContext: Equatable, Sendable {
    var messages: [LorebookMessage]
    var activePersonaID: UUID?
    var activeCharacterID: UUID?
    var activeConversationID: UUID?
    var tokenBudget: Int
    var maxEntries: Int
    var scanDepthOverride: Int?
    var maxRecursionStepsOverride: Int?
    /// Stable seed makes probability and inclusion-group choices reproducible.
    var deterministicSeed: String

    init(
        messages: [LorebookMessage],
        activePersonaID: UUID? = nil,
        activeCharacterID: UUID? = nil,
        activeConversationID: UUID? = nil,
        tokenBudget: Int = 1_024,
        maxEntries: Int = 40,
        scanDepthOverride: Int? = nil,
        maxRecursionStepsOverride: Int? = nil,
        deterministicSeed: String = ""
    ) {
        self.messages = messages
        self.activePersonaID = activePersonaID
        self.activeCharacterID = activeCharacterID
        self.activeConversationID = activeConversationID
        self.tokenBudget = max(0, tokenBudget)
        self.maxEntries = max(0, maxEntries)
        self.scanDepthOverride = scanDepthOverride.map { max(0, $0) }
        self.maxRecursionStepsOverride = maxRecursionStepsOverride.map {
            max(1, min(8, $0))
        }
        self.deterministicSeed = deterministicSeed
    }
}

enum LorebookActivationReason: String, Codable, CaseIterable, Sendable {
    case constant
    case keyword
    case recursive

    var rank: Int {
        switch self {
        case .constant: 3
        case .keyword: 2
        case .recursive: 1
        }
    }
}

struct LorebookActivationSelection: Identifiable, Equatable, Sendable {
    var id: String { documentID.uuidString + "|" + entry.id.uuidString }
    let documentID: UUID
    let documentName: String
    let entry: LorebookEntry
    let reason: LorebookActivationReason
    let matchedPrimaryKeys: [String]
    let matchedSecondaryKeys: [String]
    let recursionDepth: Int
    let tokenCount: Int
}

struct LorebookActivationResult: Equatable, Sendable {
    let selections: [LorebookActivationSelection]
    let skippedForBudget: [UUID]
    let skippedForInclusionGroup: [UUID]
    let usedTokenCount: Int
    let tokenBudget: Int

    var overflowed: Bool { !skippedForBudget.isEmpty }

    func selections(at position: LorebookInsertionPosition) -> [LorebookActivationSelection] {
        selections.filter { $0.entry.insertionPosition == position }
    }

    func renderedContent(at position: LorebookInsertionPosition) -> String {
        selections(at: position)
            .map { $0.entry.content.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

