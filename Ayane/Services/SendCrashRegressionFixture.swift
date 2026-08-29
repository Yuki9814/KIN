#if DEBUG
import Darwin
import Foundation

/// Isolated physical-device regression for the send/presentation crash.
///
/// The fixture is unreachable during an ordinary launch. It uses an in-memory
/// SwiftData store, an isolated defaults suite, and a local deterministic
/// client, so it never reads credentials, calls a provider, or changes the
/// user's conversation history.
@MainActor
enum SendCrashRegressionFixture {
    static let launchArgument = "-KINSendCrashRegression"
    static let completedMarker = "KIN_SEND_CRASH_REGRESSION_PASS"
    static let failedMarker = "KIN_SEND_CRASH_REGRESSION_FAIL"
    private static let launchEnvironmentKey = "KIN_SEND_CRASH_REGRESSION"

    struct Fixture {
        let bootstrap: PersistenceBootstrap
        let appModel: AppModel
    }

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.environment[launchEnvironmentKey] == "1"
    }

    static func make() -> Fixture {
        let suiteName = "com.example.kin.send-crash-regression"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("kin-regression-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.2, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.cloudSyncEnabled)

        let bootstrap = PersistenceController.makeContainer(
            inMemory: true,
            preferCloud: false
        )
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: SendCrashRegressionAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "local-regression-credential" },
            performLegacyConversationMigration: false,
            seedBuiltInCompanions: true
        )
        return Fixture(bootstrap: bootstrap, appModel: appModel)
    }

    static func run(on appModel: AppModel) async {
        emit("KIN_SEND_CRASH_REGRESSION_START")
        try? await Task.sleep(for: .milliseconds(750))
        for turn in 1...8 {
            appModel.send("真机发送回归第\(turn)轮")
            guard await waitUntil(timeout: 12, condition: { !appModel.isGenerating }) else {
                finish("\(failedMarker) reason=timeout turn=\(turn)", success: false)
            }
            guard appModel.errorMessage == nil else {
                finish("\(failedMarker) reason=app-error turn=\(turn)", success: false)
            }
            emit("KIN_SEND_CRASH_REGRESSION_PROGRESS turn=\(turn)")
            await Task.yield()
        }

        let completedReplies = appModel.messages.filter {
            $0.role == .assistant && $0.deliveryState == .complete
        }
        guard completedReplies.count == 8 else {
            finish(
                "\(failedMarker) reason=reply-count actual=\(completedReplies.count)",
                success: false
            )
        }
        finish("\(completedMarker) turns=8 replies=8", success: true)
    }

    private static func emit(_ message: String) {
        fputs(message + "\n", stdout)
        fflush(stdout)
    }

    private static func finish(_ message: String, success: Bool) -> Never {
        emit(message)
        exit(success ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private static func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        } while Date() < deadline
        return condition()
    }
}

private final class SendCrashRegressionAIClient: AIClientProtocol, @unchecked Sendable {
    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Self.reply)
            continuation.finish()
        }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        Self.reply
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        []
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }

    private static let reply = "第一段已经收到。第二段继续展示。第三段保持同一条回复。第四段完成。"
}
#endif
