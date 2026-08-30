import Foundation

enum ImageAspectRatio: String, Codable, CaseIterable, Sendable {
    case square = "1:1"
    case portrait = "3:4"
    case tallPortrait = "9:16"
    case landscape = "4:3"
    case wideLandscape = "16:9"

    var promptInstruction: String {
        switch self {
        case .square: "方形 1:1 构图"
        case .portrait: "竖版 3:4 人像构图"
        case .tallPortrait: "竖屏 9:16 全身或环境人像构图"
        case .landscape: "横版 4:3 场景构图"
        case .wideLandscape: "宽屏 16:9 电影感场景构图"
        }
    }
}

enum ImageQualityPreference: String, Codable, CaseIterable, Sendable {
    case draft
    case standard
    case high

    var promptInstruction: String {
        switch self {
        case .draft: "优先快速成图，细节保持清楚"
        case .standard: "细节完整、光塱自然、人物比例准确"
        case .high: "高细节、高一致性、精细材质与专业光影"
        }
    }
}

enum ImageVisualStyle: String, Codable, CaseIterable, Sendable {
    case inherit
    case photographic
    case cinematic
    case illustration
    case animeCG = "anime_cg"

    var promptInstruction: String? {
        switch self {
        case .inherit: nil
        case .photographic: "真实摄影质感，避免塑料皮肤和过度锐化"
        case .cinematic: "电影感摄影，明确主光、辅光与景深层次"
        case .illustration: "精致插画质感，结构准确，材质清晰"
        case .animeCG: "高质量 2.5D 半写实 CG，非真人摄影，非平面漫画"
        }
    }
}

struct ImageGenerationBatchOptions: Equatable, Sendable {
    var count: Int
    var aspectRatio: ImageAspectRatio
    var quality: ImageQualityPreference
    var style: ImageVisualStyle
    var preserveCharacterIdentity: Bool
    var negativePrompt: String
    var maximumRetries: Int
    var initialRetryDelay: TimeInterval
    var interRequestDelay: TimeInterval

    init(
        count: Int = 1,
        aspectRatio: ImageAspectRatio = .square,
        quality: ImageQualityPreference = .standard,
        style: ImageVisualStyle = .inherit,
        preserveCharacterIdentity: Bool = true,
        negativePrompt: String = "",
        maximumRetries: Int = 2,
        initialRetryDelay: TimeInterval = 0.8,
        interRequestDelay: TimeInterval = 0
    ) {
        self.count = max(1, min(4, count))
        self.aspectRatio = aspectRatio
        self.quality = quality
        self.style = style
        self.preserveCharacterIdentity = preserveCharacterIdentity
        self.negativePrompt = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.maximumRetries = max(0, min(3, maximumRetries))
        self.initialRetryDelay = max(0, min(10, initialRetryDelay))
        self.interRequestDelay = max(0, min(5, interRequestDelay))
    }
}

struct ImagePromptContext: Equatable, Sendable {
    var characterName: String
    var appearance: String
    var identityAnchors: [String]
    var worldContext: String
    var currentScene: String
    var relevantMemories: [String]

    init(
        characterName: String = "",
        appearance: String = "",
        identityAnchors: [String] = [],
        worldContext: String = "",
        currentScene: String = "",
        relevantMemories: [String] = []
    ) {
        self.characterName = characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appearance = appearance.trimmingCharacters(in: .whitespacesAndNewlines)
        self.identityAnchors = Self.normalized(identityAnchors, limit: 12, itemLimit: 160)
        self.worldContext = worldContext.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentScene = currentScene.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relevantMemories = Self.normalized(relevantMemories, limit: 6, itemLimit: 180)
    }

    private static func normalized(
        _ values: [String],
        limit: Int,
        itemLimit: Int
    ) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let clipped = String(trimmed.prefix(itemLimit))
            guard seen.insert(clipped).inserted else { return nil }
            return clipped
        }.prefix(limit).map { $0 }
    }
}
