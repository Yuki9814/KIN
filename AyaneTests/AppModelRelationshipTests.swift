import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelRelationshipTests: XCTestCase {
    func testRejectedContactStatePersistsUndeliveredWithoutCallingAPI() async throws {
        let (defaults, suiteName) = try makeDefaults(provider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = RelationshipCountingClient()
        var keyReads = 0
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: {
                keyReads += 1
                return "test-key"
            }
        )
        let roleID = try appModel.createCompanion(
            name: "关系测试",
            userName: "你",
            prompt: "保持清醒"
        )
        let context = ModelContext(bootstrap.container)
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == roleID }
        )
        relationship.state = .rejected
        relationship.revision += 1
        try context.save()
        appModel.refreshFromStore(force: true)

        XCTAssertTrue(appModel.canSendMessages)
        appModel.send("这条消息应当未送达")
        try await waitUntil { !appModel.isGenerating }

        let event = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>())
                .last { $0.roleID == roleID && $0.content == "这条消息应当未送达" }
        )
        XCTAssertEqual(event.deliveryState, .undelivered)
        XCTAssertEqual(keyReads, 0)
        XCTAssertEqual(client.chatRequests, 0)
    }

    func testDeleteThresholdCompletesTriggeringTurnThenRejectsNextSend() async throws {
        let (defaults, suiteName) = try makeDefaults(provider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = RelationshipCountingClient()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "test-key" }
        )
        let roleID = try appModel.createCompanion(
            name: "关系测试",
            userName: "你",
            prompt: "保持清醒"
        )

        for _ in 0..<3 {
            appModel.send("你这个废物")
            try await waitUntil { !appModel.isGenerating }
        }

        XCTAssertEqual(appModel.relationshipState, .deleted)
        XCTAssertTrue(appModel.canSendMessages)
        XCTAssertEqual(client.chatRequests, 3)
        let context = ModelContext(bootstrap.container)
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.roleID == roleID && $0.content == "你这个废物" }
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.deliveryState == .complete })
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<CompanionRelationshipTransitionRecord>())
                .contains { $0.roleID == roleID && $0.toState == .deleted }
        )

        appModel.send("删除后的下一条")
        let rejectedEvent = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>())
                .last { $0.roleID == roleID && $0.content == "删除后的下一条" }
        )
        XCTAssertEqual(rejectedEvent.deliveryState, .undelivered)
        XCTAssertEqual(client.chatRequests, 3)
    }

    func testInfiniteAffinityBuiltInNeverEntersLocalHarmOrDeletionFlow() async throws {
        let (defaults, suiteName) = try makeDefaults(provider: true)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = RelationshipCountingClient()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "test-key" },
            seedBuiltInCompanions: true
        )
        let roleID = RoleScope.legacyRoleID
        try appModel.selectCompanion(id: roleID)

        for _ in 0..<3 {
            appModel.send("你这个废物")
            try await waitUntil { !appModel.isGenerating }
        }

        let context = ModelContext(bootstrap.container)
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == roleID }
        )
        XCTAssertEqual(relationship.state, .accepted)
        XCTAssertEqual(relationship.contactMembership, .active)
        XCTAssertNil(relationship.retiredAt)
        XCTAssertEqual(relationship.harmStreak, 0)
        XCTAssertEqual(appModel.effectiveAffinityScore(for: roleID), .infinity)
        XCTAssertEqual(client.chatRequests, 3)
    }

    func testArchiveAndRestorePreserveRoleConversationMemoryBoundaryAndGroupMembership() throws {
        let (defaults, suiteName) = try makeDefaults(provider: false)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: RelationshipCountingClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let archivedRoleID = try appModel.createCompanion(
            name: "归档测试",
            userName: "你",
            prompt: "保留原始数据"
        )
        let peerRoleID = try appModel.createCompanion(
            name: "群聊同伴",
            userName: "你",
            prompt: "参与群聊"
        )
        let groupID = try appModel.createGroup(
            name: "保留群",
            participantRoleIDs: [archivedRoleID, peerRoleID]
        )
        let context = ModelContext(bootstrap.container)
        let directConversation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationRecord>())
                .first { $0.resolvedRoleID == archivedRoleID && $0.id != groupID }
        )
        let originalConversationID = directConversation.id
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == archivedRoleID }
        )
        relationship.affinityScore = 80
        relationship.revision += 1
        try context.save()
        let archivedAt = Date()

        try appModel.archiveCompanion(roleID: archivedRoleID)

        let archivedContext = ModelContext(bootstrap.container)
        let archivedRelationship = try XCTUnwrap(
            try archivedContext.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == archivedRoleID }
        )
        let archivedConversation = try XCTUnwrap(
            try archivedContext.fetch(FetchDescriptor<ConversationRecord>())
                .first { $0.id == originalConversationID }
        )
        XCTAssertFalse(appModel.companions.contains { $0.id == archivedRoleID })
        XCTAssertTrue(appModel.archivedCompanions.contains { $0.id == archivedRoleID })
        XCTAssertEqual(archivedRelationship.contactMembership, .archivedByUser)
        XCTAssertNil(archivedRelationship.retiredAt)
        XCTAssertTrue(archivedConversation.archived)
        XCTAssertTrue(
            try archivedContext.fetch(FetchDescriptor<GroupParticipantRecord>()).contains {
                $0.conversationID == groupID
                    && $0.participantRoleID == archivedRoleID
                    && $0.lifecycle == .active
                    && $0.leftAt == nil
            }
        )
        let request = try XCTUnwrap(
            try archivedContext.fetch(FetchDescriptor<FriendApplicationRecord>()).first {
                $0.roleID == archivedRoleID
                    && $0.direction == .incoming
                    && $0.status == .scheduled
            }
        )
        XCTAssertGreaterThanOrEqual(request.scheduledAt.timeIntervalSince(archivedAt), 3 * 86_400 - 1)
        XCTAssertLessThanOrEqual(request.scheduledAt.timeIntervalSince(archivedAt), 14 * 86_400 + 1)

        try appModel.restoreArchivedCompanion(roleID: archivedRoleID)

        let restoredContext = ModelContext(bootstrap.container)
        let restoredRelationship = try XCTUnwrap(
            try restoredContext.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == archivedRoleID }
        )
        let restoredConversation = try XCTUnwrap(
            try restoredContext.fetch(FetchDescriptor<ConversationRecord>())
                .first { $0.id == originalConversationID }
        )
        XCTAssertTrue(appModel.companions.contains { $0.id == archivedRoleID })
        XCTAssertFalse(appModel.archivedCompanions.contains { $0.id == archivedRoleID })
        XCTAssertEqual(restoredRelationship.contactMembership, .active)
        XCTAssertFalse(restoredConversation.archived)
        XCTAssertEqual(appModel.currentRoleID, archivedRoleID)

        try appModel.savePersona(
            name: "归档测试·已更新",
            userName: "你",
            prompt: "更新后的人格参数"
        )
        XCTAssertEqual(
            appModel.groupParticipants(conversationID: groupID)
                .first { $0.roleID == archivedRoleID }?.displayName,
            "归档测试·已更新"
        )
        XCTAssertTrue(
            appModel.groupConversations.first { $0.conversationID == groupID }?
                .participantNames.contains("归档测试·已更新") == true
        )
        XCTAssertEqual(
            try restoredContext.fetch(FetchDescriptor<CompanionProfileRecord>())
                .filter { $0.id == archivedRoleID }.count,
            1
        )
        XCTAssertTrue(
            try restoredContext.fetch(FetchDescriptor<ConversationRecord>())
                .contains { $0.id == originalConversationID && !$0.archived }
        )
    }

    private func makeDefaults(provider: Bool) throws -> (UserDefaults, String) {
        let suiteName = "AppModelRelationshipTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        if provider {
            defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
            defaults.set("fixture-model", forKey: SettingsKeys.model)
            defaults.set("", forKey: SettingsKeys.embeddingModel)
            defaults.set(false, forKey: SettingsKeys.streamResponses)
        }
        return (defaults, suiteName)
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

private final class RelationshipCountingClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var chatRequestCount = 0

    var chatRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return chatRequestCount
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        recordChatRequest()
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
        recordChatRequest()
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
        ConnectionTestResult(latency: 0, reply: "OK")
    }

    private func recordChatRequest() {
        lock.lock()
        chatRequestCount += 1
        lock.unlock()
    }
}
