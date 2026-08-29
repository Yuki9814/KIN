import Foundation
import XCTest
@testable import Ayane

final class SubscriptionOAuthServiceTests: XCTestCase {
    func testChatGPTRefreshUsesFormEncodingAndKeepsRotatedRefreshToken() async throws {
        SubscriptionOAuthURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"access_token":"new-access","refresh_token":"rotated-refresh","expires_in":3600}"#
        )
        let stale = SubscriptionOAuthCredential(
            kind: .chatGPTSubscription,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: .distantPast,
            accountID: "account-fixture",
            userID: nil
        )

        let refreshed = try await SubscriptionOAuthService(
            session: makeSession()
        ).refresh(stale)

        XCTAssertEqual(refreshed.accessToken, "new-access")
        XCTAssertEqual(refreshed.refreshToken, "rotated-refresh")
        XCTAssertEqual(refreshed.accountID, "account-fixture")
        let request = try XCTUnwrap(SubscriptionOAuthURLProtocol.capturedRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/x-www-form-urlencoded"
        )
        let values = try formValues(
            from: XCTUnwrap(SubscriptionOAuthURLProtocol.capturedRequestBody())
        )
        XCTAssertEqual(values["grant_type"], "refresh_token")
        XCTAssertEqual(values["refresh_token"], "old-refresh")
        XCTAssertNotNil(values["client_id"])
    }

    func testGrokDeviceAuthorizationRequestsCurrentConversationAndWorkspaceScopes() async throws {
        SubscriptionOAuthURLProtocol.setFixture(
            statusCode: 200,
            body: #"{"device_code":"device","user_code":"ABCD-EFGH","verification_uri":"https://accounts.x.ai/oauth2/device","expires_in":300,"interval":5}"#
        )

        _ = try await SubscriptionOAuthService(
            session: makeSession()
        ).requestDeviceAuthorization(kind: .grokSubscription)

        let request = try XCTUnwrap(SubscriptionOAuthURLProtocol.capturedRequest())
        XCTAssertEqual(request.url?.absoluteString, "https://auth.x.ai/oauth2/device/code")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-surface"), "ui")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-grok-client-version"), "1.0.10")
        let values = try formValues(
            from: XCTUnwrap(SubscriptionOAuthURLProtocol.capturedRequestBody())
        )
        let scope = try XCTUnwrap(values["scope"])
        XCTAssertTrue(scope.contains("grok-cli:access"))
        XCTAssertTrue(scope.contains("conversations:read"))
        XCTAssertTrue(scope.contains("conversations:write"))
        XCTAssertTrue(scope.contains("workspaces:read"))
        XCTAssertTrue(scope.contains("workspaces:write"))
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SubscriptionOAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func formValues(from body: Data) throws -> [String: String] {
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

private final class SubscriptionOAuthURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statusCode = 200
    private static var responseBody = Data()
    private static var lastRequest: URLRequest?
    private static var lastRequestBody: Data?

    static func setFixture(statusCode: Int, body: String) {
        lock.lock()
        self.statusCode = statusCode
        responseBody = Data(body.utf8)
        lastRequest = nil
        lastRequestBody = nil
        lock.unlock()
    }

    static func capturedRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequest
    }

    static func capturedRequestBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequestBody
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "auth.openai.com" || request.url?.host == "auth.x.ai"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.lastRequest = request
        Self.lastRequestBody = Self.bodyData(from: request)
        let statusCode = Self.statusCode
        let body = Self.responseBody
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data? {
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
}
