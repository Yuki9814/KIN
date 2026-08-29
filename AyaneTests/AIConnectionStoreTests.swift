import Foundation
import XCTest
@testable import Ayane

final class AIConnectionStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "com.example.kin.tests.ai-connection-store.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testLegacyConnectionLiveInheritsLegacyGlobalConfiguration() throws {
        defaults.set(ProviderPreset.deepSeek.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("https://legacy-one.example/v1", forKey: SettingsKeys.baseURL)
        defaults.set("legacy-model-one", forKey: SettingsKeys.model)
        defaults.set("legacy-embedding-one", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.31, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)

        let first = AIConnectionStore.legacyConnection(defaults: defaults)
        XCTAssertEqual(first.id, AIConnectionStore.legacyConnectionID)
        XCTAssertEqual(first.providerID, ProviderPreset.deepSeek.rawValue)
        XCTAssertEqual(first.baseURL, "https://legacy-one.example/v1")
        XCTAssertEqual(first.model, "legacy-model-one")
        XCTAssertEqual(first.embeddingModel, "legacy-embedding-one")
        XCTAssertEqual(first.temperature, 0.31)
        XCTAssertFalse(first.streamsResponses)

        defaults.set(ProviderPreset.openAI.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("https://legacy-two.example/v1", forKey: SettingsKeys.baseURL)
        defaults.set("legacy-model-two", forKey: SettingsKeys.model)
        defaults.set("legacy-embedding-two", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.73, forKey: SettingsKeys.temperature)
        defaults.set(true, forKey: SettingsKeys.streamResponses)

        let second = try XCTUnwrap(
            AIConnectionStore.connection(
                id: AIConnectionStore.legacyConnectionID,
                defaults: defaults
            )
        )
        XCTAssertEqual(second.id, AIConnectionStore.legacyConnectionID)
        XCTAssertEqual(second.providerID, ProviderPreset.openAI.rawValue)
        XCTAssertEqual(second.baseURL, "https://legacy-two.example/v1")
        XCTAssertEqual(second.model, "legacy-model-two")
        XCTAssertEqual(second.embeddingModel, "legacy-embedding-two")
        XCTAssertEqual(second.temperature, 0.73)
        XCTAssertTrue(second.streamsResponses)
    }

    func testAdditionalProfilesCoexistAndRemainAddressable() throws {
        let first = makeProfile(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            displayName: "第一个连接",
            providerID: "first-provider",
            baseURL: "https://first.example/v1",
            model: "first-model",
            createdAt: date(100)
        )
        let second = makeProfile(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            displayName: "第二个连接",
            providerID: "second-provider",
            baseURL: "https://second.example/v1",
            model: "second-model",
            createdAt: date(200)
        )

        try AIConnectionStore.save(first, defaults: defaults)
        try AIConnectionStore.save(second, defaults: defaults)

        let profiles = AIConnectionStore.connections(defaults: defaults)
        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(
            profiles.map(\.id),
            [AIConnectionStore.legacyConnectionID, first.id, second.id]
        )
        XCTAssertEqual(AIConnectionStore.connection(id: first.id, defaults: defaults), first)
        XCTAssertEqual(AIConnectionStore.connection(id: second.id, defaults: defaults), second)
    }

    func testDefaultConnectionStartsAtLegacyAndCanSelectAdditionalProfile() throws {
        XCTAssertEqual(
            AIConnectionStore.defaultConnectionID(defaults: defaults),
            AIConnectionStore.legacyConnectionID
        )

        let profile = makeProfile(
            id: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!,
            displayName: "默认候选",
            createdAt: date(300)
        )
        try AIConnectionStore.save(profile, defaults: defaults)
        try AIConnectionStore.setDefaultConnectionID(profile.id, defaults: defaults)

        XCTAssertEqual(
            AIConnectionStore.defaultConnectionID(defaults: defaults),
            profile.id
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(
                for: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                defaults: defaults
            ),
            profile.id
        )
        XCTAssertThrowsError(
            try AIConnectionStore.setDefaultConnectionID(
                UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
                defaults: defaults
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectionStoreError, .invalidConnection)
        }
    }

    func testRoleBindingsAreIndependentAndNilFollowsDefault() throws {
        let first = makeProfile(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            displayName: "角色一连接",
            createdAt: date(500)
        )
        let second = makeProfile(
            id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
            displayName: "角色二连接",
            createdAt: date(600)
        )
        try AIConnectionStore.save(first, defaults: defaults)
        try AIConnectionStore.save(second, defaults: defaults)

        let firstRole = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let secondRole = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        try AIConnectionStore.setConnectionID(first.id, for: firstRole, defaults: defaults)
        try AIConnectionStore.setConnectionID(second.id, for: secondRole, defaults: defaults)

        XCTAssertEqual(
            AIConnectionStore.explicitConnectionID(for: firstRole, defaults: defaults),
            first.id
        )
        XCTAssertEqual(
            AIConnectionStore.explicitConnectionID(for: secondRole, defaults: defaults),
            second.id
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: firstRole, defaults: defaults),
            first.id
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: secondRole, defaults: defaults),
            second.id
        )

        try AIConnectionStore.setConnectionID(nil, for: firstRole, defaults: defaults)
        XCTAssertNil(AIConnectionStore.explicitConnectionID(for: firstRole, defaults: defaults))
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: firstRole, defaults: defaults),
            AIConnectionStore.legacyConnectionID
        )
        XCTAssertEqual(
            AIConnectionStore.explicitConnectionID(for: secondRole, defaults: defaults),
            second.id
        )

        try AIConnectionStore.setDefaultConnectionID(first.id, defaults: defaults)
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: firstRole, defaults: defaults),
            first.id
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: secondRole, defaults: defaults),
            second.id
        )
    }

    func testDeletingConnectionCleansDefaultAndRoleBindings() throws {
        let deleted = makeProfile(
            id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
            displayName: "将删除",
            createdAt: date(700)
        )
        let retained = makeProfile(
            id: UUID(uuidString: "88888888-8888-4888-8888-888888888888")!,
            displayName: "保留连接",
            createdAt: date(800)
        )
        try AIConnectionStore.save(deleted, defaults: defaults)
        try AIConnectionStore.save(retained, defaults: defaults)
        try AIConnectionStore.setDefaultConnectionID(deleted.id, defaults: defaults)

        let deletedRole = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        let retainedRole = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!
        try AIConnectionStore.setConnectionID(deleted.id, for: deletedRole, defaults: defaults)
        try AIConnectionStore.setConnectionID(retained.id, for: retainedRole, defaults: defaults)

        deleteWithoutRequiringKeychain(deleted.id)

        XCTAssertNil(AIConnectionStore.connection(id: deleted.id, defaults: defaults))
        XCTAssertEqual(
            AIConnectionStore.defaultConnectionID(defaults: defaults),
            AIConnectionStore.legacyConnectionID
        )
        XCTAssertNil(
            AIConnectionStore.explicitConnectionID(for: deletedRole, defaults: defaults)
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: deletedRole, defaults: defaults),
            AIConnectionStore.legacyConnectionID
        )
        XCTAssertEqual(
            AIConnectionStore.explicitConnectionID(for: retainedRole, defaults: defaults),
            retained.id
        )
        XCTAssertEqual(
            AIConnectionStore.selectedConnectionID(for: retainedRole, defaults: defaults),
            retained.id
        )

        // Reusing the deleted UUID makes stale raw defaults observable without
        // depending on AIConnectionStore's private UserDefaults key names.
        let recreated = makeProfile(
            id: deleted.id,
            displayName: "同 UUID 的新连接",
            createdAt: date(900)
        )
        try AIConnectionStore.save(recreated, defaults: defaults)
        XCTAssertEqual(
            AIConnectionStore.defaultConnectionID(defaults: defaults),
            AIConnectionStore.legacyConnectionID
        )
        XCTAssertNil(
            AIConnectionStore.explicitConnectionID(for: deletedRole, defaults: defaults)
        )
    }

    func testResolvedLegacyConnectionUsesInjectedLegacyKeyLoader() throws {
        defaults.set(ProviderPreset.deepSeek.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("https://legacy.example/v1", forKey: SettingsKeys.baseURL)
        defaults.set("legacy-model", forKey: SettingsKeys.model)
        defaults.set("legacy-embedding", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.42, forKey: SettingsKeys.temperature)
        defaults.set(true, forKey: SettingsKeys.streamResponses)

        var loaderCallCount = 0
        let resolved = try AIConnectionStore.resolvedConnection(
            for: UUID(uuidString: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")!,
            defaults: defaults,
            legacyKeyLoader: {
                loaderCallCount += 1
                return "legacy-secret"
            }
        )

        XCTAssertEqual(loaderCallCount, 1)
        XCTAssertEqual(resolved.profile.id, AIConnectionStore.legacyConnectionID)
        XCTAssertEqual(resolved.credential, "legacy-secret")
        XCTAssertEqual(resolved.configuration.baseURL, "https://legacy.example/v1")
        XCTAssertEqual(resolved.configuration.model, "legacy-model")
    }

    func testSubscriptionWithoutCredentialThrowsMissingCredential() throws {
        let subscription = makeProfile(
            id: UUID(uuidString: "99999999-9999-4999-8999-999999999999")!,
            displayName: "订阅连接",
            kind: .chatGPTSubscription,
            providerID: ProviderPreset.openAI.rawValue,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5",
            createdAt: date(1_000)
        )
        try AIConnectionStore.save(subscription, defaults: defaults)
        try AIConnectionStore.setDefaultConnectionID(subscription.id, defaults: defaults)

        var legacyLoaderCalled = false
        XCTAssertThrowsError(
            try AIConnectionStore.resolvedConnection(
                for: UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!,
                defaults: defaults,
                legacyKeyLoader: {
                    legacyLoaderCalled = true
                    return "should-not-be-used"
                }
            )
        ) { error in
            XCTAssertEqual(error as? AIConnectionStoreError, .missingCredential)
        }
        XCTAssertFalse(legacyLoaderCalled)
    }

    private func makeProfile(
        id: UUID,
        displayName: String,
        kind: AIConnectionProfile.Kind = .apiKey,
        providerID: String = "custom",
        baseURL: String = "https://example.test/v1",
        model: String = "test-model",
        embeddingModel: String = "",
        temperature: Double = 0.2,
        streamsResponses: Bool = true,
        createdAt: Date
    ) -> AIConnectionProfile {
        AIConnectionProfile(
            id: id,
            displayName: displayName,
            kind: kind,
            providerID: providerID,
            baseURL: baseURL,
            model: model,
            embeddingModel: embeddingModel,
            temperature: temperature,
            streamsResponses: streamsResponses,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func deleteWithoutRequiringKeychain(_ id: UUID) {
        do {
            try AIConnectionStore.delete(id: id, defaults: defaults)
        } catch is KeychainStoreError {
            // Keychain availability is outside this UserDefaults-only test.
        } catch {
            XCTFail("Deleting a persisted connection failed before UserDefaults cleanup: \(error)")
        }
    }
}
