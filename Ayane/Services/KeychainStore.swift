import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串操作失败：\(message)（\(status)）"
        case .invalidData:
            return "钥匙串中的密钥格式无效。"
        }
    }
}

enum KeychainStore {
    // Keep the credential namespace aligned with the active app bundle. A
    // local build that uses its original Bundle ID therefore sees its
    // existing keychain items; public builds use the neutral Bundle ID.
    private static let service = (Bundle.main.bundleIdentifier ?? "com.example.kin") + ".provider"
    private static let legacyAccount = "primary-api-key"
    private static let providerAccountPrefix = "provider-api-key."
    private static let connectionCredentialPrefix = "connection-credential."
    private static let imageGenerationAccount = "image-generation-api-key"

    static func saveAPIKey(_ value: String, providerID: String) throws {
        try save(Data(value.utf8), account: providerAccount(for: providerID))
    }

    static func saveConnectionCredential(_ data: Data, connectionID: UUID) throws {
        try save(data, account: connectionAccount(for: connectionID))
    }

    static func loadConnectionCredential(connectionID: UUID) throws -> Data? {
        try loadData(account: connectionAccount(for: connectionID))
    }

    static func deleteConnectionCredential(connectionID: UUID) throws {
        try delete(account: connectionAccount(for: connectionID))
    }

    static func saveImageGenerationAPIKey(_ value: String) throws {
        try save(Data(value.utf8), account: imageGenerationAccount)
    }

    static func loadImageGenerationAPIKey() throws -> String? {
        try load(account: imageGenerationAccount)
    }

    static func deleteImageGenerationAPIKey() throws {
        try delete(account: imageGenerationAccount)
    }

    private static func save(_ data: Data, account: String) throws {
        let update: [String: Any] = [kSecValueData as String: data]
        var lastStatus = errSecMissingEntitlement

        for baseQuery in candidateBaseQueries(account: account) {
            var query = baseQuery
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if updateStatus == errSecSuccess {
                return
            }
            if updateStatus == errSecMissingEntitlement {
                lastStatus = updateStatus
                continue
            }
            guard updateStatus == errSecItemNotFound else {
                throw KeychainStoreError.unexpectedStatus(updateStatus)
            }

            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecAttrSynchronizable as String] = false
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return
            }
            if addStatus == errSecMissingEntitlement {
                lastStatus = addStatus
                continue
            }
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }

        throw KeychainStoreError.unexpectedStatus(lastStatus)
    }

    static func loadAPIKey(providerID: String) throws -> String? {
        try load(account: providerAccount(for: providerID))
    }

    /// Called only by the one-time startup migration, before the user can edit
    /// the saved endpoint. Ordinary reads never fall back to an unscoped key.
    static func migrateLegacyAPIKey(to providerID: String) throws -> String? {
        if let current = try load(account: providerAccount(for: providerID)) {
            try delete(account: legacyAccount)
            return current
        }
        guard let legacy = try load(account: legacyAccount) else { return nil }

        // Complete the new write before deleting the legacy item. A failure
        // therefore leaves the only copy intact and recoverable.
        try saveAPIKey(legacy, providerID: providerID)
        try delete(account: legacyAccount)
        return legacy
    }

    private static func load(account: String) throws -> String? {
        guard let data = try loadData(account: account) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return value
    }

    private static func loadData(account: String) throws -> Data? {
        for baseQuery in candidateBaseQueries(account: account) {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound || status == errSecMissingEntitlement {
                continue
            }
            guard status == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(status)
            }
            guard let data = item as? Data else {
                throw KeychainStoreError.invalidData
            }
            return data
        }
        return nil
    }

    static func deleteAPIKey(providerID: String) throws {
        try delete(account: providerAccount(for: providerID))
    }

    private static func delete(account: String) throws {
        for query in candidateBaseQueries(account: account) {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess
                    || status == errSecItemNotFound
                    || status == errSecMissingEntitlement else {
                throw KeychainStoreError.unexpectedStatus(status)
            }
        }
    }

    private static func providerAccount(for providerID: String) -> String {
        let safeID = providerID
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return providerAccountPrefix + (safeID.isEmpty ? ProviderPreset.custom.rawValue : safeID)
    }

    private static func connectionAccount(for connectionID: UUID) -> String {
        connectionCredentialPrefix + connectionID.uuidString.lowercased()
    }

    private static func candidateBaseQueries(account: String) -> [[String: Any]] {
        let standardQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if os(macOS)
        var dataProtectionQuery = standardQuery
        dataProtectionQuery[kSecUseDataProtectionKeychain as String] = true
        return [dataProtectionQuery, standardQuery]
        #else
        return [standardQuery]
        #endif
    }
}
