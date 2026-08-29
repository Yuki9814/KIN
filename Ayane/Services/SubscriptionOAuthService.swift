import Foundation

struct SubscriptionDeviceAuthorization: Sendable, Equatable {
    let kind: AIConnectionProfile.Kind
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let verificationURLComplete: URL?
    let pollingInterval: TimeInterval
    let expiresAt: Date
}

struct SubscriptionOAuthCredential: Codable, Sendable, Equatable {
    let kind: AIConnectionProfile.Kind
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var accountID: String?
    var userID: String?
}

struct SubscriptionAuthorization: Sendable, Equatable {
    let kind: AIConnectionProfile.Kind
    let accessToken: String
    let accountID: String?
    let userID: String?
}

enum SubscriptionOAuthError: LocalizedError, Equatable {
    case unsupportedProvider
    case invalidResponse
    case requestFailed(Int, String)
    case authorizationDenied
    case authorizationExpired
    case missingRefreshToken
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "这个连接不支持订阅登录。"
        case .invalidResponse:
            return "登录服务返回了无法识别的数据。"
        case .requestFailed(let status, let detail):
            return detail.isEmpty
                ? "登录请求失败（HTTP \(status)）。"
                : "登录请求失败（HTTP \(status)）：\(detail)"
        case .authorizationDenied:
            return "登录授权已被拒绝。"
        case .authorizationExpired:
            return "登录码已过期，请重新开始。"
        case .missingRefreshToken:
            return "登录结果缺少刷新令牌，请重新登录。"
        case .missingCredential:
            return "本机钥匙串中没有这个订阅连接，请重新登录。"
        }
    }
}

struct SubscriptionOAuthService: Sendable {
    private static let openAIClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let openAIIssuer = URL(string: "https://auth.openai.com")!
    private static let xAIClientID = "b1a00492-073a-47ea-816f-4c329264a828"
    private static let xAITokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private static let xAIDeviceURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    private static let xAIScope =
        "openid profile email offline_access grok-cli:access api:access "
        + "conversations:read conversations:write workspaces:read workspaces:write"
    private static let deviceGrantType =
        "urn:ietf:params:oauth:grant-type:device_code"
    private static let maximumErrorBodyBytes = 16 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceAuthorization(
        kind: AIConnectionProfile.Kind
    ) async throws -> SubscriptionDeviceAuthorization {
        switch kind {
        case .chatGPTSubscription:
            return try await requestOpenAIDeviceAuthorization()
        case .grokSubscription:
            return try await requestXAIDeviceAuthorization()
        case .apiKey:
            throw SubscriptionOAuthError.unsupportedProvider
        }
    }

    func completeDeviceAuthorization(
        _ authorization: SubscriptionDeviceAuthorization
    ) async throws -> SubscriptionOAuthCredential {
        switch authorization.kind {
        case .chatGPTSubscription:
            return try await completeOpenAIDeviceAuthorization(authorization)
        case .grokSubscription:
            return try await completeXAIDeviceAuthorization(authorization)
        case .apiKey:
            throw SubscriptionOAuthError.unsupportedProvider
        }
    }

    func refresh(
        _ credential: SubscriptionOAuthCredential
    ) async throws -> SubscriptionOAuthCredential {
        guard !credential.refreshToken.isEmpty else {
            throw SubscriptionOAuthError.missingRefreshToken
        }
        let response: TokenResponse
        switch credential.kind {
        case .chatGPTSubscription:
            response = try await tokenRequest(
                url: Self.openAIIssuer.appending(path: "oauth/token"),
                values: [
                    "grant_type": "refresh_token",
                    "refresh_token": credential.refreshToken,
                    "client_id": Self.openAIClientID
                ]
            )
        case .grokSubscription:
            response = try await tokenRequest(
                url: Self.xAITokenURL,
                values: [
                    "grant_type": "refresh_token",
                    "refresh_token": credential.refreshToken,
                    "client_id": Self.xAIClientID
                ],
                usesXAIHeaders: true
            )
        case .apiKey:
            throw SubscriptionOAuthError.unsupportedProvider
        }
        return try makeCredential(
            kind: credential.kind,
            response: response,
            fallbackRefreshToken: credential.refreshToken,
            fallbackAccountID: credential.accountID,
            fallbackUserID: credential.userID
        )
    }

