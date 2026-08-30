import Foundation

enum ImagePromptComposer {
    static func compose(
        userPrompt: String,
        context: ImagePromptContext = ImagePromptContext(),
        options: ImageGenerationBatchOptions = ImageGenerationBatchOptions(),
        variationIndex: Int = 0
    ) -> String {
        let request = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []
        sections.append("【画面目标】\n\(request)")

        let identity = identitySection(context: context, options: options)
        if !identity.isEmpty { sections.append("【人物连续性】\n\(identity)") }
        if !context.worldContext.isEmpty {
            sections.append("【世界与环境】\n\(context.worldContext)")
        }
        if !context.currentScene.isEmpty {
            sections.append("【当前场景】\n\(context.currentScene)")
        }
        if !context.relevantMemories.isEmpty {
            sections.append(
                "【与本次画面有关的已确认信息】\n"
                    + context.relevantMemories.map { "- \($0)" }.joined(separator: "\n")
            )
        }

        var rendering = [
            options.aspectRatio.promptInstruction,
            options.quality.promptInstruction
        ]
        if let style = options.style.promptInstruction { rendering.append(style) }
        if options.count > 1 {
            rendering.append(variationDirective(index: variationIndex, total: options.count))
        }
        sections.append("【构图与质量】\n" + rendering.map { "- \($0)" }.joined(separator: "\n"))

        let negatives = normalizedNegatives(options.negativePrompt)
        if !negatives.isEmpty {
            sections.append("【避免】\n\(negatives)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func identitySection(
        context: ImagePromptContext,
        options: ImageGenerationBatchOptions
    ) -> String {
        guard options.preserveCharacterIdentity else { return "" }
        var values: [String] = []
        if !context.characterName.isEmpty {
            values.append("人物：\(context.characterName)")
        }
        if !context.appearance.isEmpty {
            values.append("固定外貌：\(context.appearance)")
        }
        values.append(contentsOf: context.identityAnchors.map { "固定特征：\($0)" })
        if !values.isEmpty {
            values.append("保持上述身份特征稳定；服装、动作、镜头和环境可按本次要求变化。")
        }
        return values.joined(separator: "\n")
    }

    private static func variationDirective(index: Int, total: Int) -> String {
        let resolved = max(0, min(total - 1, index))
        let directions = [
            "第 1 个方案：优先清晰主体与完整叙事",
            "第 2 个方案：更换镜头机位、动作与光线关系，避免复制上一方案",
            "第 3 个方案：重新设计环境层次、服装细节与构图重心",
            "第 4 个方案：采用明显不同的景别与氛围，但保持角色身份一致"
        ]
        return directions[resolved]
    }

    private static func normalizedNegatives(_ value: String) -> String {
        value
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(20)
            .map { "- \($0)" }
            .joined(separator: "\n")
    }
}
