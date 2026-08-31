import Foundation
import XCTest
@testable import Ayane

final class MemoryAffinityCoreV2Tests: XCTestCase {
    func testMemoryPolicyUsesIntentBudgetsAndConversationContext() {
        let policy = MemoryRetrievalPolicy()
        let identity = policy.plan(for: "你还记得我叫什么吗")
        let casual = policy.plan(for: "今天挺好")
        let contextual = policy.plan(
            for: "它呢",
            recentUserMessages: ["我之前说过最喜欢乌龙茶"]
        )
        let group = policy.plan(for: "我最喜欢什么", isGroupChat: true)

        XCTAssertEqual(identity.intent, .identity)
        XCTAssertGreaterThan(identity.options.maxResults, casual.options.maxResults)
        XCTAssertTrue(identity.options.allowHighValueFallback)
        XCTAssertGreaterThanOrEqual(contextual.queryVariants.count, 2)
        XCTAssertFalse(group.allowsSensitiveMemory)
    }

    func testMemoryPolicySuppressesSensitiveMemoriesInGroups() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let memories = [
            MemorySnapshot(
                id: "public",
                text: "用户喜欢乌龙茶",
                createdAt: now,
                importance: 0.9,
                confidence: 1,
                isPinned: true
            ),
            MemorySnapshot(
                id: "sensitive",
                text: "用户喜欢乌龙茶，但这是一条私密信息",
                createdAt: now,
                importance: 1,
                confidence: 1,
                isPinned: true,
                isSensitive: true
            ),
        ]

        let results = MemoryRetrievalPolicy().retrieve(
            for: "我喜欢什么茶",
            from: memories,
            isGroupChat: true,
            now: now
        )

        XCTAssertEqual(results.map(\.id), ["public"])
    }

    func testAffinityProgressionIsIdempotentAndUsesDiminishingReturns() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let zone = TimeZone(secondsFromGMT: 0)!
        let firstEvent = AffinityProgressionPolicy.event(
            forMessage: "谢谢你",
            sourceEventID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            occurredAt: date
        )
        let initial = AffinityLedgerState(
            dimensions: .seeded(fromLegacyScore: 20)
        )
        let first = AffinityProgressionPolicy.applying(firstEvent, to: initial, timeZone: zone)
        let duplicate = AffinityProgressionPolicy.applying(firstEvent, to: first.state, timeZone: zone)
        let repeatedEvent = AffinityProgressionPolicy.event(
            forMessage: "谢谢你",
            sourceEventID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            occurredAt: date.addingTimeInterval(1)
        )
        let repeated = AffinityProgressionPolicy.applying(
            repeatedEvent,
            to: first.state,
            timeZone: zone
        )

        XCTAssertGreaterThan(first.change.legacyScoreDelta, 0)
        XCTAssertTrue(duplicate.change.wasDuplicate)
        XCTAssertEqual(duplicate.change.legacyScoreDelta, 0)
        XCTAssertLessThan(
            repeated.change.repetitionMultiplier,
            first.change.repetitionMultiplier
        )
        XCTAssertGreaterThan(repeated.change.legacyScoreDelta, 0)
        XCTAssertLessThan(repeated.change.legacyScoreDelta, first.change.legacyScoreDelta)
    }

    func testAffinityCapsPositiveGainButKeepsNegativeEvents() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var state = AffinityLedgerState(
            dimensions: .seeded(fromLegacyScore: 30)
        )
        var reachedCap = false

        for index in 0..<20 {
            let event = AffinityEvent(
                idempotencyKey: "positive:\(index)",
                kind: .sharedMilestone,
                occurredAt: date.addingTimeInterval(Double(index)),
                fingerprint: "milestone:\(index)"
            )
            let result = AffinityProgressionPolicy.applying(event, to: state, timeZone: zone)
            state = result.state
            reachedCap = reachedCap || result.change.reachedDailyPositiveCap
        }

        XCTAssertLessThanOrEqual(
            state.positiveGainToday,
            AffinityProgressionPolicy.dailyPositiveCap + 0.000_001
        )
        XCTAssertTrue(reachedCap)

        let rejection = AffinityEvent(
            idempotencyKey: "negative:1",
            kind: .rejection,
            occurredAt: date.addingTimeInterval(60)
        )
        let negative = AffinityProgressionPolicy.applying(rejection, to: state, timeZone: zone)
        XCTAssertLessThan(negative.change.legacyScoreDelta, 0)
    }
}
