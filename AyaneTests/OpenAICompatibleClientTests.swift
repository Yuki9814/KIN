import Foundation
import XCTest
@testable import Ayane

final class OpenAICompatibleClientTests: XCTestCase {
    func testEndpointAddsV1ForBareHost() throws {
        let url = try OpenAICompatibleClient.endpoint(
            baseURL: "https://example.com",
            resource: "chat/completions"
        )
        XCTAssertEqual(url.absoluteString, "https://example.com/v1/chat/completions")
    }

    func testDeepSeekBareHostUsesCanonicalChatPath() throws {
        let url = try OpenAICompatibleClient.endpoint(
            baseURL: "https://api.deepseek.com",
            resource: "chat/completions"
        )
        XCTAssertEqual(url.absoluteString, "https://api.deepseek.com/chat/completions")
    }

    func testEndpointAcceptsExistingFullChatPath() throws {
        let url = try OpenAICompatibleClient.endpoint(
            baseURL: "https://example.com/custom/v1/chat/completions",
            resource: "embeddings"
        )
        XCTAssertEqual(url.absoluteString, "https://example.com/custom/v1/embeddings")
    }

    func testEndpointPreservesExplicitCompatibleGatewayRoot() throws {
        let url = try OpenAICompatibleClient.endpoint(
            baseURL: "https://example.com/v1beta/openai/",
            resource: "chat/completions"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://example.com/v1beta/openai/chat/completions"
        )
    }

    func testEndpointPreservesArbitraryPrivateGatewayPrefix() throws {
        let url = try OpenAICompatibleClient.endpoint(
            baseURL: "https://example.com/api/ai",
            resource: "embeddings"
        )
        XCTAssertEqual(url.absoluteString, "https://example.com/api/ai/embeddings")
    }

    func testEndpointRejectsUnsupportedScheme() {
        XCTAssertThrowsError(
            try OpenAICompatibleClient.endpoint(baseURL: "file:///tmp/api", resource: "embeddings")
        )
    }

    func testSSEParserDecodesTextAndDone() throws {
        let text = try OpenAICompatibleClient.parseSSELine(
            #"data: {"choices":[{"delta":{"content":"你好"}}]}"#
        )
        XCTAssertEqual(text, .text("你好"))
        XCTAssertEqual(try OpenAICompatibleClient.parseSSELine("data: [DONE]"), .done)
        XCTAssertEqual(try OpenAICompatibleClient.parseSSELine(": keep-alive"), .ignored)
        XCTAssertEqual(
            try OpenAICompatibleClient.parseSSELine(
                #"data: {"choices":[{"delta":{"content":"完成"},"finish_reason":"stop"}]}"#
            ),
            .textAndDone("完成")
        )
    }

    func testResponsesSSEParserDecodesCodexTextAndCompletion() throws {
        XCTAssertEqual(
            try OpenAICompatibleClient.parseResponsesSSELine(
                #"data: {"type":"response.output_text.delta","delta":"你好"}"#
            ),
            .text("你好")
        )
        XCTAssertEqual(
            try OpenAICompatibleClient.parseResponsesSSELine(
                #"data: {"type":"response.completed"}"#
            ),
            .done
        )
        XCTAssertEqual(
            try OpenAICompatibleClient.parseResponsesSSELine(
                #"data: {"type":"response.created"}"#
            ),
            .ignored
        )
    }

    func testResponsesSSEParserSurfacesProviderFailure() throws {
        XCTAssertThrowsError(
            try OpenAICompatibleClient.parseResponsesSSELine(
                #"data: {"type":"response.failed","response":{"error":{"message":"model unavailable"}}}"#
            )
        ) { error in
            XCTAssertEqual(error as? AIClientError, .streamFailed("model unavailable"))
        }
    }

