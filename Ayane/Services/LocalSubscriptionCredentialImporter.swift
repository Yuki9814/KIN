import Foundation

struct LocalSubscriptionImportReceipt: Codable, Equatable, Sendable {
    let importedProviderNames: [String]
    let failedProviderNames: [String]
    let cleanupFailedProviderNames: [String]
    let importedAt: Date
}

enum LocalSubscriptionCredentialImportError: LocalizedError, Equatable {
    case invalidFile
    case fileTooLarge
    case missingAccessToken
    case missingRefreshToken

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "登录态文件格式无效。"
        case .fileTooLarge:
            return "登录态文件异常过大。"
        case .missingAccessToken:
            return "登录态缺少访问令牌。"
        case .missingRefreshToken:
            return "登录态缺少刷新令牌。"
        }
    }
}

/// Imports an explicitly provisioned local CLI login into KIN's own Keychain.
/// The plaintext source is accepted only from a fixed app-container directory,
/// is never logged or persisted in UserDefaults, and is removed after one
/// import attempt whether the credential succeeds or fails.
enum LocalSubscriptionCredentialImporter {
    static let openAIFileName = "kin-openai-oauth-import.json"
    static let grokFileName = "kin-grok-oauth-import.json"

    static let openAIConnectionID = UUID(
        uuidString: "DE51B849-6153-40A7-B1C2-EE58C1370519"
    )!
    static let grokConnectionID = UUID(
        uuidString: "34AC49B2-367F-4612-A46C-8564D2D4AE57"
    )!

    private static let receiptKey = "provider.localSubscriptionImportReceipt.v1"
    private static let maximumSourceBytes = 4 * 1_024 * 1_024

    private struct Source {
        let fileName: String
        let providerName: String
        let kind: AIConnectionProfile.Kind
        let connectionID: UUID
        let displayName: String
        let providerID: String
        let baseURL: String
        let model: String
    }

    private static let sources = [
        Source(
            fileName: openAIFileName,
            providerName: "OpenAI",
            kind: .chatGPTSubscription,
            connectionID: openAIConnectionID,
            displayName: "ChatGPT（本机登录态）",
            providerID: ProviderPreset.openAI.rawValue,
            baseURL: "https://chatgpt.com/backend-api/codex",
            model: "gpt-5.5"
        ),
        Source(
            fileName: grokFileName,
            providerName: "Grok",
            kind: .grokSubscription,
            connectionID: grokConnectionID,
            displayName: "Grok（本机登录态）",
            providerID: ProviderPreset.xAI.rawValue,
            baseURL: "https://cli-chat-proxy.grok.com/v1",
            model: "grok-build"
        )
    ]

    static func importPendingIfAvailable(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> String? {
        #if os(iOS)
        guard let receipt = importPending(
            in: fileManager.temporaryDirectory,
            defaults: defaults,
            fileManager: fileManager
        ) else {
            return nil
        }
        if receipt.failedProviderNames.isEmpty,
           receipt.cleanupFailedProviderNames.isEmpty {
            return nil
        }
        var details: [String] = []
        if !receipt.failedProviderNames.isEmpty {
            details.append("导入失败：" + receipt.failedProviderNames.joined(separator: "、"))
        }
        if !receipt.cleanupFailedProviderNames.isEmpty {
            details.append("中转文件清理失败：" + receipt.cleanupFailedProviderNames.joined(separator: "、"))
        }
        return "本机订阅登录态处理未完全成功（\(details.joined(separator: "；"))）。"
        #else
        return nil
        #endif
    }

    @discardableResult
    static func importPending(
        in directory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> LocalSubscriptionImportReceipt? {
        var imported: [String] = []
        var failed: [String] = []
        var cleanupFailed: [String] = []
        var foundSource = false

        for source in sources {
            let url = directory.appending(path: source.fileName)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            foundSource = true

            #if os(iOS)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            #endif

            do {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw LocalSubscriptionCredentialImportError.invalidFile
                }
                guard (values.fileSize ?? 0) <= maximumSourceBytes else {
                    throw LocalSubscriptionCredentialImportError.fileTooLarge
                }

                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let credential = try credential(
                    from: data,
                    kind: source.kind,
                    now: now
                )
                try save(credential, source: source, defaults: defaults, now: now)
                imported.append(source.providerName)
            } catch {
                failed.append(source.providerName)
            }

            do {
                try fileManager.removeItem(at: url)
            } catch {
                cleanupFailed.append(source.providerName)
            }
        }

        guard foundSource else { return nil }

        let receipt = LocalSubscriptionImportReceipt(
            importedProviderNames: imported,
            failedProviderNames: failed,
            cleanupFailedProviderNames: cleanupFailed,
            importedAt: now
        )
        if let encoded = try? JSONEncoder().encode(receipt) {
            defaults.set(encoded, forKey: receiptKey)
        }
        return receipt
    }

    static func lastReceipt(
        defaults: UserDefaults = .standard
    ) -> LocalSubscriptionImportReceipt? {
        guard let data = defaults.data(forKey: receiptKey) else { return nil }
        return try? JSONDecoder().decode(LocalSubscriptionImportReceipt.self, from: data)
    }

    static func credential(
        from data: Data,
        kind: AIConnectionProfile.Kind,
        now: Date = Date()
    ) throws -> SubscriptionOAuthCredential {
        guard data.count <= maximumSourceBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw LocalSubscriptionCredentialImportError.invalidFile
        }
        let candidates = candidateDictionaries(in: root)
        let accessKeys: [String]
        switch kind {
        case .chatGPTSubscription:
            accessKeys = ["access_token", "accessToken", "access"]
        case .grokSubscription:
            accessKeys = ["key", "access_token", "accessToken", "access"]
        case .apiKey:
            throw SubscriptionOAuthError.unsupportedProvider
        }

        guard let accessToken = firstString(in: candidates, keys: accessKeys) else {
            throw LocalSubscriptionCredentialImportError.missingAccessToken
        }
        guard let refreshToken = firstString(
            in: candidates,
            keys: ["refresh_token", "refreshToken", "refresh"]
        ) else {
            throw LocalSubscriptionCredentialImportError.missingRefreshToken
        }
        let idToken = firstString(
            in: candidates,
            keys: ["id_token", "idToken"]
        )
        let explicitAccountID = firstString(
            in: candidates,
            keys: ["account_id", "accountID", "chatgpt_account_id"]
        )
        let explicitUserID = firstString(
            in: candidates,
            keys: ["user_id", "userID", "subject", "sub"]
        )
        let expiresAt = firstDate(
            in: candidates,
            keys: ["expires_at", "expiresAt", "expires", "expiration"]
        ) ?? jwtExpiration(idToken) ?? jwtExpiration(accessToken)
            ?? now.addingTimeInterval(-1)

        return SubscriptionOAuthCredential(
            kind: kind,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            accountID: explicitAccountID
                ?? accountID(from: idToken)
                ?? accountID(from: accessToken),
            userID: explicitUserID
                ?? subject(from: idToken)
                ?? subject(from: accessToken)
        )
    }

