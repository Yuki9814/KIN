import Foundation

struct CharacterCardPromptPlan: Equatable, Sendable {
    let characterName: String
    let userName: String
    let personaPrompt: String
    let systemPrompt: String
    let postHistoryInstructions: String
    let firstMessages: [String]
    let exampleMessages: String
    /// Creator notes are user-facing metadata and must never enter the model prompt.
    let creatorNotes: String
    let lorebook: LorebookDocument?
}

struct CharacterCardQualityReport: Equatable, Sendable {
    let estimatedPermanentTokens: Int
    let estimatedExampleTokens: Int
    let loreEntryCount: Int
    let warnings: [String]

    var isReady: Bool { warnings.isEmpty }
}

struct CardProbe: Decodable {
    let spec: String?
}

struct V1Card: Codable {
    let name: String
    let description: String
    let personality: String
    let scenario: String
    let firstMessage: String
    let exampleMessages: String

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case personality
        case scenario
        case firstMessage = "first_mes"
        case exampleMessages = "mes_example"
    }

    var document: CharacterCardDocument {
        CharacterCardDocument(
            name: name,
            description: description,
            personality: personality,
            scenario: scenario,
            firstMessage: firstMessage,
            exampleMessages: exampleMessages
        )
    }
}

struct V2Envelope: Codable {
    let spec: String
    let specVersion: String
    let data: V2Data

    enum CodingKeys: String, CodingKey {
        case spec
        case specVersion = "spec_version"
        case data
    }

    init(document: CharacterCardDocument) {
        spec = "chara_card_v2"
        specVersion = document.specVersion.characterCardNonEmpty ?? "2.0"
        data = V2Data(document: document)
    }

    var document: CharacterCardDocument {
        data.document(spec: spec, specVersion: specVersion)
    }
}

struct V2Data: Codable {
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

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case personality
        case scenario
        case firstMessage = "first_mes"
        case exampleMessages = "mes_example"
        case creatorNotes = "creator_notes"
        case systemPrompt = "system_prompt"
        case postHistoryInstructions = "post_history_instructions"
        case alternateGreetings = "alternate_greetings"
        case characterBook = "character_book"
        case tags
        case creator
        case characterVersion = "character_version"
        case extensions
    }

    init(document: CharacterCardDocument) {
        name = document.name
        description = document.description
        personality = document.personality
        scenario = document.scenario
        firstMessage = document.firstMessage
        exampleMessages = document.exampleMessages
        creatorNotes = document.creatorNotes
        systemPrompt = document.systemPrompt
        postHistoryInstructions = document.postHistoryInstructions
        alternateGreetings = document.alternateGreetings
        characterBook = document.characterBook
        tags = document.tags
        creator = document.creator
        characterVersion = document.characterVersion
        extensions = document.extensions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        personality = try container.decodeIfPresent(String.self, forKey: .personality) ?? ""
        scenario = try container.decodeIfPresent(String.self, forKey: .scenario) ?? ""
        firstMessage = try container.decodeIfPresent(String.self, forKey: .firstMessage) ?? ""
        exampleMessages = try container.decodeIfPresent(String.self, forKey: .exampleMessages) ?? ""
        creatorNotes = try container.decodeIfPresent(String.self, forKey: .creatorNotes) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
        postHistoryInstructions = try container.decodeIfPresent(
            String.self,
            forKey: .postHistoryInstructions
        ) ?? ""
        alternateGreetings = try container.decodeIfPresent(
            [String].self,
            forKey: .alternateGreetings
        ) ?? []
        characterBook = try container.decodeIfPresent(CharacterCardBook.self, forKey: .characterBook)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        creator = try container.decodeIfPresent(String.self, forKey: .creator) ?? ""
        characterVersion = try container.decodeIfPresent(String.self, forKey: .characterVersion) ?? ""
        extensions = try container.decodeIfPresent(
            [String: PortableJSONValue].self,
            forKey: .extensions
        ) ?? [:]
    }

    func document(spec: String, specVersion: String) -> CharacterCardDocument {
        CharacterCardDocument(
            spec: spec,
            specVersion: specVersion,
            name: name,
            description: description,
            personality: personality,
            scenario: scenario,
            firstMessage: firstMessage,
            exampleMessages: exampleMessages,
            creatorNotes: creatorNotes,
            systemPrompt: systemPrompt,
            postHistoryInstructions: postHistoryInstructions,
            alternateGreetings: alternateGreetings,
            characterBook: characterBook,
            tags: tags,
            creator: creator,
            characterVersion: characterVersion,
            extensions: extensions
        )
    }
}

extension String {
    var characterCardNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
