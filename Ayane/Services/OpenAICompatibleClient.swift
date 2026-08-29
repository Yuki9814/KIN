import Foundation

enum AIClientError: LocalizedError, Equatable {
    case invalidBaseURL
    case missingModel
    case invalidResponse
    case httpStatus(Int, String)
    case emptyResponse
    case malformedStream
    case streamFailed(String)
    case missingEmbeddingModel
    case subscriptionEmbeddingUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "API 地址无效，请填写完整的 http 或 https 地址。"
        case .missingModel:
            return "请先填写聊天模型名称。"
        case .invalidResponse:
            return "API 返回了无法识别的响应。"
        case .httpStatus(let code, let message):
            return message.isEmpty ? "API 请求失败（HTTP \(code)）。" : "API 请求失败（HTTP \(code)）：\(message)"
        case .emptyResponse:
            return "模型没有返回可显示的内容。"
        case .malformedStream:
            return "流式响应格式无效。"
        case .streamFailed(let message):
            return message.isEmpty ? "模型流式响应失败。" : "模型流式响应失败：\(message)"
        case .missingEmbeddingModel:
            return "未配置向量模型。"
        case .subscriptionEmbeddingUnsupported:
            return "订阅登录连接不提供向量接口；长期记忆仍可使用本地关键词检索。"
        }
    }
}

enum SSEChunk: Equatable {
    case text(String)
    case textAndDone(String)
    case done
    case ignored
}

private struct RequestAuthorization: Sendable {
    let token: String
    let subscriptionKind: AIConnectionProfile.Kind?
    let accountID: String?
    let userID: String?
}

protocol AIClientProtocol {
    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error>

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float]

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult
}

extension AIClientProtocol {
    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        try await complete(
            messages: messages,
            configuration: configuration,
            apiKey: apiKey,
            temperature: nil,
            maxTokens: nil
        )
    }
}

struct OpenAICompatibleClient: AIClientProtocol {
    private let session: URLSession
    private let subscriptionAuthorizationResolver:
        (String) async throws -> SubscriptionAuthorization?
    private static let codexInstallationID: String = {
        let key = "provider.codexInstallationID"
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }()

