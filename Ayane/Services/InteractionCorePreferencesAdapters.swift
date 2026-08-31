import Foundation

extension GroupInteractionPreferences {
    /// Converts the portable persisted value into the strongly typed planner
    /// value. The persisted strings intentionally use stable UI-facing camelCase
    /// names, while the planner enums use snake_case raw values for wire formats.
    /// Accept both spellings so existing preferences and future cross-platform
    /// payloads resolve to the same deterministic strategy.
    var turnStrategy: GroupReplyStrategy {
        switch strategyRaw {
        case "manual":
            return .manual
        case "listOrder", "list_order":
            return .listOrder
        case "pooled":
            return .pooled
        case "natural":
            return .natural
        default:
            return .natural
        }
    }

    var promptAssemblyMode: GroupPromptAssemblyMode {
        switch promptAssemblyModeRaw {
        case "joinCharacterCards", "join_character_cards":
            return .joinCharacterCards
        case "swapActiveCharacter", "swap_active_character":
            return .swapActiveCharacter
        default:
            return .swapActiveCharacter
        }
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
