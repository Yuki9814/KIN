import XCTest
@testable import Ayane

final class MessageBubbleSegmenterTests: XCTestCase {
    func testChineseSentenceBoundariesKeepPunctuation() {
        let input = "第一段先把事情说明白，然后补充一个足够长的背景。第二段继续说明现在的选择，并给出下一步的安排。第三段收束今天的结论。"

        let segments = MessageBubbleSegmenter.segments(for: input)

        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertEqual(segments.joined(), input.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertTrue(segments.allSatisfy { $0.count <= MessageBubbleSegmenter.hardMaximumLength })
        XCTAssertTrue(segments.allSatisfy { $0.last.map(isChineseSentencePunctuation) ?? false })
    }

    func testEnglishPunctuationAndDecimalDoNotSplitInsideNumber() {
        let input = "The first update is ready, and version 3.14 remains unchanged. The second update explains what happens next! Please review it before lunch?"

        let segments = MessageBubbleSegmenter.segment(input)

        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertEqual(segments.joined(), input)
        XCTAssertTrue(segments.contains { $0.contains("3.14") })
        XCTAssertTrue(segments.allSatisfy { $0.count <= MessageBubbleSegmenter.hardMaximumLength })
    }

    func testLongUnpunctuatedTextUsesHardGraphemeLimit() {
        let input = String(repeating: "没有标点的连续中文文本", count: 12)

        let segments = MessageBubbleSegmenter.segments(for: input)

        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertEqual(segments.joined(), input)
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty && $0.count <= 72 })
    }

    func testWhitespaceAndConsecutiveLineBreaksCreateNoEmptyBubble() {
        let input = "  第一段内容足够长，可以在这里看到段落边界的处理。\n\n\t第二段内容也足够长，可以继续保持可读性。  "

        let segments = MessageBubbleSegmenter.segments(for: input)

        XCTAssertEqual(segments.joined(), input.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertFalse(segments.contains(where: { $0.isEmpty }))
        XCTAssertFalse(segments.contains(where: { $0.allSatisfy(\.isWhitespace) }))
        XCTAssertTrue(segments.contains { $0.contains("第一段") })
        XCTAssertTrue(segments.contains { $0.contains("第二段") })
    }

    func testWhitespaceOnlyAssistantTextProducesNoSegments() {
        XCTAssertEqual(MessageBubbleSegmenter.segments(for: " \n\t\r\n "), [])
        XCTAssertEqual(MessageBubbleSegmenter.segment(""), [])
    }

    func testUserTextRemainsOneValueEvenWhenLong() {
        let input = String(repeating: "用户消息 ", count: 40)

        XCTAssertEqual(
            MessageBubbleSegmenter.segments(for: input, role: .user),
            [input]
        )
    }

    func testEmojiAndCombiningCharactersStayIntact() {
        let family = "👨‍👩‍👧‍👦"
        let composed = "e\u{301}"
        let input = String(repeating: family + composed, count: 30) + "。最后一句。"

        let segments = MessageBubbleSegmenter.segments(for: input)

        XCTAssertEqual(segments.joined(), input)
        XCTAssertTrue(segments.allSatisfy { $0.count <= MessageBubbleSegmenter.hardMaximumLength })
        XCTAssertTrue(segments.allSatisfy { segment in
            !segment.unicodeScalars.contains(where: { $0.value == 0x200D })
                || segment.contains(family)
        })
        XCTAssertTrue(segments.joined().contains(composed))
    }

    private func isChineseSentencePunctuation(_ character: Character) -> Bool {
        character == "。" || character == "！" || character == "？" || character == "；"
    }
}
