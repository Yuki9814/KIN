import XCTest

@testable import Ayane

final class GroupResponseCoordinatorTokenBoundaryTests: XCTestCase {
    func testNameMentionsRequireCompleteTokenBoundaries() {
        let ids = makeIDs(2)
        let members = [
            GroupResponseCoordinator.Member(roleID: ids[0], displayName: "安"),
            GroupResponseCoordinator.Member(roleID: ids[1], displayName: "安娜")
        ]
        let coordinator = GroupResponseCoordinator()

        XCTAssertEqual(
            coordinator.mentionedRoleIDs(in: "请 @安 回答", members: members),
            [ids[0]]
        )
        XCTAssertEqual(
            coordinator.mentionedRoleIDs(in: "请 @安娜 回答", members: members),
            [ids[1]]
        )
        XCTAssertTrue(
            coordinator.mentionedRoleIDs(in: "请 @安娜们 回答", members: members).isEmpty
        )
        XCTAssertTrue(
            coordinator.mentionedRoleIDs(in: "mail@安娜.example", members: members).isEmpty
        )
    }

    func testExplicitRoleIDsDisambiguateDuplicateNames() {
        let ids = makeIDs(2)
        let members = [
            GroupResponseCoordinator.Member(roleID: ids[0], displayName: "绫音", order: 0),
            GroupResponseCoordinator.Member(roleID: ids[1], displayName: "绫音", order: 1)
        ]
        let coordinator = GroupResponseCoordinator()

        XCTAssertEqual(
            coordinator.responseOrder(
                members: members,
                message: "@绫音",
                explicitlyMentionedRoleIDs: [ids[1]]
            ),
            [ids[1]]
        )
    }

    private func makeIDs(_ count: Int) -> [UUID] {
        (1...count).map {
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))!
        }
    }
}
