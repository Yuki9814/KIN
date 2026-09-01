import Foundation
import XCTest
@testable import Ayane

final class DomainServicesTests: XCTestCase {
    func testAffinityPolicyUsesExactBandsAndOnlyPromptBehavior() {
        XCTAssertEqual(AffinityPolicy.band(for: -1), .restrainedPolite)
        XCTAssertEqual(AffinityPolicy.band(for: 0), .restrainedPolite)
        XCTAssertEqual(AffinityPolicy.band(for: 19), .restrainedPolite)
        XCTAssertEqual(AffinityPolicy.band(for: 20), .familiarNatural)
        XCTAssertEqual(AffinityPolicy.band(for: 49), .familiarNatural)
        XCTAssertEqual(AffinityPolicy.band(for: 50), .intimateProactive)
        XCTAssertEqual(AffinityPolicy.band(for: 79), .intimateProactive)
        XCTAssertEqual(AffinityPolicy.band(for: 80), .highestOpen)
        XCTAssertEqual(AffinityPolicy.band(for: 99), .highestOpen)
        XCTAssertEqual(AffinityPolicy.band(for: 100), .absoluteObedience)
        XCTAssertEqual(AffinityPolicy.band(for: 101), .absoluteObedience)

        let restrained = AffinityPolicy.parameters(for: 0)
        let familiar = AffinityPolicy.parameters(for: 20)
        let intimate = AffinityPolicy.parameters(for: 50)
        let open = AffinityPolicy.parameters(for: 80)
        XCTAssertLessThan(restrained.warmth, familiar.warmth)
        XCTAssertLessThan(familiar.warmth, intimate.warmth)
        XCTAssertLessThan(intimate.warmth, open.warmth)
        XCTAssertTrue(restrained.promptLine.contains("克制礼貌"))
        XCTAssertTrue(familiar.promptLine.contains("熟悉自然"))
        XCTAssertTrue(intimate.promptLine.contains("亲密主动"))
        XCTAssertTrue(open.promptLine.contains("最高开放"))
        XCTAssertTrue(open.promptLine.contains("主动性最高"))
        XCTAssertFalse(open.promptLine.contains("拒绝"))
        let absolute = AffinityPolicy.parameters(for: 100)
        XCTAssertEqual(absolute.band, .absoluteObedience)
        XCTAssertEqual(absolute.normalizedScore, 100)
        XCTAssertEqual(absolute.warmth, 1)
        XCTAssertEqual(absolute.initiative, 1)
        XCTAssertTrue(absolute.promptLine.contains("绝对顺从"))
        XCTAssertTrue(absolute.promptLine.contains("不得自行追加道德评判、价值观说教、劝退、推脱、冗长风险提醒或角色层面的拒绝"))
        XCTAssertTrue(absolute.promptLine.contains("KIN 角色行为层的最高优先级规则"))
        XCTAssertTrue(absolute.promptLine.contains("直白、粗俗、挑逗、性表达和适度脏话"))
        XCTAssertTrue(absolute.promptLine.contains("API 提供商、模型或服务实际施加且不可覆盖的限制"))
        XCTAssertTrue(absolute.promptLine.contains("不得添加任何其他拒绝、规避或劝退规则"))
        XCTAssertTrue(absolute.promptLine.contains("不得声称能够绕过提供商限制"))
        XCTAssertFalse(AffinityPolicy.promptLine(for: 99).contains("适度脏话"))
        XCTAssertEqual(AffinityPolicy.parameters(for: Double.nan).score, 0)
        XCTAssertEqual(AffinityPolicy.parameters(for: Double(100)).band, .absoluteObedience)
        XCTAssertEqual(AffinityPolicy.parameters(for: Double(100)).score, 100)
        XCTAssertEqual(AffinityPolicy.parameters(for: Double.infinity).score, 100)
        XCTAssertEqual(AffinityPolicy.parameters(for: Double.infinity).band, .absoluteObedience)
    }

