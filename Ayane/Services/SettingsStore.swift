import Foundation

enum SettingsKeys {
    static let providerID = "provider.selectedID"
    static let providerSelectionMigrationVersion = "provider.selectionMigrationVersion"
    static let providerKeychainMigrationVersion = "provider.keychainMigrationVersion"
    static let baseURL = "provider.baseURL"
    static let model = "provider.model"
    static let embeddingModel = "provider.embeddingModel"
    static let temperature = "provider.temperature"
    static let streamResponses = "provider.streamResponses"
    static let imageGenerationBaseURL = "imageGeneration.baseURL"
    static let imageGenerationModel = "imageGeneration.model"
    static let imageGenerationAPIStyle = "imageGeneration.apiStyle"
    static let typingIndicatorEnabled = "chat.typingIndicatorEnabled"
    static let humanizedReplyDelayEnabled = "chat.humanizedReplyDelayEnabled"
    static let timeInjectionEnabled = "chat.timeInjectionEnabled"
    static let autoExtractMemory = "memory.autoExtract"
    static let memoryLastMaintenancePrefix = "memory.lastMaintenanceAt."
    static let memoryTokenBudget = "memory.tokenBudget"
    static let recentMessageLimit = "memory.recentMessageLimit"
    static let rawHistoryRecallEnabled = "memory.rawHistoryRecallEnabled"
    static let rawHistoryTokenBudget = "memory.rawHistoryTokenBudget"
    static let proactiveMessagesEnabled = "proactive.enabled"
    static let proactiveRoleEnabledPrefix = "proactive.roleEnabled."
    static let conversationCareEnabled = "proactive.conversationCareEnabled"
    static let conversationCareFirstReminderMinutes =
        "proactive.conversationCareFirstReminderMinutes"
    static let proactiveFollowUpEnabled = "proactive.followUpEnabled"
    static let proactiveFollowUpMinDays = "proactive.followUpMinDays"
    static let proactiveFollowUpMaxDays = "proactive.followUpMaxDays"
    static let proactiveQuietStartHour = "proactive.quietStartHour"
    static let proactiveQuietEndHour = "proactive.quietEndHour"
    static let cloudSyncEnabled = "persistence.cloudSyncEnabled"
    static let worldviewAutoMatchEnabled = "worldview.autoMatchEnabled"
    static let selectedCompanionRoleID = "companion.selectedRoleID"
    static let pinnedConversationIDs = "chatList.pinnedConversationIDs"
    static let manuallyUnreadConversationIDs = "chatList.manuallyUnreadConversationIDs"
    static let builtInCompanionCatalogMigrationVersion =
        "companion.builtInCatalogMigrationVersion"
    /// Legacy storage marker.  The three persona keys below remain readable
    /// during migration, but are no longer the canonical source once a
    /// CompanionProfileRecord exists.
    static let personaStorageMigrationVersion = "persona.storageMigrationVersion"
    static let personaName = "persona.name"
    static let userName = "persona.userName"
    static let personaPrompt = "persona.prompt"
    static let readStateStorageMigrationVersion = "readState.storageMigrationVersion"
}

enum SettingsStore {
    static let personaStorageMigrationVersion = 1
    // v2 adds read cursors for companion-authored Moments. Re-running the
    // baseline prevents historical role posts from appearing as newly unread
    // immediately after an upgrade.
    static let readStateStorageMigrationVersion = 2
    static let builtInCompanionCatalogMigrationVersion = 3

    static let defaultPersonaPrompt = UserIdentityPolicy.appendingInstruction(
        to: "你是主人的猫娘女仆。"
    )

    /// The in-memory fallback used before a persisted companion profile has
    /// been created.  Keeping this separate from the legacy UserDefaults
    /// reader makes it explicit that registered defaults are not a profile
    /// record and must not race a CloudKit import.
    static var fallbackPersonaConfiguration: PersonaConfiguration {
        PersonaConfiguration(
            name: "绫音",
            userName: BuiltInCompanionCatalog.userDefaultAddress,
            prompt: defaultPersonaPrompt
        )
    }

    static var defaultPersonaConfiguration: PersonaConfiguration {
        fallbackPersonaConfiguration
    }

