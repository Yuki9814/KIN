import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelConversationDataActionsTests: XCTestCase {
    func testRecallRejectsOlderUserMessageAndKeepsAssistantReply() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = ModelContext(fixture.bootstrap.container)
        let conversationID = fixture.appModel.currentConversation.id
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let u1 = makeEvent(conversationID: conversationID, role: .user, text: "第一句", index: 1, at: start)
        let a1 = makeEvent(conversationID: conversationID, role: .assistant, text: "第一句回复", index: 2, at: start)
        let u2 = makeEvent(conversationID: conversationID, role: .user, text: "最后一句", index: 3, at: start)
        let a2 = makeEvent(conversationID: conversationID, role: .assistant, text: "最后一句回复", index: 4, at: start)
        [u1, a1, u2, a2].forEach(context.insert)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        XCTAssertThrowsError(try fixture.appModel.recallUserMessage(id: u1.id))
        try fixture.appModel.recallUserMessage(id: u2.id)

        let stored = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertTrue(try XCTUnwrap(stored.first { $0.id == u2.id }).redacted)
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.id == a2.id }).redacted)
        XCTAssertEqual(fixture.appModel.messages.map(\.content), ["第一句", "第一句回复", "最后一句回复"])
        XCTAssertEqual(fixture.appModel.latestRecallableUserEventID, u1.id)
    }

    func testDeleteFromUserMessageRedactsCompleteFollowingSuffix() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = ModelContext(fixture.bootstrap.container)
        let conversationID = fixture.appModel.currentConversation.id
        let start = Date(timeIntervalSince1970: 1_800_100_000)
        let events = [
            makeEvent(conversationID: conversationID, role: .user, text: "U1", index: 1, at: start),
            makeEvent(conversationID: conversationID, role: .assistant, text: "A1", index: 2, at: start),
            makeEvent(conversationID: conversationID, role: .user, text: "U2", index: 3, at: start),
            makeEvent(conversationID: conversationID, role: .assistant, text: "A2", index: 4, at: start),
            makeEvent(conversationID: conversationID, role: .user, text: "U3", index: 5, at: start),
            makeEvent(conversationID: conversationID, role: .assistant, text: "A3", index: 6, at: start)
        ]
        events.forEach(context.insert)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.deleteMessageAndFollowing(id: events[2].id)

        let stored = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<ConversationEvent>())
        let stateByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.redacted) })
        XCTAssertEqual(events.map { stateByID[$0.id] ?? false }, [false, false, true, true, true, true])
        XCTAssertEqual(fixture.appModel.messages.map(\.content), ["U1", "A1"])
    }

    func testRoleChatClearDoesNotTouchOtherDirectChatOrSharedGroup() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let roleA = try fixture.appModel.createCompanion(name: "甲", userName: "你", prompt: "甲")
        let roleB = try fixture.appModel.createCompanion(name: "乙", userName: "你", prompt: "乙")
        let groupID = try fixture.appModel.createGroup(
            name: "共同群聊",
            participantRoleIDs: [roleA, roleB]
        )
        let context = ModelContext(fixture.bootstrap.container)
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let directA = try XCTUnwrap(conversations.first { $0.resolvedRoleID == roleA && $0.id != groupID })
        let directB = try XCTUnwrap(conversations.first { $0.resolvedRoleID == roleB && $0.id != groupID })
        let start = Date(timeIntervalSince1970: 1_800_200_000)
        let eventA = makeEvent(
            conversationID: directA.id,
            roleID: roleA,
            role: .user,
            text: "甲的单聊",
            index: 1,
            at: start
        )
        let eventB = makeEvent(
            conversationID: directB.id,
            roleID: roleB,
            role: .user,
            text: "乙的单聊",
            index: 2,
            at: start
        )
        let groupEvent = makeEvent(
            conversationID: groupID,
            roleID: roleA,
            role: .assistant,
            text: "甲在群聊里的消息",
            index: 3,
            at: start,
            senderRoleID: roleA
        )
        let archivedConversationID = UUID()
        let archivedConversation = ConversationRecord(
            id: archivedConversationID,
            title: "甲的旧单聊",
            createdAt: start,
            roleID: roleA
        )
        archivedConversation.archived = true
        let queuedPresentation = ChatTurnPresentationRecord(
            conversationID: archivedConversationID,
            roleID: roleA,
            segments: ["不应在清空后出现"],
            state: .waiting,
            idempotencyKey: "assistant-reply:\(UUID().uuidString.lowercased())",
            createdAt: start,
            updatedAt: start,
            revision: 1,
            deviceID: "fixture"
        )
        let directProactive = ProactiveMessageTaskRecord(
            roleID: roleA,
            conversationID: directA.id,
            state: .scheduled,
            lastUserEventID: eventA.id,
            revision: 1,
            deviceID: "fixture"
        )
        let groupProactive = ProactiveMessageTaskRecord(
            roleID: roleA,
            conversationID: groupID,
            state: .scheduled,
            lastUserEventID: groupEvent.id,
            revision: 1,
            deviceID: "fixture"
        )
        [eventA, eventB, groupEvent].forEach(context.insert)
        context.insert(archivedConversation)
        context.insert(queuedPresentation)
        context.insert(directProactive)
        context.insert(groupProactive)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        let clearedCount = try fixture.appModel.clearDirectChatHistory(roleID: roleA)
        XCTAssertGreaterThanOrEqual(clearedCount, 1)

        let stored = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertTrue(try XCTUnwrap(stored.first { $0.id == eventA.id }).redacted)
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.id == eventB.id }).redacted)
        XCTAssertFalse(try XCTUnwrap(stored.first { $0.id == groupEvent.id }).redacted)
        let storedPresentation = try XCTUnwrap(
            try ModelContext(fixture.bootstrap.container)
                .fetch(FetchDescriptor<ChatTurnPresentationRecord>())
                .first { $0.id == queuedPresentation.id }
        )
        XCTAssertEqual(storedPresentation.state, .cancelled)
        let proactive = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        XCTAssertEqual(proactive.first { $0.id == directProactive.id }?.state, .cancelled)
        XCTAssertEqual(proactive.first { $0.id == groupProactive.id }?.state, .scheduled)
    }

    func testRoleMemoryClearScrubsOldDataAndAllowsNewPostResetMemory() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let roleID = try fixture.appModel.createCompanion(name: "记忆角色", userName: "你", prompt: "记住事实")
        let context = ModelContext(fixture.bootstrap.container)
        let conversation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationRecord>()).first {
                $0.resolvedRoleID == roleID
            }
        )
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let oldEvent = makeEvent(
            conversationID: conversation.id,
            roleID: roleID,
            role: .user,
            text: "我喜欢乌龙茶",
            index: 1,
            at: oldDate
        )
        context.insert(oldEvent)
        try context.save()
        _ = try MemoryRepository.apply(
            [candidate(eventID: oldEvent.id, value: "乌龙茶", quote: oldEvent.content)],
            eventContents: [oldEvent.id: oldEvent.content],
            eventDates: [oldEvent.id: oldDate],
            context: context,
            deviceID: "fixture",
            extractorID: "fixture",
            roleID: roleID
        )
        context.insert(MemorySummaryRecord(
            conversationID: conversation.id,
            scope: "rolling",
            content: "用户喜欢乌龙茶",
            firstEventID: oldEvent.id,
            lastEventID: oldEvent.id,
            coveredEventCount: 1,
            extractorID: "fixture",
            roleID: roleID
        ))
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        XCTAssertEqual(try fixture.appModel.clearAllMemories(roleID: roleID), 1)

        let clearedContext = ModelContext(fixture.bootstrap.container)
        let clearedMemory = try XCTUnwrap(
            try clearedContext.fetch(FetchDescriptor<MemoryAssertionRecord>()).first {
                $0.resolvedRoleID == roleID
            }
        )
        XCTAssertEqual(clearedMemory.state, .forgotten)
        XCTAssertEqual(clearedMemory.value, "")
        XCTAssertTrue(
            try clearedContext.fetch(FetchDescriptor<MemoryEvidenceRecord>())
                .filter { $0.resolvedRoleID == roleID }
                .isEmpty
        )
        XCTAssertTrue(
            try clearedContext.fetch(FetchDescriptor<MemorySummaryRecord>())
                .filter { $0.resolvedRoleID == roleID }
                .allSatisfy { $0.content.isEmpty }
        )
        let resetAt = try XCTUnwrap(
            try clearedContext.fetch(FetchDescriptor<MemoryTombstoneRecord>())
                .filter {
                    $0.resolvedRoleID == roleID
                        && $0.reason == MemoryRepository.roleResetReason
                        && $0.canonicalKey.isEmpty
                }
                .map(\.deletedAt)
                .max()
        )

        let newEvent = makeEvent(
            conversationID: conversation.id,
            roleID: roleID,
            role: .user,
            text: "最近我喜欢茉莉花茶",
            index: 2,
            at: resetAt.addingTimeInterval(1)
        )
        clearedContext.insert(newEvent)
        try clearedContext.save()

        let staleApplied = try MemoryRepository.apply(
            [candidate(
                eventID: oldEvent.id,
                value: "旧乌龙茶",
                quote: oldEvent.content,
                explicit: true
            )],
            eventContents: [oldEvent.id: oldEvent.content],
            // A stale caller cannot forge a post-reset timestamp for the old
            // persisted source event.
            eventDates: [oldEvent.id: resetAt.addingTimeInterval(10)],
            context: clearedContext,
            deviceID: "fixture",
            extractorID: "fixture",
            roleID: roleID
        )
        XCTAssertEqual(staleApplied, 0)

        let applied = try MemoryRepository.apply(
            [candidate(
                eventID: newEvent.id,
                value: "茉莉花茶",
                quote: newEvent.content,
                explicit: false
            )],
            eventContents: [newEvent.id: newEvent.content],
            eventDates: [newEvent.id: newEvent.occurredAt],
            context: clearedContext,
            deviceID: "fixture",
            extractorID: "fixture",
            roleID: roleID
        )
        XCTAssertEqual(applied, 1)
        XCTAssertTrue(
            try clearedContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
                .contains { $0.resolvedRoleID == roleID && $0.value == "茉莉花茶" }
        )
    }

    func testRedactedSourceCannotCreateOrChangeMemory() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let roleID = fixture.appModel.currentRoleID
        let context = ModelContext(fixture.bootstrap.container)
        let event = makeEvent(
            conversationID: fixture.appModel.currentConversation.id,
            roleID: roleID,
            role: .user,
            text: "这条已删除的信息不能进记忆",
            index: 1,
            at: Date(timeIntervalSince1970: 1_800_300_000)
        )
        event.redacted = true
        context.insert(event)
        try context.save()

        XCTAssertThrowsError(
            try MemoryRepository.apply(
                [candidate(eventID: event.id, value: "不能保留", quote: event.content)],
                eventContents: [event.id: event.content],
                eventDates: [event.id: event.occurredAt],
                context: context,
                deviceID: "fixture",
                extractorID: "fixture",
                roleID: roleID
            )
        ) { error in
            XCTAssertEqual(error as? MemoryRepositoryError, .sourceEventRedacted(event.id))
        }
    }

    func testRecallKeepsAssistantReplyButLateProactiveGenerationCannotSurvive() async throws {
        let suiteName = "AppModelConversationDataActionsTests.proactive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = BlockingProactiveConversationActionClient()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )

        appModel.send("回复后我会撤回这一句")
        try await waitUntil {
            client.requestCount >= 2 && !appModel.isGenerating
        }
        let context = ModelContext(bootstrap.container)
        let userEvent = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>())
                .first { $0.role == .user && !$0.redacted }
        )
        try appModel.recallUserMessage(id: userEvent.id)
        client.releaseProactiveGeneration()
        try await Task.sleep(for: .milliseconds(80))

        let storedEvents = try context.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertTrue(try XCTUnwrap(storedEvents.first { $0.id == userEvent.id }).redacted)
        XCTAssertTrue(storedEvents.contains { $0.role == .assistant && !$0.redacted })
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).isEmpty)
    }

    func testRoleProactiveDisableCancelsLateGenerationEvenAfterImmediateReenable() async throws {
        let suiteName = "AppModelConversationDataActionsTests.proactive-toggle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = BlockingProactiveConversationActionClient()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )

        appModel.send("生成中的主动消息随后会被关闭")
        try await waitUntil {
            client.requestCount >= 2 && !appModel.isGenerating
        }
        let roleID = appModel.currentRoleID
        SettingsStore.setProactiveMessagesEnabled(false, roleID: roleID, defaults: defaults)
        appModel.proactiveMessagingSettingDidChange(enabled: false, roleID: roleID)
        SettingsStore.setProactiveMessagesEnabled(true, roleID: roleID, defaults: defaults)
        appModel.proactiveMessagingSettingDidChange(enabled: true, roleID: roleID)
        client.releaseProactiveGeneration()
        try await Task.sleep(for: .milliseconds(80))

        let context = ModelContext(bootstrap.container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).isEmpty)
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "AppModelConversationDataActionsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: NoopConversationActionClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        return Fixture(
            appModel: appModel,
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func makeEvent(
        conversationID: UUID,
        roleID: UUID = RoleScope.legacyRoleID,
        role: EventRole,
        text: String,
        index: Int,
        at start: Date,
        senderRoleID: UUID? = nil
    ) -> ConversationEvent {
        ConversationEvent(
            conversationID: conversationID,
            deviceID: "fixture",
            deviceSequence: index,
            logicalTimestamp: String(format: "%03d-fixture", index),
            occurredAt: start.addingTimeInterval(Double(index)),
            role: role,
            content: text,
            contentHash: ContentHasher.sha256(text),
            roleID: roleID,
            senderRoleID: senderRoleID
        )
    }

    private func candidate(
        eventID: UUID,
        value: String,
        quote: String,
        explicit: Bool = true
    ) -> ExtractedMemoryCandidate {
        ExtractedMemoryCandidate(
            operation: .upsert,
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: value,
            canonicalKey: "user.favorite_drink",
            confidence: 0.95,
            importance: 0.7,
            explicit: explicit,
            sensitive: false,
            sourceEventID: eventID,
            sourceQuote: quote,
            startUTF16: 0,
            endUTF16: quote.utf16.count,
            validFrom: nil,
            validTo: nil
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
        XCTFail("Timed out waiting for conversation action")
    }
}

@MainActor
private struct Fixture {
    let appModel: AppModel
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
}

private final class BlockingProactiveConversationActionClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var proactiveContinuation: CheckedContinuation<String, Never>?

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
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
        let ordinal: Int = lock.withLock {
            requests += 1
            return requests
        }
        if ordinal == 1 { return "这条 AI 回复需要保留。" }
        return await withCheckedContinuation { continuation in
            lock.withLock { proactiveContinuation = continuation }
        }
    }

    func releaseProactiveGeneration() {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Never>? in
            defer { proactiveContinuation = nil }
            return proactiveContinuation
        }
        continuation?.resume(returning: #"{"initial":"迟到的主动消息","follow_up":""}"#)
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] { [] }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}

private final class NoopConversationActionClient: AIClientProtocol, @unchecked Sendable {
    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String { "" }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] { [] }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}
