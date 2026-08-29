import XCTest
@testable import Ayane

final class ProviderCatalogTests: XCTestCase {
    override func tearDown() {
        ProviderCatalogURLProtocol.reset()
        super.tearDown()
    }

    func testPresetModelListURLsFollowProviderContracts() throws {
        XCTAssertEqual(
            try ProviderPreset.deepSeek.modelListURL(for: "https://api.deepseek.com").absoluteString,
            "https://api.deepseek.com/models"
        )

        let qwen = try ProviderPreset.qwen.modelListURL(
            for: "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
        )
        XCTAssertEqual(qwen.path, "/api/v1/models")
        let qwenQuery = try XCTUnwrap(URLComponents(url: qwen, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(qwenQuery.contains(URLQueryItem(name: "capabilities", value: "TG")))
        XCTAssertTrue(qwenQuery.contains(URLQueryItem(name: "page_no", value: "1")))
        XCTAssertTrue(qwenQuery.contains(URLQueryItem(name: "page_size", value: "100")))

        let siliconFlow = try ProviderPreset.siliconFlow.modelListURL(
            for: "https://api.siliconflow.cn/v1"
        )
        XCTAssertEqual(siliconFlow.path, "/v1/models")
        let siliconQuery = try XCTUnwrap(
            URLComponents(url: siliconFlow, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertTrue(siliconQuery.contains(URLQueryItem(name: "type", value: "text")))
        XCTAssertTrue(siliconQuery.contains(URLQueryItem(name: "sub_type", value: "chat")))

        XCTAssertEqual(
            try ProviderPreset.custom.modelListURL(
                for: "https://example.test/v1beta/openai"
            ).absoluteString,
            "https://example.test/v1beta/openai/models"
        )
        XCTAssertEqual(
            try ProviderPreset.together.modelListURL(
                for: ProviderPreset.together.defaultBaseURL
            ).absoluteString,
            "https://api.together.ai/v1/models"
        )

        let openRouter = try ProviderPreset.openRouter.modelListURL(
            for: ProviderPreset.openRouter.defaultBaseURL
        )
        let openRouterQuery = try XCTUnwrap(
            URLComponents(url: openRouter, resolvingAgainstBaseURL: false)?.queryItems
        )
        XCTAssertEqual(openRouter.path, "/api/v1/models")
        XCTAssertTrue(
            openRouterQuery.contains(URLQueryItem(name: "output_modalities", value: "text"))
        )
        XCTAssertTrue(
            openRouterQuery.contains(
                URLQueryItem(name: "supported_parameters", value: "temperature,max_tokens")
            )
        )
    }

    func testQwenSharedChinaAddressRequiresWorkspaceOrManualModel() {
        XCTAssertThrowsError(
            try ProviderPreset.qwen.modelListURL(
                for: "https://dashscope.aliyuncs.com/compatible-mode/v1"
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderModelDiscoveryError,
                .qwenWorkspaceAddressRequired
            )
        }
    }

    func testQwenSharedUSAddressAlsoRequiresWorkspaceOrManualModel() {
        XCTAssertThrowsError(
            try ProviderPreset.qwen.modelListURL(
                for: "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
            )
        ) { error in
            XCTAssertEqual(
                error as? ProviderModelDiscoveryError,
                .qwenWorkspaceAddressRequired
            )
        }
    }

    func testCustomCredentialIdentityChangesWithHostButNotTrailingSlash() {
        let first = ProviderPreset.custom.credentialID(for: "https://one.example/v1/")
        let equivalent = ProviderPreset.custom.credentialID(for: "https://ONE.example/v1")
        let second = ProviderPreset.custom.credentialID(for: "https://two.example/v1")
        let otherTenant = ProviderPreset.custom.credentialID(
            for: "https://one.example/v1?tenant=other"
        )
        XCTAssertEqual(first, equivalent)
        XCTAssertNotEqual(first, second)
        XCTAssertNotEqual(first, otherTenant)
        XCTAssertTrue(first.hasPrefix("custom-"))
    }

    func testExplicitCustomProviderRemainsCustomOnKnownHost() throws {
        let suiteName = "AyaneTests.ProviderSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(ProviderPreset.custom.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("https://api.openai.com/v1", forKey: SettingsKeys.baseURL)
        defaults.set(1, forKey: SettingsKeys.providerSelectionMigrationVersion)

        XCTAssertEqual(SettingsStore.selectedProvider(defaults: defaults), .custom)
        XCTAssertTrue(
            ProviderPreset.custom.credentialID(for: "https://api.openai.com/v1")
                .hasPrefix("custom-")
        )
    }

    func testPresetMatchingRecognizesCanonicalAndQwenWorkspaceHosts() {
        XCTAssertEqual(
            ProviderPreset.matching(baseURL: "https://api.deepseek.com"),
            .deepSeek
        )
        XCTAssertEqual(
            ProviderPreset.matching(
                baseURL: "https://workspace.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
            ),
            .qwen
        )
        XCTAssertNil(ProviderPreset.matching(baseURL: "https://private.example.test/v1"))
    }

    func testModelDiscoveryDecodesOpenAIEnvelopeAndFiltersNonChatModels() async throws {
        ProviderCatalogURLProtocol.setFixture(
            statusCode: 200,
            body: #"""
            {
              "data": [
                {"id":"chat-fast","object":"model"},
                {"id":"chat-fast","object":"model"},
                {"id":"text-embedding-3-small","object":"model"},
                {"id":"disabled-chat","capabilities":{"completion_chat":false}}
              ]
            }
            """#
        )

        let models = try await makeClient().listChatModels(
            provider: .custom,
            baseURL: "https://unit.test/v1",
            apiKey: "test-only"
        )

        XCTAssertEqual(models, ["chat-fast"])
        let request = try XCTUnwrap(ProviderCatalogURLProtocol.capturedRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://unit.test/v1/models")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
    }

    func testModelDiscoveryDecodesQwenOutputEnvelope() async throws {
        ProviderCatalogURLProtocol.setFixture(
            statusCode: 200,
            body: #"""
            {
              "success": true,
              "output": {
                "models": [
                  {"model":"qwen-chat"},
                  {"model":"qwen-image-max"}
                ]
              }
            }
            """#
        )

        let models = try await makeClient().listChatModels(
            provider: .qwen,
            baseURL: "https://unit.test/compatible-mode/v1",
            apiKey: "test-only"
        )
        XCTAssertEqual(models, ["qwen-chat"])
    }

    func testTogetherModelDiscoveryUsesOfficialTypeToFilterNonChatModels() async throws {
        ProviderCatalogURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"data":[{"id":"chat-model","type":"chat"},{"id":"vision-core","type":"image"},{"id":"reranker","type":"rerank"}]}"#
        )

        let models = try await makeClient().listChatModels(
            provider: .together,
            baseURL: "https://unit.test/v1",
            apiKey: "test-only"
        )
        XCTAssertEqual(models, ["chat-model"])
    }

    func testOpenAIAndGroqProviderFiltersRejectKnownNonChatModels() async throws {
        ProviderCatalogURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"data":[{"id":"gpt-5.2"},{"id":"babbage-002"},{"id":"davinci-002"}]}"#
        )
        let openAIModels = try await makeClient().listChatModels(
            provider: .openAI,
            baseURL: "https://unit.test/v1",
            apiKey: "test-only"
        )
        XCTAssertEqual(openAIModels, ["gpt-5.2"])

        ProviderCatalogURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"data":[{"id":"llama-4-chat"},{"id":"llama-guard-4"},{"id":"prompt-guard-2"}]}"#
        )
        let groqModels = try await makeClient().listChatModels(
            provider: .groq,
            baseURL: "https://unit.test/v1",
            apiKey: "test-only"
        )
        XCTAssertEqual(groqModels, ["llama-4-chat"])
    }

    func testModelDiscoverySurfacesProviderErrorMessage() async {
        ProviderCatalogURLProtocol.setFixture(
            statusCode: 401,
            body: #"{"error":{"message":"invalid test credential"}}"#
        )

        do {
            _ = try await makeClient().listChatModels(
                provider: .custom,
                baseURL: "https://unit.test/v1",
                apiKey: "test-only"
            )
            XCTFail("Expected discovery to fail")
        } catch let error as AIClientError {
            XCTAssertEqual(error, .httpStatus(401, "invalid test credential"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeClient() -> ProviderModelCatalogClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderCatalogURLProtocol.self]
        return ProviderModelCatalogClient(session: URLSession(configuration: configuration))
    }
}

private final class ProviderCatalogURLProtocol: URLProtocol {
    private struct Fixture {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    private static var fixture: Fixture?
    private static var latestRequest: URLRequest?

    static func setFixture(statusCode: Int, body: String) {
        lock.lock()
        fixture = Fixture(statusCode: statusCode, body: Data(body.utf8))
        latestRequest = nil
        lock.unlock()
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return latestRequest
    }

    static func reset() {
        lock.lock()
        fixture = nil
        latestRequest = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "unit.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixture
        Self.latestRequest = request
        Self.lock.unlock()

        guard let fixture,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: fixture.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
