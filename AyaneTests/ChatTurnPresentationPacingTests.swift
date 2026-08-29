import XCTest
@testable import Ayane

final class ChatTurnPresentationPacingTests: XCTestCase {
    func testOrdinarySentencesKeepEveryNaturalBoundary() {
        let input = "第一句内容。第二句内容！第三句内容？"

        XCTAssertEqual(
            ChatTurnPresentationService().segments(for: input),
            ["第一句内容。", "第二句内容！", "第三句内容？"]
        )
    }

    func testParagraphBoundaryRemainsLosslessWithoutMergingFollowingSentence() {
        let input = "第一段没有句号\n\n第二段先说一句。第二段再说一句。"
        let segments = ChatTurnPresentationService().segments(for: input)

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.joined(), input)
        XCTAssertTrue(segments[1].hasPrefix("\n\n"))
        XCTAssertEqual(segments[1], "\n\n第二段先说一句。")
        XCTAssertEqual(segments[2], "第二段再说一句。")
    }

    func testCodeAndStructuredListRemainOneDisplayUnit() {
        let service = ChatTurnPresentationService()

        XCTAssertEqual(
            service.segments(for: "```swift\nlet answer = 42\nreturn answer\n```").count,
            1
        )
        XCTAssertEqual(
            service.segments(for: "1. 第一步\n2. 第二步\n3. 第三步").count,
            1
        )
    }

    func testHumanizedPacingUsesInitialRangeAndCurrentSegmentLength() async {
        let recorder = DelayRecorder()
        let service = ChatTurnPresentationService(
            configuration: .init(firstDelayRange: 3...5),
            sleeper: { seconds in recorder.record(seconds) },
            randomUnit: { 0.5 }
        )
        let input = String(repeating: "甲", count: 10) + "。"
            + String(repeating: "乙", count: 30) + "。"
            + String(repeating: "丙", count: 50) + "。"

        let result = await service.present(text: input, onSegment: { _ in })

        XCTAssertFalse(result.isCancelled)
        XCTAssertEqual(recorder.values.count, 3)
        XCTAssertEqual(recorder.values[0], 4, accuracy: 0.000_001)
        XCTAssertEqual(recorder.values[1], 3.05, accuracy: 0.000_001)
        XCTAssertEqual(recorder.values[2], 4, accuracy: 0.000_001)
    }

    func testDisabledPacingShowsFirstImmediatelyAndUsesFixedContinuationDelay() async {
        let recorder = DelayRecorder()
        let service = ChatTurnPresentationService(
            sleeper: { seconds in recorder.record(seconds) },
            randomUnit: { 0 }
        )
        let input = "第一段。第二段。第三段。"

        let result = await service.present(
            text: input,
            firstDelayEnabled: false,
            onSegment: { _ in }
        )

        XCTAssertFalse(result.isCancelled)
        XCTAssertEqual(result.displayedSegments.count, 3)
        XCTAssertEqual(recorder.values, [1.2, 1.2])
    }

    func testContinuationDelayClampsAndCountsExtendedGraphemes() {
        XCTAssertEqual(
            ChatTurnPresentationService.continuationDelay(
                for: String(repeating: "字", count: 1),
                humanized: true
            ),
            1.55,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ChatTurnPresentationService.continuationDelay(
                for: String(repeating: "字", count: 100),
                humanized: true
            ),
            4,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ChatTurnPresentationService.continuationDelay(
                for: "👨‍👩‍👧‍👦",
                humanized: true
            ),
            1.55,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ChatTurnPresentationService.continuationDelay(
                for: "任意文本",
                humanized: false
            ),
            1.2,
            accuracy: 0.000_001
        )
    }
}

private final class DelayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TimeInterval] = []

    var values: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func record(_ value: TimeInterval) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
