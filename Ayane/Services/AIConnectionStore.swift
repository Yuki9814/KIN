import Foundation

/// A non-secret description of one model connection. Secrets and OAuth tokens
/// are stored separately in the device Keychain and are never encoded here.
struct AIConnectionProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case apiKey
        case chatGPTSubscription
        case grokSubscription

        var title: String {
            switch self {
            case .apiKey:
                return "API Key"
            case .chatGPTSubscription:
                return "ChatGPT 登录"
            case .grokSubscription:
                return "Grok 登录"
            }
        }

        var providerTitle: String {
            switch self {
            case .apiKey:
                return "OpenAI 兼容 API"
            case .chatGPTSubscription:
                return "OpenAI"
            case .grokSubscription:
                return "xAI"
            }
        }
    }

    let id: UUID
    var displayName: String
    var kind: Kind
    var providerID: String
    var baseURL: String
    var model: String
    var embeddingModel: String
    var temperature: Double
    var streamsResponses: Bool
    let createdAt: Date
    var updatedAt: Date

    var configuration: ProviderConfiguration {
        ProviderConfiguration(
            baseURL: baseURL,
            model: model,
            embeddingModel: embeddingModel,
            temperature: temperature,
            streamsResponses: streamsResponses
        )
    }
}

struct ResolvedAIConnection: Sendable {
    let profile: AIConnectionProfile
    let configuration: ProviderConfiguration
    /// API-key connections carry their actual key. Subscription connections
    /// carry an opaque local reference that the network client resolves and
    /// refreshes from Keychain immediately before a request.
    let credential: String
}

enum AIConnectionStoreError: LocalizedError, Equatable {
    case invalidConnection
    case protectedConnection
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .invalidConnection:
            return "这个 AI 连接已不存在。"
        case .protectedConnection:
            return "当前 API Key 连接用于兼容已有设置，不能删除。"
        case .missingCredential:
            return "这个连接尚未完成登录或保存凭据。"
        }
    }
}

enum AIConnectionStore {
    /// A stable synthetic identity for the API settings that existed before
    /// multi-connection support. Its live values continue to come from the old
    /// keys, so an upgrade preserves the user's DeepSeek setup without copying
    /// or exposing its Keychain item.
    static let legacyConnectionID = UUID(
        uuidString: "6B6C2C6E-5164-4BA5-A0AB-0E41B0E54B85"
    )!

    private static let profilesKey = "provider.connections.v1"
    private static let defaultConnectionIDKey = "provider.defaultConnectionID.v1"
    private static let roleBindingsKey = "provider.roleBindings.v1"
    private static let oauthReferencePrefix = "ayane-oauth-reference:"

    static func connections(defaults: UserDefaults = .standard) -> [AIConnectionProfile] {
        [legacyConnection(defaults: defaults)] + additionalConnections(defaults: defaults)
    }