    private static func save(
        _ credential: SubscriptionOAuthCredential,
        source: Source,
        defaults: UserDefaults,
        now: Date
    ) throws {
        let existing = AIConnectionStore.connection(
            id: source.connectionID,
            defaults: defaults
        )
        let profile = AIConnectionProfile(
            id: source.connectionID,
            displayName: source.displayName,
            kind: source.kind,
            providerID: source.providerID,
            baseURL: source.baseURL,
            model: source.model,
            embeddingModel: "",
            temperature: 0.8,
            streamsResponses: true,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        let encoded = try JSONEncoder().encode(credential)
        try KeychainStore.saveConnectionCredential(
            encoded,
            connectionID: source.connectionID
        )
        do {
            try AIConnectionStore.save(profile, defaults: defaults)
        } catch {
            try? KeychainStore.deleteConnectionCredential(
                connectionID: source.connectionID
            )
            throw error
        }
    }

    private static func candidateDictionaries(
        in root: [String: Any]
    ) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func visit(_ dictionary: [String: Any], depth: Int) {
            guard depth <= 4 else { return }
            for value in dictionary.values {
                if let nested = value as? [String: Any] {
                    visit(nested, depth: depth + 1)
                }
            }
            result.append(dictionary)
        }
        visit(root, depth: 0)
        return result
    }

    private static func firstString(
        in dictionaries: [[String: Any]],
        keys: [String]
    ) -> String? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })
        for dictionary in dictionaries {
            for (key, value) in dictionary where normalizedKeys.contains(key.lowercased()) {
                if let string = value as? String {
                    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    private static func firstDate(
        in dictionaries: [[String: Any]],
        keys: [String]
    ) -> Date? {
        let normalizedKeys = Set(keys.map { $0.lowercased() })
        for dictionary in dictionaries {
            for (key, value) in dictionary where normalizedKeys.contains(key.lowercased()) {
                if let date = date(from: value) { return date }
            }
        }
        return nil
    }

    private static func date(from value: Any) -> Date? {
        if let number = value as? NSNumber {
            return date(fromEpoch: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        if let number = Double(string) {
            return date(fromEpoch: number)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func date(fromEpoch rawValue: Double) -> Date? {
        guard rawValue.isFinite, rawValue > 0 else { return nil }
        let seconds = rawValue > 100_000_000_000 ? rawValue / 1_000 : rawValue
        return Date(timeIntervalSince1970: seconds)
    }

    private static func jwtExpiration(_ token: String?) -> Date? {
        guard let token,
              let value = jwtClaims(token)?["exp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: value.doubleValue)
    }

    private static func subject(from token: String?) -> String? {
        jwtClaims(token)?["sub"] as? String
    }

    private static func accountID(from token: String?) -> String? {
        guard let claims = jwtClaims(token) else { return nil }
        if let value = claims["chatgpt_account_id"] as? String, !value.isEmpty {
            return value
        }
        if let value = claims["https://api.openai.com/auth.chatgpt_account_id"] as? String,
           !value.isEmpty {
            return value
        }
        if let auth = claims["https://api.openai.com/auth"] as? [String: Any],
           let value = auth["chatgpt_account_id"] as? String,
           !value.isEmpty {
            return value
        }
        if let organizations = claims["organizations"] as? [[String: Any]],
           let value = organizations.first?["id"] as? String,
           !value.isEmpty {
            return value
        }
        return nil
    }

    private static func jwtClaims(_ token: String?) -> [String: Any]? {
        guard let token else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var value = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value.append("=") }
        guard let data = Data(base64Encoded: value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any] else {
            return nil
        }
        return claims
    }
}
