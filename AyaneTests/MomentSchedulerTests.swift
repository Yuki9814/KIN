import XCTest
@testable import Ayane

final class MomentSchedulerTests: XCTestCase {
    private let roleA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let roleB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testRecordDefaultsAndRoleSummaryStayScoped() {
        let task = CompanionMomentTaskRecord(
            roleID: roleA,
            instruction: "写一句晚安",
            scheduledAt: date(100)
        )

        XCTAssertEqual(task.state, .scheduled)
        XCTAssertEqual(task.resolvedRoleID, roleA)
        XCTAssertEqual(task.summary.roleID, roleA)
        XCTAssertEqual(task.summary.resolvedRoleID, roleA)
        XCTAssertEqual(task.summary.instruction, "写一句晚安")
        XCTAssertEqual(task.attemptCount, 0)
        XCTAssertEqual(task.leaseOwner, "")
        XCTAssertNil(task.leaseExpiresAt)
    }

    func testClaimIsDueLeaseBoundAndIdempotentPerOwner() {
        let scheduler = MomentScheduler(leaseDuration: 10)
        let task = MomentTaskSnapshot(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            roleID: roleA,
            instruction: "写一句早安",
            scheduledAt: date(100),
            createdAt: date(90),
            updatedAt: date(90)
        )

        XCTAssertFalse(scheduler.isDue(task, now: date(99)))
        XCTAssertEqual(scheduler.claim(task, owner: "worker-a", now: date(99)).action, .notDue)

        let first = scheduler.claim(task, owner: "worker-a", now: date(100))
        XCTAssertEqual(first.action, .claimed)
        XCTAssertEqual(first.after.roleID, roleA)
        XCTAssertEqual(first.after.state, .running)
        XCTAssertEqual(first.after.attemptCount, 1)
        XCTAssertEqual(first.after.leaseOwner, "worker-a")
        XCTAssertEqual(first.after.leaseExpiresAt, date(110))

        let sameOwner = scheduler.claim(first.after, owner: " worker-a ", now: date(101))
        XCTAssertEqual(sameOwner.action, .leaseHeld)
        XCTAssertEqual(sameOwner.after, first.after)

        let otherOwner = scheduler.claim(first.after, owner: "worker-b", now: date(101))
        XCTAssertEqual(otherOwner.action, .leaseHeld)
        XCTAssertEqual(otherOwner.after.roleID, roleA)
        XCTAssertEqual(otherOwner.after.leaseOwner, "worker-a")

        let otherRole = MomentTaskSnapshot(
            id: first.after.id,
            roleID: roleB,
            instruction: first.after.instruction,
            scheduledAt: first.after.scheduledAt
        )
        let roleBClaim = scheduler.claim(otherRole, owner: "worker-b", now: date(100))
        XCTAssertEqual(roleBClaim.action, .claimed)
        XCTAssertEqual(roleBClaim.after.roleID, roleB)
    }

    func testFailureReleasesForRetryAndPublishedTaskIsIdempotent() {
        let scheduler = MomentScheduler(leaseDuration: 20)
        let task = MomentTaskSnapshot(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            roleID: roleA,
            instruction: "记录今天的光",
            scheduledAt: date(200),
            createdAt: date(190),
            updatedAt: date(190)
        )

        let claimed = scheduler.claim(task, owner: "worker-a", now: date(200)).after
        let released = scheduler.release(
            claimed,
            owner: "worker-a",
            error: "生成失败",
            now: date(201)
        )
        XCTAssertEqual(released.action, .released)
        XCTAssertEqual(released.after.state, .scheduled)
        XCTAssertEqual(released.after.attemptCount, 1)
        XCTAssertEqual(released.after.lastError, "生成失败")
        XCTAssertEqual(released.after.roleID, roleA)
        XCTAssertNil(released.after.leaseExpiresAt)

        let retried = scheduler.claim(released.after, owner: "worker-a", now: date(202)).after
        XCTAssertEqual(retried.attemptCount, 2)
        let published = scheduler.publish(
            retried,
            owner: "worker-a",
            resultText: "今天也留一点光给自己。",
            now: date(203)
        )
        XCTAssertEqual(published.action, .published)
        XCTAssertEqual(published.after.state, .published)
        XCTAssertEqual(published.after.resultText, "今天也留一点光给自己。")
        XCTAssertEqual(published.after.publishedAt, date(203))
        XCTAssertEqual(published.after.roleID, roleA)
        XCTAssertEqual(published.after.leaseOwner, "")

        let duplicate = scheduler.publish(
            published.after,
            owner: "worker-b",
            resultText: "不应覆盖",
            now: date(204)
        )
        XCTAssertEqual(duplicate.action, .alreadyPublished)
        XCTAssertEqual(duplicate.after, published.after)
        XCTAssertFalse(duplicate.shouldPublish)
    }

    func testUnknownPersistedStateFailsClosedToCancelled() {
        let task = CompanionMomentTaskRecord(
            roleID: roleB,
            stateRaw: "future-terminal-state"
        )

        XCTAssertEqual(task.state, .cancelled)
        XCTAssertEqual(task.resolvedRoleID, roleB)
    }
}