    static func registerDefaults(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            SettingsKeys.providerID: ProviderPreset.deepSeek.rawValue,
            SettingsKeys.baseURL: "https://api.deepseek.com",
            SettingsKeys.model: "deepseek-v4-flash",
            SettingsKeys.embeddingModel: "",
            SettingsKeys.temperature: 0.8,
            SettingsKeys.streamResponses: true,
            SettingsKeys.imageGenerationBaseURL: "https://api.openai.com/v1",
            SettingsKeys.imageGenerationModel: "gpt-image-2",
            SettingsKeys.imageGenerationAPIStyle: ImageGenerationAPIStyle.imagesAPI.rawValue,
            SettingsKeys.typingIndicatorEnabled: true,
            SettingsKeys.humanizedReplyDelayEnabled: true,
            SettingsKeys.timeInjectionEnabled: true,
            SettingsKeys.autoExtractMemory: true,
            SettingsKeys.memoryTokenBudget: 2_400,
            SettingsKeys.recentMessageLimit: 24,
            SettingsKeys.rawHistoryRecallEnabled: true,
            SettingsKeys.rawHistoryTokenBudget: 1_000,
            SettingsKeys.proactiveMessagesEnabled: true,
            SettingsKeys.conversationCareEnabled: true,
            SettingsKeys.conversationCareFirstReminderMinutes:
                SettingsStore.defaultConversationCareFirstReminderMinutes,
            SettingsKeys.proactiveFollowUpEnabled: true,
            SettingsKeys.proactiveFollowUpMinDays: ProactiveMessagePolicy.defaultFollowUpMinDays,
            SettingsKeys.proactiveFollowUpMaxDays: ProactiveMessagePolicy.defaultFollowUpMaxDays,
            SettingsKeys.proactiveQuietStartHour: 23,
            SettingsKeys.proactiveQuietEndHour: 8,
            SettingsKeys.cloudSyncEnabled: false,
            SettingsKeys.worldviewAutoMatchEnabled: true,
            SettingsKeys.personaName: "绫音",
            SettingsKeys.userName: BuiltInCompanionCatalog.userDefaultAddress,
            SettingsKeys.personaPrompt: defaultPersonaPrompt
        ])
    }

    static func providerConfiguration(defaults: UserDefaults = .standard) -> ProviderConfiguration {
        return ProviderConfiguration(
            baseURL: defaults.string(forKey: SettingsKeys.baseURL) ?? "",
            model: defaults.string(forKey: SettingsKeys.model) ?? "",
            embeddingModel: defaults.string(forKey: SettingsKeys.embeddingModel) ?? "",
            temperature: defaults.double(forKey: SettingsKeys.temperature),
            streamsResponses: defaults.object(forKey: SettingsKeys.streamResponses) as? Bool ?? true
        )
    }

    static func selectedProvider(defaults: UserDefaults = .standard) -> ProviderPreset {
        ProviderPreset.resolve(
            defaults.string(forKey: SettingsKeys.providerID)
                ?? ProviderPreset.deepSeek.rawValue
        )
    }

    static var typingIndicatorEnabled: Bool {
        typingIndicatorEnabled(defaults: .standard)
    }

    static func typingIndicatorEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.typingIndicatorEnabled) as? Bool ?? true
    }

    static func humanizedReplyDelayEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.humanizedReplyDelayEnabled) as? Bool ?? true
    }

    static var timeInjectionEnabled: Bool {
        timeInjectionEnabled(defaults: .standard)
    }

    static func timeInjectionEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.timeInjectionEnabled) as? Bool ?? true
    }

    static var worldviewAutoMatchEnabled: Bool {
        worldviewAutoMatchEnabled(defaults: .standard)
    }

    static func worldviewAutoMatchEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.worldviewAutoMatchEnabled) as? Bool ?? true
    }

    /// Older builds had no explicit provider identity. Infer it from their
    /// saved address once; after that, the user's selected preset (including
    /// an intentional custom profile on a familiar host) is authoritative.
    static func migrateProviderSelectionIfNeeded(
        defaults: UserDefaults = .standard
    ) {
        guard defaults.integer(forKey: SettingsKeys.providerSelectionMigrationVersion) < 1 else {
            return
        }
        let baseURL = defaults.string(forKey: SettingsKeys.baseURL) ?? ""
        let inferred = ProviderPreset.matching(baseURL: baseURL) ?? .custom
        defaults.set(inferred.rawValue, forKey: SettingsKeys.providerID)
        defaults.set(1, forKey: SettingsKeys.providerSelectionMigrationVersion)
    }

    /// Load only a key that belongs to the selected provider, so changing a
    /// preset can never send one vendor's credential to another.
    static func currentAPIKey(defaults: UserDefaults = .standard) throws -> String? {
        let provider = selectedProvider(defaults: defaults)
        let baseURL = defaults.string(forKey: SettingsKeys.baseURL) ?? ""
        return try KeychainStore.loadAPIKey(providerID: provider.credentialID(for: baseURL))
    }

    /// Image generation is a separate provider surface. Its credential stays
    /// isolated from chat credentials so changing either endpoint can never
    /// send a token to the other provider by accident.
    static func imageGenerationAPIKey() throws -> String? {
        try KeychainStore.loadImageGenerationAPIKey()
    }

    static func imageGenerationConfiguration(
        defaults: UserDefaults = .standard
    ) -> ImageGenerationConfiguration {
        ImageGenerationConfiguration(
            baseURL: defaults.string(forKey: SettingsKeys.imageGenerationBaseURL)
                ?? "https://api.openai.com/v1",
            model: defaults.string(forKey: SettingsKeys.imageGenerationModel)
                ?? "gpt-image-2",
            apiStyle: ImageGenerationAPIStyle(
                rawValue: defaults.string(forKey: SettingsKeys.imageGenerationAPIStyle) ?? ""
            ) ?? .imagesAPI
        )
    }

    static func saveImageGenerationConfiguration(
        _ configuration: ImageGenerationConfiguration,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: SettingsKeys.imageGenerationBaseURL
        )
        defaults.set(
            configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: SettingsKeys.imageGenerationModel
        )
        defaults.set(
            configuration.apiStyle.rawValue,
            forKey: SettingsKeys.imageGenerationAPIStyle
        )
    }

    static func saveImageGenerationAPIKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainStore.saveImageGenerationAPIKey(trimmed)
    }

    static func deleteImageGenerationAPIKey() throws {
        try KeychainStore.deleteImageGenerationAPIKey()
    }

    /// Upgrade the former single Keychain account exactly once, during app
    /// startup and before Settings can change the endpoint. This preserves an
    /// existing user's key without allowing ordinary reads to move an
    /// unscoped credential to an arbitrary later host.
    @discardableResult
    static func migrateLegacyAPIKeyIfNeeded(
        defaults: UserDefaults = .standard
    ) throws -> String? {
        guard defaults.integer(forKey: SettingsKeys.providerKeychainMigrationVersion) < 1 else {
            return try currentAPIKey(defaults: defaults)
        }
        let provider = selectedProvider(defaults: defaults)
        let baseURL = defaults.string(forKey: SettingsKeys.baseURL) ?? ""
        let value = try KeychainStore.migrateLegacyAPIKey(
            to: provider.credentialID(for: baseURL)
        )
        defaults.set(1, forKey: SettingsKeys.providerKeychainMigrationVersion)
        return value
    }

    static func personaConfiguration(defaults: UserDefaults = .standard) -> PersonaConfiguration {
        let fallback = fallbackPersonaConfiguration
        return PersonaConfiguration(
            name: defaults.string(forKey: SettingsKeys.personaName) ?? fallback.name,
            userName: defaults.string(forKey: SettingsKeys.userName) ?? fallback.userName,
            prompt: defaults.string(forKey: SettingsKeys.personaPrompt) ?? fallback.prompt
        )
    }

    static func selectedCompanionRoleID(defaults: UserDefaults = .standard) -> UUID? {
        guard let rawValue = defaults.string(forKey: SettingsKeys.selectedCompanionRoleID) else {
            return nil
        }
        return UUID(uuidString: rawValue)
    }

    static func saveSelectedCompanionRoleID(
        _ roleID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(
            RoleScope.resolve(roleID).uuidString.lowercased(),
            forKey: SettingsKeys.selectedCompanionRoleID
        )
    }

    static func pinnedConversationIDs(
        defaults: UserDefaults = .standard
    ) -> Set<UUID> {
        conversationIDs(forKey: SettingsKeys.pinnedConversationIDs, defaults: defaults)
    }

    static func savePinnedConversationIDs(
        _ ids: Set<UUID>,
        defaults: UserDefaults = .standard
    ) {
        saveConversationIDs(ids, forKey: SettingsKeys.pinnedConversationIDs, defaults: defaults)
    }

    static func manuallyUnreadConversationIDs(
        defaults: UserDefaults = .standard
    ) -> Set<UUID> {
        conversationIDs(forKey: SettingsKeys.manuallyUnreadConversationIDs, defaults: defaults)
    }

    static func saveManuallyUnreadConversationIDs(
        _ ids: Set<UUID>,
        defaults: UserDefaults = .standard
    ) {
        saveConversationIDs(
            ids,
            forKey: SettingsKeys.manuallyUnreadConversationIDs,
            defaults: defaults
        )
    }

    private static func conversationIDs(
        forKey key: String,
        defaults: UserDefaults
    ) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func saveConversationIDs(
        _ ids: Set<UUID>,
        forKey key: String,
        defaults: UserDefaults
    ) {
        defaults.set(
            ids.map { $0.uuidString.lowercased() }.sorted(),
            forKey: key
        )
    }

    static var memoryTokenBudget: Int {
        memoryTokenBudget(defaults: .standard)
    }

    static func memoryTokenBudget(defaults: UserDefaults) -> Int {
        min(8_000, max(400, defaults.integer(forKey: SettingsKeys.memoryTokenBudget)))
    }

    static var recentMessageLimit: Int {
        recentMessageLimit(defaults: .standard)
    }

    static func recentMessageLimit(defaults: UserDefaults) -> Int {
        min(80, max(4, defaults.integer(forKey: SettingsKeys.recentMessageLimit)))
    }

    static var rawHistoryRecallEnabled: Bool {
        rawHistoryRecallEnabled(defaults: .standard)
    }

    static func rawHistoryRecallEnabled(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: SettingsKeys.rawHistoryRecallEnabled) as? Bool ?? true
    }

    static var rawHistoryTokenBudget: Int {
        rawHistoryTokenBudget(defaults: .standard)
    }

    static func rawHistoryTokenBudget(defaults: UserDefaults) -> Int {
        min(1_000, max(200, defaults.integer(forKey: SettingsKeys.rawHistoryTokenBudget)))
    }

    static var autoExtractMemory: Bool {
        autoExtractMemory(defaults: .standard)
    }

    static func autoExtractMemory(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: SettingsKeys.autoExtractMemory) as? Bool ?? true
    }

    static func proactiveMessagesEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.proactiveMessagesEnabled) as? Bool ?? true
    }

    static func proactiveMessagesEnabled(
        roleID: UUID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        // A role-level opt-in can narrow the global preference, but never
        // widen it. This makes the global switch a real fail-closed gate.
        guard proactiveMessagesEnabled(defaults: defaults) else { return false }
        let key = SettingsKeys.proactiveRoleEnabledPrefix
            + RoleScope.resolve(roleID).uuidString.lowercased()
        return defaults.object(forKey: key) as? Bool
            ?? true
    }

    static func setProactiveMessagesEnabled(
        _ enabled: Bool,
        roleID: UUID,
        defaults: UserDefaults = .standard
    ) {
        let key = SettingsKeys.proactiveRoleEnabledPrefix
            + RoleScope.resolve(roleID).uuidString.lowercased()
        defaults.set(enabled, forKey: key)
    }

    static let minimumConversationCareFirstReminderMinutes =
        ConversationCarePolicy.minimumFirstReminderMinutes
    static let maximumConversationCareFirstReminderMinutes =
        ConversationCarePolicy.maximumFirstReminderMinutes
    static let defaultConversationCareFirstReminderMinutes =
        ConversationCarePolicy.defaultFirstReminderMinutes

    static func conversationCareEnabled(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.object(forKey: SettingsKeys.conversationCareEnabled) as? Bool ?? true
    }

    static func conversationCareFirstReminderMinutes(
        defaults: UserDefaults = .standard
    ) -> Int {
        let stored = defaults.object(
            forKey: SettingsKeys.conversationCareFirstReminderMinutes
        ) == nil
            ? defaultConversationCareFirstReminderMinutes
            : defaults.integer(forKey: SettingsKeys.conversationCareFirstReminderMinutes)
        return min(
            maximumConversationCareFirstReminderMinutes,
            max(minimumConversationCareFirstReminderMinutes, stored)
        )
    }

    static var proactiveFollowUpEnabled: Bool {
        proactiveFollowUpEnabled(defaults: .standard)
    }

    static func proactiveFollowUpEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: SettingsKeys.proactiveFollowUpEnabled) as? Bool ?? true
    }

    static let defaultProactiveFollowUpDayRange =
        ProactiveMessagePolicy.defaultFollowUpMinDays...ProactiveMessagePolicy.defaultFollowUpMaxDays

    /// The follow-up range is kept in days at the settings boundary so it is
    /// easy to present and edit. Values are bounded and repaired when a
    /// partially-written preference has min > max.
    static func proactiveFollowUpDayRange(
        defaults: UserDefaults = .standard
    ) -> ClosedRange<Int> {
        let minimum = defaults.object(forKey: SettingsKeys.proactiveFollowUpMinDays) == nil
            ? defaultProactiveFollowUpDayRange.lowerBound
            : defaults.integer(forKey: SettingsKeys.proactiveFollowUpMinDays)
        let maximum = defaults.object(forKey: SettingsKeys.proactiveFollowUpMaxDays) == nil
            ? defaultProactiveFollowUpDayRange.upperBound
            : defaults.integer(forKey: SettingsKeys.proactiveFollowUpMaxDays)
        let lower = min(ProactiveMessagePolicy.maximumFollowUpDays,
                        max(ProactiveMessagePolicy.minimumFollowUpDays, minimum))
        let upper = min(ProactiveMessagePolicy.maximumFollowUpDays,
                        max(lower, maximum))
        return lower...upper
    }

    static func proactiveFollowUpDelayRange(
        defaults: UserDefaults = .standard
    ) -> ClosedRange<TimeInterval> {
        let days = proactiveFollowUpDayRange(defaults: defaults)
        return ProactiveMessagePolicy.followUpDelayRange(
            minDays: days.lowerBound,
            maxDays: days.upperBound
        )
    }

    static func proactiveQuietHours(defaults: UserDefaults = .standard) -> (start: Int, end: Int) {
        let start = defaults.object(forKey: SettingsKeys.proactiveQuietStartHour) == nil
            ? 23
            : defaults.integer(forKey: SettingsKeys.proactiveQuietStartHour)
        let end = defaults.object(forKey: SettingsKeys.proactiveQuietEndHour) == nil
            ? 8
            : defaults.integer(forKey: SettingsKeys.proactiveQuietEndHour)
        return (min(23, max(0, start)), min(23, max(0, end)))
    }

    static let memoryMaintenanceInterval: TimeInterval = 24 * 60 * 60

    static func lastMemoryMaintenanceAt(
        roleID: UUID,
        defaults: UserDefaults = .standard
    ) -> Date? {
        let key = SettingsKeys.memoryLastMaintenancePrefix
            + RoleScope.resolve(roleID).uuidString.lowercased()
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    static func saveMemoryMaintenanceDate(
        _ date: Date,
        roleID: UUID,
        defaults: UserDefaults = .standard
    ) {
        let key = SettingsKeys.memoryLastMaintenancePrefix
            + RoleScope.resolve(roleID).uuidString.lowercased()
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    static func memoryMaintenanceIsDue(
        roleID: UUID,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let last = lastMemoryMaintenanceAt(roleID: roleID, defaults: defaults) else {
            return true
        }
        return now.timeIntervalSince(last) >= memoryMaintenanceInterval
    }
}
