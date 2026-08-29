import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelMemoryMaintenanceTests: XCTestCase {
    func testFourRapidTurnsTriggerBatchExtractionAndRemainSerial() async throws {
        let suiteName = "AppModelMemoryMaintenanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.2, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(true, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)

        let fixtureClient = DelayedFixtureAIClient()
        fixtureClient.metrics.reset()

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        let turns = [
            "第一轮，我喜欢茶",
            "第二轮，我补充喜欢乌龙茶",
            "第三轮，我常在下午喝茶",
            "第四轮，请把这几件事一起整理"
        ]
        for (index, text) in turns.enumerated() {
            appModel.send(text)
            try await waitUntil {
                !appModel.isGenerating
                    && appModel.messages.filter {
                        $0.role == .assistant && $0.deliveryState == .complete
                    }.count == index + 1
            }
        }
        try await waitUntil(timeout: 6) {
            !appModel.isOrganizingMemory && appModel.pendingMemoryCount == 0
        }

        let snapshot = fixtureClient.metrics.snapshot()
        XCTAssertEqual(snapshot.chatRequests, 4)
        XCTAssertEqual(snapshot.extractionRequests, 4)
        XCTAssertEqual(snapshot.maximumConcurrentExtractions, 1)

        let context = ModelContext(bootstrap.container)
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        let users = events
            .filter { $0.role == .user }
            .sorted { $0.deviceSequence < $1.deviceSequence }
        let assistants = events
            .filter { $0.role == .assistant && $0.deliveryState == .complete }
            .sorted { $0.deviceSequence < $1.deviceSequence }
        XCTAssertEqual(users.count, 4)
        XCTAssertEqual(assistants.map(\.parentEventID), users.map { Optional($0.id) })
        XCTAssertTrue(users.allSatisfy {
            $0.memoryProcessedAt != nil
                && $0.memoryProcessingVersion == MemoryExtractionParser.processingVersion
        })
    }

    func testExplicitMemoryDoesNotScheduleDuplicateExtraction() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        appModel.send("请记住我喜欢乌龙茶")
        try await waitUntil(timeout: 4) {
            !appModel.isGenerating
                && !appModel.isOrganizingMemory
                && appModel.pendingMemoryCount == 0
        }

        XCTAssertEqual(fixtureClient.metrics.snapshot().extractionRequests, 0)
        let context = ModelContext(bootstrap.container)
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        let user = try XCTUnwrap(events.first { $0.role == .user })
        XCTAssertEqual(user.memoryProcessingVersion, MemoryExtractionParser.processingVersion)
        XCTAssertNotNil(user.memoryProcessedAt)
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertTrue(memories.contains { $0.value == "我喜欢乌龙茶" })
    }

    func testExplicitMemoryPersistsWithoutConfiguredAIConnection() throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        defaults.set("", forKey: SettingsKeys.baseURL)
        defaults.set("", forKey: SettingsKeys.model)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: DelayedFixtureAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        appModel.send("请记住我喜欢乌龙茶")

        XCTAssertFalse(appModel.isGenerating)
        let context = ModelContext(bootstrap.container)
        let memory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first
        )
        XCTAssertEqual(memory.value, "我喜欢乌龙茶")
        XCTAssertEqual(memory.state, .active)
    }

    func testOrdinaryDirectFactBecomesActiveAndIsRecalledWithoutEmbedding() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DirectFactFixtureAIClient()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let roleID = try appModel.createCompanion(
            name: "测试角色",
            userName: "用户",
            prompt: "自然聊天并尊重用户边界"
        )
        XCTAssertEqual(appModel.currentRoleID, roleID)

        appModel.send("我住在上海")
        try await waitUntil(timeout: 6) {
            !appModel.isGenerating
                && !appModel.isOrganizingMemory
                && appModel.pendingMemoryCount == 0
                && appModel.memoryCount == 1
        }

        let context = ModelContext(bootstrap.container)
        let memory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first
        )
        XCTAssertEqual(memory.value, "上海")
        XCTAssertEqual(memory.state, .active)
        XCTAssertEqual(memory.resolvedRoleID, roleID)

        appModel.send("你还记得我住在哪里吗？")
        try await waitUntil(timeout: 4) { !appModel.isGenerating }
        XCTAssertTrue(fixtureClient.lastChatPrompt().contains("上海"))
    }

    func testInterleavedParentRepliesPairStrictlyAndKeepEvidenceOnReply() async throws {
        let defaults = try makeDefaults(autoExtract: false)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = ParentPairingFixtureAIClient()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        let conversationID = appModel.currentConversation.id
        let user1 = ConversationEvent(
            id: uuid(7_101),
            conversationID: conversationID,
            deviceID: "legacy-device",
            deviceSequence: 1,
            logicalTimestamp: "000001",
            occurredAt: Date(timeIntervalSince1970: 1),
            role: .user,
            content: "U1 请求",
            contentHash: ContentHasher.sha256("U1 请求")
        )
        let user2 = ConversationEvent(
            id: uuid(7_102),
            conversationID: conversationID,
            deviceID: "legacy-device",
            deviceSequence: 2,
            logicalTimestamp: "000002",
            occurredAt: Date(timeIntervalSince1970: 2),
            role: .user,
            content: "U2 请求",
            contentHash: ContentHasher.sha256("U2 请求")
        )
        let assistant1 = ConversationEvent(
            id: uuid(7_103),
            conversationID: conversationID,
            deviceID: "legacy-device",
            deviceSequence: 3,
            logicalTimestamp: "000003",
            occurredAt: Date(timeIntervalSince1970: 3),
            role: .assistant,
            content: "A1 独有证据",
            contentHash: ContentHasher.sha256("A1 独有证据"),
            parentEventID: user1.id
        )
        let assistant2 = ConversationEvent(
            id: uuid(7_104),
            conversationID: conversationID,
            deviceID: "legacy-device",
            deviceSequence: 4,
            logicalTimestamp: "000004",
            occurredAt: Date(timeIntervalSince1970: 4),
            role: .assistant,
            content: "A2 独有证据",
            contentHash: ContentHasher.sha256("A2 独有证据"),
            parentEventID: user2.id
        )
        let context = ModelContext(bootstrap.container)
        context.insert(user1)
        context.insert(user2)
        context.insert(assistant1)
        context.insert(assistant2)
        try context.save()
        appModel.refreshFromStore(force: true)

        XCTAssertEqual(appModel.pendingMemoryCount, 2)
        appModel.retryPendingMemory(limit: 2)
        try await waitUntil(timeout: 6) {
            !appModel.isOrganizingMemory && appModel.pendingMemoryCount == 0
        }

        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        let evidenceByEvent = Dictionary(uniqueKeysWithValues: evidence.map { ($0.eventID, $0) })
        XCTAssertEqual(Set(evidenceByEvent.keys), Set([assistant1.id, assistant2.id]))
        XCTAssertEqual(
            evidenceByEvent[assistant1.id]?.quoteHash,
            ContentHasher.sha256(assistant1.content)
        )
        XCTAssertEqual(
            evidenceByEvent[assistant2.id]?.quoteHash,
            ContentHasher.sha256(assistant2.content)
        )
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(
            Set(memories.map(\.value)),
            Set([assistant1.content, assistant2.content])
        )
    }

    func testLargeConversationLoadsLatestWindowThenPaginatesAll520Events() throws {
        let defaults = try makeDefaults(autoExtract: false)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: DelayedFixtureAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let context = ModelContext(bootstrap.container)
        insertEvents(count: 520, into: context, conversationID: appModel.currentConversation.id)
        appModel.refreshFromStore(force: true)

        XCTAssertEqual(appModel.messages.count, 240)
        XCTAssertEqual(appModel.messages.first?.content, "事件 281")
        XCTAssertEqual(appModel.messages.last?.content, "事件 520")
        XCTAssertTrue(appModel.hasOlderMessages)

        appModel.loadOlderMessages()
        XCTAssertEqual(appModel.messages.count, 480)
        XCTAssertEqual(appModel.messages.first?.content, "事件 41")
        XCTAssertEqual(appModel.messages.last?.content, "事件 520")
        XCTAssertTrue(appModel.hasOlderMessages)

        appModel.loadOlderMessages()
        XCTAssertEqual(appModel.messages.count, 520)
        XCTAssertEqual(appModel.messages.first?.content, "事件 1")
        XCTAssertEqual(appModel.messages.last?.content, "事件 520")
        XCTAssertFalse(appModel.hasOlderMessages)
        XCTAssertEqual(appModel.messages.map(\.content), (1...520).map { "事件 \($0)" })
    }

    func testPendingMemoryCountAndRetryIncludeEventsOutsideUIWindow() async throws {
        let defaults = try makeDefaults(autoExtract: false)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let context = ModelContext(bootstrap.container)
        insertEvents(
            count: 300,
            into: context,
            conversationID: appModel.currentConversation.id,
            role: .user
        )
        appModel.refreshFromStore(force: true)

        XCTAssertEqual(appModel.messages.count, 240)
        XCTAssertEqual(appModel.pendingMemoryCount, 300)

        appModel.retryPendingMemory(limit: 1)
        try await waitUntil(timeout: 3) {
            !appModel.isOrganizingMemory && appModel.pendingMemoryCount == 299
        }
        let events = try context.fetch(
            FetchDescriptor<ConversationEvent>(
                sortBy: [SortDescriptor(\.deviceSequence, order: .forward)]
            )
        )
        XCTAssertEqual(
            events.first?.memoryProcessingVersion,
            MemoryExtractionParser.processingVersion
        )
        XCTAssertNotNil(events.first?.memoryProcessedAt)
    }

    func testStartupResumesPersistedMemoryBacklogWithoutAnotherChat() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient(extractionDelay: .milliseconds(1))
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        context.insert(ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "绫音"
        ))
        insertEvents(
            count: 2,
            into: context,
            conversationID: AppModel.defaultConversationID,
            role: .user
        )

        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        XCTAssertEqual(appModel.pendingMemoryCount, 2)

        try await waitUntil(timeout: 6) {
            !appModel.isGenerating
                && !appModel.isOrganizingMemory
                && appModel.pendingMemoryCount == 0
        }
        XCTAssertEqual(fixtureClient.metrics.snapshot().extractionRequests, 2)
    }

    func testHistoricalRecallResolvesAWindowOutsideCandidateFromStore() async throws {
        let defaults = try makeDefaults(autoExtract: false, rawHistory: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let context = ModelContext(bootstrap.container)
        insertEvents(
            count: 520,
            into: context,
            conversationID: appModel.currentConversation.id,
            oldNeedle: "legacy-memory-token-abc"
        )
        appModel.refreshFromStore(force: true)
        XCTAssertFalse(appModel.messages.contains { $0.content.contains("legacy-memory-token-abc") })

        appModel.send("请找出 legacy-memory-token-abc")
        try await waitUntil(timeout: 4) { !appModel.isGenerating }
        XCTAssertTrue(fixtureClient.lastChatPrompt().contains("事件 1：legacy-memory-token-abc"))
    }

    func testAutomaticMaintenanceContinuesAfterTwentyRoundsUntilBacklogIsEmpty() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient(extractionDelay: .milliseconds(1))
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let context = ModelContext(bootstrap.container)
        insertEvents(
            count: 22,
            into: context,
            conversationID: appModel.currentConversation.id,
            role: .user
        )
        appModel.refreshFromStore(force: true)

        appModel.send("触发自动补整")
        try await waitUntil(timeout: 6) {
            !appModel.isGenerating
                && !appModel.isOrganizingMemory
                && appModel.pendingMemoryCount == 0
        }
        XCTAssertGreaterThanOrEqual(fixtureClient.metrics.snapshot().extractionRequests, 23)
    }

    func testMemoryStoreRevisionChangesForSameCountDurableUpdatesButNotIdlePolling() throws {
        let defaults = try makeDefaults(autoExtract: false)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: DelayedFixtureAIClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )

        let initialRevision = appModel.memoryStoreRevision
        appModel.refreshFromStore()
        XCTAssertEqual(appModel.memoryStoreRevision, initialRevision)

        let context = ModelContext(bootstrap.container)
        let memory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "drink",
            value: "茶",
            canonicalKey: "user.drink",
            state: .active,
            confidence: 0.9,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "test"
        )
        context.insert(memory)
        try context.save()
        appModel.refreshFromStore(force: true)
        XCTAssertEqual(appModel.memoryStoreRevision, initialRevision + 1)

        memory.value = "乌龙茶"
        memory.updatedAt = memory.updatedAt.addingTimeInterval(10)
        try context.save()
        appModel.refreshFromStore(force: true)
        XCTAssertEqual(appModel.memoryStoreRevision, initialRevision + 2)
    }

    func testLastUsedMemoriesRemainScopedWhenSwitchingCompanions() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: DelayedFixtureAIClient(extractionDelay: .milliseconds(1)),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let firstRoleID = appModel.currentRoleID
        let context = ModelContext(bootstrap.container)
        let firstRoleMemory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "role_isolation_marker",
            value: "只属于第一个角色的琥珀标记",
            canonicalKey: "user.role_isolation_marker",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 1_000,
            extractorID: "role-isolation-fixture",
            deviceID: "test",
            roleID: firstRoleID
        )
        firstRoleMemory.isPinned = true
        context.insert(firstRoleMemory)
        try context.save()
        appModel.refreshFromStore(force: true)

        appModel.send("琥珀标记是什么？")
        try await waitUntil(timeout: 4) {
            !appModel.isGenerating && !appModel.lastUsedMemories.isEmpty
        }
        XCTAssertEqual(appModel.lastUsedMemories.map(\.id), [firstRoleMemory.id])

        let secondRoleID = try appModel.createCompanion(
            name: "第二角色",
            userName: "用户",
            prompt: "保持角色记忆独立"
        )
        XCTAssertEqual(appModel.currentRoleID, secondRoleID)
        XCTAssertTrue(appModel.lastUsedMemories.isEmpty)
        XCTAssertEqual(appModel.memoryCount, 0)

        try appModel.selectCompanion(id: firstRoleID)
        XCTAssertEqual(appModel.lastUsedMemories.map(\.id), [firstRoleMemory.id])
        XCTAssertEqual(appModel.memoryCount, 1)
    }

    func testGroupMemoryRejectsCrossConversationAndMismatchedSenderRows() async throws {
        let defaults = try makeDefaults(autoExtract: true)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        let fixtureClient = DelayedFixtureAIClient(extractionDelay: .milliseconds(1))
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: fixtureClient,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        let firstRoleID = try appModel.createCompanion(
            name: "群聊甲",
            userName: "用户",
            prompt: "保留群聊私人记忆"
        )
        let secondRoleID = try appModel.createCompanion(
            name: "群聊乙",
            userName: "用户",
            prompt: "保留群聊私人记忆"
        )
        let groupConversationID = try appModel.createGroup(
            name: "记忆边界群",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        let context = ModelContext(bootstrap.container)
        let sharedUserID = uuid(7_201)
        let sharedUser = ConversationEvent(
            id: sharedUserID,
            conversationID: groupConversationID,
            deviceID: "group-memory-fixture",
            deviceSequence: 1,
            logicalTimestamp: "000001",
            occurredAt: Date(timeIntervalSince1970: 1),
            role: .user,
            content: "群聊共享用户内容",
            contentHash: ContentHasher.sha256("群聊共享用户内容"),
            roleID: nil,
            senderRoleID: nil
        )
        let validAssistant = ConversationEvent(
            id: uuid(7_202),
            conversationID: groupConversationID,
            deviceID: "group-memory-fixture",
            deviceSequence: 2,
            logicalTimestamp: "000002",
            occurredAt: Date(timeIntervalSince1970: 2),
            role: .assistant,
            content: "甲的有效回应",
            contentHash: ContentHasher.sha256("甲的有效回应"),
            parentEventID: sharedUserID,
            roleID: firstRoleID,
            senderRoleID: firstRoleID
        )
        let crossConversationParent = ConversationEvent(
            id: uuid(7_203),
            conversationID: AppModel.defaultConversationID,
            deviceID: "group-memory-fixture",
            deviceSequence: 3,
            logicalTimestamp: "000003",
            occurredAt: Date(timeIntervalSince1970: 3),
            role: .user,
            content: "不应成为群聊父事件",
            contentHash: ContentHasher.sha256("不应成为群聊父事件"),
            roleID: nil,
            senderRoleID: nil
        )
        let crossConversationAssistant = ConversationEvent(
            id: uuid(7_204),
            conversationID: groupConversationID,
            deviceID: "group-memory-fixture",
            deviceSequence: 4,
            logicalTimestamp: "000004",
            occurredAt: Date(timeIntervalSince1970: 4),
            role: .assistant,
            content: "跨会话回应",
            contentHash: ContentHasher.sha256("跨会话回应"),
            parentEventID: crossConversationParent.id,
            roleID: firstRoleID,
            senderRoleID: firstRoleID
        )
        let mismatchedAssistant = ConversationEvent(
            id: uuid(7_205),
            conversationID: groupConversationID,
            deviceID: "group-memory-fixture",
            deviceSequence: 5,
            logicalTimestamp: "000005",
            occurredAt: Date(timeIntervalSince1970: 5),
            role: .assistant,
            content: "角色字段不一致",
            contentHash: ContentHasher.sha256("角色字段不一致"),
            parentEventID: sharedUserID,
            roleID: firstRoleID,
            senderRoleID: secondRoleID
        )
        for event in [sharedUser, validAssistant, crossConversationParent,
                      crossConversationAssistant, mismatchedAssistant] {
            context.insert(event)
        }
        try context.save()

        appModel.refreshFromStore(force: true)
        try await waitUntil(timeout: 7) {
            !appModel.isOrganizingMemory
                && fixtureClient.metrics.snapshot().extractionRequests == 1
        }

        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertNotNil(events.first { $0.id == validAssistant.id }?.memoryProcessedAt)
        XCTAssertNil(events.first { $0.id == crossConversationAssistant.id }?.memoryProcessedAt)
        XCTAssertNil(events.first { $0.id == mismatchedAssistant.id }?.memoryProcessedAt)
    }

    private let defaultsSuiteName = "AppModelMemoryMaintenanceTests.\(UUID().uuidString)"

    private func makeDefaults(
        autoExtract: Bool,
        rawHistory: Bool = false
    ) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.2, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(autoExtract, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(rawHistory, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        return defaults
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private func insertEvents(
        count: Int,
        into context: ModelContext,
        conversationID: UUID,
        role: EventRole = .assistant,
        oldNeedle: String? = nil
    ) {
        for index in 1...count {
            let body: String
            if index == 1, let oldNeedle {
                body = "事件 \(index)：\(oldNeedle)"
            } else {
                body = "事件 \(index)"
            }
            context.insert(ConversationEvent(
                conversationID: conversationID,
                deviceID: "fixture-device",
                deviceSequence: index,
                logicalTimestamp: String(format: "%06d", index),
                occurredAt: Date(timeIntervalSince1970: TimeInterval(index)),
                role: role,
                content: body,
                contentHash: ContentHasher.sha256(body)
            ))
        }
        try? context.save()
    }

    private func waitUntil(
        timeout: TimeInterval = 4,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for AppModel state")
        throw WaitError.timedOut
    }

    private enum WaitError: Error {
        case timedOut
    }
}

private final class DelayedFixtureAIClient: AIClientProtocol, @unchecked Sendable {
    let metrics = RequestMetrics()
    private let extractionDelay: Duration
    private let promptCapture = PromptCapture()

    init(extractionDelay: Duration = .milliseconds(250)) {
        self.extractionDelay = extractionDelay
    }

    func lastChatPrompt() -> String {
        promptCapture.read()
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("流式测试回复")
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
        let extraction = messages.contains { message in
            message.content.contains("只做证据抽取")
        }
        let ordinal = metrics.begin(extraction: extraction)
        if extraction {
            defer { metrics.end(extraction: true) }
            try await Task.sleep(for: extractionDelay)
            return #"{"memories":[]}"#
        }
        promptCapture.write(messages)
        try await Task.sleep(for: .milliseconds(20))
        return "第 \(ordinal) 轮回复"
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
}

private final class DirectFactFixtureAIClient: AIClientProtocol, @unchecked Sendable {
    private let promptCapture = PromptCapture()

    func lastChatPrompt() -> String {
        promptCapture.read()
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("收到")
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
        guard messages.contains(where: { $0.content.contains("只做证据抽取") }) else {
            promptCapture.write(messages)
            return "收到"
        }
        guard let payload = messages.last?.content.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: payload) as? [[String: String]],
              let source = rows.first(where: {
                  $0["role"] == EventRole.user.rawValue && $0["content"] == "我住在上海"
              }),
              let eventID = source["event_id"] else {
            return #"{"memories":[]}"#
        }
        return """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":0.95,"importance":0.8,"explicit":false,"sensitive":false,
          "source_event_id":"\(eventID)","source_quote":"我住在上海",
          "valid_from":null,"valid_to":null
        }]}
        """
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
}

private final class ParentPairingFixtureAIClient: AIClientProtocol, @unchecked Sendable {
    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield("未使用的聊天回复")
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
        guard messages.contains(where: { $0.content.contains("只做证据抽取") }),
              let payload = messages.last?.content.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: payload) as? [[String: String]],
              let assistant = rows.first(where: { $0["role"] == EventRole.assistant.rawValue }),
              let eventID = assistant["event_id"],
              let content = assistant["content"] else {
            return #"{"memories":[]}"#
        }

        let canonicalKey = content.contains("A1")
            ? "companion.commitment.a1"
            : "companion.commitment.a2"
        let memory: [String: Any] = [
            "operation": "upsert",
            "kind": MemoryKind.commitment.rawValue,
            "subject": "companion",
            "predicate": "promise",
            "value": content,
            "canonical_key": canonicalKey,
            "confidence": 0.99,
            "importance": 0.8,
            "explicit": true,
            "sensitive": false,
            "source_event_id": eventID,
            "source_quote": content
        ]
        let envelope: [String: Any] = ["memories": [memory]]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
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
}

private final class PromptCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func write(_ messages: [APIChatMessage]) {
        lock.lock()
        value = messages.map { "\($0.role):\($0.content)" }.joined(separator: "\n")
        lock.unlock()
    }

    func read() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class RequestMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var chatRequests = 0
    private var extractionRequests = 0
    private var activeExtractions = 0
    private var maximumConcurrentExtractions = 0

    func reset() {
        lock.lock()
        chatRequests = 0
        extractionRequests = 0
        activeExtractions = 0
        maximumConcurrentExtractions = 0
        lock.unlock()
    }

    func begin(extraction: Bool) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if extraction {
            extractionRequests += 1
            activeExtractions += 1
            maximumConcurrentExtractions = max(maximumConcurrentExtractions, activeExtractions)
            return extractionRequests
        }
        chatRequests += 1
        return chatRequests
    }

    func end(extraction: Bool) {
        guard extraction else { return }
        lock.lock()
        activeExtractions = max(0, activeExtractions - 1)
        lock.unlock()
    }

    func snapshot() -> (
        chatRequests: Int,
        extractionRequests: Int,
        maximumConcurrentExtractions: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (chatRequests, extractionRequests, maximumConcurrentExtractions)
    }
}
