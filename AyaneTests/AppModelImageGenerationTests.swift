import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelImageGenerationTests: XCTestCase {
    func testGenerateImageUsesDedicatedClientAndPersistsAssistantImage() async throws {
        let suiteName = "AppModelImageGenerationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        SettingsStore.registerDefaults(defaults: defaults)
        defaults.set("https://unit.image/v1", forKey: SettingsKeys.imageGenerationBaseURL)
        defaults.set("fixture-image-model", forKey: SettingsKeys.imageGenerationModel)
        defaults.set(
            ImageGenerationAPIStyle.imagesAPI.rawValue,
            forKey: SettingsKeys.imageGenerationAPIStyle
        )
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)

        let bootstrap = PersistenceController.makeContainer(
            inMemory: true,
            preferCloud: false
        )
        let chatClient = ImageGenerationFailIfChatClient()
        let pngData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let imageClient = FixtureImageGenerationClient(imageData: pngData)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: chatClient,
            imageGenerationClient: imageClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil },
            imageGenerationAPIKeyLoader: { "image-only-key" }
        )

        appModel.generateImage(
            prompt: "雨夜便利店",
            targetRoleID: appModel.currentRoleID,
            targetConversationID: appModel.currentConversation.id
        )
        try await waitUntil {
            imageClient.requestCount == 1 && !appModel.isGenerating
        }

        XCTAssertNil(appModel.errorMessage)
        XCTAssertEqual(chatClient.requestCount, 0)
        XCTAssertEqual(imageClient.lastPrompt, "雨夜便利店")
        XCTAssertEqual(imageClient.lastAPIKey, "image-only-key")
        XCTAssertEqual(imageClient.lastConfiguration?.model, "fixture-image-model")

        let context = ModelContext(bootstrap.container)
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.conversationID == appModel.currentConversation.id && !$0.redacted
            }
            .sorted { $0.deviceSequence < $1.deviceSequence }
        let userEvent = try XCTUnwrap(events.first { $0.role == .user })
        let assistantEvent = try XCTUnwrap(events.first { $0.role == .assistant })
        XCTAssertEqual(userEvent.content, "生成图片：雨夜便利店")
        XCTAssertEqual(userEvent.payloadKind, .text)
        XCTAssertEqual(assistantEvent.parentEventID, userEvent.id)
        XCTAssertEqual(assistantEvent.payloadKind, .image)
        XCTAssertEqual(assistantEvent.imageData, pngData)
        XCTAssertEqual(assistantEvent.deliveryState, .complete)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for image generation")
        throw WaitError.timedOut
    }

    private enum WaitError: Error {
        case timedOut
    }
}

private final class FixtureImageGenerationClient: ImageGenerationClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let imageData: Data
    private var storedRequestCount = 0
    private var storedPrompt: String?
    private var storedConfiguration: ImageGenerationConfiguration?
    private var storedAPIKey: String?

    init(imageData: Data) {
        self.imageData = imageData
    }

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    var lastPrompt: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedPrompt
    }

    var lastConfiguration: ImageGenerationConfiguration? {
        lock.lock()
        defer { lock.unlock() }
        return storedConfiguration
    }

    var lastAPIKey: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedAPIKey
    }

    func generateImage(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) async throws -> GeneratedImageResult {
        record(prompt: prompt, configuration: configuration, apiKey: apiKey)
        return GeneratedImageResult(data: imageData, revisedPrompt: nil)
    }

    private func record(
        prompt: String,
        configuration: ImageGenerationConfiguration,
        apiKey: String
    ) {
        lock.lock()
        storedRequestCount += 1
        storedPrompt = prompt
        storedConfiguration = configuration
        storedAPIKey = apiKey
        lock.unlock()
    }
}

private final class ImageGenerationFailIfChatClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequestCount = 0

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        recordRequest()
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AIClientError.emptyResponse)
        }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        recordRequest()
        throw AIClientError.emptyResponse
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        recordRequest()
        return []
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        recordRequest()
        throw AIClientError.emptyResponse
    }

    private func recordRequest() {
        lock.lock()
        storedRequestCount += 1
        lock.unlock()
    }
}