    static func legacyConnection(defaults: UserDefaults = .standard) -> AIConnectionProfile {
        let provider = SettingsStore.selectedProvider(defaults: defaults)
        let configuration = SettingsStore.providerConfiguration(defaults: defaults)
        return AIConnectionProfile(
            id: legacyConnectionID,
            displayName: provider.title + "（现有）",
            kind: .apiKey,
            providerID: provider.rawValue,
            baseURL: configuration.baseURL,
            model: configuration.model,
            embeddingModel: configuration.embeddingModel,
            temperature: configuration.temperature,
            streamsResponses: configuration.streamsResponses,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    static func connection(
        id: UUID,
        defaults: UserDefaults = .standard
    ) -> AIConnectionProfile? {
        connections(defaults: defaults).first { $0.id == id }
    }

    static func defaultConnectionID(defaults: UserDefaults = .standard) -> UUID {
        guard let raw = defaults.string(forKey: defaultConnectionIDKey),
              let id = UUID(uuidString: raw),
              connection(id: id, defaults: defaults) != nil else {
            return legacyConnectionID
        }
        return id
    }

    static func setDefaultConnectionID(
        _ id: UUID,
        defaults: UserDefaults = .standard
    ) throws {
        guard connection(id: id, defaults: defaults) != nil else {
            throw AIConnectionStoreError.invalidConnection
        }
        defaults.set(id.uuidString.lowercased(), forKey: defaultConnectionIDKey)
    }

    static func explicitConnectionID(
        for roleID: UUID,
        defaults: UserDefaults = .standard
    ) -> UUID? {
        let bindings = roleBindings(defaults: defaults)
        let key = RoleScope.resolve(roleID).uuidString.lowercased()
        guard let raw = bindings[key],
              let id = UUID(uuidString: raw),
              connection(id: id, defaults: defaults) != nil else {
            return nil
        }
        return id
    }

    static func selectedConnectionID(
        for roleID: UUID,
        defaults: UserDefaults = .standard
    ) -> UUID {
        explicitConnectionID(for: roleID, defaults: defaults)
            ?? defaultConnectionID(defaults: defaults)
    }

    static func setConnectionID(
        _ id: UUID?,
        for roleID: UUID,
        defaults: UserDefaults = .standard
    ) throws {
        if let id, connection(id: id, defaults: defaults) == nil {
            throw AIConnectionStoreError.invalidConnection
        }
        var bindings = roleBindings(defaults: defaults)
        let key = RoleScope.resolve(roleID).uuidString.lowercased()
        if let id {
            bindings[key] = id.uuidString.lowercased()
        } else {
            bindings.removeValue(forKey: key)
        }
        saveRoleBindings(bindings, defaults: defaults)
    }

    static func save(
        _ profile: AIConnectionProfile,
        defaults: UserDefaults = .standard
    ) throws {
        guard profile.id != legacyConnectionID else {
            throw AIConnectionStoreError.protectedConnection
        }
        var profiles = additionalConnections(defaults: defaults)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try saveAdditionalConnections(profiles, defaults: defaults)
    }

    static func delete(
        id: UUID,
        defaults: UserDefaults = .standard
    ) throws {
        guard id != legacyConnectionID else {
            throw AIConnectionStoreError.protectedConnection
        }
        var profiles = additionalConnections(defaults: defaults)
        guard profiles.contains(where: { $0.id == id }) else {
            throw AIConnectionStoreError.invalidConnection
        }
        let wasDefault =
            defaults.string(forKey: defaultConnectionIDKey)?.lowercased()
                == id.uuidString.lowercased()
        profiles.removeAll { $0.id == id }
        try saveAdditionalConnections(profiles, defaults: defaults)

        if wasDefault {
            defaults.set(
                legacyConnectionID.uuidString.lowercased(),
                forKey: defaultConnectionIDKey
            )
        }
        let removedValue = id.uuidString.lowercased()
        let filteredBindings = roleBindings(defaults: defaults).filter { $0.value != removedValue }
        saveRoleBindings(filteredBindings, defaults: defaults)
        try KeychainStore.deleteConnectionCredential(connectionID: id)
    }

    static func resolvedConnection(
        for roleID: UUID,
        defaults: UserDefaults = .standard,
        legacyKeyLoader: () throws -> String?
    ) throws -> ResolvedAIConnection {
        let id = selectedConnectionID(for: roleID, defaults: defaults)
        guard let profile = connection(id: id, defaults: defaults) else {
            throw AIConnectionStoreError.invalidConnection
        }
        let credential: String
        if id == legacyConnectionID {
            credential = try legacyKeyLoader() ?? ""
        } else {
            switch profile.kind {
            case .apiKey:
                guard let data = try KeychainStore.loadConnectionCredential(connectionID: id),
                      let value = String(data: data, encoding: .utf8),
                      !value.isEmpty else {
                    throw AIConnectionStoreError.missingCredential
                }
                credential = value
            case .chatGPTSubscription, .grokSubscription:
                guard try KeychainStore.loadConnectionCredential(connectionID: id) != nil else {
                    throw AIConnectionStoreError.missingCredential
                }
                credential = oauthReference(for: id)
            }
        }
        return ResolvedAIConnection(
            profile: profile,
            configuration: profile.configuration,
            credential: credential
        )
    }

    static func oauthReference(for id: UUID) -> String {
        oauthReferencePrefix + id.uuidString.lowercased()
    }

    static func connectionID(fromOAuthReference value: String) -> UUID? {
        guard value.hasPrefix(oauthReferencePrefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(oauthReferencePrefix.count)))
    }

    private static func additionalConnections(
        defaults: UserDefaults
    ) -> [AIConnectionProfile] {
        guard let data = defaults.data(forKey: profilesKey),
              let profiles = try? JSONDecoder().decode([AIConnectionProfile].self, from: data) else {
            return []
        }
        return profiles
            .filter { $0.id != legacyConnectionID }
            .sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private static func saveAdditionalConnections(
        _ profiles: [AIConnectionProfile],
        defaults: UserDefaults
    ) throws {
        let data = try JSONEncoder().encode(profiles)
        defaults.set(data, forKey: profilesKey)
    }

    private static func roleBindings(defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: roleBindingsKey) as? [String: String] ?? [:]
    }

    private static func saveRoleBindings(
        _ bindings: [String: String],
        defaults: UserDefaults
    ) {
        defaults.set(bindings, forKey: roleBindingsKey)
    }
}
