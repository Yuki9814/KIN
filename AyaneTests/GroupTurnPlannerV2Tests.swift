import Foundation
import XCTest
@testable import Ayane

final class GroupTurnPlannerV2Tests: XCTestCase {
    func testCoordinatorKeepsTwoCompanionMinimumForMessagePlanning() {
        let onlyID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let member = GroupResponseCoordinator.Member(
            roleID: onlyID,
            displayName: "唯一成员",
            order: 0,
            topicRelevance: 1,
            personalityFit: 1,
            affinityScore: 100
        )

        let result = GroupResponseCoordinator().responseOrder(
            members: [member],
            message: "继续",
            explicitlyMentionedRoleIDs: Set<UUID>()
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testPlannerHonorsMentionsAndManualControl() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let mutedID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
        let members = [
            GroupTurnMember(
                roleID: firstID,
                displayName: "甲",
                order: 0,
                topicRelevance: 0.95,
                personalityFit: 0.8,
                affinityScore: 80
            ),
            GroupTurnMember(
                roleID: secondID,
                displayName: "乙",
                order: 1,
                topicRelevance: 0.75,
                personalityFit: 0.7,
                affinityScore: 70
            ),
            GroupTurnMember(
                roleID: mutedID,
                displayName: "丙",
                order: 2,
                isMuted: true
            ),
        ]
        let planner = GroupTurnPlanner()
        let mentioned = planner.plan(
            members: members,
            message: "@乙 只回答这一条"
        )
        let mutedManual = planner.plan(
            members: members,
            message: "",
            context: GroupTurnPlanningContext(
                strategy: .manual,
                manuallySelectedRoleID: mutedID
            )
        )
        let forcedManual = planner.plan(
            members: members,
            message: "",
            context: GroupTurnPlanningContext(
                strategy: .manual,
                manuallySelectedRoleID: mutedID,
                forceManualSpeaker: true
            )
        )

        XCTAssertEqual(mentioned.responseOrder, [secondID])
        XCTAssertTrue(mutedManual.isEmpty)
        XCTAssertEqual(forcedManual.responseOrder, [mutedID])
        XCTAssertTrue(forcedManual.wasExplicitlyDirected)
        XCTAssertTrue(forcedManual.shouldGenerateSequentially)
    }

    func testMentionAllAndPooledFairness() {
        let ids = (21...23).map {
            UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                $0
            ))!
        }
        let names = ["甲", "乙", "丙"]
        let members = ids.enumerated().map { index, id in
            GroupTurnMember(
                roleID: id,
                displayName: names[index],
                order: index,
                topicRelevance: 0.8 - Double(index) * 0.1,
                personalityFit: 0.7,
                affinityScore: 60,
                hasSpokenSinceUserMessage: index == 0
            )
        }
        let planner = GroupTurnPlanner()
        let everyone = planner.plan(
            members: members,
            message: "@所有人 都说说"
        )
        let pooled = planner.plan(
            members: members,
            message: "继续",
            context: GroupTurnPlanningContext(strategy: .pooled)
        )

        XCTAssertEqual(everyone.responseOrder, ids)
        XCTAssertEqual(
            everyone.selections.map(\.reason),
            Array(repeating: .mentionAll, count: 3)
        )
        XCTAssertEqual(pooled.selections.count, 1)
        XCTAssertNotEqual(pooled.responseOrder.first, ids[0])
    }

    func testNaturalModeUsesAtMostConfiguredAutomaticResponders() {
        let ids = (41...44).map {
            UUID(uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                $0
            ))!
        }
        let members = ids.enumerated().map { index, id in
            GroupTurnMember(
                roleID: id,
                displayName: "成员\(index)",
                order: index,
                topicRelevance: 0.9,
                personalityFit: 0.9,
                affinityScore: 90,
                talkativeness: 0.9
            )
        }
        let plan = GroupTurnPlanner().plan(
            members: members,
            message: "大家怎么看？都来回答",
            context: GroupTurnPlanningContext(
                strategy: .natural,
                maxAutomaticResponders: 2
            )
        )

        XCTAssertEqual(plan.selections.count, 2)
        XCTAssertEqual(plan.promptAssemblyMode, .swapActiveCharacter)
        XCTAssertTrue(plan.shouldGenerateSequentially)
    }
}
