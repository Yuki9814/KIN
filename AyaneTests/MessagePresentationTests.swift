import XCTest
@testable import Ayane

final class MessagePresentationTests: XCTestCase {
    func testChatTimeLabelsPreserveElapsedDayContext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 29,
            hour: 21,
            minute: 14
        )))
        let today = try XCTUnwrap(calendar.date(byAdding: .minute, value: -12, to: now))
        let fiveDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))

        XCTAssertEqual(
            ChatView.messageTimeLabel(for: today, relativeTo: now, calendar: calendar),
            "今天 21:02"
        )
        XCTAssertEqual(
            ChatView.messageTimeLabel(for: fiveDaysAgo, relativeTo: now, calendar: calendar),
            "5天前"
        )
    }

    func testTypingIndicatorTitleRequiresBothSettingAndGeneration() {
        XCTAssertEqual(
            ChatView.navigationTitle(
                personaName: "绫音",
                isGenerating: true,
                typingIndicatorEnabled: true
            ),
            "正在输入中…"
        )
        XCTAssertEqual(
            ChatView.navigationTitle(
                personaName: "绫音",
                isGenerating: true,
                typingIndicatorEnabled: false
            ),
            "绫音"
        )
        XCTAssertEqual(
            ChatView.navigationTitle(
                personaName: "绫音",
                isGenerating: false,
                typingIndicatorEnabled: true
            ),
            "绫音"
        )
    }

    func testStickerLabelStaysOnTheSingleConversationEventAccessibilityElement() {
        let label = MessageBubble.makeAccessibilityText(
            role: .assistant,
            content: "别怕，我在这里。",
            state: .complete,
            companionName: "绫音",
            stickerLabel: "安慰的 Q 版角色表情"
        )

        XCTAssertEqual(label, "绫音的消息：别怕，我在这里。，安慰的 Q 版角色表情")
    }

    func testAccessibilityTextDoesNotAddStickerWhenDecorationIsAbsent() {
        let label = MessageBubble.makeAccessibilityText(
            role: .user,
            content: "今天想散步。",
            state: .complete,
            companionName: "绫音"
        )

        XCTAssertEqual(label, "你的消息：今天想散步。")
    }

    func testCancelledVisiblePrefixDoesNotExposeTechnicalStopStatus() {
        let label = MessageBubble.makeAccessibilityText(
            role: .assistant,
            content: "我刚才已经发出的这一句。",
            state: .cancelled,
            companionName: "绫音"
        )

        XCTAssertEqual(label, "绫音的消息：我刚才已经发出的这一句。")
        XCTAssertFalse(label.contains("已停止"))
    }
}
