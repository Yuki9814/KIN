import Foundation
import XCTest
@testable import Ayane

@MainActor
final class RawConversationRetrieverTests: XCTestCase {
    func testRetrieveRejectsUnsafeAndOutOfScopeEvents() {
        let conversationID = UUID()
        let otherConversationID = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        let current = makeEvent(
            id: UUID(),
            conversationID: conversationID,
            role: .user,
            content: "本轮问题",
            hash: "current-hash",
            occurredAt: now
        )

        let valid = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "可以保留的历史",
            hash: "valid-hash",
            occurredAt: date(900)
        )
        let sameID = current
        let recent = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "最近消息",
            hash: "recent-hash",
            occurredAt: date(890)
        )
        let suppressed = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "已抑制来源",
            hash: "suppressed-hash",
            occurredAt: date(880)
        )
        let forgotten = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "已遗忘来源",
            hash: "forgotten-hash",
            occurredAt: date(870)
        )
        let otherConversation = makeEvent(
            conversationID: otherConversationID,
            role: .user,
            content: "另一个会话",
            hash: "other-hash",
            occurredAt: date(860)
        )
        let system = makeEvent(
            conversationID: conversationID,
            role: .system,
            content: "系统内容",
            hash: "system-hash",
            occurredAt: date(850)
        )
        let streaming = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "尚在流式传输",
            hash: "streaming-hash",
            occurredAt: date(840),
            deliveryState: .streaming
        )
        let redacted = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "红线内容",
            hash: "redacted-hash",
            occurredAt: date(830)
        )
        redacted.redacted = true
        let blank = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: " \n\t",
            hash: "blank-hash",
            occurredAt: date(820)
        )
        let future = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "未来内容",
            hash: "future-hash",
            occurredAt: date(1_100)
        )
        let sameHash = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "不同原文但同哈希",
            hash: "current-hash",
            occurredAt: date(810)
        )
        let sameContent = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: current.content,
            hash: "different-hash",
            occurredAt: date(800)
        )

        let events = [
            valid, sameID, recent, suppressed, forgotten, otherConversation, system,
            streaming, redacted, blank, future, sameHash, sameContent
        ]
        let candidates = events.map {
            LocalConversationSearchIndex.SearchCandidate(eventID: $0.id, score: 0.8)
        }

        let excerpts = RawConversationRetriever.retrieve(
            candidates: candidates,
            events: events,
            currentEvent: current,
            recentEventIDs: [recent.id],
            suppressedSourceEventIDs: [suppressed.id],
            forgottenSourceEventIDs: [forgotten.id],
            currentConversationID: conversationID,
            limit: 20
        )

        XCTAssertEqual(excerpts.map(\.eventID), [valid.id.uuidString])
    }

    func testAssistantPenaltyAndStableScoreThenTimeOrdering() {
        let conversationID = UUID()
        let current = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "当前",
            hash: "current",
            occurredAt: date(1_000)
        )
        let highUser = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "用户高分",
            hash: "high-user",
            occurredAt: date(500)
        )
        let highAssistant = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "助手高分",
            hash: "high-assistant",
            occurredAt: date(950)
        )
        let tieOlder = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "同分较旧",
            hash: "tie-older",
            occurredAt: date(100)
        )
        let tieNewer = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "同分较新",
            hash: "tie-newer",
            occurredAt: date(200)
        )

        let candidates = [
            LocalConversationSearchIndex.SearchCandidate(eventID: tieOlder.id, score: 0.5),
            LocalConversationSearchIndex.SearchCandidate(eventID: highAssistant.id, score: 1.0),
            LocalConversationSearchIndex.SearchCandidate(eventID: tieNewer.id, score: 0.5),
            LocalConversationSearchIndex.SearchCandidate(eventID: highUser.id, score: 0.8)
        ]
        let excerpts = RawConversationRetriever.retrieve(
            candidates: candidates,
            events: [tieOlder, highAssistant, tieNewer, highUser],
            currentEvent: current,
            currentConversationID: conversationID
        )

        XCTAssertEqual(excerpts.map(\.content), ["用户高分", "助手高分", "同分较新", "同分较旧"])
        XCTAssertEqual(excerpts[0].score, 0.8, accuracy: 0.000_01)
        XCTAssertEqual(excerpts[1].score, 0.65, accuracy: 0.000_01)
        XCTAssertEqual(excerpts[2].score, 0.5, accuracy: 0.000_01)
    }

    func testContentHashDeduplicatesKeepingBestEffectiveScore() {
        let conversationID = UUID()
        let current = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "当前问题",
            hash: "current",
            occurredAt: date(1_000)
        )
        let lower = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "同一个来源的旧版本",
            hash: "same-source",
            occurredAt: date(100)
        )
        let higher = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "同一个来源的高分版本",
            hash: "same-source",
            occurredAt: date(900)
        )
        let other = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "另一个来源",
            hash: "other-source",
            occurredAt: date(800)
        )

        let excerpts = RawConversationRetriever.retrieve(
            candidates: [
                .init(eventID: lower.id, score: 0.3),
                .init(eventID: higher.id, score: 0.9),
                .init(eventID: other.id, score: 0.4)
            ],
            events: [lower, higher, other],
            currentEvent: current,
            currentConversationID: conversationID
        )

        XCTAssertEqual(excerpts.count, 2)
        XCTAssertEqual(excerpts.first?.eventID, higher.id.uuidString)
        XCTAssertEqual(excerpts.first?.score ?? -1, Float(0.585), accuracy: Float(0.000_01))
        XCTAssertFalse(excerpts.dropFirst().contains { $0.eventID == lower.id.uuidString })
    }

    func testManifestIsOrderIndependentButReflectsStateAndRedaction() {
        let conversationID = UUID()
        let first = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "第一条",
            hash: "first",
            occurredAt: date(100)
        )
        let second = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "第二条",
            hash: "second",
            occurredAt: date(200)
        )

        let ordered = RawConversationRetriever.manifest(events: [first, second])
        let reversed = RawConversationRetriever.manifest(events: [second, first])
        XCTAssertEqual(ordered, reversed)

        second.deliveryStateRaw = EventDeliveryState.streaming.rawValue
        let changedDelivery = RawConversationRetriever.manifest(events: [first, second])
        XCTAssertNotEqual(ordered, changedDelivery)

        second.deliveryStateRaw = EventDeliveryState.complete.rawValue
        second.redacted = true
        let changedRedaction = RawConversationRetriever.manifest(events: [second, first])
        XCTAssertNotEqual(ordered, changedRedaction)
    }

    func testIndexableRequiresCompleteVisibleUserOrAssistantText() {
        let conversationID = UUID()
        let user = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "用户文本",
            hash: "user"
        )
        let assistant = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "助手文本",
            hash: "assistant"
        )
        XCTAssertTrue(RawConversationRetriever.isIndexable(event: user))
        XCTAssertTrue(RawConversationRetriever.isIndexable(event: assistant))

        let system = makeEvent(
            conversationID: conversationID,
            role: .system,
            content: "系统",
            hash: "system"
        )
        let streaming = makeEvent(
            conversationID: conversationID,
            role: .user,
            content: "流式",
            hash: "streaming",
            deliveryState: .streaming
        )
        let blank = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: " \n",
            hash: "blank"
        )
        let redacted = makeEvent(
            conversationID: conversationID,
            role: .assistant,
            content: "红线",
            hash: "redacted"
        )
        redacted.redacted = true

        XCTAssertFalse(RawConversationRetriever.isIndexable(event: system))
        XCTAssertFalse(RawConversationRetriever.isIndexable(event: streaming))
        XCTAssertFalse(RawConversationRetriever.isIndexable(event: blank))
        XCTAssertFalse(RawConversationRetriever.isIndexable(event: redacted))
    }

    private func makeEvent(
        id: UUID = UUID(),
        conversationID: UUID,
        role: EventRole,
        content: String,
        hash: String,
        occurredAt: Date = Date(timeIntervalSince1970: 1_000),
        deliveryState: EventDeliveryState = .complete
    ) -> ConversationEvent {
        ConversationEvent(
            id: id,
            conversationID: conversationID,
            deviceID: "test",
            deviceSequence: 1,
            logicalTimestamp: "(occurredAt.timeIntervalSince1970)",
            occurredAt: occurredAt,
            role: role,
            content: content,
            contentHash: hash,
            deliveryState: deliveryState
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
