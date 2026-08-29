import XCTest
@testable import Ayane

final class LocalSubscriptionCredentialImporterTests: XCTestCase {
    func testCodexNestedTokensMapWithoutPersistingSourceShape() throws {
        let expiration = Date(timeIntervalSince1970: 1_900_000_000)
        let access = jwt([
            "exp": expiration.timeIntervalSince1970,
            "sub": "openai-user",
            "https://api.openai.com/auth.chatgpt_account_id": "account-1"
        ])
        let data = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": [
                "access_token": access,
                "refresh_token": "openai-refresh",
                "id_token": jwt(["sub": "openai-user"]),
                "account_id": "account-1"
            ]
        ])

        let credential = try LocalSubscriptionCredentialImporter.credential(
            from: data,
            kind: .chatGPTSubscription
        )

        XCTAssertEqual(credential.kind, .chatGPTSubscription)
        XCTAssertEqual(credential.accessToken, access)
        XCTAssertEqual(credential.refreshToken, "openai-refresh")
        XCTAssertEqual(credential.accountID, "account-1")
        XCTAssertEqual(credential.userID, "openai-user")
        XCTAssertEqual(credential.expiresAt, expiration)
    }

    func testGrokCompositeProviderObjectMapsKeyAndISOExpiration() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "https://auth.x.ai::client": [
                "key": "grok-access",
                "refresh_token": "grok-refresh",
                "expires_at": "2030-03-17T17:46:40Z",
                "user_id": "xai-user"
            ]
        ])

        let credential = try LocalSubscriptionCredentialImporter.credential(
            from: data,
            kind: .grokSubscription
        )

        XCTAssertEqual(credential.kind, .grokSubscription)
        XCTAssertEqual(credential.accessToken, "grok-access")
        XCTAssertEqual(credential.refreshToken, "grok-refresh")
        XCTAssertEqual(credential.userID, "xai-user")
        XCTAssertEqual(
            credential.expiresAt,
            ISO8601DateFormatter().date(from: "2030-03-17T17:46:40Z")
        )
    }

    func testCredentialRejectsMissingRefreshToken() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "tokens": ["access_token": "access-only"]
        ])

        XCTAssertThrowsError(
            try LocalSubscriptionCredentialImporter.credential(
                from: data,
                kind: .chatGPTSubscription
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalSubscriptionCredentialImportError,
                .missingRefreshToken
            )
        }
    }

    private func jwt(_ claims: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: claims))
        return "\(header).\(payload).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
