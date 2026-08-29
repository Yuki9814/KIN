import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelConversationCareTests: XCTestCase {
    func testSettingsDefaultsAndBounds() throws {
        let suiteName = "AppModelConversationCareTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(SettingsStore.conversationCareEnabled(defaults: defaults))
        XCTAssertEqual(
            SettingsStore.conversationCareFirstReminderMinutes(defaults: defaults),
            90
        )

        defaults.set(false, forKey: SettingsKeys.conversationCareEnabled)
        defaults.set(10, forKey: SettingsKeys.conversationCareFirstReminderMinutes)
        XCTAssertFalse(SettingsStore.conversationCareEnabled(defaults: defaults))
        XCTAssertEqual(
            SettingsStore.conversationCareFirstReminderMinutes(defaults: defaults),
            60
        )

        defaults.set(999, forKey: SettingsKeys.conversationCareFirstReminderMinutes)
        XCTAssertEqual(
            SettingsStore.conversationCareFirstReminderMinutes(defaults: defaults),
            180
        )
    }

    func testDueCareIsGeneratedAtDeliveryTimeAndRemainsIdempotent() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date()
        try insertContinuousConversation(
            into: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id,
            roleID: fixture.appModel.currentRoleID,
            now: now
        )

        fixture.appModel.processDueProactiveTasks(
            now: now,
            allowConversationCareDelivery: false
        )
        let scheduled = careTasks(in: fixture.bootstrap.container)
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(scheduled.map(\.followUpCount).sorted(), [0, 1])
        XCTAssertEqual(
            scheduled.filter { $0.followUpCount == 0 }.first?.scheduledAt
                .timeIntervalSince(now) ?? 0,
            -10 * 60,
            accuracy: 0.5
        )
        XCTAssertEqual(
            scheduled.filter { $0.followUpCount == 1 }.first?.scheduledAt
                .timeIntervalSince(now) ?? 0,
            80 * 60,
            accuracy: 0.5
        )

        let scheduledIDs = Set(scheduled.map(\.id))
        let restartedModel = AppModel(
            bootstrap: fixture.bootstrap,
            client: fixture.client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: fixture.defaults,
            apiKeyLoader: { "fixture-key" },
            performLegacyConversationMigration: false,
            seedBuiltInCompanions: false
        )
        XCTAssertEqual(
            Set(careTasks(in: fixture.bootstrap.container).map(\.id)),
            scheduledIDs
        )

        restartedModel.conversationCareAppActivityDidChange(isActive: true)
        restartedModel.processDueProactiveTasks(now: now)
        try await waitUntil {
            self.careTasks(in: fixture.bootstrap.container)
                .contains { $0.followUpCount == 0 && $0.state == .completed }
        }

        XCTAssertEqual(fixture.client.completeRequestCount, 1)
        let delivered = deliveredCareEvents(
            in: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id
        )
        XCTAssertEqual(delivered.count, 1)
        XCTAssertEqual(delivered.first?.content, "主人，我们已经聊很久了，先让眼睛休息一下吧。")
        let prompt = try XCTUnwrap(fixture.client.latestUserPrompt)
        XCTAssertTrue(prompt.contains("已经连续聊天 100 分钟"))
        XCTAssertTrue(prompt.contains("本轮连续聊天开始"))
        XCTAssertTrue(prompt.contains("最近对话"))

        restartedModel.processDueProactiveTasks(now: now.addingTimeInterval(1))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.client.completeRequestCount, 1)
        XCTAssertEqual(
            deliveredCareEvents(
                in: fixture.bootstrap.container,
                conversationID: fixture.appModel.currentConversation.id
            ).count,
            1
        )
    }

    func testIdleSessionCancelsPersistedCareWithoutGenerating() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date()
        try insertContinuousConversation(
            into: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id,
            roleID: fixture.appModel.currentRoleID,
            now: now
        )
        fixture.appModel.processDueProactiveTasks(
            now: now,
            allowConversationCareDelivery: false
        )
        XCTAssertEqual(careTasks(in: fixture.bootstrap.container).count, 2)

        fixture.appModel.processDueProactiveTasks(
            now: now.addingTimeInterval(21 * 60)
        )

        let tasks = careTasks(in: fixture.bootstrap.container)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertTrue(tasks.allSatisfy { $0.state == .cancelled })
        XCTAssertEqual(fixture.client.completeRequestCount, 0)
        XCTAssertTrue(
            deliveredCareEvents(
                in: fixture.bootstrap.container,
                conversationID: fixture.appModel.currentConversation.id
            ).isEmpty
        )
    }

    func testCareDoesNotGenerateUntilApplicationIsActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date()
        try insertContinuousConversation(
            into: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id,
            roleID: fixture.appModel.currentRoleID,
            now: now
        )

        fixture.appModel.processDueProactiveTasks(now: now)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.client.completeRequestCount, 0)

        fixture.appModel.conversationCareAppActivityDidChange(isActive: true)
        fixture.appModel.processDueProactiveTasks(now: now)
        try await waitUntil {
            self.careTasks(in: fixture.bootstrap.container)
                .contains { $0.followUpCount == 0 && $0.state == .completed }
        }
        XCTAssertEqual(fixture.client.completeRequestCount, 1)
    }

    func testUnparentedProactiveAssistantEventsDoNotBridgeAConversationSession() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date()
        try insertConversation(
            into: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id,
            roleID: fixture.appModel.currentRoleID,
            now: now,
            offsets: [
                (-100, .assistant),
                (-85, .user),
                (-70, .assistant),
                (-55, .user),
                (-40, .assistant),
                (-25, .user),
                (-10, .assistant),
                (-2, .user)
            ],
            parentAssistantReplies: false
        )

        fixture.appModel.processDueProactiveTasks(
            now: now,
            allowConversationCareDelivery: false
        )

        XCTAssertTrue(careTasks(in: fixture.bootstrap.container).isEmpty)
    }

    func testOverdueMilestonesDeliverInOrderAcrossSchedulerPasses() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let now = Date()
        try insertConversation(
            into: fixture.bootstrap.container,
            conversationID: fixture.appModel.currentConversation.id,
            roleID: fixture.appModel.currentRoleID,
            now: now,
            offsets: [
                (-190, .user), (-176, .assistant),
                (-162, .user), (-148, .assistant),
                (-134, .user), (-120, .assistant),
                (-106, .user), (-92, .assistant),
                (-78, .user), (-64, .assistant),
                (-50, .user), (-36, .assistant),
                (-22, .user), (-8, .assistant),
                (-2, .user)
            ]
        )
        fixture.appModel.conversationCareAppActivityDidChange(isActive: true)

        fixture.appModel.processDueProactiveTasks(now: now)
        try await waitUntil {
            self.careTasks(in: fixture.bootstrap.container)
                .contains { $0.followUpCount == 0 && $0.state == .completed }
        }
        XCTAssertEqual(fixture.client.completeRequestCount, 1)
        XCTAssertFalse(
            careTasks(in: fixture.bootstrap.container)
                .contains { $0.followUpCount == 1 && $0.state == .completed }
        )

        fixture.appModel.processDueProactiveTasks(now: now.addingTimeInterval(1))
        try await waitUntil {
            self.careTasks(in: fixture.bootstrap.container)
                .contains { $0.followUpCount == 1 && $0.state == .completed }
        }
        XCTAssertEqual(fixture.client.completeRequestCount, 2)
    }

    private func makeFixture() throws -> ConversationCareFixture {
        let suiteName = "AppModelConversationCareTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(ProviderPreset.deepSeek.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(true, forKey: SettingsKeys.conversationCareEnabled)
        defaults.set(90, forKey: SettingsKeys.conversationCareFirstReminderMinutes)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(
            inMemory: true,
            preferCloud: false
        )
        let client = ConversationCareCapturingClient(
            response: "主人，我们已经聊很久了，先让眼睛休息一下吧。"
        )
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" },
            performLegacyConversationMigration: false,
            seedBuiltInCompanions: false
        )
        return ConversationCareFixture(
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName,
            client: client,
            appModel: appModel
        )
    }

    private func insertContinuousConversation(
        into container: ModelContainer,
        conversationID: UUID,
        roleID: UUID,
        now: Date
    ) throws {
        let offsets: [(minutes: Int, role: EventRole)] = [
            (-100, .user),
            (-86, .assistant),
            (-72, .user),
            (-58, .assistant),
            (-44, .user),
            (-30, .assistant),
            (-16, .user),
            (-2, .assistant)
        ]
        try insertConversation(
            into: container,
            conversationID: conversationID,
            roleID: roleID,
            now: now,
            offsets: offsets
        )
    }

    private func insertConversation(
        into container: ModelContainer,
        conversationID: UUID,
        roleID: UUID,
        now: Date,
        offsets: [(minutes: Int, role: EventRole)],
        parentAssistantReplies: Bool = true
    ) throws {
        let context = ModelContext(container)
        var lastUserEventID: UUID?
        for (index, item) in offsets.enumerated() {
            let content = item.role == .user
                ? "用户消息 \(index)"
                : "角色回复 \(index)"
            let eventID = UUID()
            context.insert(ConversationEvent(
                id: eventID,
                conversationID: conversationID,
                deviceID: "care-test",
                deviceSequence: index + 1,
                logicalTimestamp: String(format: "care-%02d", index),
                occurredAt: now.addingTimeInterval(TimeInterval(item.minutes * 60)),
                role: item.role,
                content: content,
                contentHash: ContentHasher.sha256(content),
                parentEventID: item.role == .assistant && parentAssistantReplies
                    ? lastUserEventID
                    : nil,
                deliveryState: .complete,
                roleID: roleID
            ))
            if item.role == .user { lastUserEventID = eventID }
        }
        try context.save()
    }

    private func careTasks(in container: ModelContainer) -> [ProactiveMessageTaskRecord] {
        let context = ModelContext(container)
        return ((try? context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())) ?? [])
            .filter { $0.idempotencyKey.hasPrefix("conversation-care:") }
            .sorted {
                if $0.followUpCount != $1.followUpCount {
                    return $0.followUpCount < $1.followUpCount
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func deliveredCareEvents(
        in container: ModelContainer,
        conversationID: UUID
    ) -> [ConversationEvent] {
        let context = ModelContext(container)
        return ((try? context.fetch(FetchDescriptor<ConversationEvent>())) ?? [])
            .filter {
                $0.conversationID == conversationID
                    && $0.role == .assistant
                    && $0.content == "主人，我们已经聊很久了，先让眼睛休息一下吧。"
            }
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
        XCTFail("Timed out waiting for continuous-conversation care")
    }
}

private struct ConversationCareFixture {
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
    let client: ConversationCareCapturingClient
    let appModel: AppModel
}

private final class ConversationCareCapturingClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let response: String
    private var requests = 0
    private var userPrompt: String?

    init(response: String) {
        self.response = response
    }

    var completeRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    var latestUserPrompt: String? {
        lock.lock()
        defer { lock.unlock() }
        return userPrompt
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
        record(messages)
        return response
    }

    private func record(_ messages: [APIChatMessage]) {
        lock.lock()
        requests += 1
        userPrompt = messages.last(where: { $0.role == "user" })?.content
        lock.unlock()
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
