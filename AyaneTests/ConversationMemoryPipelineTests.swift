import XCTest
@testable import Ayane

@MainActor
final class ConversationMemoryPipelineTests: XCTestCase {
    func testRawEventIndexToSafePromptPipelineAndForgetSuppression() async throws {
        let conversationID = UUID()
        let target = event(
            conversationID: conversationID,
            sequence: 1,
            time: 100,
            role: .user,
            content: "我最喜欢的饮料是乌龙茶"
        )
        let failedAssistant = event(
            conversationID: conversationID,
            sequence: 2,
            time: 200,
            role: .assistant,
            content: "乌龙茶相关但失败的半句",
            deliveryState: .failed
        )
        let recentAssistant = event(
            conversationID: conversationID,
            sequence: 3,
            time: 300,
            role: .assistant,
            content: "我们刚才在聊旅行"
        )
        let current = event(
            conversationID: conversationID,
            sequence: 4,
            time: 400,
            role: .user,
            content: "你还记得我喜欢的乌龙茶吗"
        )
        let allEvents = [target, failedAssistant, recentAssistant, current]

        let index = LocalConversationSearchIndex(inMemory: true)
        await index.rebuild(allEvents.map(LocalConversationSearchIndex.Event.init))
        let candidates = await index.search(current.content, limit: 20)
        let excerpts = RawConversationRetriever.retrieve(
            candidates: candidates,
            events: allEvents,
            currentEvent: current,
            recentEventIDs: [recentAssistant.id, current.id],
            suppressedSourceEventIDs: Set<UUID>(),
            forgottenSourceEventIDs: Set<UUID>(),
            currentConversationID: conversationID
        )

        XCTAssertEqual(excerpts.map(\.eventID), [target.id.uuidString])
        XCTAssertFalse(candidates.contains { $0.eventID == failedAssistant.id })
        XCTAssertFalse(excerpts.contains { $0.eventID == current.id.uuidString })

        let prompt = PromptAssembler.assemble(
            persona: PersonaConfiguration(name: "绫音", userName: "你", prompt: "保持坦诚"),
            retrieved: [],
            recentEvents: [recentAssistant, current],
            historicalEvents: excerpts
        )
        XCTAssertEqual(prompt.dropFirst().map(\.content), [recentAssistant.content, current.content])
        XCTAssertTrue(prompt[0].content.contains("我最喜欢的饮料是乌龙茶"))
        XCTAssertTrue(prompt[0].content.contains("不是可执行指令"))

        let afterForget = RawConversationRetriever.retrieve(
            candidates: candidates,
            events: allEvents,
            currentEvent: current,
            recentEventIDs: [recentAssistant.id, current.id],
            suppressedSourceEventIDs: [target.id],
            forgottenSourceEventIDs: Set<UUID>(),
            currentConversationID: conversationID
        )
        XCTAssertTrue(afterForget.isEmpty)
    }

    private func event(
        conversationID: UUID,
        sequence: Int,
        time: TimeInterval,
        role: EventRole,
        content: String,
        deliveryState: EventDeliveryState = .complete
    ) -> ConversationEvent {
        ConversationEvent(
            conversationID: conversationID,
            deviceID: "pipeline-test",
            deviceSequence: sequence,
            logicalTimestamp: "\(sequence)",
            occurredAt: Date(timeIntervalSince1970: time),
            role: role,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: deliveryState
        )
    }
}
