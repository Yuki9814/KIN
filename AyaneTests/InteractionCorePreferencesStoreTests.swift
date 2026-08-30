import Foundation
import XCTest
@testable import Ayane

final class InteractionCorePreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "InteractionCorePreferencesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGroupDefaultsArePrivateNaturalAndBounded() {
        let preferences = InteractionCorePreferencesStore.groupPreferences(
            conversationID: UUID(),
            defaults: defaults
        )

        XCTAssertEqual(preferences.strategyRaw, "natural")
        XCTAssertEqual(preferences.promptAssemblyModeRaw, "swapActiveCharacter")
        XCTAssertEqual(preferences.maximumAutomaticResponders, 2)
        XCTAssertFalse(preferences.allowSensitiveMemory)
    }

    func testGroupPreferencesRoundTripAndStayConversationScoped() throws {
        let firstID = UUID()
        let secondID = UUID()
        let configured = GroupInteractionPreferences(
            strategyRaw: "manual",
            promptAssemblyModeRaw: "joinCharacterCards",
            maximumAutomaticResponders: 4,
            allowSensitiveMemory: true
        )

        try InteractionCorePreferencesStore.saveGroupPreferences(
            configured,
            conversationID: firstID,
            defaults: defaults
        )

        XCTAssertEqual(
            InteractionCorePreferencesStore.groupPreferences(
                conversationID: firstID,
                defaults: defaults
            ),
            configured
        )
        XCTAssertEqual(
            InteractionCorePreferencesStore.groupPreferences(
                conversationID: secondID,
                defaults: defaults
            ),
            .defaultValue
        )
    }

    func testInvalidGroupValuesNormalizeBeforePersistence() throws {
        let conversationID = UUID()
        let invalid = GroupInteractionPreferences(
            schemaVersion: 0,
            strategyRaw: "unknown",
            promptAssemblyModeRaw: "all-cards-always",
            maximumAutomaticResponders: 99,
            allowSensitiveMemory: false
        )

        try InteractionCorePreferencesStore.saveGroupPreferences(
            invalid,
            conversationID: conversationID,
            defaults: defaults
        )
        let stored = InteractionCorePreferencesStore.groupPreferences(
            conversationID: conversationID,
            defaults: defaults
        )

        XCTAssertEqual(stored.schemaVersion, 1)
        XCTAssertEqual(stored.strategyRaw, "natural")
        XCTAssertEqual(stored.promptAssemblyModeRaw, "swapActiveCharacter")
        XCTAssertEqual(stored.maximumAutomaticResponders, 4)
    }

    func testImagePreferencesRoundTripClampAndConnectionIsolation() throws {
        let firstConnectionID = UUID()
        let secondConnectionID = UUID()
        let longNegativePrompt = String(repeating: "x", count: 2_500)
        let configured = ImageInteractionPreferences(
            imageCount: 8,
            aspectRatioRaw: "tallPortrait",
            qualityRaw: "high",
            styleRaw: "animeCG",
            preserveCharacterIdentity: false,
            negativePrompt: longNegativePrompt,
            maximumRetries: 20
        )

        try InteractionCorePreferencesStore.saveImagePreferences(
            configured,
            connectionID: firstConnectionID,
            defaults: defaults
        )
        let stored = InteractionCorePreferencesStore.imagePreferences(
            connectionID: firstConnectionID,
            defaults: defaults
        )

        XCTAssertEqual(stored.imageCount, 4)
        XCTAssertEqual(stored.aspectRatioRaw, "tallPortrait")
        XCTAssertEqual(stored.qualityRaw, "high")
        XCTAssertEqual(stored.styleRaw, "animeCG")
        XCTAssertFalse(stored.preserveCharacterIdentity)
        XCTAssertEqual(stored.negativePrompt.count, 2_000)
        XCTAssertEqual(stored.maximumRetries, 3)
        XCTAssertEqual(
            InteractionCorePreferencesStore.imagePreferences(
                connectionID: secondConnectionID,
                defaults: defaults
            ),
            .defaultValue
        )
        XCTAssertEqual(
            InteractionCorePreferencesStore.imagePreferences(
                connectionID: nil,
                defaults: defaults
            ),
            .defaultValue
        )
    }

    func testCorruptPayloadFailsClosedToDefaultsAndClearRestoresDefaults() throws {
        let conversationID = UUID()
        let configured = GroupInteractionPreferences(strategyRaw: "pooled")
        try InteractionCorePreferencesStore.saveGroupPreferences(
            configured,
            conversationID: conversationID,
            defaults: defaults
        )
        XCTAssertEqual(
            InteractionCorePreferencesStore.groupPreferences(
                conversationID: conversationID,
                defaults: defaults
            ).strategyRaw,
            "pooled"
        )

        InteractionCorePreferencesStore.clearGroupPreferences(
            conversationID: conversationID,
            defaults: defaults
        )
        XCTAssertEqual(
            InteractionCorePreferencesStore.groupPreferences(
                conversationID: conversationID,
                defaults: defaults
            ),
            .defaultValue
        )
    }
}
