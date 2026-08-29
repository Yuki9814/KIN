import XCTest
@testable import Ayane

final class RelationshipStateMachineTests: XCTestCase {
    private let machine = RelationshipStateMachine()

    func testApplicationAcceptsBenignTextAndRejectsObviousHarm() {
        let accepted = machine.reduce(
            machine.initialState,
            event: .application(text: "你好，我想认识你")
        )
        XCTAssertEqual(accepted.to, .accepted)
        XCTAssertEqual(accepted.reasonCode, .applicationAccepted)

        let rejected = machine.reduce(
            machine.initialState,
            event: .application(text: "滚开，你这个废物")
        )
        XCTAssertEqual(rejected.to, .rejected)
        XCTAssertEqual(rejected.reasonCode, .applicationRejectedForHarm)
        XCTAssertTrue(rejected.assessment.isPotentiallyHarmful)
    }

    func testOnlyUserTextIsScored() {
        let state = RelationshipStateMachine.State(state: .accepted)
        let decision = machine.reduce(
            state,
            event: RelationshipEvent(
                kind: .message,
                text: "shut up, idiot",
                role: .assistant
            )
        )
        XCTAssertEqual(decision.to, .accepted)
        XCTAssertEqual(decision.after.harmStreak, 0)
        XCTAssertEqual(decision.after.hurtScore, 0)
        XCTAssertEqual(decision.reasonCode, .ignoredNonUserText)
    }

    func testContinuousHarmDeletesAcceptedRelationship() {
        var state = RelationshipStateMachine.State(state: .accepted)
        for _ in 0..<2 {
            state = machine.reduce(state, event: .userMessage("滚开" )).after
            XCTAssertEqual(state.relationshipState, .accepted)
        }
        let final = machine.reduce(state, event: .userMessage("滚开"))
        XCTAssertEqual(final.to, .deleted)
        XCTAssertEqual(final.reasonCode, .harmThresholdReached)
    }

    func testBenignMessageBreaksHarmStreak() {
        var state = RelationshipStateMachine.State(state: .accepted)
        state = machine.reduce(state, event: .userMessage("滚开")).after
        XCTAssertEqual(state.harmStreak, 1)

        state = machine.reduce(state, event: .userMessage("今天想和你好好说话")).after
        XCTAssertEqual(state.relationshipState, .accepted)
        XCTAssertEqual(state.harmStreak, 0)

        state = machine.reduce(state, event: .userMessage("滚开")).after
        XCTAssertEqual(state.relationshipState, .accepted)
        XCTAssertEqual(state.harmStreak, 1)
    }

    func testApologiesRecoverRejectedRelationshipAfterThreshold() {
        let rejected = RelationshipStateMachine.State(state: .rejected)
        let waiting = machine.reduce(rejected, event: .recoveryRequest("对不起，我错了"))
        XCTAssertEqual(waiting.to, .recoveryPending)
        XCTAssertEqual(waiting.after.apologyAttempts, 1)

        let recovered = machine.reduce(waiting.after, event: .recoveryRequest("请原谅我"))
        XCTAssertEqual(recovered.to, .accepted)
        XCTAssertEqual(recovered.reasonCode, .recoveryAccepted)
        XCTAssertEqual(recovered.after.harmStreak, 0)
    }

    func testHarmDuringRecoveryBlocksRelationship() {
        let waiting = RelationshipStateMachine.State(state: .recoveryPending)
        let decision = machine.reduce(waiting, event: .userMessage("你这个垃圾"))
        XCTAssertEqual(decision.to, .blocked)
        XCTAssertEqual(decision.reasonCode, .recoveryBlockedForHarm)
    }

    func testHighDignityAndIndependenceIncreaseSensitivity() {
        let state = RelationshipStateMachine.State(
            state: .accepted,
            harmThreshold: 3,
            dignity: 1,
            independence: 1,
            boundarySensitivity: 0
        )
        let first = machine.reduce(state, event: .userMessage("滚开"))
        let second = machine.reduce(first.after, event: .userMessage("滚开"))
        XCTAssertEqual(second.to, .deleted)
        XCTAssertGreaterThanOrEqual(second.after.boundarySensitivity, 1)
    }
}
