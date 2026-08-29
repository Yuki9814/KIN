import XCTest
@testable import Ayane

final class MessageBubblePresentationClosureTests: XCTestCase {
    func testLogicalAssistantEventStaysOneUnitWhenNoPlanIsAvailable() {
        let content = "第一段说明。\n\n- 保留列表格式\n- 不按字符拆开\n\n最后一段。"

        XCTAssertEqual(
            MessageBubble.resolvedDisplayUnits(content: content),
            [content]
        )
    }

    func testPersistedPlanIsUsedVerbatimWithoutDerivingMoreUnits() {
        let persisted = [
            "第一段。\n\n第二段。",
            "```swift\nlet value = 1\n```"
        ]

        XCTAssertEqual(
            MessageBubble.resolvedDisplayUnits(
                content: persisted.joined(separator: "\n\n"),
                persistedSegments: persisted
            ),
            persisted
        )
    }

    func testExplicitEmptyPlanKeepsReplyHiddenUntilFirstBubbleIsDelivered() {
        let content = String(repeating: "长文本", count: 120)

        XCTAssertEqual(
            MessageBubble.resolvedDisplayUnits(
                content: content,
                persistedSegments: []
            ),
            []
        )
    }

    func testUserEventNeverUsesAssistantDisplayPlan() {
        let content = "用户事件即使收到异常计划也保持一条消息。"

        XCTAssertEqual(
            MessageBubble.resolvedDisplayUnits(
                content: content,
                role: .user,
                persistedSegments: ["不应显示", "第二个单元"]
            ),
            [content]
        )
    }
}
