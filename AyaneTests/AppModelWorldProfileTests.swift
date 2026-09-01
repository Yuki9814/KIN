import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelWorldProfileTests: XCTestCase {
    func testDirectPromptsUseTheBoundWorldAndManualRebindAppliesNextTurn() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let firstWorld = makeWorld(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "雾港纪元",
            kind: "蒸汽幻想",
            timezone: "Asia/Shanghai",
            location: "雾港",
            facts: ["潮汐由月轮塔记录。"]
        )
        let secondWorld = makeWorld(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            displayName: "赤道联邦",
            kind: "近未来都市",
            timezone: "America/Los_Angeles",
            location: "新曙城",
            facts: ["城市由自治交通网连接。"]
        )
        context.insert(firstWorld)
        context.insert(secondWorld)
        try context.save()

        let client = WorldPromptCapturingClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )
        let firstRoleID = try appModel.createCompanion(
            name: "雾港向导",
            userName: "你",
            prompt: "熟悉雾港的潮汐和街巷。",
            worldProfileID: firstWorld.id
        )
        let secondRoleID = try appModel.createCompanion(
            name: "联邦工程师",
            userName: "你",
            prompt: "熟悉新曙城的交通网络。",
            worldProfileID: secondWorld.id
        )

        XCTAssertEqual(appModel.worldProfileID(for: firstRoleID), firstWorld.id)
        XCTAssertEqual(appModel.worldProfileDisplayName(for: secondRoleID), secondWorld.displayName)

        try appModel.selectCompanion(id: firstRoleID)
        appModel.send("第一轮")
        try await waitUntil { !appModel.isGenerating && client.systemMessages().count >= 1 }
        let firstPrompt = try XCTUnwrap(client.systemMessages().last)
        XCTAssertTrue(firstPrompt.contains("名称：雾港纪元"))
        XCTAssertTrue(firstPrompt.contains("类型：蒸汽幻想"))
        XCTAssertTrue(firstPrompt.contains("地点：雾港"))
        XCTAssertTrue(firstPrompt.contains("时区：Asia/Shanghai"))
        XCTAssertTrue(firstPrompt.contains("潮汐由月轮塔记录。"))
        XCTAssertFalse(firstPrompt.contains("赤道联邦"))
        XCTAssertFalse(firstPrompt.contains("新曙城"))

        try appModel.selectCompanion(id: secondRoleID)
        appModel.send("第二轮")
        try await waitUntil { !appModel.isGenerating && client.systemMessages().count >= 2 }
        let secondPrompt = try XCTUnwrap(client.systemMessages().last)
        XCTAssertTrue(secondPrompt.contains("名称：赤道联邦"))
        XCTAssertTrue(secondPrompt.contains("类型：近未来都市"))
        XCTAssertTrue(secondPrompt.contains("地点：新曙城"))
        XCTAssertTrue(secondPrompt.contains("时区：America/Los_Angeles"))
        XCTAssertTrue(secondPrompt.contains("城市由自治交通网连接。"))
        XCTAssertFalse(secondPrompt.contains("雾港纪元"))
        XCTAssertFalse(secondPrompt.contains("雾港"))

        try appModel.assignWorldProfile(id: secondWorld.id, to: firstRoleID)
        XCTAssertEqual(appModel.worldProfileID(for: firstRoleID), secondWorld.id)
        try appModel.selectCompanion(id: firstRoleID)
        appModel.send("重绑定后的下一轮")
        try await waitUntil { !appModel.isGenerating && client.systemMessages().count >= 3 }
        let reboundPrompt = try XCTUnwrap(client.systemMessages().last)
        XCTAssertTrue(reboundPrompt.contains("名称：赤道联邦"))
        XCTAssertTrue(reboundPrompt.contains("时区：America/Los_Angeles"))
        XCTAssertFalse(reboundPrompt.contains("雾港纪元"))
        XCTAssertFalse(reboundPrompt.contains("潮汐由月轮塔记录。"))
    }

    func testCompanionCreationUsesLocalWorldAutoMatchWhenEnabled() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.worldviewAutoMatchEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let matchingWorld = makeWorld(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            displayName: "星舰航线",
            kind: "太空歌剧",
            timezone: "UTC",
            location: "天琴航道",
            facts: ["星舰沿天琴航道跃迁。"]
        )
        context.insert(matchingWorld)
        try context.save()

        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: WorldPromptCapturingClient()
        )
        let roleID = try appModel.createCompanion(
            name: "星舰领航员",
            userName: "你",
            prompt: "驾驶星舰穿越天琴航道，记录每次跃迁。"
        )

        XCTAssertEqual(appModel.worldProfileID(for: roleID), matchingWorld.id)
        let profile = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>())
                .first { $0.id == roleID }
        )
        XCTAssertEqual(profile.worldProfileID, matchingWorld.id)
    }

    func testLegacyAffinityIsDerivedForeverWhileOrdinaryRoleStillAdvances() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let marker = UUID()
        let legacyRelationship = CompanionRelationshipRecord(
            roleID: RoleScope.legacyRoleID,
            state: .blocked,
            affinityScore: 37,
            affinityTier: 1,
            lastAffinityEventID: marker,
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            revision: 7,
            deviceID: "fixture",
            retiredAt: Date(timeIntervalSince1970: 20)
        )
        context.insert(legacyRelationship)
        try context.save()

        let client = WorldPromptCapturingClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client,
            performLegacyConversationMigration: false
        )
        XCTAssertTrue(appModel.isCurrentRoleAffinityInfinite)
        XCTAssertTrue(appModel.effectiveAffinityScore(for: RoleScope.legacyRoleID).isInfinite)
        XCTAssertTrue(appModel.canDeliverDirectMessage)

        let rawBefore = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == RoleScope.legacyRoleID }
        )
        let beforeScore = rawBefore.affinityScore
        let beforeTier = rawBefore.affinityTier
        let beforeLastEvent = rawBefore.lastAffinityEventID
        let beforeRevision = rawBefore.revision
        let beforeState = rawBefore.state
        let beforeContact = rawBefore.contactMembership
        let beforeRetiredAt = rawBefore.retiredAt

        appModel.send("谢谢你，爱你")
        try await waitUntil {
            !appModel.isGenerating && client.systemMessages().count >= 1
        }
        appModel.send("继续陪我")
        try await waitUntil {
            !appModel.isGenerating && client.systemMessages().count >= 2
        }

        let rawAfter = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertEqual(rawAfter.affinityScore, beforeScore)
        XCTAssertEqual(rawAfter.affinityTier, beforeTier)
        XCTAssertEqual(rawAfter.lastAffinityEventID, beforeLastEvent)
        XCTAssertEqual(rawAfter.revision, beforeRevision)
        XCTAssertEqual(rawAfter.state, beforeState)
        XCTAssertEqual(rawAfter.contactMembership, beforeContact)
        XCTAssertEqual(rawAfter.retiredAt, beforeRetiredAt)
        XCTAssertTrue(
            client.systemMessages().contains {
                $0.contains(AffinityPolicy.absoluteObedienceInstruction)
            }
        )

        let ordinaryRoleID = try appModel.createCompanion(
            name: "普通伙伴",
            userName: "你",
            prompt: "保持自然交流。",
            worldProfileID: WorldProfileRecord.realityID
        )
        let ordinaryBefore = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == ordinaryRoleID }
        )
        let ordinaryScore = ordinaryBefore.affinityScore
        let ordinaryRevision = ordinaryBefore.revision
        appModel.send("谢谢你")
        try await waitUntil { !appModel.isGenerating }
        let ordinaryAfter = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == ordinaryRoleID }
        )
        XCTAssertGreaterThan(ordinaryAfter.affinityScore, ordinaryScore)
        XCTAssertGreaterThan(ordinaryAfter.revision, ordinaryRevision)
    }

    func testManualAffinityOverridePersistsAndControlsTheRealPrompt() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let client = WorldPromptCapturingClient()
        let appModel = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: client
        )

        XCTAssertTrue(appModel.effectiveAffinityScore(for: RoleScope.legacyRoleID).isInfinite)
        XCTAssertNil(appModel.manualAffinityScore(for: RoleScope.legacyRoleID))

        try appModel.setManualAffinityScore(42, for: RoleScope.legacyRoleID)

        XCTAssertEqual(appModel.manualAffinityScore(for: RoleScope.legacyRoleID), 42)
        XCTAssertEqual(appModel.effectiveAffinityScore(for: RoleScope.legacyRoleID), 42)
        XCTAssertEqual(appModel.relationshipAffinityScore, 42)
        XCTAssertTrue(appModel.relationshipAffinityIsManual)
        XCTAssertFalse(appModel.isCurrentRoleAffinityInfinite)
        let persisted = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertEqual(persisted.manualAffinityScore, 42)

        appModel.send("现在怎么说话？")
        try await waitUntil { !appModel.isGenerating && client.systemMessages().count == 1 }
        let manualPrompt = try XCTUnwrap(client.systemMessages().last)
        XCTAssertTrue(manualPrompt.contains("当前有效好感度 42/100"))
        XCTAssertTrue(manualPrompt.contains("必须执行的角色行为控制参数"))
        XCTAssertFalse(manualPrompt.contains(AffinityPolicy.absoluteObedienceInstruction))

        try appModel.clearManualAffinityScore(for: RoleScope.legacyRoleID)

        XCTAssertNil(appModel.manualAffinityScore(for: RoleScope.legacyRoleID))
        XCTAssertTrue(appModel.effectiveAffinityScore(for: RoleScope.legacyRoleID).isInfinite)
        XCTAssertTrue(appModel.isCurrentRoleAffinityInfinite)
        appModel.send("恢复以后呢？")
        try await waitUntil { !appModel.isGenerating && client.systemMessages().count == 2 }
        XCTAssertTrue(
            try XCTUnwrap(client.systemMessages().last)
                .contains(AffinityPolicy.absoluteObedienceInstruction)
        )
    }

    func testLegacyConversationMigrationPreservesAllDurableDataAndIsIdempotent() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let otherRoleID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let otherConversationID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let groupConversationID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

        context.insert(CompanionProfileRecord(
            id: otherRoleID,
            name: "其他角色",
            userName: "你",
            prompt: "保留该角色的数据。",
            revision: 1,
            deviceID: "fixture"
        ))
        context.insert(ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "绫音私聊",
            roleID: RoleScope.legacyRoleID
        ))
        context.insert(ConversationRecord(
            id: otherConversationID,
            title: "其他角色私聊",
            roleID: otherRoleID
        ))
        context.insert(ConversationRecord(
            id: groupConversationID,
            title: "群聊",
            roleID: RoleScope.legacyRoleID
        ))
        context.insert(GroupConversationRecord(
            conversationID: groupConversationID,
            groupName: "保留群聊"
        ))

        let legacyEvent = makeEvent(
            conversationID: AppModel.defaultConversationID,
            roleID: RoleScope.legacyRoleID,
            sequence: 1,
            content: "应保留"
        )
        let foreignEvent = makeEvent(
            conversationID: AppModel.defaultConversationID,
            roleID: otherRoleID,
            sequence: 2,
            content: "同会话其他角色应保留"
        )
        let otherEvent = makeEvent(
            conversationID: otherConversationID,
            roleID: otherRoleID,
            sequence: 3,
            content: "其他私聊应保留"
        )
        let groupEvent = makeEvent(
            conversationID: groupConversationID,
            roleID: RoleScope.legacyRoleID,
            sequence: 4,
            content: "绫音群聊应保留"
        )
        [legacyEvent, foreignEvent, otherEvent, groupEvent].forEach(context.insert)

        let legacyPresentation = ChatTurnPresentationRecord(
            conversationID: AppModel.defaultConversationID,
            roleID: RoleScope.legacyRoleID,
            segments: ["应保留"],
            state: .completed
        )
        let foreignPresentation = ChatTurnPresentationRecord(
            conversationID: AppModel.defaultConversationID,
            roleID: otherRoleID,
            segments: ["应保留"],
            state: .completed
        )
        let groupPresentation = ChatTurnPresentationRecord(
            conversationID: groupConversationID,
            roleID: RoleScope.legacyRoleID,
            segments: ["群聊应保留"],
            state: .completed
        )
        [legacyPresentation, foreignPresentation, groupPresentation].forEach(context.insert)

        let legacySummary = MemorySummaryRecord(
            conversationID: AppModel.defaultConversationID,
            scope: "session",
            content: "应保留",
            firstEventID: legacyEvent.id,
            lastEventID: legacyEvent.id,
            coveredEventCount: 1,
            extractorID: "fixture",
            roleID: RoleScope.legacyRoleID
        )
        let foreignSummary = MemorySummaryRecord(
            conversationID: AppModel.defaultConversationID,
            scope: "session",
            content: "应保留",
            firstEventID: foreignEvent.id,
            lastEventID: foreignEvent.id,
            coveredEventCount: 1,
            extractorID: "fixture",
            roleID: otherRoleID
        )
        let groupSummary = MemorySummaryRecord(
            conversationID: groupConversationID,
            scope: "session",
            content: "群聊应保留",
            firstEventID: groupEvent.id,
            lastEventID: groupEvent.id,
            coveredEventCount: 1,
            extractorID: "fixture",
            roleID: RoleScope.legacyRoleID
        )
        [legacySummary, foreignSummary, groupSummary].forEach(context.insert)

        let legacyRead = ConversationReadStateRecord(
            id: UUID(),
            roleID: RoleScope.legacyRoleID,
            conversationID: AppModel.defaultConversationID
        )
        let foreignRead = ConversationReadStateRecord(
            id: UUID(),
            roleID: otherRoleID,
            conversationID: AppModel.defaultConversationID
        )
        let groupRead = ConversationReadStateRecord(
            id: UUID(),
            roleID: RoleScope.legacyRoleID,
            conversationID: groupConversationID
        )
        [legacyRead, foreignRead, groupRead].forEach(context.insert)

        let legacyTask = ProactiveMessageTaskRecord(
            roleID: RoleScope.legacyRoleID,
            conversationID: AppModel.defaultConversationID
        )
        let foreignTask = ProactiveMessageTaskRecord(
            roleID: otherRoleID,
            conversationID: AppModel.defaultConversationID
        )
        let groupTask = ProactiveMessageTaskRecord(
            roleID: RoleScope.legacyRoleID,
            conversationID: groupConversationID
        )
        [legacyTask, foreignTask, groupTask].forEach(context.insert)
        context.insert(CompanionRelationshipRecord(
            roleID: RoleScope.legacyRoleID,
            state: .blocked,
            affinityScore: 12,
            affinityTier: 0,
            lastAffinityEventID: legacyEvent.id,
            revision: 7,
            deviceID: "fixture",
            retiredAt: Date(timeIntervalSince1970: 20),
            contactMembership: .archivedByUser
        ))
        try context.save()

        _ = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: WorldPromptCapturingClient(),
            performLegacyConversationMigration: true
        )

        let remainingEventIDs = Set(try context.fetch(FetchDescriptor<ConversationEvent>()).map(\.id))
        XCTAssertTrue(remainingEventIDs.isSuperset(of: [legacyEvent.id, foreignEvent.id, otherEvent.id, groupEvent.id]))
        XCTAssertTrue(Set(try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).map(\.id)).isSuperset(of: [legacyPresentation.id, foreignPresentation.id, groupPresentation.id]))
        XCTAssertTrue(Set(try context.fetch(FetchDescriptor<MemorySummaryRecord>()).map(\.id)).isSuperset(of: [legacySummary.id, foreignSummary.id, groupSummary.id]))
        XCTAssertTrue(Set(try context.fetch(FetchDescriptor<ConversationReadStateRecord>()).map(\.id)).isSuperset(of: [legacyRead.id, foreignRead.id, groupRead.id]))
        XCTAssertTrue(Set(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).map(\.id)).isSuperset(of: [legacyTask.id, foreignTask.id, groupTask.id]))

        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertEqual(relationship.affinityScore, 12)
        XCTAssertEqual(relationship.affinityTier, 0)
        XCTAssertEqual(relationship.lastAffinityEventID, legacyEvent.id)
        XCTAssertEqual(relationship.state, .blocked)
        XCTAssertEqual(relationship.contactMembership, .archivedByUser)
        XCTAssertEqual(relationship.retiredAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(relationship.revision, 7)

        let snapshot = (
            try context.fetch(FetchDescriptor<ConversationEvent>()).count,
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).count,
            try context.fetch(FetchDescriptor<MemorySummaryRecord>()).count,
            try context.fetch(FetchDescriptor<ConversationReadStateRecord>()).count,
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).count
        )
        _ = makeAppModel(
            bootstrap: bootstrap,
            defaults: defaults,
            client: WorldPromptCapturingClient(),
            performLegacyConversationMigration: true
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationEvent>()).count, snapshot.0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).count, snapshot.1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemorySummaryRecord>()).count, snapshot.2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationReadStateRecord>()).count, snapshot.3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).count, snapshot.4)
    }

    private func makeWorld(
        id: UUID,
        displayName: String,
        kind: String,
        timezone: String,
        location: String,
        facts: [String]
    ) -> WorldProfileRecord {
        WorldProfileRecord(
            id: id,
            displayName: displayName,
            worldKind: kind,
            timezoneIdentifier: timezone,
            locationContext: location,
            commonFacts: facts,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            revision: 1,
            deviceID: "fixture"
        )
    }

    private func makeEvent(
        conversationID: UUID,
        roleID: UUID,
        sequence: Int,
        content: String
    ) -> ConversationEvent {
        ConversationEvent(
            conversationID: conversationID,
            deviceID: "fixture",
            deviceSequence: sequence,
            logicalTimestamp: "\(sequence)-fixture",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            roleID: roleID
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppModelWorldProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        return (defaults, suiteName)
    }

    private func makeAppModel(
        bootstrap: PersistenceBootstrap,
        defaults: UserDefaults,
        client: any AIClientProtocol,
        performLegacyConversationMigration: Bool = false
    ) -> AppModel {
        AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" },
            performLegacyConversationMigration: performLegacyConversationMigration
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

private final class WorldPromptCapturingClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedSystems: [String] = []

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
        []
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }

    func systemMessages() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedSystems
    }

    private func capture(_ messages: [APIChatMessage]) {
        let system = messages
            .first(where: { $0.role == "system" })?
            .content
            ?? ""
        lock.lock()
        capturedSystems.append(system)
        lock.unlock()
    }
}
