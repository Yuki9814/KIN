import Foundation

extension GroupInteractionPreferences {
    /// Converts the portable persisted value into the strongly typed planner
    /// value. Unknown values have already been normalized by the preferences
    /// initializer, but the fallback keeps decoding future data fail-closed.
    var turnStrategy: GroupTurnStrategy {
        GroupTurnStrategy(rawValue: strategyRaw) ?? .natural
    }

    var promptAssemblyMode: GroupPromptAssemblyMode {
        GroupPromptAssemblyMode(rawValue: promptAssemblyModeRaw) ?? .swapActiveCharacter
    }
}

extension ImageInteractionPreferences {
    /// Maps provider-independent defaults onto the current batch executor. The
    /// provider adapter remains responsible for capability filtering before a
    /// concrete request is sent.
    var batchOptions: ImageGenerationBatchOptions {
        ImageGenerationBatchOptions(
            count: imageCount,
            aspectRatio: aspectRatioRaw == "square"
                ? .square
                : aspectRatioRaw == "tallPortrait"
                    ? .tallPortrait
                    : aspectRatioRaw == "landscape"
                        ? .landscape
                        : aspectRatioRaw == "wideLandscape"
                            ? .wideLandscape
                            : .portrait,
            quality: qualityRaw == "draft"
                ? .draft
                : qualityRaw == "high"
                    ? .high
                    : .standard,
            style: styleRaw == "photographic"
                ? .photographic
                : styleRaw == "cinematic"
                    ? .cinematic
                    : styleRaw == "illustration"
                        ? .illustration
                        : styleRaw == "animeCG"
                            ? .animeCG
                            : .inherit,
            preserveCharacterIdentity: preserveCharacterIdentity,
            negativePrompt: negativePrompt,
            maximumRetries: maximumRetries
        )
    }
}
