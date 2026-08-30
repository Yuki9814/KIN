import Foundation
import XCTest
@testable import Ayane

final class InteractionCoreV2Tests: XCTestCase {
    func testMemoryPolicyClassifiesIntentExpandsShortQueriesAndProtectsSensitiveGroupMemory() {
        let policy = MemoryRetrievalPolicy()
        XCTAssertEqual(policy.classify("我的资料是什么"), .identity)
        XCTAssertEqual(policy.classify("我最喜欢喝什么"), .preference)
        XCTAssertEqual(policy.classify("帮我优化这个项目"), .task)

        let shortPlan = policy.plan(
            for: "那个呢",
            recentUserMessages: ["我们刚才在聊乌龙茶", "我最喜欢哪一种饮料"]
        )
        XCTAssertGreaterThan(shortPlan.queryVariants.count, 1)
        XCTAssertTrue(shortPlan.queryVariants.contains { $0.contains("乌龙茶") })

        let memories = [
            MemorySnapshot(
                id: "tea",
                text: "用户最喜欢喝乌龙茶",
                sourceID: "profile",
                importance: 0.95,
                confidence: 0.98,
                isPinned: true
            ),
            MemorySnapshot(
                id: "private-id",
                text: "用户身份证号码是 110101199001010000",
                sourceID: "private",
                importance: 1,
                confidence: 1,
                isPinned: true,
                isSensitive: true
            )
        ]

        let preferenceResults = policy.retrieve(
            for: "我最喜欢喝什么",
            from: memories
        )
        XCTAssertEqual(preferenceResults.first?.id, "tea")

        let groupResults = policy.retrieve(
            for: "身份证号码是什么",
            from: memories,
            isGroupChat: true
        )
        XCTAssertFalse(groupResults.contains { $0.id == "private-id" })
    }

    func testAffinityPolicyIsIdempotentUsesDiminishingReturnsAndDoesNotFarmNeutralMessages() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let initial = AffinityLedgerState(
            dimensions: .seeded(fromLegacyScore: 50)
        )
        let firstEvent = AffinityEvent(
            idempotencyKey: "message:first",
            kind: .appreciation,
            occurredAt: time,
            fingerprint: "thanks"
        )
        let first = AffinityProgressionPolicy.applying(
            firstEvent,
            to: initial,
            timeZone: timeZone
        )
        XCTAssertGreaterThan(first.change.legacyScoreDelta, 0)

        let duplicate = AffinityProgressionPolicy.applying(
            firstEvent,
            to: first.state,
            timeZone: timeZone
        )
        XCTAssertTrue(duplicate.change.wasDuplicate)
        XCTAssertEqual(duplicate.change.legacyScoreDelta, 0, accuracy: 0.000_001)

        let second = AffinityProgressionPolicy.applying(
            AffinityEvent(
                idempotencyKey: "message:second",
                kind: .appreciation,
                occurredAt: time,
                fingerprint: "thanks"
            ),
            to: first.state,
            timeZone: timeZone
        )
        XCTAssertLessThan(second.change.legacyScoreDelta, first.change.legacyScoreDelta)