    private func requestOpenAIDeviceAuthorization() async throws
        -> SubscriptionDeviceAuthorization {
        let url = Self.openAIIssuer.appending(path: "api/accounts/deviceauth/usercode")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            OpenAIDeviceRequest(clientID: Self.openAIClientID)
        )
        let data = try await send(request)
        let response = try JSONDecoder().decode(OpenAIDeviceResponse.self, from: data)
        guard !response.deviceAuthID.isEmpty, !response.userCode.isEmpty,
              let verificationURL = URL(string: "https://auth.openai.com/codex/device") else {
            throw SubscriptionOAuthError.invalidResponse
        }
        let interval = max(response.intervalSeconds, 1)
        return SubscriptionDeviceAuthorization(
            kind: .chatGPTSubscription,
            deviceCode: response.deviceAuthID,
            userCode: response.userCode,
            verificationURL: verificationURL,
            verificationURLComplete: nil,
            pollingInterval: interval + 3,
            expiresAt: Date().addingTimeInterval(15 * 60)
        )
    }

    private func completeOpenAIDeviceAuthorization(
        _ authorization: SubscriptionDeviceAuthorization
    ) async throws -> SubscriptionOAuthCredential {
        let pollURL = Self.openAIIssuer.appending(path: "api/accounts/deviceauth/token")
        while Date() < authorization.expiresAt {
            try Task.checkCancellation()
            var request = URLRequest(url: pollURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.httpBody = try JSONEncoder().encode(
                OpenAIPollRequest(
                    deviceAuthID: authorization.deviceCode,
                    userCode: authorization.userCode
                )
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SubscriptionOAuthError.invalidResponse
            }
            if (200..<300).contains(http.statusCode) {
                let code = try JSONDecoder().decode(OpenAIPollResponse.self, from: data)
                let tokens = try await tokenRequest(
                    url: Self.openAIIssuer.appending(path: "oauth/token"),
                    values: [
                        "grant_type": "authorization_code",
                        "code": code.authorizationCode,
                        "redirect_uri": "https://auth.openai.com/deviceauth/callback",
                        "client_id": Self.openAIClientID,
                        "code_verifier": code.codeVerifier
                    ]
                )
                return try makeCredential(
                    kind: .chatGPTSubscription,
                    response: tokens
                )
            }
            if http.statusCode != 403 && http.statusCode != 404 {
                throw requestError(status: http.statusCode, data: data)
            }
            try await Task.sleep(for: .seconds(authorization.pollingInterval))
        }
        throw SubscriptionOAuthError.authorizationExpired
    }

    private func requestXAIDeviceAuthorization() async throws
        -> SubscriptionDeviceAuthorization {
        var request = URLRequest(url: Self.xAIDeviceURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue(Self.grokClientVersion, forHTTPHeaderField: "x-grok-client-version")
        request.setValue("ui", forHTTPHeaderField: "x-grok-client-surface")
        request.httpBody = formData([
            "client_id": Self.xAIClientID,
            "scope": Self.xAIScope,
            "referrer": "grok-build"
        ])
        let data = try await send(request)
        let response = try JSONDecoder().decode(XAIDeviceResponse.self, from: data)
        guard !response.deviceCode.isEmpty, !response.userCode.isEmpty,
              let verificationURL = URL(string: response.verificationURI) else {
            throw SubscriptionOAuthError.invalidResponse
        }
        return SubscriptionDeviceAuthorization(
            kind: .grokSubscription,
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURL: verificationURL,
            verificationURLComplete: response.verificationURIComplete.flatMap(URL.init(string:)),
            pollingInterval: max(response.interval ?? 5, 1),
            expiresAt: Date().addingTimeInterval(max(response.expiresIn ?? 300, 30))
        )
    }

    private func completeXAIDeviceAuthorization(
        _ authorization: SubscriptionDeviceAuthorization
    ) async throws -> SubscriptionOAuthCredential {
        var interval = authorization.pollingInterval
        while Date() < authorization.expiresAt {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(interval))
            guard Date() < authorization.expiresAt else {
                throw SubscriptionOAuthError.authorizationExpired
            }
            var request = URLRequest(url: Self.xAITokenURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 30
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue(Self.grokClientVersion, forHTTPHeaderField: "x-grok-client-version")
            request.setValue("ui", forHTTPHeaderField: "x-grok-client-surface")
            request.httpBody = formData([
                "grant_type": Self.deviceGrantType,
                "client_id": Self.xAIClientID,
                "device_code": authorization.deviceCode
            ])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SubscriptionOAuthError.invalidResponse
            }
            if (200..<300).contains(http.statusCode) {
                let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
                return try makeCredential(kind: .grokSubscription, response: tokens)
            }
            let error = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data)
            switch error?.error {
            case "authorization_pending":
                break
            case "slow_down":
                interval += 5
            case "access_denied", "authorization_denied":
                throw SubscriptionOAuthError.authorizationDenied
            case "expired_token":
                throw SubscriptionOAuthError.authorizationExpired
            default:
                throw requestError(status: http.statusCode, data: data)
            }
        }
        throw SubscriptionOAuthError.authorizationExpired
    }

    private func tokenRequest(
        url: URL,
        values: [String: String],
        usesXAIHeaders: Bool = false
    ) async throws -> TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        if usesXAIHeaders {
            request.setValue(Self.grokClientVersion, forHTTPHeaderField: "x-grok-client-version")
            request.setValue("ui", forHTTPHeaderField: "x-grok-client-surface")
        }
        request.httpBody = formData(values)
        let data = try await send(request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func makeCredential(
        kind: AIConnectionProfile.Kind,
        response: TokenResponse,
        fallbackRefreshToken: String? = nil,
        fallbackAccountID: String? = nil,
        fallbackUserID: String? = nil
    ) throws -> SubscriptionOAuthCredential {
        guard !response.accessToken.isEmpty else {
            throw SubscriptionOAuthError.invalidResponse
        }
        let refreshToken = response.refreshToken ?? fallbackRefreshToken ?? ""
        guard !refreshToken.isEmpty else {
            throw SubscriptionOAuthError.missingRefreshToken
        }
        let accountID = Self.accountID(
            idToken: response.idToken,
            accessToken: response.accessToken
        ) ?? fallbackAccountID
        let userID = (kind == .grokSubscription
            ? Self.xAIUserID(idToken: response.idToken, accessToken: response.accessToken)
            : Self.subject(idToken: response.idToken, accessToken: response.accessToken))
            ?? fallbackUserID
        return SubscriptionOAuthCredential(
            kind: kind,
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(max(response.expiresIn ?? 3_600, 60)),
            accountID: accountID,
            userID: userID
        )
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SubscriptionOAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw requestError(status: http.statusCode, data: data)
        }
        return data
    }

    private func requestError(status: Int, data: Data) -> SubscriptionOAuthError {
        let bounded = Data(data.prefix(Self.maximumErrorBodyBytes))
        let decoded = (try? JSONDecoder().decode(OAuthErrorResponse.self, from: bounded))
        let detail = decoded?.errorDescription ?? decoded?.error
            ?? String(data: bounded, encoding: .utf8) ?? ""
        return .requestFailed(status, detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func formData(_ values: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = values
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func accountID(idToken: String?, accessToken: String) -> String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            guard let claims = jwtClaims(token) else { continue }
            if let value = claims["chatgpt_account_id"] as? String, !value.isEmpty {
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
        }
        return nil
    }

    private static func subject(idToken: String?, accessToken: String) -> String? {
        for token in [idToken, accessToken].compactMap({ $0 }) {
            if let value = jwtClaims(token)?["sub"] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Team and organization grants route through their selected principal;
    /// personal grants continue to use the OIDC subject from the ID token.
    private static func xAIUserID(idToken: String?, accessToken: String) -> String? {
        if let claims = jwtClaims(accessToken),
           let principalType = (claims["principal_type"] ?? claims["principalType"]) as? String,
           principalType == "Team" || principalType == "Organization",
           let principalID = (claims["principal_id"] ?? claims["principalId"]) as? String,
           !principalID.isEmpty {
            return principalID
        }
        return subject(idToken: idToken, accessToken: accessToken)
    }

    /// xAI versions the OAuth/CLI wire protocol independently from this app.
    private static let grokClientVersion = "1.0.10"

    private static func jwtClaims(_ token: String) -> [String: Any]? {
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

actor SubscriptionTokenBroker {
    static let shared = SubscriptionTokenBroker()

    private var refreshTasks: [UUID: Task<SubscriptionOAuthCredential, Error>] = [:]

    func authorization(forOAuthReference reference: String) async throws
        -> SubscriptionAuthorization {
        guard let connectionID = AIConnectionStore.connectionID(fromOAuthReference: reference),
              let data = try KeychainStore.loadConnectionCredential(connectionID: connectionID),
              var credential = try? JSONDecoder().decode(
                  SubscriptionOAuthCredential.self,
                  from: data
              ) else {
            throw SubscriptionOAuthError.missingCredential
        }

        if credential.expiresAt.timeIntervalSinceNow <= 120 {
            if let existing = refreshTasks[connectionID] {
                do {
                    credential = try await existing.value
                } catch {
                    // A failed shared refresh must not poison every future
                    // request with the same already-completed failed Task.
                    refreshTasks[connectionID] = nil
                    throw error
                }
            } else {
                let staleCredential = credential
                let task = Task {
                    try await SubscriptionOAuthService().refresh(staleCredential)
                }
                refreshTasks[connectionID] = task
                do {
                    credential = try await task.value
                    let encoded = try JSONEncoder().encode(credential)
                    try KeychainStore.saveConnectionCredential(
                        encoded,
                        connectionID: connectionID
                    )
                    refreshTasks[connectionID] = nil
                } catch {
                    refreshTasks[connectionID] = nil
                    throw error
                }
            }
        }

        return SubscriptionAuthorization(
            kind: credential.kind,
            accessToken: credential.accessToken,
            accountID: credential.accountID,
            userID: credential.userID
        )
    }
}

private struct OpenAIDeviceRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

private struct OpenAIDeviceResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: StringOrNumber

    var intervalSeconds: TimeInterval {
        max(interval.doubleValue ?? 5, 1)
    }

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case interval
    }
}

private struct OpenAIPollRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct OpenAIPollResponse: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct XAIDeviceResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: TimeInterval?
    let interval: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let expiresIn: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private enum StringOrNumber: Decodable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .number(try container.decode(Double.self))
        }
    }

    var doubleValue: Double? {
        switch self {
        case .string(let value):
            return Double(value)
        case .number(let value):
            return value
        }
    }
}
