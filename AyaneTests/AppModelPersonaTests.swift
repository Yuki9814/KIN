import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelPersonaTests: XCTestCase {
    func testEmptyStoreUsesFallbackWithoutCreatingCloudProfile() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)

        let appModel = makeAppModel(bootstrap: bootstrap, defaults: defaults)

        XCTAssertEqual(appModel.persona, SettingsStore.fallbackPersonaConfiguration)
        let context = ModelContext(bootstrap.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionProfileRecord>()), 0)
    }

    func testSavePublishesAndPersistsPersonaSnapshot() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = makeAppModel(bootstrap: bootstrap, defaults: defaults)

        try appModel.savePersona(
            name: "  星遥  ",
            userName: "  阿澈  ",
            prompt: "  保持清醒而温柔  "
        )

        XCTAssertEqual(appModel.persona.name, "星遥")
        XCTAssertEqual(appModel.persona.userName, "阿澈")
        XCTAssertTrue(appModel.persona.prompt.hasPrefix("保持清醒而温柔"))
        XCTAssertTrue(appModel.persona.prompt.contains("用户资料由本机设置提供"))
        XCTAssertEqual(
            appModel.persona.prompt.components(separatedBy: "【统一用户资料】").count - 1,
            1
        )
        let context = ModelContext(bootstrap.container)
        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(profiles.first?.revision, 1)
        XCTAssertEqual(profiles.first?.deviceID, defaults.string(forKey: "device.stableID"))
    }

    func testLegacyPersonaBackfillsOnceAndModelWinsAfterRestart() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("旧版角色", forKey: SettingsKeys.personaName)
        defaults.set("旧版称呼", forKey: SettingsKeys.userName)
        defaults.set("旧版提示", forKey: SettingsKeys.personaPrompt)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)

        let first = makeAppModel(bootstrap: bootstrap, defaults: defaults)
        XCTAssertEqual(first.persona.name, "旧版角色")

        defaults.set("不应覆盖", forKey: SettingsKeys.personaName)
        let second = makeAppModel(bootstrap: bootstrap, defaults: defaults)
        XCTAssertEqual(second.persona.name, "旧版角色")
        let context = ModelContext(bootstrap.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionProfileRecord>()), 1)
    }

    func testForcedRefreshPublishesRemotePersonaUpdate() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = makeAppModel(bootstrap: bootstrap, defaults: defaults)
        try appModel.savePersona(name: "绫音", userName: "你", prompt: "旧提示")

        let remoteContext = ModelContext(bootstrap.container)
        let profile = try XCTUnwrap(
            try remoteContext.fetch(FetchDescriptor<CompanionProfileRecord>()).first
        )
        profile.name = "远端角色"
        profile.prompt = "远端更新提示"
        profile.revision += 1
        profile.updatedAt = profile.updatedAt.addingTimeInterval(10)
        profile.deviceID = "remote-device"
        try remoteContext.save()

        appModel.refreshFromStore(force: true)

        XCTAssertEqual(appModel.persona.name, "远端角色")
        XCTAssertEqual(appModel.persona.prompt, "远端更新提示")
    }

    func testClearConversationDataPreservesPersona() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = makeAppModel(bootstrap: bootstrap, defaults: defaults)
        try appModel.savePersona(name: "保留角色", userName: "你", prompt: "保留提示")

        try await appModel.clearAllLocalData()

        XCTAssertEqual(appModel.persona.name, "保留角色")
        let context = ModelContext(bootstrap.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionProfileRecord>()), 1)
    }

    func testCreatesAndSwitchesIndependentCompanionRoles() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = makeAppModel(bootstrap: bootstrap, defaults: defaults)
        let legacyRoleID = appModel.currentRoleID

        let newRoleID = try appModel.createCompanion(
            name: "星遥",
            userName: "阿澈",
            prompt: "保持清醒而温柔"
        )

        XCTAssertNotEqual(newRoleID, legacyRoleID)
        XCTAssertEqual(appModel.currentRoleID, newRoleID)
        XCTAssertEqual(appModel.persona.name, "星遥")
        XCTAssertEqual(Set(appModel.companions.map(\.id)), Set([legacyRoleID, newRoleID]))

        try appModel.savePersona(name: "星遥二号", userName: "阿澈", prompt: "独立提示")
        try appModel.selectCompanion(id: legacyRoleID)
        XCTAssertEqual(appModel.persona, SettingsStore.fallbackPersonaConfiguration)
        try appModel.selectCompanion(id: newRoleID)
        XCTAssertEqual(appModel.persona.name, "星遥二号")
        XCTAssertTrue(appModel.persona.prompt.hasPrefix("独立提示"))
        XCTAssertTrue(appModel.persona.prompt.contains("用户资料由本机设置提供"))
        XCTAssertEqual(
            appModel.persona.prompt.components(separatedBy: "【统一用户资料】").count - 1,
            1
        )

        let context = ModelContext(bootstrap.container)
        let roleConversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        XCTAssertEqual(roleConversations.filter { $0.resolvedRoleID == newRoleID }.count, 1)
        XCTAssertEqual(roleConversations.filter { $0.resolvedRoleID == legacyRoleID }.count, 1)
    }

    func testSelectedCompanionPersistsAcrossAppModelRestart() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let first = makeAppModel(bootstrap: bootstrap, defaults: defaults)

        let selectedRoleID = try first.createCompanion(
            name: "星遥",
            userName: "阿澈",
            prompt: "保持清醒而温柔"
        )
        XCTAssertEqual(first.currentRoleID, selectedRoleID)

        let reopened = makeAppModel(bootstrap: bootstrap, defaults: defaults)

        XCTAssertEqual(reopened.currentRoleID, selectedRoleID)
        XCTAssertEqual(reopened.persona.name, "星遥")
    }

    func testChatPromptUsesLatestPersistedPersona() async throws {
        let (defaults, suiteName) = try makeDefaults(configureProvider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = PersonaCapturingAIClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )
        try appModel.savePersona(name: "星遥", userName: "阿澈", prompt: "只使用最新人格")

        appModel.send("你好")
        try await waitUntil { !appModel.isGenerating && appModel.messages.count >= 2 }

        let system = try XCTUnwrap(client.capturedSystemMessage())
        XCTAssertTrue(system.contains("只使用最新人格"))
        XCTAssertTrue(system.contains("当前角色名：星遥"))
        XCTAssertTrue(system.contains("用户称呼：阿澈"))
    }

    func testChatPromptCarriesStoredTimeForYesterdayPlanAndCurrentTurn() async throws {
        let (defaults, suiteName) = try makeDefaults(configureProvider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.timeInjectionEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = PersonaCapturingAIClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )

        let oldPlanText = "我要去玩一小时游戏，再回来找你。"
        let storeContext = ModelContext(bootstrap.container)
        storeContext.insert(ConversationEvent(
            conversationID: appModel.currentConversation.id,
            deviceID: "seed-device",
            deviceSequence: 900,
            logicalTimestamp: "seed-yesterday-plan",
            occurredAt: Date().addingTimeInterval(-26 * 60 * 60),
            role: .user,
            content: oldPlanText,
            contentHash: "seed-yesterday-plan",
            roleID: appModel.currentRoleID
        ))
        try storeContext.save()
        appModel.refreshFromStore(force: true)

        appModel.send("今天想聊点别的。")
        try await waitUntil { !appModel.isGenerating && appModel.messages.count >= 3 }

        let captured = try XCTUnwrap(client.capturedChatMessages())
        let system = try XCTUnwrap(captured.first(where: { $0.role == "system" }))
        XCTAssertTrue(system.content.contains("不得把旧计划当作用户刚刚提出"))
        XCTAssertTrue(system.content.contains("上一次已成功发送的用户消息发生于"))

        let userMessages = captured.filter { $0.role == "user" }
        let oldPlan = try XCTUnwrap(userMessages.first(where: { $0.content.contains(oldPlanText) }))
        XCTAssertTrue(oldPlan.content.contains("【本地消息时间："))
        XCTAssertTrue(oldPlan.content.contains("距当前约1天"))

        let current = try XCTUnwrap(userMessages.first(where: { $0.content.contains("今天想聊点别的。") }))
        XCTAssertTrue(current.content.contains("【本地消息时间："))
        XCTAssertTrue(current.content.contains("今天，距当前不足1分钟"))
    }

    func testTimeContextFindsPreviousUserBeyondVisibleMessageWindow() async throws {
        let (defaults, suiteName) = try makeDefaults(configureProvider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.timeInjectionEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = PersonaCapturingAIClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )
        let storeContext = ModelContext(bootstrap.container)
        let oldUserAt = Date().addingTimeInterval(-48 * 60 * 60)
        let oldUser = ConversationEvent(
            conversationID: appModel.currentConversation.id,
            deviceID: "window-seed",
            deviceSequence: 1,
            logicalTimestamp: "window-user",
            occurredAt: oldUserAt,
            role: .user,
            content: "窗口之外的上一条用户消息",
            contentHash: "window-user",
            roleID: appModel.currentRoleID
        )
        storeContext.insert(oldUser)
        let assistantStart = Date().addingTimeInterval(-60 * 60)
        for index in 0..<241 {
            let content = "填充回复 \(index)"
            storeContext.insert(ConversationEvent(
                conversationID: appModel.currentConversation.id,
                deviceID: "window-seed",
                deviceSequence: index + 2,
                logicalTimestamp: String(format: "window-%03d", index),
                occurredAt: assistantStart.addingTimeInterval(TimeInterval(index)),
                role: .assistant,
                content: content,
                contentHash: content,
                roleID: appModel.currentRoleID
            ))
        }
        try storeContext.save()
        appModel.refreshFromStore(force: true)
        XCTAssertFalse(appModel.messages.contains(where: { $0.id == oldUser.id }))

        appModel.send("现在重新说话。")
        try await waitUntil {
            !appModel.isGenerating && client.capturedChatMessages() != nil
        }

        let system = try XCTUnwrap(
            client.capturedChatMessages()?.first(where: { $0.role == "system" })
        )
        XCTAssertTrue(system.content.contains("上一次已成功发送的用户消息发生于"))
        XCTAssertTrue(system.content.contains("间隔分类 1-3d"))
        XCTAssertFalse(system.content.contains("暂无上次有效消息"))
    }

    func testConnectionTestIgnoresAnOlderResultAfterRestarting() async throws {
        let (defaults, suiteName) = try makeDefaults(configureProvider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = ConnectionRaceAIClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )

        appModel.testConnection()
        try await Task.sleep(for: .milliseconds(20))
        appModel.testConnection()

        try await waitUntil { !appModel.isTestingConnection }
        XCTAssertEqual(appModel.connectionTestText, "连接成功，2 ms，回复：新配置")

        // The first request intentionally ignores cancellation and finishes
        // later. It must not overwrite the second request's visible result.
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(appModel.connectionTestText, "连接成功，2 ms，回复：新配置")
    }

    func testChatAndConnectionCaptureConfigurationKeyPairBeforeAsyncWork() async throws {
        let (defaults, suiteName) = try makeDefaults(configureProvider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = CredentialCapturingAIClient()
        var currentKey = "provider-a-key"
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { currentKey }
        )

        appModel.send("验证凭据绑定")
        currentKey = "provider-b-key"
        try await waitUntil { !appModel.isGenerating && appModel.messages.count >= 2 }
        XCTAssertEqual(client.chatCredential()?.apiKey, "provider-a-key")
        XCTAssertEqual(client.chatCredential()?.baseURL, "https://unit.test/v1")

        currentKey = "connection-a-key"
        appModel.testConnection()
        currentKey = "connection-b-key"
        try await waitUntil { !appModel.isTestingConnection }
        XCTAssertEqual(client.connectionCredential()?.apiKey, "connection-a-key")
        XCTAssertEqual(client.connectionCredential()?.baseURL, "https://unit.test/v1")
    }

    private func makeDefaults(
        configureProvider: Bool = false
    ) throws -> (UserDefaults, String) {
        let suiteName = "AppModelPersonaTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        if configureProvider {
            defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
            defaults.set("fixture-model", forKey: SettingsKeys.model)
            defaults.set(false, forKey: SettingsKeys.streamResponses)
        }
        return (defaults, suiteName)
    }

    private func makeAppModel(
        bootstrap: PersistenceBootstrap,
        defaults: UserDefaults,
        client: any AIClientProtocol = PersonaCapturingAIClient()
    ) -> AppModel {
        AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for AppModel state")
    }
}

