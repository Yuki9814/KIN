import Foundation

struct CharacterCardDocument: Codable, Equatable, Sendable {
    static let maximumImportBytes = 20 * 1_024 * 1_024
    static let maximumImportMegabytes = maximumImportBytes / 1_024 / 1_024

    var spec: String
    var specVersion: String
    var name: String
    var description: String
    var personality: String
    var scenario: String
    var firstMessage: String
    var exampleMessages: String
    var creatorNotes: String
    var systemPrompt: String
    var postHistoryInstructions: String
    var alternateGreetings: [String]
    var characterBook: CharacterCardBook?
    var tags: [String]
    var creator: String
    var characterVersion: String
    var extensions: [String: PortableJSONValue]

    init(
        spec: String = "chara_card_v2",
        specVersion: String = "2.0",
        name: String,
        description: String = "",
        personality: String = "",
        scenario: String = "",
        firstMessage: String = "",
        exampleMessages: String = "",
        creatorNotes: String = "",
        systemPrompt: String = "",
        postHistoryInstructions: String = "",
        alternateGreetings: [String] = [],
        characterBook: CharacterCardBook? = nil,
        tags: [String] = [],
        creator: String = "",
        characterVersion: String = "",
        extensions: [String: PortableJSONValue] = [:]
    ) {
        self.spec = spec
        self.specVersion = specVersion
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description
        self.personality = personality
        self.scenario = scenario
        self.firstMessage = firstMessage
        self.exampleMessages = exampleMessages
        self.creatorNotes = creatorNotes
        self.systemPrompt = systemPrompt
        self.postHistoryInstructions = postHistoryInstructions
        self.alternateGreetings = Self.normalizedStrings(alternateGreetings)
        self.characterBook = characterBook
        self.tags = Self.normalizedStrings(tags)
        self.creator = creator
        self.characterVersion = characterVersion
        self.extensions = extensions
    }

    static func decode(from data: Data) throws -> CharacterCardDocument {
        guard data.count <= maximumImportBytes else {
            throw CharacterCardImportError.fileTooLarge(
                maximumMegabytes: maximumImportMegabytes
            )
        }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(CardProbe.self, from: data) else {
            throw CharacterCardImportError.invalidJSON
        }
        let document: CharacterCardDocument
        if let spec = probe.spec {
            guard spec == "chara_card_v2" else {
                throw CharacterCardImportError.unsupportedSpecification(spec)
            }
            guard let envelope = try? decoder.decode(V2Envelope.self, from: data) else {
                throw CharacterCardImportError.invalidJSON
            }
            document = envelope.document
        } else {
            guard let card = try? decoder.decode(V1Card.self, from: data) else {
                throw CharacterCardImportError.invalidJSON
            }
            document = card.document
        }
        guard !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CharacterCardImportError.missingName
        }
        return document
    }

    func encodedV2(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(V2Envelope(document: self))
    }

    func promptPlan(
        userName: String,
        defaultSystemPrompt: String = "",
        defaultPostHistoryInstructions: String = ""
    ) -> CharacterCardPromptPlan {
        let characterName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUserName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
            .characterCardNonEmpty ?? "用户"
        let resolvedDescription = replacingMacros(
            in: description,
            characterName: characterName,
            userName: resolvedUserName
        )
        let resolvedPersonality = replacingMacros(
            in: personality,
            characterName: characterName,
            userName: resolvedUserName
        )
        let resolvedScenario = replacingMacros(
            in: scenario,
            characterName: characterName,
            userName: resolvedUserName
        )
        let personaPrompt = [
            promptSection("角色描述", resolvedDescription),
            promptSection("性格摘要", resolvedPersonality),
            promptSection("当前场景", resolvedScenario)
        ].compactMap { $0 }.joined(separator: "\n\n")

        let system = mergeOverride(
            systemPrompt,
            fallback: defaultSystemPrompt,
            characterName: characterName,
            userName: resolvedUserName
        )
        let postHistory = mergeOverride(
            postHistoryInstructions,
            fallback: defaultPostHistoryInstructions,
            characterName: characterName,
            userName: resolvedUserName
        )
        let greetings = Self.normalizedStrings([firstMessage] + alternateGreetings).map {
            replacingMacros(
                in: $0,
                characterName: characterName,
                userName: resolvedUserName
            )
        }
        let examples = replacingMacros(
            in: exampleMessages,
            characterName: characterName,
            userName: resolvedUserName
        )
        return CharacterCardPromptPlan(
            characterName: characterName,
            userName: resolvedUserName,
            personaPrompt: personaPrompt,
            systemPrompt: system,
            postHistoryInstructions: postHistory,
            firstMessages: greetings,
            exampleMessages: examples,
            creatorNotes: creatorNotes,
            lorebook: characterBook?.lorebook(fallbackName: characterName)
        )
    }

    /// Maps a rich card into KIN's current single-prompt persona without losing
    /// model-visible fields. Native card persistence can keep the richer fields
    /// separate, while legacy callers still receive coherent behavior today.
    func legacyCompatiblePersonaPrompt(userName: String) -> String {
        let plan = promptPlan(userName: userName)
        return [
            promptSection("角色系统指令", plan.systemPrompt),
            plan.personaPrompt.characterCardNonEmpty,
            promptSection("示例对话", plan.exampleMessages),
            promptSection("临近回复的强化指令", plan.postHistoryInstructions)
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    func qualityReport(userName: String) -> CharacterCardQualityReport {
        let plan = promptPlan(userName: userName)
        var warnings: [String] = []
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("缺少角色描述，模型只能依赖名称和聊天历史推断身份。")
        }
        if personality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("缺少性格摘要，群聊中更容易出现角色同质化。")
        }
        if firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("缺少首条消息，无法稳定示范回复长度与叙述风格。")
        }
        if plan.postHistoryInstructions.count > 2_000 {
            warnings.append("后置指令过长，会长期挤占最近对话的上下文。")
        }
        let permanent = [plan.personaPrompt, plan.systemPrompt, plan.postHistoryInstructions]
            .joined(separator: "\n")
        let permanentTokens = MemoryTokenizer.tokenCount(of: permanent)
        if permanentTokens > 3_000 {
            warnings.append("永久角色上下文超过约 3000 token，建议把细节拆到按需激活的世界书。")
        }
        return CharacterCardQualityReport(
            estimatedPermanentTokens: permanentTokens,
            estimatedExampleTokens: MemoryTokenizer.tokenCount(of: plan.exampleMessages),
            loreEntryCount: characterBook?.entries.count ?? 0,
            warnings: warnings
        )
    }

    static func stableUUID(_ value: String) -> UUID {
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

    private static func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private func replacingMacros(
        in value: String,
        characterName: String,
        userName: String
    ) -> String {
        value
            .replacingOccurrences(of: "{{char}}", with: characterName, options: .caseInsensitive)
            .replacingOccurrences(of: "<bot>", with: characterName, options: .caseInsensitive)
            .replacingOccurrences(of: "{{user}}", with: userName, options: .caseInsensitive)
            .replacingOccurrences(of: "<user>", with: userName, options: .caseInsensitive)
    }

    private func mergeOverride(
        _ override: String,
        fallback: String,
        characterName: String,
        userName: String
    ) -> String {
        let trimmedOverride = override.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmedOverride.isEmpty ? fallback : trimmedOverride
        let merged = source.replacingOccurrences(
            of: "{{original}}",
            with: fallback,
            options: .caseInsensitive
        )
        return replacingMacros(
            in: merged,
            characterName: characterName,
            userName: userName
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func promptSection(_ title: String, _ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "【\(title)】\n\(trimmed)"
    }
}
