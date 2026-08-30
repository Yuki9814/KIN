import Foundation
import XCTest
@testable import Ayane

final class GroupTurnPlannerPreferencesTests: XCTestCase {
    func testConversationPreferencesDriveStrategyLimitPromptModeAndPrivacy() throws {
        let suiteName = "GroupTurnPlannerPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let conversationID = UUID()
        try InteractionCorePreferencesStore.saveGroupPreferences(
            GroupInteractionPreferences(
                strategyRaw: "natural",
                promptAssemblyModeRaw: "joinCharacterCards",
                maximumAutomaticResponders: 1,
                allowSensitiveMemory: true
            ),
            conversationID: conversationID,
            defaults: defaults
        )
        let members = [
            GroupTurnMember(
                roleID: UUID(),
                displayName: "甲",
                order: 0,
                topicRelevance: 0.9,
                personalityFit: 0.9,
                affinityScore: 90,
                talkativeness: 0.9
            ),
            GroupTurnMember(
                roleID: UUID(),
                displayName: "乙",
                order: 1,
                topicRelevance: 0.8,
                personalityFit: 0.8,
                affinityScore: 80,
                talkativeness: 0.8
            )
        ]

        let result = GroupTurnPlanner().plan(
            members: members,
            message: "大家怎么看？",
            conversationID: conversationID,
            defaults: defaults
        )

        XCTAssertEqual(result.plan.selections.count, 1)
        XCTAssertEqual(result.promptAssemblyMode, .joinCharacterCards)
        XCTAssertTrue(result.allowsSensitiveMemory)
    }

    func testMissingPreferencesUseSafeDefaults() {
        let suiteName = "GroupTurnPlannerPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let result = GroupTurnPlanner().plan(
            members: [
                GroupTurnMember(
                    roleID: UUID(),
                    displayName: "甲",
                    order: 0,
                    topicRelevance: 1,
                    personalityFit: 1,
                    affinityScore: 100
                )
            ],
            message: "继续",
            conversationID: UUID(),
            defaults: defaults
        )

        XCTAssertEqual(result.promptAssemblyMode, .swapActiveCharacter)
        XCTAssertFalse(result.allowsSensitiveMemory)
    }
}