private final class CredentialCapturingAIClient: AIClientProtocol, @unchecked Sendable {
    struct Credential: Equatable {
        let baseURL: String
        let apiKey: String
    }

    private let lock = NSLock()
    private var chatValue: Credential?
    private var connectionValue: Credential?

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        captureChat(configuration: configuration, apiKey: apiKey)
        return AsyncThrowingStream { continuation in
            continuation.yield("测试回复")
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
        captureChat(configuration: configuration, apiKey: apiKey)
        return "测试回复"
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
        lock.lock()
        connectionValue = Credential(baseURL: configuration.baseURL, apiKey: apiKey)
        lock.unlock()
        return ConnectionTestResult(latency: 0, reply: "OK")
    }

    func chatCredential() -> Credential? {
        lock.lock()
        defer { lock.unlock() }
        return chatValue
    }

    func connectionCredential() -> Credential? {
        lock.lock()
        defer { lock.unlock() }
        return connectionValue
    }

    private func captureChat(configuration: ProviderConfiguration, apiKey: String) {
        lock.lock()
        chatValue = Credential(baseURL: configuration.baseURL, apiKey: apiKey)
        lock.unlock()
    }
}

private final class PersonaCapturingAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var systemMessage: String?
    private var chatMessages: [APIChatMessage]?

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        capture(messages)
        return AsyncThrowingStream { continuation in
            continuation.yield("测试回复")
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
        capture(messages)
        return "测试回复"
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        throw AIClientError.missingEmbeddingModel
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }

    func capturedSystemMessage() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return systemMessage
    }

    func capturedChatMessages() -> [APIChatMessage]? {
        lock.lock()
        defer { lock.unlock() }
        return chatMessages
    }

    private func capture(_ messages: [APIChatMessage]) {
        lock.lock()
        systemMessage = messages.first(where: { $0.role == "system" })?.content
        chatMessages = messages
        lock.unlock()
    }
}

private final class ConnectionRaceAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var connectionRequests = 0

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
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
        "unused"
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
        let request = nextConnectionRequest()

        if request == 1 {
            // Deliberately swallow cancellation to verify the AppModel's
            // generation guard, not just cooperative Task cancellation.
            try? await Task.sleep(for: .milliseconds(180))
            return ConnectionTestResult(latency: 0.001, reply: "旧配置")
        }
        try? await Task.sleep(for: .milliseconds(10))
        return ConnectionTestResult(latency: 0.002, reply: "新配置")
    }

    private func nextConnectionRequest() -> Int {
        lock.lock()
        defer { lock.unlock() }
        connectionRequests += 1
        return connectionRequests
    }
}