    init(
        session: URLSession = .shared,
        subscriptionAuthorizationResolver: @escaping (String) async throws
            -> SubscriptionAuthorization? = OpenAICompatibleClient.resolveSubscriptionAuthorization
    ) {
        self.session = session
        self.subscriptionAuthorizationResolver = subscriptionAuthorizationResolver
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let authorization = try await resolvedAuthorization(apiKey: apiKey)
                    let request = try makeChatRequest(
                        messages: messages,
                        configuration: configuration,
                        authorization: authorization,
                        stream: true,
                        temperature: configuration.temperature,
                        maxTokens: nil
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        let body = try await Self.readErrorBody(from: bytes)
                        try Self.validate(response: response, body: body)
                    } else {
                        try Self.validate(response: response, body: Data())
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let chunk = authorization.subscriptionKind == .chatGPTSubscription
                            ? try Self.parseResponsesSSELine(line)
                            : try Self.parseSSELine(line)
                        switch chunk {
                        case .text(let text):
                            continuation.yield(text)
                        case .textAndDone(let text):
                            continuation.yield(text)
                            continuation.finish()
                            return
                        case .done:
                            continuation.finish()
                            return
                        case .ignored:
                            continue
                        }
                    }
                    continuation.finish(throwing: AIClientError.malformedStream)
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        let authorization = try await resolvedAuthorization(apiKey: apiKey)
        if authorization.subscriptionKind == .chatGPTSubscription {
            let request = try makeChatRequest(
                messages: messages,
                configuration: configuration,
                authorization: authorization,
                stream: true,
                temperature: temperature ?? configuration.temperature,
                maxTokens: maxTokens
            )
            return try await collectStreamingText(
                from: request,
                usesResponsesEvents: true
            )
        }
        let request = try makeChatRequest(
            messages: messages,
            configuration: configuration,
            authorization: authorization,
            stream: false,
            temperature: temperature ?? configuration.temperature,
            maxTokens: maxTokens
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, body: data)
        let content = try JSONDecoder().decode(
            ChatCompletionResponse.self,
            from: data
        ).choices.first?.message.content
        guard let content = content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AIClientError.emptyResponse
        }
        return content
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        let model = configuration.embeddingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AIClientError.missingEmbeddingModel
        }
        let authorization = try await resolvedAuthorization(apiKey: apiKey)
        guard authorization.subscriptionKind == nil else {
            throw AIClientError.subscriptionEmbeddingUnsupported
        }
        let endpoint = try Self.endpoint(baseURL: configuration.baseURL, resource: "embeddings")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        Self.apply(authorization, to: &request)
        request.httpBody = try JSONEncoder().encode(EmbeddingRequest(model: model, input: text))
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, body: data)
        let envelope = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        guard let vector = envelope.data.first?.embedding, !vector.isEmpty else {
            throw AIClientError.invalidResponse
        }
        return vector
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        let startedAt = Date()
        let reply = try await complete(
            messages: [
                APIChatMessage(role: "system", content: "你正在执行连接测试。"),
                APIChatMessage(role: "user", content: "只回复 OK。")
            ],
            configuration: configuration,
            apiKey: apiKey,
            temperature: 0,
            maxTokens: 16
        )
        return ConnectionTestResult(latency: Date().timeIntervalSince(startedAt), reply: reply)
    }

    static func endpoint(baseURL: String, resource: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            throw AIClientError.invalidBaseURL
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        let knownSuffixes = ["/chat/completions", "/embeddings"]
        if let suffix = knownSuffixes.first(where: { path.hasSuffix($0) }) {
            path.removeLast(suffix.count)
        }
        if path.isEmpty {
            // DeepSeek's canonical public Chat Completions contract uses the
            // bare API root (`/chat/completions`). Other generic bare hosts
            // keep the conventional OpenAI-compatible `/v1` default.
            path = components.host?.lowercased() == "api.deepseek.com" ? "" : "/v1"
        }
        // A non-empty path is an explicit OpenAI-compatible API root. Preserve
        // roots such as `/v1beta/openai` and private gateway prefixes instead
        // of silently rewriting them to an invalid `.../v1` route. Only a bare
        // host receives the conventional `/v1` default above.
        components.path = path + "/" + resource
        guard let url = components.url else {
            throw AIClientError.invalidBaseURL
        }
        return url
    }

    static func parseSSELine(_ line: String) throws -> SSEChunk {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else {
            return .ignored
        }
        guard trimmed.hasPrefix("data:") else {
            return .ignored
        }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8) else {
            throw AIClientError.malformedStream
        }
        let envelope = try JSONDecoder().decode(ChatStreamResponse.self, from: data)
        guard let choice = envelope.choices.first else {
            return .ignored
        }
        let hasFinishReason = choice.finishReason?.isEmpty == false
        if let delta = choice.delta?.content, !delta.isEmpty {
            return hasFinishReason ? .textAndDone(delta) : .text(delta)
        }
        return hasFinishReason ? .done : .ignored
    }

    static func parseResponsesSSELine(_ line: String) throws -> SSEChunk {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix(":") else {
            return .ignored
        }
        guard trimmed.hasPrefix("data:") else {
            return .ignored
        }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return .done
        }
        guard let data = payload.data(using: .utf8) else {
            throw AIClientError.malformedStream
        }
        let event = try JSONDecoder().decode(ResponsesStreamEvent.self, from: data)
        switch event.type {
        case "response.output_text.delta":
            guard let delta = event.delta, !delta.isEmpty else { return .ignored }
            return .text(delta)
        case "response.completed":
            return .done
        case "response.failed", "response.incomplete":
            throw AIClientError.streamFailed(event.failureMessage ?? "上游未提供失败原因")
        default:
            return .ignored
        }
    }

    private func collectStreamingText(
        from request: URLRequest,
        usesResponsesEvents: Bool
    ) async throws -> String {
        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            let body = try await Self.readErrorBody(from: bytes)
            try Self.validate(response: response, body: body)
        } else {
            try Self.validate(response: response, body: Data())
        }

        var accumulated = ""
        var completed = false
        responseLines: for try await line in bytes.lines {
            try Task.checkCancellation()
            let chunk = usesResponsesEvents
                ? try Self.parseResponsesSSELine(line)
                : try Self.parseSSELine(line)
            switch chunk {
            case .text(let text):
                accumulated += text
            case .textAndDone(let text):
                accumulated += text
                completed = true
                break responseLines
            case .done:
                completed = true
                break responseLines
            case .ignored:
                continue
            }
        }
        guard completed else { throw AIClientError.malformedStream }
        let content = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AIClientError.emptyResponse }
        return content
    }

    private static let maxErrorBodyBytes = 64 * 1024

    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var body = Data()
        body.reserveCapacity(maxErrorBodyBytes)
        for try await byte in bytes {
            body.append(byte)
            if body.count >= maxErrorBodyBytes {
                break
            }
        }
        return body
    }

    private func makeChatRequest(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        authorization: RequestAuthorization,
        stream: Bool,
        temperature: Double,
        maxTokens: Int?
    ) throws -> URLRequest {
        let configuredModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = authorization.subscriptionKind == .grokSubscription
            ? "grok-build"
            : configuredModel
        guard !model.isEmpty else {
            throw AIClientError.missingModel
        }
        if authorization.subscriptionKind == .chatGPTSubscription {
            return try makeChatGPTResponsesRequest(
                messages: messages,
                model: model,
                authorization: authorization,
                stream: stream,
                maxTokens: maxTokens
            )
        }
        let endpoint: URL
        if authorization.subscriptionKind == .grokSubscription {
            endpoint = URL(
                string: "https://cli-chat-proxy.grok.com/v1/chat/completions"
            )!
        } else {
            endpoint = try Self.endpoint(
                baseURL: configuration.baseURL,
                resource: "chat/completions"
            )
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = stream ? 300 : 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        Self.apply(authorization, to: &request)
        if authorization.subscriptionKind == .grokSubscription {
            request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
            request.setValue(Self.grokClientVersion, forHTTPHeaderField: "x-grok-client-version")
            request.setValue("kin-ios", forHTTPHeaderField: "x-grok-client-identifier")
            request.setValue("interactive", forHTTPHeaderField: "x-grok-client-mode")
            request.setValue(model, forHTTPHeaderField: "x-grok-model-override")
        }
        let isOfficialOpenAI = Self.isOfficialOpenAI(configuration)
        let usesReasoningParameters = Self.usesOpenAIReasoningParameters(configuration)
        let requestMessages = usesReasoningParameters
            ? messages.map { message in
                message.role == "system"
                    ? APIChatMessage(role: "developer", content: message.content)
                    : message
            }
            : messages
        let boundedTemperature = min(max(temperature, 0), 2)
        let completionLimit = usesReasoningParameters
            ? maxTokens.map { max($0, 256) }
            : maxTokens
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: model,
            messages: requestMessages,
            temperature: usesReasoningParameters ? nil : boundedTemperature,
            stream: stream,
            maxTokens: isOfficialOpenAI ? nil : maxTokens,
            maxCompletionTokens: isOfficialOpenAI ? completionLimit : nil,
            thinking: Self.deepSeekThinkingConfiguration(for: configuration)
        ))
        return request
    }

    private func makeChatGPTResponsesRequest(
        messages: [APIChatMessage],
        model: String,
        authorization: RequestAuthorization,
        stream: Bool,
        maxTokens: Int?
    ) throws -> URLRequest {
        let endpoint = URL(
            string: "https://chatgpt.com/backend-api/codex/responses"
        )!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = stream ? 300 : 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            stream ? "text/event-stream" : "application/json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("kin-ios", forHTTPHeaderField: "originator")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "session-id")
        request.setValue(requestID, forHTTPHeaderField: "thread-id")
        request.setValue(requestID, forHTTPHeaderField: "x-codex-window-id")
        request.setValue(requestID, forHTTPHeaderField: "x-client-request-id")
        request.setValue(
            Self.codexInstallationID,
            forHTTPHeaderField: "x-codex-installation-id"
        )
        request.setValue("model=\(model)", forHTTPHeaderField: "x-codex-routing-hint")
        request.setValue("KIN/0.1 (iOS)", forHTTPHeaderField: "User-Agent")
        Self.apply(authorization, to: &request)

        let instructionParts = messages
            .filter { $0.role == "system" || $0.role == "developer" }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let instructions = instructionParts.isEmpty
            ? "You are a helpful assistant. Follow the user's instructions."
            : instructionParts.joined(separator: "\n\n")
        let input = messages
            .filter { $0.role != "system" && $0.role != "developer" }
            .map {
                ResponsesInputMessage(
                    type: "message",
                    role: $0.role == "assistant" ? "assistant" : "user",
                    content: [
                        ResponsesInputContent(
                            type: $0.role == "assistant" ? "output_text" : "input_text",
                            text: $0.content
                        )
                    ]
                )
            }
        request.httpBody = try JSONEncoder().encode(
            ResponsesRequest(
                model: model,
                instructions: instructions,
                input: input,
                stream: stream,
                store: false,
                reasoning: ResponsesReasoning(effort: "medium"),
                include: ["reasoning.encrypted_content"],
                promptCacheKey: requestID,
                clientMetadata: [
                    "x-codex-installation-id": Self.codexInstallationID,
                    "session_id": requestID,
                    "thread_id": requestID,
                    "x-codex-window-id": requestID
                ]
            )
        )
        return request
    }

    private func resolvedAuthorization(apiKey: String) async throws -> RequestAuthorization {
        guard let authorization = try await subscriptionAuthorizationResolver(apiKey) else {
            return RequestAuthorization(
                token: apiKey,
                subscriptionKind: nil,
                accountID: nil,
                userID: nil
            )
        }
        return RequestAuthorization(
            token: authorization.accessToken,
            subscriptionKind: authorization.kind,
            accountID: authorization.accountID,
            userID: authorization.userID
        )
    }

    private static func resolveSubscriptionAuthorization(
        _ reference: String
    ) async throws -> SubscriptionAuthorization? {
        guard AIConnectionStore.connectionID(fromOAuthReference: reference) != nil else {
            return nil
        }
        return try await SubscriptionTokenBroker.shared.authorization(
            forOAuthReference: reference
        )
    }

    /// The CLI proxy versions its wire contract independently from KIN's app
    /// version and rejects obsolete clients. Keep this pinned to the reviewed
    /// upstream `xai-grok-version` release.
    private static let grokClientVersion = "1.0.10"

    private static func apply(
        _ authorization: RequestAuthorization,
        to request: inout URLRequest
    ) {
        if !authorization.token.isEmpty {
            request.setValue(
                "Bearer \(authorization.token)",
                forHTTPHeaderField: "Authorization"
            )
        }
        if authorization.subscriptionKind == .chatGPTSubscription,
           let accountID = authorization.accountID,
           !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        if authorization.subscriptionKind == .grokSubscription,
           let userID = authorization.userID,
           !userID.isEmpty {
            request.setValue(userID, forHTTPHeaderField: "x-userid")
        }
    }

    /// OpenAI's current Chat Completions contract replaces `max_tokens` with
    /// `max_completion_tokens`. Its reasoning families also reject sampling
    /// temperature and use `developer` in place of the former `system` role.
    /// Keep this adaptation on OpenAI's own host so compatible third-party
    /// providers continue receiving their established request shape.
    private static func usesOpenAIReasoningParameters(
        _ configuration: ProviderConfiguration
    ) -> Bool {
        guard isOfficialOpenAI(configuration) else { return false }
        let model = configuration.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return model.hasPrefix("o1")
            || model.hasPrefix("o3")
            || model.hasPrefix("o4")
            || model.hasPrefix("gpt-5")
    }

    private static func isOfficialOpenAI(_ configuration: ProviderConfiguration) -> Bool {
        URLComponents(
            string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host?.lowercased() == "api.openai.com"
    }

    /// DeepSeek V4 enables thinking by default. For this conversational app,
    /// the explicitly selected Flash model should return the visible reply
    /// directly instead of spending a short connection test's token budget on
    /// hidden reasoning. Keep the extension scoped to DeepSeek's own endpoint
    /// so other OpenAI-compatible providers never receive an unknown field.
    private static func deepSeekThinkingConfiguration(
        for configuration: ProviderConfiguration
    ) -> DeepSeekThinkingConfiguration? {
        let host = URLComponents(
            string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )?.host?.lowercased()
        let model = configuration.model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard host == "api.deepseek.com", model.hasPrefix("deepseek-v4-") else {
            return nil
        }
        return DeepSeekThinkingConfiguration(type: "disabled")
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var message = ""
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: body) {
                message = envelope.error.message
            } else if let raw = String(data: body, encoding: .utf8) {
                message = String(raw.prefix(500))
            }
            throw AIClientError.httpStatus(http.statusCode, message)
        }
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [APIChatMessage]
    let temperature: Double?
    let stream: Bool
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let thinking: DeepSeekThinkingConfiguration?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, thinking
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct DeepSeekThinkingConfiguration: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct ResponsesRequest: Encodable {
    let model: String
    let instructions: String
    let input: [ResponsesInputMessage]
    let stream: Bool
    let store: Bool
    let reasoning: ResponsesReasoning
    let include: [String]
    let promptCacheKey: String
    let clientMetadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case model, instructions, input, stream, store, reasoning, include
        case promptCacheKey = "prompt_cache_key"
        case clientMetadata = "client_metadata"
    }
}

private struct ResponsesReasoning: Encodable {
    let effort: String
}

private struct ResponsesInputMessage: Encodable {
    let type: String
    let role: String
    let content: [ResponsesInputContent]
}

private struct ResponsesInputContent: Encodable {
    let type: String
    let text: String
}

private struct ResponsesStreamEvent: Decodable {
    struct Failure: Decodable {
        let message: String?
        let code: String?
    }

    struct IncompleteDetails: Decodable {
        let reason: String?
    }

    struct Response: Decodable {
        let error: Failure?
        let incompleteDetails: IncompleteDetails?

        enum CodingKeys: String, CodingKey {
            case error
            case incompleteDetails = "incomplete_details"
        }
    }

    let type: String
    let delta: String?
    let error: Failure?
    let response: Response?

    var failureMessage: String? {
        error?.message
            ?? response?.error?.message
            ?? response?.incompleteDetails?.reason
            ?? error?.code
            ?? response?.error?.code
    }
}

private struct ChatStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }
    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}

private struct EmbeddingRequest: Encodable {
    let model: String
    let input: String
}

private struct EmbeddingResponse: Decodable {
    struct Item: Decodable {
        let embedding: [Float]
    }
    let data: [Item]
}
