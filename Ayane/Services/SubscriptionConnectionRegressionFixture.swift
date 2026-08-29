#if DEBUG
import Darwin
import Foundation

/// Runs the same subscription request path as the connection screen while
/// keeping credentials inside the device Keychain. Enabled only by an explicit
/// debug launch environment variable and never included in Release builds.
@MainActor
enum SubscriptionConnectionRegressionFixture {
    private static let launchEnvironmentKey = "KIN_SUBSCRIPTION_CONNECTION_REGRESSION"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[launchEnvironmentKey] == "1"
    }

    static func run() async {
        emit("KIN_SUBSCRIPTION_CONNECTION_START")
        let profiles = AIConnectionStore.connections()
        let expectedKinds: [AIConnectionProfile.Kind] = [
            .chatGPTSubscription,
            .grokSubscription
        ]
        var failures = 0

        for kind in expectedKinds {
            var requestStage = "authorization"
            guard let profile = profiles
                .filter({ $0.kind == kind })
                .max(by: { $0.updatedAt < $1.updatedAt }) else {
                failures += 1
                emit("KIN_SUBSCRIPTION_CONNECTION_RESULT kind=\(kind.rawValue) status=missing")
                continue
            }

            do {
                guard let credentialData = try KeychainStore.loadConnectionCredential(
                    connectionID: profile.id
                ), let credential = try? JSONDecoder().decode(
                    SubscriptionOAuthCredential.self,
                    from: credentialData
                ) else {
                    failures += 1
                    emit("KIN_SUBSCRIPTION_CONNECTION_RESULT kind=\(kind.rawValue) status=missing-credential")
                    continue
                }
                let expirySeconds = Int(credential.expiresAt.timeIntervalSinceNow.rounded())
                let host = URL(string: profile.baseURL)?.host ?? "invalid"
                emit(
                    "KIN_SUBSCRIPTION_CONNECTION_AUTH kind=\(kind.rawValue) "
                    + "expires_in_seconds=\(expirySeconds) host=\(host)"
                )
                let reference = AIConnectionStore.oauthReference(for: profile.id)
                let authorization: SubscriptionAuthorization
                do {
                    authorization = try await SubscriptionTokenBroker.shared.authorization(
                        forOAuthReference: reference
                    )
                    emit("KIN_SUBSCRIPTION_CONNECTION_AUTH kind=\(kind.rawValue) status=pass")
                } catch {
                    failures += 1
                    emit(
                        "KIN_SUBSCRIPTION_CONNECTION_RESULT kind=\(kind.rawValue) "
                        + "status=fail stage=authorization category=\(safeCategory(for: error))"
                    )
                    continue
                }
                let client = OpenAICompatibleClient(
                    subscriptionAuthorizationResolver: { _ in authorization }
                )
                requestStage = "connection"
                let result = try await client.testConnection(
                    configuration: profile.configuration,
                    apiKey: reference
                )
                let latency = Int((result.latency * 1_000).rounded())

                // `testConnection` covers ChatGPT's Responses stream and
                // Grok's non-streaming JSON path. Exercise `streamChat` too,
                // because ordinary role messages use that API in AppModel.
                requestStage = "stream-chat"
                var chunkCount = 0
                var characterCount = 0
                for try await chunk in client.streamChat(
                    messages: [
                        APIChatMessage(role: "system", content: "你正在执行流式聊天可用性测试。"),
                        APIChatMessage(role: "user", content: "只回复：连接正常。")
                    ],
                    configuration: profile.configuration,
                    apiKey: reference
                ) {
                    let visible = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !visible.isEmpty else { continue }
                    chunkCount += 1
                    characterCount += visible.count
                }
                guard chunkCount > 0, characterCount > 0 else {
                    throw AIClientError.emptyResponse
                }
                emit(
                    "KIN_SUBSCRIPTION_CONNECTION_RESULT kind=\(kind.rawValue) "
                    + "status=pass latency_ms=\(latency)"
                )
                emit(
                    "KIN_SUBSCRIPTION_STREAM_RESULT kind=\(kind.rawValue) "
                    + "status=pass chunks=\(chunkCount) characters=\(characterCount)"
                )
            } catch {
                failures += 1
                emit(
                    "KIN_SUBSCRIPTION_CONNECTION_RESULT kind=\(kind.rawValue) "
                    + "status=fail stage=\(requestStage) category=\(safeCategory(for: error))"
                )
            }
        }

        if failures == 0 {
            finish("KIN_SUBSCRIPTION_CONNECTION_PASS", success: true)
        }
        finish("KIN_SUBSCRIPTION_CONNECTION_FAIL count=\(failures)", success: false)
    }

    private static func safeCategory(for error: Error) -> String {
        if let clientError = error as? AIClientError {
            switch clientError {
            case .invalidBaseURL: return "invalid-base-url"
            case .missingModel: return "missing-model"
            case .invalidResponse: return "invalid-response"
            case .httpStatus(let status, _): return "http-\(status)"
            case .emptyResponse: return "empty-response"
            case .malformedStream: return "malformed-stream"
            case .streamFailed: return "stream-failed"
            case .missingEmbeddingModel: return "missing-embedding-model"
            case .subscriptionEmbeddingUnsupported: return "subscription-embedding-unsupported"
            }
        }
        if let oauthError = error as? SubscriptionOAuthError {
            switch oauthError {
            case .unsupportedProvider: return "oauth-unsupported-provider"
            case .invalidResponse: return "oauth-invalid-response"
            case .requestFailed(let status, let detail):
                return "oauth-http-\(status)-\(oauthFailureTag(detail))"
            case .authorizationDenied: return "oauth-authorization-denied"
            case .authorizationExpired: return "oauth-authorization-expired"
            case .missingRefreshToken: return "oauth-missing-refresh-token"
            case .missingCredential: return "oauth-missing-credential"
            }
        }
        if let urlError = error as? URLError {
            return "url-\(urlError.code.rawValue)-\(urlError.code)"
        }
        return String(reflecting: type(of: error))
            .replacingOccurrences(of: " ", with: "-")
    }

    private static func oauthFailureTag(_ detail: String) -> String {
        let value = detail.lowercased()
        let knownTags = [
            "refresh_token_expired",
            "refresh_token_reused",
            "refresh_token_invalidated",
            "invalid_grant",
            "invalid_client",
            "unsupported_grant_type",
            "access_denied",
            "cloudflare",
            "forbidden"
        ]
        return knownTags.first(where: value.contains) ?? "other"
    }

    private static func emit(_ message: String) {
        fputs(message + "\n", stdout)
        fflush(stdout)
    }

    private static func finish(_ message: String, success: Bool) -> Never {
        emit(message)
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
#endif
