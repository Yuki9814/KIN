import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class ChatTurnPresentationResumeTests: XCTestCase {
    func testStartupResumesSingleQueueIntoOneLogicalEvent() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)

        let initial = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        let conversationID = initial.currentConversation.id
        let roleID = initial.currentRoleID
        let parentID = UUID()
        let assistantID = UUID()
        let presentationID = UUID()
        let now = Date(timeIntervalSince1970: 10)
        let context = ModelContext(bootstrap.container)
        context.insert(ConversationEvent(
            id: parentID,
            conversationID: conversationID,
            deviceID: "resume-device",
            deviceSequence: 1,
            logicalTimestamp: "001",
            occurredAt: now,
            role: .user,
            content: "请继续",
            contentHash: ContentHasher.sha256("请继续"),
            deliveryState: .complete,
            roleID: roleID
        ))
        context.insert(ConversationEvent(
            id: assistantID,
            conversationID: conversationID,
            deviceID: "resume-device",
            deviceSequence: 2,
            logicalTimestamp: "002",
            occurredAt: now.addingTimeInterval(1),
            role: .assistant,
            content: "第一段。",
            contentHash: ContentHasher.sha256("第一段。"),
            parentEventID: parentID,
            deliveryState: .streaming,
            roleID: roleID
        ))
        context.insert(ChatTurnPresentationRecord(
            id: presentationID,
            conversationID: conversationID,
            roleID: roleID,
            logicalReplyEventID: assistantID,
            segments: ["第一段。", "第二段。"],
            displayProgress: 0.5,
            displayedSegmentCount: 1,
            state: .delivering,
            plannedAt: now,
            startedAt: now,
            idempotencyKey: "assistant-reply:\(parentID.uuidString.lowercased())",
            createdAt: now,
            updatedAt: now,
            revision: 2,
            deviceID: "resume-device"
        ))
        try context.save()
        withExtendedLifetime(initial) {}

        let resumed = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        try await waitUntil {
            let rows = (try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? []
            return rows.first(where: { $0.id == presentationID })?.state == .completed
        }

        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == conversationID && $0.role == .assistant }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, assistantID)
        XCTAssertEqual(events.first?.content, "第一段。\n\n第二段。")
        XCTAssertEqual(events.first?.deliveryState, .complete)
        let presentation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
                .first { $0.id == presentationID }
        )
        XCTAssertEqual(presentation.logicalReplyEventID, assistantID)
        XCTAssertEqual(presentation.displayedSegmentCount, 2)
        XCTAssertEqual(presentation.displayProgress, 1)
        withExtendedLifetime(resumed) {}
    }

    func testStartupResumesGroupQueueAndKeepsSpeakingRoleOnOneEvent() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let initial = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        let context = ModelContext(bootstrap.container)
        let conversationID = UUID()
        let roleID = UUID()
        let parentID = UUID()
        let assistantID = UUID()
        let presentationID = UUID()
        let now = Date(timeIntervalSince1970: 20)
        context.insert(ConversationRecord(
            id: conversationID,
            title: "恢复群聊",
            createdAt: now,
            roleID: nil
        ))
        context.insert(GroupConversationRecord(
            conversationID: conversationID,
            groupName: "恢复群聊",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "resume-device"
        ))
        context.insert(GroupParticipantRecord(
            conversationID: conversationID,
            participantRoleID: roleID,
            participantKind: .companion,
            displayName: "角色甲",
            joinedAt: now,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "resume-device"
        ))
        context.insert(ConversationEvent(
            id: parentID,
            conversationID: conversationID,
            deviceID: "resume-device",
            deviceSequence: 3,
            logicalTimestamp: "003",
            occurredAt: now,
            role: .user,
            content: "群聊继续",
            contentHash: ContentHasher.sha256("群聊继续"),
            deliveryState: .complete
        ))
        context.insert(ConversationEvent(
            id: assistantID,
            conversationID: conversationID,
            deviceID: "resume-device",
            deviceSequence: 4,
            logicalTimestamp: "004",
            occurredAt: now.addingTimeInterval(1),
            role: .assistant,
            content: "群聊第一段。",
            contentHash: ContentHasher.sha256("群聊第一段。"),
            parentEventID: parentID,
            deliveryState: .streaming,
            roleID: roleID,
            senderRoleID: roleID
        ))
        context.insert(ChatTurnPresentationRecord(
            id: presentationID,
            conversationID: conversationID,
            roleID: roleID,
            logicalReplyEventID: assistantID,
            segments: ["群聊第一段。", "群聊第二段。"],
            displayProgress: 0.5,
            displayedSegmentCount: 1,
            state: .delivering,
            plannedAt: now,
            startedAt: now,
            idempotencyKey: "group-reply:\(parentID.uuidString.lowercased()):\(roleID.uuidString.lowercased())",
            createdAt: now,
            updatedAt: now,
            revision: 2,
            deviceID: "resume-device"
        ))
        try context.save()
        withExtendedLifetime(initial) {}

        let resumed = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        resumed.openGroup(conversationID: conversationID)
        try await waitUntil {
            let rows = (try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? []
            return rows.first(where: { $0.id == presentationID })?.state == .completed
        }

        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == conversationID && $0.role == .assistant }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.senderRoleID, roleID)
        XCTAssertEqual(events.first?.content, "群聊第一段。\n\n群聊第二段。")
        XCTAssertEqual(events.first?.deliveryState, .complete)
        withExtendedLifetime(resumed) {}
    }

    func testGeneratingRecordWithoutPlanBecomesExplicitFailure() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let initial = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        let context = ModelContext(bootstrap.container)
        let parentID = UUID()
        let now = Date(timeIntervalSince1970: 30)
        context.insert(ConversationEvent(
            id: parentID,
            conversationID: initial.currentConversation.id,
            deviceID: "resume-device",
            deviceSequence: 5,
            logicalTimestamp: "005",
            occurredAt: now,
            role: .user,
            content: "中断",
            contentHash: ContentHasher.sha256("中断"),
            deliveryState: .complete,
            roleID: initial.currentRoleID
        ))
        let presentationID = UUID()
        context.insert(ChatTurnPresentationRecord(
            id: presentationID,
            conversationID: initial.currentConversation.id,
            roleID: initial.currentRoleID,
            state: .generating,
            idempotencyKey: "assistant-reply:\(parentID.uuidString.lowercased())",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "resume-device"
        ))
        try context.save()
        withExtendedLifetime(initial) {}

        let resumed = AppModel(
            bootstrap: bootstrap,
            client: ResumeNoopAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        try await waitUntil {
            let rows = (try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? []
            return rows.first(where: { $0.id == presentationID })?.state == .failed
        }
        let presentation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
                .first { $0.id == presentationID }
        )
        XCTAssertFalse(presentation.failureMessage.isEmpty)
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<ConversationEvent>()).contains {
                $0.role == .assistant && $0.parentEventID == parentID
            }
        )
        withExtendedLifetime(resumed) {}
    }

    func testNewUserTurnCancelsVisibleQueueBeforeStartingNextTurn() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = ResumeSequencedAIClient(responses: [
            String(repeating: "旧回复第一段", count: 10) + "。旧回复隐藏段。",
            "新回复已完成。"
        ])
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        let context = ModelContext(bootstrap.container)
        appModel.send("旧消息")
        try await waitUntil {
            let rows = (try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? []
            return rows.contains {
                $0.state == .delivering && $0.displayedSegmentCount == 1
            }
        }

        appModel.send("新消息不能丢")
        try await waitUntil(timeout: 5) {
            client.chatRequests == 2
                && !appModel.isGenerating
                && ((try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? [])
                    .contains { $0.state == .completed }
        }

        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
            .sorted { $0.deviceSequence < $1.deviceSequence }
        let users = events.filter { $0.role == .user }
        let assistants = events.filter { $0.role == .assistant }
        XCTAssertEqual(users.map(\.content), ["旧消息", "新消息不能丢"])
        XCTAssertEqual(assistants.count, 2)
        XCTAssertEqual(assistants[0].deliveryState, .complete)
        XCTAssertFalse(assistants[0].content.contains("旧回复隐藏段"))
        XCTAssertEqual(assistants[1].content, "新回复已完成。")
        XCTAssertEqual(assistants[1].deliveryState, .complete)
    }

    func testReopeningSameConversationKeepsInFlightReplyAlive() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = ResumeControlledAIClient(reply: "离开聊天页后仍然完成。")
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        let context = ModelContext(bootstrap.container)
        let roleID = appModel.currentRoleID
        let conversationID = appModel.currentConversation.id

        appModel.send("请慢慢想")
        try await waitUntil {
            client.chatRequests == 1 && appModel.isGenerating
        }

        // The home list re-selects the row when the user opens this chat again.
        // That navigation round trip must not be interpreted as Stop/Cancel.
        try appModel.selectCompanion(id: roleID)
        XCTAssertTrue(appModel.isGenerating)
        XCTAssertEqual(appModel.currentConversation.id, conversationID)
        client.releaseReply()

        try await waitUntil {
            !appModel.isGenerating
                && ((try? context.fetch(FetchDescriptor<ConversationEvent>())) ?? [])
                    .contains {
                        $0.conversationID == conversationID
                            && $0.role == .assistant
                            && $0.deliveryState == .complete
                            && $0.content == "离开聊天页后仍然完成。"
                    }
        }
        XCTAssertEqual(client.cancelledRequests, 0)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "ChatTurnPresentationResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        return (defaults, suiteName)
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
        XCTFail("Timed out waiting for presentation recovery")
    }
}

