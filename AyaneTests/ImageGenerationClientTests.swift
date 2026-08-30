import Foundation
import XCTest
@testable import Ayane

final class ImageGenerationClientTests: XCTestCase {
    func testImagesAPISendsDedicatedRequestAndDecodesBase64() async throws {
        let pngData = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))
        ImageGenerationURLProtocol.setResponses([
            "/v1/images/generations": .json(
                #"{"data":[{"b64_json":"\#(Self.pngBase64)","revised_prompt":"雨夜便利店"}]}"#
            )
        ])

        let result = try await makeClient().generateImage(
            prompt: "雨夜便利店",
            configuration: ImageGenerationConfiguration(
                baseURL: "https://unit.image/v1",
                model: "gpt-image-2",
                apiStyle: .imagesAPI
            ),
            apiKey: "image-fixture-key"
        )

        XCTAssertEqual(result.data, pngData)
        XCTAssertEqual(result.revisedPrompt, "雨夜便利店")
        let request = try XCTUnwrap(ImageGenerationURLProtocol.requests().first)
        XCTAssertEqual(request.url?.absoluteString, "https://unit.image/v1/images/generations")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer image-fixture-key"
        )
        let body = try XCTUnwrap(ImageGenerationURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "gpt-image-2")
        XCTAssertEqual(json["prompt"] as? String, "雨夜便利店")
        XCTAssertEqual(json["n"] as? Int, 1)
        XCTAssertEqual(json["size"] as? String, "1024x1024")
    }

    func testImagesAPIAcceptsURLAndDoesNotForwardCredentialToCDN() async throws {
        let pngData = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))
        let fixtureKey = "cdn-fixture-key"
        ImageGenerationURLProtocol.setResponses([
            "/v1/images/generations": .json(
                #"{"data":[{"url":"https://unit.image/generated/result.png"}]}"#
            ),
            "/generated/result.png": .image(pngData)
        ])

        let result = try await makeClient().generateImage(
            prompt: "portrait",
            configuration: ImageGenerationConfiguration(
                baseURL: "https://unit.image/v1",
                model: "compatible-image-model",
                apiStyle: .imagesAPI
            ),
            apiKey: fixtureKey
        )

        XCTAssertEqual(result.data, pngData)
        let requests = ImageGenerationURLProtocol.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Authorization"),
            "Bearer \(fixtureKey)"
        )
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
    }

    func testReturnedImageURLRejectsLocalPrivateAndCredentialedTargets() async throws {
        let candidates = [
            "http://example.com/result.png",
            "https://localhost/result.png",
            "https://127.0.0.1/result.png",
            "https://10.0.0.4/result.png",
            "https://169.254.169.254/latest/meta-data",
            "https://[::1]/result.png",
            "https://user:pass@example.com/result.png"
        ]

        for value in candidates {
            let url = try XCTUnwrap(URL(string: value))
            let isSafe = await OpenAICompatibleImageGenerationClient
                .isSafeRemoteImageURL(url)
            XCTAssertFalse(isSafe, value)
        }
    }

    func testReturnedImageRedirectResponseIsRejected() async throws {
        ImageGenerationURLProtocol.setResponses([
            "/v1/images/generations": .json(
                #"{"data":[{"url":"https://unit.image/generated/redirect.png"}]}"#
            ),
            "/generated/redirect.png": .data(
                Data(),
                contentType: "text/plain",
                statusCode: 302
            )
        ])

        do {
            _ = try await makeClient().generateImage(
                prompt: "portrait",
                configuration: ImageGenerationConfiguration(
                    baseURL: "https://unit.image/v1",
                    model: "compatible-image-model",
                    apiStyle: .imagesAPI
                ),
                apiKey: "redirect-fixture-key"
            )
            XCTFail("Expected redirect rejection")
        } catch {
            XCTAssertEqual(error as? ImageGenerationClientError, .unsafeImageURL)
        }
    }

    func testMultimodalChatSendsModalitiesAndParsesOpenRouterDataURL() async throws {
        let pngData = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))
        let dataURL = "data:image/png;base64,\(Self.pngBase64)"
        let response = [
            "choices": [[
                "message": [
                    "images": [["image_url": ["url": dataURL]]]
                ]
            ]]
        ] as [String: Any]
        let responseData = try JSONSerialization.data(withJSONObject: response)
        ImageGenerationURLProtocol.setResponses([
            "/v1/chat/completions": .data(responseData, contentType: "application/json")
        ])

        let result = try await makeClient().generateImage(
            prompt: "a paper crane",
            configuration: ImageGenerationConfiguration(
                baseURL: "https://unit.image/v1",
                model: "google/gemini-image",
                apiStyle: .chatCompletions
            ),
            apiKey: "router-key"
        )

        XCTAssertEqual(result.data, pngData)
        let request = try XCTUnwrap(ImageGenerationURLProtocol.requests().first)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        let body = try XCTUnwrap(ImageGenerationURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["modalities"] as? [String], ["image", "text"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "a paper crane"]])
        XCTAssertEqual(json["stream"] as? Bool, false)
    }

    func testOpenRouterImagesUsesCurrentDedicatedEndpointAndMinimalBody() async throws {
        ImageGenerationURLProtocol.setResponses([
            "/api/v1/images": .json(
                #"{"data":[{"b64_json":"\#(Self.pngBase64)"}]}"#
            )
        ])

        _ = try await makeClient().generateImage(
            prompt: "red panda astronaut",
            configuration: ImageGenerationConfiguration(
                baseURL: "https://unit.image/api/v1",
                model: "openai/gpt-image-1",
                apiStyle: .openRouterImages
            ),
            apiKey: "router-key"
        )

        let request = try XCTUnwrap(ImageGenerationURLProtocol.requests().first)
        XCTAssertEqual(request.url?.path, "/api/v1/images")
        let body = try XCTUnwrap(ImageGenerationURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "openai/gpt-image-1")
        XCTAssertEqual(json["prompt"] as? String, "red panda astronaut")
        XCTAssertNil(json["size"])
        XCTAssertNil(json["n"])
    }

    func testEndpointRejectsIncompleteOrResponsesRouteAndReplacesWrongRoute() throws {
        XCTAssertThrowsError(
            try OpenAICompatibleImageGenerationClient.endpoint(
                for: ImageGenerationConfiguration(
                    baseURL: "https://gateway.test/custom/images",
                    model: "image-model",
                    apiStyle: .imagesAPI
                )
            )
        ) { error in
            XCTAssertEqual(error as? ImageGenerationClientError, .incompleteImagesEndpoint)
        }
        XCTAssertThrowsError(
            try OpenAICompatibleImageGenerationClient.endpoint(
                for: ImageGenerationConfiguration(
                    baseURL: "https://gateway.test/v1/responses",
                    model: "image-model",
                    apiStyle: .imagesAPI
                )
            )
        ) { error in
            XCTAssertEqual(error as? ImageGenerationClientError, .unsupportedResponsesEndpoint)
        }
        XCTAssertEqual(
            try OpenAICompatibleImageGenerationClient.endpoint(
                for: ImageGenerationConfiguration(
                    baseURL: "https://gateway.test/v1/chat/completions",
                    model: "image-model",
                    apiStyle: .imagesAPI
                )
            ).absoluteString,
            "https://gateway.test/v1/images/generations"
        )
    }

    private func makeClient() -> OpenAICompatibleImageGenerationClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageGenerationURLProtocol.self]
        return OpenAICompatibleImageGenerationClient(
            session: URLSession(configuration: configuration),
            remoteImageURLValidator: { url in
                url.scheme == "https" && url.host == "unit.image"
            }
        )
    }

    private static let pngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

private final class ImageGenerationURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let contentType: String
        let body: Data

        static func json(_ value: String, statusCode: Int = 200) -> Response {
            Response(
                statusCode: statusCode,
                contentType: "application/json",
                body: Data(value.utf8)
            )
        }

        static func image(_ value: Data, statusCode: Int = 200) -> Response {
            data(value, contentType: "image/png", statusCode: statusCode)
        }

        static func data(
            _ value: Data,
            contentType: String,
            statusCode: Int = 200
        ) -> Response {
            Response(statusCode: statusCode, contentType: contentType, body: value)
        }
    }

    private static let lock = NSLock()
    private static var storedResponses: [String: Response] = [:]
    private static var storedRequests: [URLRequest] = []

    static func setResponses(_ responses: [String: Response]) {
        lock.lock()
        storedResponses = responses
        storedRequests = []
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
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

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "unit.image"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.lock.lock()
        Self.storedRequests.append(request)
        let response = Self.storedResponses[path]
        Self.lock.unlock()
        guard let response,
              let url = request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": response.contentType]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