        let neutral = AffinityProgressionPolicy.applying(
            AffinityEvent(
                idempotencyKey: "message:neutral",
                kind: .neutralMessage,
                occurredAt: time
            ),
            to: second.state,
            timeZone: timeZone
        )
        XCTAssertEqual(neutral.change.legacyScoreDelta, 0, accuracy: 0.000_001)
        XCTAssertLessThanOrEqual(neutral.state.positiveGainToday, AffinityProgressionPolicy.dailyPositiveCap)
    }

    func testGroupTurnPlannerHonorsMentionsMentionAllAndLastSpeakerFairness() {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let thirdID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let members = [
            GroupTurnMember(
                roleID: firstID,
                displayName: "甲",
                order: 0,
                topicRelevance: 0.8,
                personalityFit: 0.8,
                affinityScore: 60
            ),
            GroupTurnMember(
                roleID: secondID,
                displayName: "乙",
                order: 1,
                topicRelevance: 0.8,
                personalityFit: 0.8,
                affinityScore: 60
            ),
            GroupTurnMember(
                roleID: thirdID,
                displayName: "丙",
                order: 2,
                topicRelevance: 0.5,
                personalityFit: 0.5,
                affinityScore: 50
            )
        ]
        let planner = GroupTurnPlanner()

        let mentioned = planner.plan(
            members: members,
            message: "@乙 这件事你怎么看？"
        )
        XCTAssertEqual(mentioned.responseOrder, [secondID])
        XCTAssertEqual(mentioned.selections.first?.reason, .explicitMention)
        XCTAssertTrue(mentioned.shouldGenerateSequentially)

        let everyone = planner.plan(
            members: members,
            message: "@所有人 大家都说说看"
        )
        XCTAssertEqual(everyone.responseOrder, [firstID, secondID, thirdID])
        XCTAssertEqual(Set(everyone.selections.map(\.reason)), [.mentionAll])

        let fairTurn = planner.plan(
            members: members,
            message: "这句话由谁接着说？",
            context: GroupTurnPlanningContext(lastSpeakerRoleID: firstID)
        )
        XCTAssertEqual(fairTurn.responseOrder.first, secondID)
    }

    func testImagePromptComposerKeepsIdentityAspectRatioAndDistinctBatchDirections() {
        let context = ImagePromptContext(
            characterName: "绫音",
            appearance: "淡紫色杏眼，右眼下泪痣，黑色高马尾",
            identityAnchors: ["眉心莲花花钿", "白皙自然皮肤质感"],
            worldContext: "宋代庭院",
            currentScene: "暮色回廊",
            relevantMemories: ["偏好素雅衣着"]
        )
        let options = ImageGenerationBatchOptions(
            count: 3,
            aspectRatio: .tallPortrait,
            quality: .high,
            style: .animeCG,
            preserveCharacterIdentity: true,
            negativePrompt: "畸形手指, 多余人物"
        )
        let first = ImagePromptComposer.compose(
            userPrompt: "生成一张回廊写真",
            context: context,
            options: options,
            variationIndex: 0
        )
        let second = ImagePromptComposer.compose(
            userPrompt: "生成一张回廊写真",
            context: context,
            options: options,
            variationIndex: 1
        )

        XCTAssertTrue(first.contains("绫音"))
        XCTAssertTrue(first.contains("淡紫色杏眼"))
        XCTAssertTrue(first.contains("9:16"))
        XCTAssertTrue(first.contains("2.5D"))
        XCTAssertTrue(first.contains("畸形手指"))
        XCTAssertNotEqual(first, second)
    }

    func testImageBatchExecutorRetriesTransientFailureAndKeepsPartialResultShape() async {
        let client = RetryingImageClient()
        let executor = ImageGenerationBatchExecutor(
            client: client,
            sleeper: { _ in }
        )
        let result = await executor.generate(
            userPrompt: "测试生图",
            options: ImageGenerationBatchOptions(count: 2, maximumRetries: 1),
            configuration: ImageGenerationConfiguration(
                baseURL: "https://example.com/v1",
                model: "image-model",
                apiStyle: .imagesAPI
            ),
            apiKey: "test-key"
        )

        XCTAssertEqual(result.images.count, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(await client.attemptCount(), 3)
        XCTAssertTrue(result.images.allSatisfy { $0.attempts >= 1 })
    }
}

private actor RetryingImageClient: ImageGenerationClientProtocol {
    private var attempts = 0

    func generateImage(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async throws -> GeneratedImageResult {
        attempts += 1
        if attempts == 1 {
            throw URLError(.timedOut)
        }
        return GeneratedImageResult(
            data: Data("image-\(attempts)".utf8),
            revisedPrompt: prompt
        )
    }

    func attemptCount() -> Int {
        attempts
    }
}