private struct ResumeNoopAIClient: AIClientProtocol {
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
        ""
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
}

private final class ResumeSequencedAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String]
    private var count = 0

    init(responses: [String]) {
        self.responses = responses
    }

    var chatRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(nextResponse())
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
        nextResponse()
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

    private func nextResponse() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return responses.isEmpty ? "默认回复。" : responses.removeFirst()
    }
}

private final class ResumeControlledAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let reply: String
    private var requestCount = 0
    private var cancellationCount = 0
    private var replyReleased = false
    private var replyContinuation: CheckedContinuation<Void, Never>?

    init(reply: String) {
        self.reply = reply
    }

    var chatRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var cancelledRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancellationCount
    }

    func releaseReply() {
        lock.lock()
        replyReleased = true
        let continuation = replyContinuation
        replyContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

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
        recordRequest()
        await waitForReplyRelease()
        do {
            try Task.checkCancellation()
            return reply
        } catch is CancellationError {
            recordCancellation()
            throw CancellationError()
        }
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

    private func recordRequest() {
        lock.lock()
        requestCount += 1
        lock.unlock()
    }

    private func recordCancellation() {
        lock.lock()
        cancellationCount += 1
        lock.unlock()
    }

    private func waitForReplyRelease() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if replyReleased {
                lock.unlock()
                continuation.resume()
            } else {
                replyContinuation = continuation
                lock.unlock()
            }
        }
    }
}