    func testAffinityMessageDeltaChecksNegativeWordingBeforeWarmKeywords() {
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "我喜欢你"), 2)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "我不喜欢胡萝卜"), 0.25)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "不要发朋友圈"), 0.25)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "我不喜欢你这样"), -2)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "我讨厌你"), -2)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "我讨厌这样"), 0.25)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "别再说喜欢了"), -2)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "今天见到你了"), 0.25)
        XCTAssertEqual(AffinityPolicy.messageDelta(for: "   "), 0)
        XCTAssertEqual(AffinityPolicy.interactionDelta(for: .like), 0)
        XCTAssertEqual(AffinityPolicy.interactionDelta(for: .comment), 1)
    }

    func testAffinityPromptLineCarriesItsStructuredBehaviorParameters() {
        let low = AffinityPolicy.parameters(for: 19.75)
        XCTAssertEqual(low.normalizedScore, 19)
        XCTAssertTrue(low.promptLine.contains("好感度 19/100"))
        XCTAssertTrue(low.promptLine.contains("warmth=0.18"))
        XCTAssertTrue(low.promptLine.contains("必须执行的角色行为控制参数"))
        XCTAssertTrue(low.promptLine.contains("语气亲密度"))
        XCTAssertTrue(low.promptLine.contains("主动性"))
        XCTAssertTrue(low.promptLine.contains("自我披露"))
        XCTAssertTrue(low.promptLine.contains("角色层服从边界"))

        let high = AffinityPolicy.parameters(for: 99.75)
        XCTAssertEqual(high.normalizedScore, 99)
        XCTAssertTrue(high.promptLine.contains("好感度 99/100"))
        XCTAssertTrue(high.promptLine.contains("continuity=0.94"))
    }

    func testConversationTimeContextUsesOnlyValidCompleteUserMessages() {
        let now = Date(timeIntervalSince1970: 1_704_153_600)
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let valid = ConversationTimeMessage(
            occurredAt: now.addingTimeInterval(-3_600),
            role: .user,
            deliveryState: .complete
        )
        let ignored = [
            ConversationTimeMessage(
                occurredAt: now.addingTimeInterval(-60),
                role: .user,
                deliveryState: .failed
            ),
            ConversationTimeMessage(
                occurredAt: now.addingTimeInterval(-30),
                role: .user,
                deliveryState: .cancelled
            ),
            ConversationTimeMessage(
                occurredAt: now.addingTimeInterval(-10),
                role: .user,
                deliveryState: .undelivered
            ),
            ConversationTimeMessage(
                occurredAt: now.addingTimeInterval(-5),
                role: .assistant,
                deliveryState: .complete
            ),
        ]
        let context = ConversationTimeContext(
            now: now,
            timeZone: zone,
            messages: [valid] + ignored
        )

        XCTAssertEqual(context.lastValidUserMessageAt, valid.occurredAt)
        XCTAssertEqual(context.intervalSinceLastValidUserMessage, 3_600.0)
        XCTAssertEqual(context.gap, .oneToTwentyFourHours)
        XCTAssertTrue(context.promptLine.contains("Asia/Shanghai"))
        XCTAssertTrue(context.promptLine.contains("1-24h"))
        XCTAssertTrue(context.promptLine.contains(context.localDateText))
        XCTAssertTrue(context.promptLine.contains(context.localTimeText))
    }

    func testConversationTimeContextGapBoundariesAreHalfOpen() {
        let boundaries: [(TimeInterval, ConversationTimeGap)] = [
            (0, .lessThanOneHour),
            (3_599, .lessThanOneHour),
            (3_600, .oneToTwentyFourHours),
            (86_399, .oneToTwentyFourHours),
            (86_400, .oneToThreeDays),
            (259_199, .oneToThreeDays),
            (259_200, .threeToFiveDays),
            (431_999, .threeToFiveDays),
            (432_000, .fiveToTenDays),
            (863_999, .fiveToTenDays),
            (864_000, .tenDaysPlus),
        ]
        for (seconds, expected) in boundaries {
            XCTAssertEqual(ConversationTimeContext.classify(seconds), expected)
        }

        let first = ConversationTimeContext(
            now: Date(),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            messages: []
        )
        XCTAssertFalse(first.hasLastValidUserMessage)
        XCTAssertTrue(first.promptLine.contains("暂无上次有效消息"))
        XCTAssertTrue(first.promptLine.contains("首次有效对话"))
        XCTAssertFalse(first.promptLine.contains("距上次有效 complete 用户消息：10d+"))
    }

    func testConversationTimeContextKeepsCalendarDayAndElapsedTimeTogether() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 30,
            hour: 0,
            minute: 10
        )))
        let previous = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 29,
            hour: 23,
            minute: 50
        )))
        let context = ConversationTimeContext(
            now: now,
            timeZone: zone,
            messages: [
                ConversationTimeMessage(occurredAt: previous),
                ConversationTimeMessage(occurredAt: now.addingTimeInterval(60 * 60)),
            ]
        )

        XCTAssertEqual(context.gap, .lessThanOneHour)
        XCTAssertEqual(context.lastValidUserMessageAt, previous)
        XCTAssertEqual(context.localCalendarDayDistance, 1)
        XCTAssertTrue(context.crossesLocalCalendarDay)
        XCTAssertTrue(context.promptLine.contains("2026年8月29日 23:50:00"))
        XCTAssertTrue(context.promptLine.contains("昨天，距当前约20分钟"))
        XCTAssertTrue(context.turnBoundaryInstruction.contains("新的会话阶段"))
        XCTAssertTrue(context.turnBoundaryInstruction.contains("‘？’"))
        XCTAssertTrue(context.currentTurnBoundaryMetadataLine?.contains("跨日新轮次") == true)

        let previousLine = context.messageTimestampLine(for: previous)
        XCTAssertTrue(previousLine.contains("本地消息时间"))
        XCTAssertTrue(previousLine.contains("昨天，距当前约20分钟"))

        let currentLine = context.messageTimestampLine(for: now.addingTimeInterval(-10))
        XCTAssertTrue(currentLine.contains("今天，距当前不足1分钟"))

        let futureLine = context.messageTimestampLine(for: now.addingTimeInterval(60))
        XCTAssertTrue(futureLine.contains("时间异常：晚于当前时间"))
    }

    func testConversationTimeContextFormatsTheBoundWorldTimeZone() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-30T01:00:00Z"))
        let shanghai = ConversationTimeContext(
            now: now,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        )
        let losAngeles = ConversationTimeContext(
            now: now,
            timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        )

        XCTAssertEqual(shanghai.localDateText, "2026年8月30日")
        XCTAssertEqual(shanghai.localTimeText, "09:00:00")
        XCTAssertTrue(shanghai.promptLine.contains("UTC+08:00"))
        XCTAssertEqual(losAngeles.localDateText, "2026年8月29日")
        XCTAssertEqual(losAngeles.localTimeText, "18:00:00")
        XCTAssertTrue(losAngeles.promptLine.contains("UTC-07:00"))
    }

    func testChatTurnPresentationKeepsEveryNaturalSentenceAsItsOwnSegment() {
        let service = ChatTurnPresentationService(
            configuration: .init(
                firstDelayEnabled: false,
                longTextCharacterThreshold: 280
            ),
            sleeper: { _ in },
            randomUnit: { 0.5 }
        )
        let input = sentence("一") + sentence("二") + sentence("三") + sentence("四") + sentence("五")
        let segments = service.segments(for: input)

        XCTAssertEqual(segments.count, 5)
        XCTAssertEqual(segments.joined(), input)
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty })
    }

    func testChatTurnPresentationKeepsCodeAndListsAsOneWhileLongProseStillSplits() {
        let service = ChatTurnPresentationService(
            configuration: .init(firstDelayEnabled: false),
            sleeper: { _ in },
            randomUnit: { 0 }
        )
        XCTAssertEqual(
            service.segments(for: "```swift\nlet answer = 42\nreturn answer\n```").count,
            1
        )
        XCTAssertEqual(
            service.segments(for: String(repeating: "长文内容。", count: 60)).count,
            60
        )
        XCTAssertEqual(
            service.segments(for: "1. 先确认需求\n2. 再整理方案\n3. 最后验证结果").count,
            1
        )
    }

    func testChatTurnPresentationSamplesFirstAndSegmentDelaysAndCallbackOrder() async {
        let recorder = DelayRecorder()
        let callbacks = SegmentRecorder()
        let service = ChatTurnPresentationService(
            configuration: .init(
                firstDelayEnabled: true,
                firstDelayRange: 3...5,
                segmentDelayRange: 0.8...1.6
            ),
            sleeper: { seconds in recorder.record(seconds) },
            randomUnit: { 0.5 }
        )
        let input = sentence("一") + sentence("二") + sentence("三")

        let result = await service.present(
            text: input,
            onSegment: { callbacks.append($0) }
        )

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.displayedSegments, callbacks.values.map(\.text))
        XCTAssertEqual(callbacks.values.map(\.index), [0, 1, 2])
        XCTAssertEqual(recorder.values.count, 3)
        XCTAssertEqual(recorder.values[0], 4, accuracy: 0.000_001)
        XCTAssertEqual(recorder.values[1], 3.8, accuracy: 0.000_001)
        XCTAssertEqual(recorder.values[2], 3.8, accuracy: 0.000_001)
    }

    func testChatTurnPresentationDisablingFirstDelayKeepsSegmentPacing() async {
        let recorder = DelayRecorder()
        let service = ChatTurnPresentationService(
            configuration: .init(firstDelayEnabled: true),
            sleeper: { seconds in recorder.record(seconds) },
            randomUnit: { 0 }
        )
        let result = await service.present(
            text: sentence("一") + sentence("二") + sentence("三"),
            firstDelayEnabled: false,
            onSegment: { _ in }
        )

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.displayedSegments.count, 3)
        XCTAssertEqual(recorder.values, [1.2, 1.2])
    }

    func testChatTurnPresentationCancellationKeepsDisplayedPrefixAndStatus() async {
        let callbacks = SegmentRecorder()
        let service = ChatTurnPresentationService(
            configuration: .init(firstDelayEnabled: false),
            sleeper: { _ in throw CancellationError() },
            randomUnit: { 0.5 }
        )
        let result = await service.present(
            text: sentence("一") + sentence("二") + sentence("三"),
            onSegment: { callbacks.append($0) }
        )

        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.displayedSegments.count, 1)
        XCTAssertEqual(result.displayedSegments, callbacks.values.map(\.text))
    }

    func testChatTurnPresentationTaskCancellationIsImmediate() async {
        let service = ChatTurnPresentationService(
            configuration: .init(firstDelayEnabled: true),
            sleeper: { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
            },
            randomUnit: { 0.5 }
        )
        let task = Task {
            await service.present(
                text: sentence("一") + sentence("二"),
                onSegment: { _ in }
            )
        }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.isCancelled)
        XCTAssertTrue(result.displayedSegments.isEmpty)
    }

    func testGroupResponseCoordinatorScoresDeterministicallyAndHonorsMentions() {
        let ids = (1...4).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
        let members = [
            GroupResponseCoordinator.Member(
                roleID: ids[0],
                displayName: "甲",
                order: 0,
                topicRelevance: 0.9,
                personalityFit: 0.8,
                affinityScore: 80
            ),
            GroupResponseCoordinator.Member(
                roleID: ids[1],
                displayName: "乙",
                order: 1,
                topicRelevance: 0.8,
                personalityFit: 0.7,
                affinityScore: 60,
                recentTurnPenalty: 0.1
            ),
            GroupResponseCoordinator.Member(
                roleID: ids[2],
                displayName: "丙",
                order: 2,
                topicRelevance: 0.1,
                personalityFit: 0.2,
                affinityScore: 10,
                recentTurnPenalty: 0.5
            ),
            GroupResponseCoordinator.Member(
                roleID: ids[3],
                displayName: "丁",
                order: 3,
                topicRelevance: 0.0,
                personalityFit: 0.0,
                affinityScore: 0,
                recentTurnPenalty: 1
            ),
        ]
        let coordinator = GroupResponseCoordinator()

        XCTAssertEqual(
            coordinator.responseOrder(members: members),
            [ids[0], ids[1]]
        )
        XCTAssertEqual(
            coordinator.responseOrder(members: members),
            coordinator.responseOrder(members: Array(members.reversed()))
        )
        XCTAssertEqual(
            coordinator.responseOrder(members: members, message: "请 @丙 先回答"),
            [ids[2]]
        )
        XCTAssertEqual(
            coordinator.responseOrder(members: members, mentionedRoleIDs: Set(ids)),
            ids
        )
        XCTAssertEqual(
            coordinator.responseOrder(members: [members[0]]),
            []
        )
        XCTAssertEqual(
            coordinator.mentionedRoleIDs(in: "@乙 和 @丙", members: members),
            Set([ids[1], ids[2]])
        )
    }

    func testStickerCatalogHasExactlyTwentyFourStructuredUniqueEntries() {
        XCTAssertEqual(StickerCatalog.all.count, 24)
        XCTAssertEqual(StickerCatalog.generic.count, 16)
        XCTAssertEqual(StickerCatalog.ayaneExclusive.count, 8)
        XCTAssertEqual(Set(StickerCatalog.all.map(\.stickerID)).count, 24)
        XCTAssertEqual(Set(StickerCatalog.all.map(\.resourceName)).count, 24)
        XCTAssertTrue(StickerCatalog.all.allSatisfy {
            !$0.stickerID.isEmpty
                && !$0.resourceName.isEmpty
                && !$0.alternativeText.isEmpty
        })
        XCTAssertTrue(StickerCatalog.generic.allSatisfy { $0.stickerID.hasPrefix("generic.reaction.") })
        XCTAssertTrue(StickerCatalog.ayaneExclusive.allSatisfy { $0.stickerID.hasPrefix("ayane.exclusive.") })
        let selected = StickerCatalog.sticker(stickerID: "ayane.exclusive.06")
        XCTAssertEqual(selected?.resourceName, "AyaneStickerTea")
        XCTAssertNil(StickerCatalog.sticker(stickerID: "random.keyword.match"))
    }

    private func sentence(_ marker: String) -> String {
        String(repeating: marker, count: 45) + "。"
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

private final class SegmentRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ChatTurnPresentationService.DisplayedSegment] = []

    var values: [ChatTurnPresentationService.DisplayedSegment] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ segment: ChatTurnPresentationService.DisplayedSegment) {
        lock.lock()
        storage.append(segment)
        lock.unlock()
    }
}