    func testChatGPTCompleteUsesStreamingResponsesAndAggregatesText() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"O\"}\n\n"
                + "data: {\"type\":\"response.output_text.delta\",\"delta\":\"K\"}\n\n"
                + "data: {\"type\":\"response.completed\"}\n\n"
        )
        let client = OpenAICompatibleClient(
            session: makeSession(),
            subscriptionAuthorizationResolver: { _ in
                SubscriptionAuthorization(
                    kind: .chatGPTSubscription,
                    accessToken: "fixture-token",
                    accountID: "account-fixture",
                    userID: nil
                )
            }
        )
        let chatGPT = ProviderConfiguration(
            baseURL: "https://chatgpt.com/backend-api/codex",
            model: "gpt-5.5",
            embeddingModel: "",
            temperature: 0.2,
            streamsResponses: false
        )

        let reply = try await client.complete(
            messages: [APIChatMessage(role: "user", content: "只回复 OK")],
            configuration: chatGPT,
            apiKey: "fixture-reference",
            temperature: 0,
            maxTokens: 16
        )

        XCTAssertEqual(reply, "OK")
        let request = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequest())
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://chatgpt.com/backend-api/codex/responses"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "ChatGPT-Account-Id"),
            "account-fixture"
        )
        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertNotNil(json["client_metadata"] as? [String: String])
        XCTAssertNil(json["max_output_tokens"])
    }

    func testGrokRequestUsesCurrentInteractiveHeadersAndSelectedModel() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#,
            contentType: "application/json"
        )
        let client = OpenAICompatibleClient(
            session: makeSession(),
            subscriptionAuthorizationResolver: { _ in
                SubscriptionAuthorization(
                    kind: .grokSubscription,
                    accessToken: "fixture-token",
                    accountID: nil,
                    userID: "user-fixture"
                )
            }
        )
        let grok = ProviderConfiguration(
            baseURL: "https://cli-chat-proxy.grok.com/v1",
            model: "untrusted-editable-model",
            embeddingModel: "",
            temperature: 0.2,
            streamsResponses: true
        )

        _ = try await client.complete(
            messages: [APIChatMessage(role: "user", content: "测试")],
            configuration: grok,
            apiKey: "fixture-reference",
            temperature: 0,
            maxTokens: 16
        )

        let request = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequest())
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://cli-chat-proxy.grok.com/v1/chat/completions"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-userid"), "user-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-mode"), "interactive")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-identifier"), "kin-ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-version"), "1.0.10")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-model-override"), "grok-build")
        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "grok-build")
    }

    func testStreamChatCompletesOnDoneMarker() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: "data: {\"choices\":[{\"delta\":{\"content\":\"你好\"}}]}\n\ndata: [DONE]\n\n"
        )

        let chunks = try await collect(
            OpenAICompatibleClient(session: makeSession()).streamChat(
                messages: [APIChatMessage(role: "user", content: "测试")],
                configuration: configuration,
                apiKey: ""
            )
        )

        XCTAssertEqual(chunks, ["你好"])
    }

    func testStreamChatCompletesOnFinishReasonWithContent() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: "data: {\"choices\":[{\"delta\":{\"content\":\"完成\"},\"finish_reason\":\"stop\"}]}\n\n"
        )

        let chunks = try await collect(
            OpenAICompatibleClient(session: makeSession()).streamChat(
                messages: [APIChatMessage(role: "user", content: "测试")],
                configuration: configuration,
                apiKey: ""
            )
        )

        XCTAssertEqual(chunks, ["完成"])
    }

    func testStreamChatThrowsMalformedStreamOnUnexpectedEOF() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: "data: {\"choices\":[{\"delta\":{\"content\":\"部分回答\"}}]}\n\n"
        )

        var chunks: [String] = []
        do {
            for try await chunk in OpenAICompatibleClient(session: makeSession()).streamChat(
                messages: [APIChatMessage(role: "user", content: "测试")],
                configuration: configuration,
                apiKey: ""
            ) {
                chunks.append(chunk)
            }
            XCTFail("Expected malformedStream")
        } catch let error as AIClientError {
            XCTAssertEqual(error, .malformedStream)
        }

        XCTAssertEqual(chunks, ["部分回答"])
    }

    func testStreamChatNon2xxPreservesServerErrorBody() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 429,
            body: "{\"error\":{\"message\":\"请求过于频繁\"}}",
            contentType: "application/json"
        )

        do {
            _ = try await collect(
                OpenAICompatibleClient(session: makeSession()).streamChat(
                    messages: [APIChatMessage(role: "user", content: "测试")],
                    configuration: configuration,
                    apiKey: ""
                )
            )
            XCTFail("Expected HTTP error")
        } catch let error as AIClientError {
            XCTAssertEqual(error, .httpStatus(429, "请求过于频繁"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDeepSeekV4FlashUsesNonThinkingMode() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#,
            contentType: "application/json"
        )
        let deepSeek = ProviderConfiguration(
            baseURL: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            embeddingModel: "",
            temperature: 0.8,
            streamsResponses: true
        )

        _ = try await OpenAICompatibleClient(session: makeSession()).complete(
            messages: [APIChatMessage(role: "user", content: "测试")],
            configuration: deepSeek,
            apiKey: "test-only",
            temperature: 0,
            maxTokens: 16
        )

        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let thinking = try XCTUnwrap(json["thinking"] as? [String: String])
        XCTAssertEqual(thinking["type"], "disabled")
    }

    func testGenericProviderOmitsDeepSeekThinkingField() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#,
            contentType: "application/json"
        )

        _ = try await OpenAICompatibleClient(session: makeSession()).complete(
            messages: [APIChatMessage(role: "user", content: "测试")],
            configuration: configuration,
            apiKey: "test-only",
            temperature: 0,
            maxTokens: 16
        )

        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertNil(json["thinking"])
    }

    func testOfficialOpenAIReasoningModelUsesCompatibleParameters() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#,
            contentType: "application/json"
        )
        let openAIReasoning = ProviderConfiguration(
            baseURL: "https://api.openai.com/v1",
            model: "o3",
            embeddingModel: "",
            temperature: 0.8,
            streamsResponses: true
        )

        _ = try await OpenAICompatibleClient(session: makeSession()).complete(
            messages: [
                APIChatMessage(role: "system", content: "系统提示"),
                APIChatMessage(role: "user", content: "测试")
            ],
            configuration: openAIReasoning,
            apiKey: "test-only",
            temperature: 0,
            maxTokens: 16
        )

        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertNil(json["temperature"])
        XCTAssertNil(json["max_tokens"])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 256)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "developer")
    }

    func testOfficialOpenAINonReasoningModelUsesMaxCompletionTokens() async throws {
        OpenAICompatibleURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"choices":[{"message":{"content":"OK"}}]}"#,
            contentType: "application/json"
        )
        let openAIChat = ProviderConfiguration(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1-mini",
            embeddingModel: "",
            temperature: 0.8,
            streamsResponses: true
        )

        _ = try await OpenAICompatibleClient(session: makeSession()).complete(
            messages: [APIChatMessage(role: "user", content: "测试")],
            configuration: openAIChat,
            apiKey: "test-only",
            temperature: 0.2,
            maxTokens: 16
        )

        let body = try XCTUnwrap(OpenAICompatibleURLProtocol.capturedRequestBody())
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["temperature"] as? Double, 0.2)
        XCTAssertNil(json["max_tokens"])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 16)
    }

    private let configuration = ProviderConfiguration(
        baseURL: "https://unit.test/v1",
        model: "fixture-model",
        embeddingModel: "",
        temperature: 0.7,
        streamsResponses: true
    )

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenAICompatibleURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(
        _ stream: AsyncThrowingStream<String, Error>
    ) async throws -> [String] {
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }
        return chunks
    }
}

private final class OpenAICompatibleURLProtocol: URLProtocol {
    private struct Fixture {
        let response: HTTPURLResponse
        let body: Data
    }

    private static let lock = NSLock()
    private static var fixture: Fixture!
    private static var requestBody: Data?
    private static var lastRequest: URLRequest?

    static func setFixture(
        statusCode: Int,
        body: String,
        contentType: String = "text/event-stream"
    ) {
        let response = HTTPURLResponse(
            url: URL(string: "https://unit.test/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        lock.lock()
        fixture = Fixture(response: response, body: Data(body.utf8))
        requestBody = nil
        lastRequest = nil
        lock.unlock()
    }

    static func capturedRequestBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return requestBody
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequest
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "unit.test"
            || host == "api.deepseek.com"
            || host == "api.openai.com"
            || host == "chatgpt.com"
            || host == "cli-chat-proxy.grok.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let currentFixture = Self.fixture!
        Self.lastRequest = request
        Self.requestBody = Self.bodyData(from: request)
        Self.lock.unlock()
        client?.urlProtocol(
            self,
            didReceive: currentFixture.response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: currentFixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(buffer, count: count)
        }
    }
}
