import Foundation

struct CharacterCardImportPreview: Equatable, Sendable {
    let card: CharacterCardDocument
    let resolvedPersonaPrompt: String
    let firstMessages: [String]
    let creatorNotes: String
    let qualityReport: CharacterCardQualityReport
    let embeddedLorebook: LorebookDocument?

    var preferredFirstMessage: String? { firstMessages.first }
}

struct CharacterCardImportResult: Equatable, Sendable {
    let roleID: UUID
    let preview: CharacterCardImportPreview
}

@MainActor
extension AppModel {
    func previewCharacterCardImport(
        data: Data,
        userName: String
    ) throws -> CharacterCardImportPreview {
        let card = try CharacterCardDocument.decode(from: data)
        let plan = card.promptPlan(userName: userName)
        return CharacterCardImportPreview(
            card: card,
            resolvedPersonaPrompt: card.legacyCompatiblePersonaPrompt(userName: userName),
            firstMessages: plan.firstMessages,
            creatorNotes: plan.creatorNotes,
            qualityReport: card.qualityReport(userName: userName),
            embeddedLorebook: plan.lorebook
        )
    }

    @discardableResult
    func importCharacterCard(
        data: Data,
        userName: String,
        worldProfileID: UUID? = nil
    ) throws -> CharacterCardImportResult {
        let preview = try previewCharacterCardImport(data: data, userName: userName)
        let resolvedPrompt = preview.resolvedPersonaPrompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrompt = "保持“\(preview.card.name)”的角色身份、表达风格和连续性。"
        let roleID = try createCompanion(
            name: preview.card.name,
            userName: userName,
            prompt: resolvedPrompt.isEmpty ? fallbackPrompt : resolvedPrompt,
            worldProfileID: worldProfileID
        )
        return CharacterCardImportResult(roleID: roleID, preview: preview)
    }
}
