import Foundation

/// User-controlled interaction preferences that are safe to keep outside the
/// durable conversation fact store. These values change how a future turn is
/// planned; they never rewrite an existing message, relationship event, memory,
/// lore entry, or generated image.
struct GroupInteractionPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultValue = GroupInteractionPreferences()

    var schemaVersion: Int
    var strategyRaw: String
    var promptAssemblyModeRaw: String
    var maximumAutomaticResponders: Int
    var allowSensitiveMemory: Bool

    init(
        schemaVersion: Int = currentSchemaVersion,
        strategyRaw: String = "natural",
        promptAssemblyModeRaw: String = "swapActiveCharacter",
        maximumAutomaticResponders: Int = 2,
        allowSensitiveMemory: Bool = false
    ) {
        self.schemaVersion = max(1, schemaVersion)
        self.strategyRaw = Self.normalizedChoice(
            strategyRaw,
            allowed: ["manual", "natural", "listOrder", "pooled"],
            fallback: "natural"
        )
        self.promptAssemblyModeRaw = Self.normalizedChoice(
            promptAssemblyModeRaw,
            allowed: ["swapActiveCharacter", "joinCharacterCards"],
            fallback: "swapActiveCharacter"
        )
        self.maximumAutomaticResponders = min(max(1, maximumAutomaticResponders), 4)
        self.allowSensitiveMemory = allowSensitiveMemory
    }

    var normalized: GroupInteractionPreferences {
        GroupInteractionPreferences(
            schemaVersion: schemaVersion,
            strategyRaw: strategyRaw,
            promptAssemblyModeRaw: promptAssemblyModeRaw,
            maximumAutomaticResponders: maximumAutomaticResponders,
            allowSensitiveMemory: allowSensitiveMemory
        )
    }

    private static func normalizedChoice(
        _ value: String,
        allowed: Set<String>,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowed.contains(trimmed) ? trimmed : fallback
    }
}

/// Provider-independent image defaults. Raw strings deliberately remain a
/// portable boundary: a provider capability adapter can map them onto the
/// subset supported by one concrete API without pretending every vendor has
/// identical parameters.
struct ImageInteractionPreferences: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultValue = ImageInteractionPreferences()

    var schemaVersion: Int
    var imageCount: Int
    var aspectRatioRaw: String
    var qualityRaw: String
    var styleRaw: String
    var preserveCharacterIdentity: Bool
    var negativePrompt: String
    var maximumRetries: Int

    init(
        schemaVersion: Int = currentSchemaVersion,
        imageCount: Int = 1,
        aspectRatioRaw: String = "portrait",
        qualityRaw: String = "standard",
        styleRaw: String = "inherit",
        preserveCharacterIdentity: Bool = true,
        negativePrompt: String = "",
        maximumRetries: Int = 2
    ) {
        self.schemaVersion = max(1, schemaVersion)
        self.imageCount = min(max(1, imageCount), 4)
        self.aspectRatioRaw = Self.normalizedChoice(
            aspectRatioRaw,
            allowed: ["square", "portrait", "tallPortrait", "landscape", "wideLandscape"],
            fallback: "portrait"
        )
        self.qualityRaw = Self.normalizedChoice(
            qualityRaw,
            allowed: ["draft", "standard", "high"],
            fallback: "standard"
        )
        self.styleRaw = Self.normalizedChoice(
            styleRaw,
            allowed: ["inherit", "photographic", "cinematic", "illustration", "animeCG"],
            fallback: "inherit"
        )
        self.preserveCharacterIdentity = preserveCharacterIdentity
        self.negativePrompt = String(
            negativePrompt
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(2_000)
        )
        self.maximumRetries = min(max(0, maximumRetries), 3)
    }

    var normalized: ImageInteractionPreferences {
        ImageInteractionPreferences(
            schemaVersion: schemaVersion,
            imageCount: imageCount,
            aspectRatioRaw: aspectRatioRaw,
            qualityRaw: qualityRaw,
            styleRaw: styleRaw,
            preserveCharacterIdentity: preserveCharacterIdentity,
            negativePrompt: negativePrompt,
            maximumRetries: maximumRetries
        )
    }

    private static func normalizedChoice(
        _ value: String,
        allowed: Set<String>,
        fallback: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowed.contains(trimmed) ? trimmed : fallback
    }
}

enum InteractionCorePreferencesStore {
    private static let namespace = "kin.interaction-core-v2"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func groupPreferences(
        conversationID: UUID,
        defaults: UserDefaults = .standard
    ) -> GroupInteractionPreferences {
        read(
            GroupInteractionPreferences.self,
            key: groupKey(conversationID),
            fallback: .defaultValue,
            defaults: defaults
        ).normalized
    }

    static func saveGroupPreferences(
        _ preferences: GroupInteractionPreferences,
        conversationID: UUID,
        defaults: UserDefaults = .standard
    ) throws {
        try write(
            preferences.normalized,
            key: groupKey(conversationID),
            defaults: defaults
        )
    }

    static func clearGroupPreferences(
        conversationID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: groupKey(conversationID))
    }

    static func imagePreferences(
        connectionID: UUID?,
        defaults: UserDefaults = .standard
    ) -> ImageInteractionPreferences {
        read(
            ImageInteractionPreferences.self,
            key: imageKey(connectionID),
            fallback: .defaultValue,
            defaults: defaults
        ).normalized
    }

    static func saveImagePreferences(
        _ preferences: ImageInteractionPreferences,
        connectionID: UUID?,
        defaults: UserDefaults = .standard
    ) throws {
        try write(
            preferences.normalized,
            key: imageKey(connectionID),
            defaults: defaults
        )
    }

    static func clearImagePreferences(
        connectionID: UUID?,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: imageKey(connectionID))
    }

    private static func read<Value: Decodable>(
        _ type: Value.Type,
        key: String,
        fallback: Value,
        defaults: UserDefaults
    ) -> Value {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else {
            return fallback
        }
        return value
    }

    private static func write<Value: Encodable>(
        _ value: Value,
        key: String,
        defaults: UserDefaults
    ) throws {
        defaults.set(try encoder.encode(value), forKey: key)
    }

    private static func groupKey(_ conversationID: UUID) -> String {
        "\(namespace).group.\(conversationID.uuidString.lowercased())"
    }

    private static func imageKey(_ connectionID: UUID?) -> String {
        let identity = connectionID?.uuidString.lowercased() ?? "default"
        return "\(namespace).image.\(identity)"
    }
}
