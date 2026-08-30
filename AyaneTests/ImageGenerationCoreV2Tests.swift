import Foundation
import XCTest
@testable import Ayane

final class ImageGenerationCoreV2Tests: XCTestCase {
    func testPromptComposerPreservesIdentityAndDiversifiesBatchPrompts() {
        let context = ImagePromptContext(
            characterName: "绫音",
            appearance: "淡紫色眼睛，右眼下泪痣，眉心莲花花钿",
            identityAnchors: ["高马尾", "柔和鹅蛋脸"],
            worldContext: "宋代庭院",
            currentScene: "雨后廊下",
            relevantMemories: ["偏好素雅衣装"]
        )
        let options = ImageGenerationBatchOptions(
            count: 2,
            aspectRatio: .portrait,
            quality: .high,
            style: .animeCG,
            negativePrompt: "畸形，重复人物"
        )
        let first = ImagePromptComposer.compose(
            userPrompt: "生成一张人物写真",
            context: context,
            options: options,
            variationIndex: 0
        )
        let second = ImagePromptComposer.compose(
            userPrompt: "生成一张人物写真",
            context: context,
            options: options,
            variationIndex: 1
        )

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("淡紫色眼睛"))
        XCTAssertTrue(first.contains("保持上述身份特征稳定"))
        XCTAssertTrue(first.contains("2.5D 半写实 CG"))
        XCTAssertTrue(first.contains("畸形"))
        XCTAssertTrue(second.contains("更换镜头机位"))
    }

    func testBatchExecutorRetriesTransientFailure() async {
        let client = ScriptedImageClient(outcomes: [
            .failure(.httpStatus(429, "rate limited")),
            .success(GeneratedImageResult(
                data: Data([1, 2, 3]),
                revisedPrompt: nil
            )),
        ])
        let executor = ImageGenerationBatchExecutor(
            client: client,
            sleeper: { _ in }
        )
        let result = await executor.generate(
            userPrompt: "测试",
            options: ImageGenerationBatchOptions(
                count: 1,
                maximumRetries: 2
            ),
            configuration: ImageGenerationConfiguration(
                baseURL: "https://example.com/v1",
                model: "image-model",
                apiStyle: .imagesAPI
            ),
            apiKey: "fixture"
        )
        let attemptCount = await client.attemptCount

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.images.first?.attempts, 2)
        XCTAssertEqual(attemptCount, 2)
    }

    func testBatchExecutorReportsPartialFailureWithoutDiscardingSuccess() async {
        let client = ScriptedImageClient(outcomes: [
            .success(GeneratedImageResult(
                data: Data([1]),
                revisedPrompt: "first"
            )),
            .failure(.httpStatus(400, "bad request")),
        ])
        let executor = ImageGenerationBatchExecutor(
            client: client,
            sleeper: { _ in }
        )
        let result = await executor.generate(
            userPrompt: "测试两张图",
            options: ImageGenerationBatchOptions(
                count: 2,
                maximumRetries: 0
            ),
            configuration: ImageGenerationConfiguration(
                baseURL: "https://example.com/v1",
                model: "image-model",
                apiStyle: .imagesAPI
            ),
            apiKey: "fixture"
        )

        XCTAssertTrue(result.isPartial)
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.attempts, 1)
    }
}

private actor ScriptedImageClient: ImageGenerationClientProtocol {
    enum Outcome: Sendable {
        case success(GeneratedImageResult)
        case failure(ImageGenerationClientError)
    }

    private var outcomes: [Outcome]
    private(set) var attemptCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func generateImage(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async throws -> GeneratedImageResult {
        attemptCount += 1
        guard !outcomes.isEmpty else {
            throw ImageGenerationClientError.invalidResponse
        }
        switch outcomes.removeFirst() {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}
