import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class DataExportServiceTests: XCTestCase {
    func testExportIncludesAllPersistedDataAndReadableSettings() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let conversation = ConversationRecord(title: "导出测试")
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "test-device",
            deviceSequence: 1,
            logicalTimestamp: "1-test-device-1",
            role: .user,
            content: "我喜欢乌龙茶",
            contentHash: ContentHasher.sha256("我喜欢乌龙茶")
        )
        let memory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "乌龙茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.98,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "test-device"
        )
        memory.embeddingData = Data([1, 2, 3])
        memory.embeddingModelID = "fixture-embedding"
        let evidence = MemoryEvidenceRecord(
            memoryID: memory.id,
            eventID: event.id,
            startUTF16: 0,
            endUTF16: 6,
            relation: .supports,
            quoteHash: ContentHasher.sha256(event.content),
            confidence: 0.98
        )
        let summary = MemorySummaryRecord(
            conversationID: conversation.id,
            scope: "session",
            content: "用户喜欢乌龙茶。",
            firstEventID: event.id,
            lastEventID: event.id,
            coveredEventCount: 1,
            extractorID: "fixture"
        )
        let tombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "user.favorite_drink",
            sourceEventIDs: [event.id],
            deviceID: "test-device",
            reason: "fixture"
        )
        let conversationReadState = ConversationReadStateRecord(
            roleID: RoleScope.legacyRoleID,
            conversationID: conversation.id,
            lastReadOccurredAt: event.occurredAt,
            lastReadLogicalTimestamp: event.logicalTimestamp,
            lastReadEventID: event.id,
            updatedAt: event.occurredAt,
            revision: 2,
            deviceID: "test-device"
        )
        let momentPostID = UUID()
        let momentReadState = MomentReadStateRecord(
            postID: momentPostID,
            lastReadCreatedAt: event.occurredAt,
            lastReadInteractionID: nil,
            updatedAt: event.occurredAt,
            revision: 3,
            deviceID: "test-device"
        )

        context.insert(conversation)
        context.insert(event)
        context.insert(memory)
        context.insert(evidence)
        context.insert(summary)
        context.insert(tombstone)
        context.insert(conversationReadState)
        context.insert(momentReadState)
        try context.save()

        let suiteName = "AyaneTests.DataExport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://example.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set(ProviderPreset.custom.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("fixture-chat", forKey: SettingsKeys.model)
        defaults.set("fixture-embedding", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.4, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(12, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(800, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(true, forKey: SettingsKeys.cloudSyncEnabled)
        defaults.set("绫音测试", forKey: SettingsKeys.personaName)
        defaults.set("测试者", forKey: SettingsKeys.userName)
        defaults.set("保持清醒", forKey: SettingsKeys.personaPrompt)

        let exportDate = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try DataExportService.export(context: context, defaults: defaults, now: exportDate)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\n"), "Export should be pretty printed for manual inspection.")
        XCTAssertTrue(json.contains("导出测试"))
        XCTAssertTrue(json.contains("我喜欢乌龙茶"))
        XCTAssertTrue(json.contains("fixture-embedding"))
        XCTAssertTrue(json.contains("保持清醒"))
        XCTAssertFalse(json.contains("api-secret"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(AyaneDataExport.self, from: data)
        XCTAssertEqual(payload.schemaVersion, AyaneDataExport.currentSchemaVersion)
        XCTAssertEqual(payload.exportedAt, exportDate)
        XCTAssertEqual(payload.conversations.count, 1)
        XCTAssertEqual(payload.events.count, 1)
        XCTAssertEqual(payload.memories.count, 1)
        XCTAssertEqual(payload.evidence.count, 1)
        XCTAssertEqual(payload.summaries.count, 1)
        XCTAssertEqual(payload.tombstones.count, 1)
        XCTAssertEqual(payload.conversationReadStates.count, 1)
        XCTAssertEqual(payload.conversationReadStates.first?.conversationID, conversation.id)
        XCTAssertEqual(payload.conversationReadStates.first?.lastReadEventID, event.id)
        XCTAssertEqual(payload.momentReadStates.count, 1)
        XCTAssertEqual(payload.momentReadStates.first?.postID, momentPostID)
        XCTAssertEqual(payload.momentReadStates.first?.revision, 3)
        XCTAssertEqual(payload.tombstones.first?.canonicalKey, "user.favorite_drink")
        XCTAssertEqual(payload.tombstones.first?.sourceEventIDs, [event.id])
        XCTAssertEqual(payload.persona.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(payload.persona.createdAt, AyanePersonaExport.legacyEpoch)
        XCTAssertEqual(payload.persona.updatedAt, AyanePersonaExport.legacyEpoch)
        XCTAssertEqual(payload.persona.revision, 0)
        XCTAssertEqual(payload.persona.deviceID, "")
        XCTAssertEqual(payload.persona.userName, "测试者")
        XCTAssertEqual(payload.settings.provider.baseURL, "https://example.test/v1")
        XCTAssertEqual(payload.settings.provider.providerID, ProviderPreset.custom.rawValue)
        XCTAssertEqual(payload.settings.memory.tokenBudget, 1_200)
        XCTAssertFalse(payload.settings.memory.rawHistoryRecallEnabled)
        XCTAssertEqual(payload.settings.memory.rawHistoryTokenBudget, 800)
        XCTAssertEqual(payload.memories.first?.embeddingBase64, Data([1, 2, 3]).base64EncodedString())
    }

    func testExportPrefersPersistedProfileAndPreservesV5Metadata() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let profileCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let profileUpdatedAt = Date(timeIntervalSince1970: 1_700_000_123)
        let profile = CompanionProfileRecord(
            id: CompanionProfileRecord.singletonID,
            name: "持久绫音",
            userName: "本地用户",
            prompt: "来自 SwiftData 的角色设定",
            createdAt: profileCreatedAt,
            updatedAt: profileUpdatedAt,
            revision: 7,
            deviceID: "profile-device"
        )
        context.insert(profile)
        try context.save()

        let defaults = try makeDefaults()
        defaults.set("旧版角色", forKey: SettingsKeys.personaName)
        defaults.set("旧版用户", forKey: SettingsKeys.userName)
        defaults.set("不应优先", forKey: SettingsKeys.personaPrompt)

        let exportDate = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try DataExportService.export(
            context: context,
            defaults: defaults,
            now: exportDate
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(AyaneDataExport.self, from: data)

        XCTAssertEqual(payload.schemaVersion, AyaneDataExport.currentSchemaVersion)
        XCTAssertEqual(payload.persona.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(payload.persona.name, "持久绫音")
        XCTAssertEqual(payload.persona.userName, "本地用户")
        XCTAssertEqual(payload.persona.prompt, "来自 SwiftData 的角色设定")
        XCTAssertEqual(payload.persona.createdAt, profileCreatedAt)
        XCTAssertEqual(payload.persona.updatedAt, profileUpdatedAt)
        XCTAssertEqual(payload.persona.revision, 7)
        XCTAssertEqual(payload.persona.deviceID, "profile-device")
        XCTAssertEqual(payload.profiles.count, 1)
        XCTAssertEqual(payload.profiles.first?.roleID, CompanionProfileRecord.singletonID)

        let roundTripEncoder = JSONEncoder()
        roundTripEncoder.dateEncodingStrategy = .iso8601
        let roundTripped = try decoder.decode(
            AyaneDataExport.self,
            from: try roundTripEncoder.encode(payload)
        )
        XCTAssertEqual(roundTripped.persona, payload.persona)
    }

    func testV6ExportIncludesMultipleProfilesAndRoleScopedRecords() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let legacyProfile = CompanionProfileRecord(
            id: RoleScope.legacyRoleID,
            name: "绫音",
            userName: "你",
            prompt: "legacy",
            revision: 1,
            deviceID: "legacy-device"
        )
        let secondRoleID = UUID(uuidString: "3B5A7D9E-37DE-4AF2-BE3C-7BA5A29C0B41")!
        let secondProfile = CompanionProfileRecord(
            id: secondRoleID,
            name: "另一角色",
            userName: "用户",
            prompt: "second",
            revision: 1,
            deviceID: "second-device"
        )
        let legacyConversation = ConversationRecord(
            title: "legacy 会话",
            roleID: RoleScope.legacyRoleID
        )
        let secondConversation = ConversationRecord(
            title: "second 会话",
            roleID: secondRoleID
        )
        let legacyContent = "legacy 内容"
        let secondContent = "second 内容"
        let legacyEvent = ConversationEvent(
            conversationID: legacyConversation.id,
            deviceID: "legacy-device",
            deviceSequence: 1,
            logicalTimestamp: "1-legacy-device-1",
            role: .user,
            content: legacyContent,
            contentHash: ContentHasher.sha256(legacyContent),
            roleID: RoleScope.legacyRoleID
        )
        let secondEvent = ConversationEvent(
            conversationID: secondConversation.id,
            deviceID: "second-device",
            deviceSequence: 1,
            logicalTimestamp: "1-second-device-1",
            role: .user,
            content: secondContent,
            contentHash: ContentHasher.sha256(secondContent),
            roleID: secondRoleID
        )
        let legacyMemory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "乌龙茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 1,
            observedAt: legacyEvent.occurredAt,
            extractorID: "fixture",
            deviceID: "legacy-device",
            roleID: RoleScope.legacyRoleID
        )
        let secondMemory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "咖啡",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 1,
            observedAt: secondEvent.occurredAt,
            extractorID: "fixture",
            deviceID: "second-device",
            roleID: secondRoleID
        )

        context.insert(legacyProfile)
        context.insert(secondProfile)
        context.insert(legacyConversation)
        context.insert(secondConversation)
        context.insert(legacyEvent)
        context.insert(secondEvent)
        context.insert(legacyMemory)
        context.insert(secondMemory)
        try context.save()

        let defaults = try makeDefaults()
        let payload = try DataExportService.makePayload(
            context: context,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertEqual(payload.schemaVersion, AyaneDataExport.currentSchemaVersion)
        XCTAssertEqual(Set(payload.profiles.compactMap(\.roleID)), [RoleScope.legacyRoleID, secondRoleID])
        XCTAssertEqual(Set(payload.conversations.compactMap(\.roleID)), [RoleScope.legacyRoleID, secondRoleID])
        XCTAssertEqual(Set(payload.events.compactMap(\.roleID)), [RoleScope.legacyRoleID, secondRoleID])
        XCTAssertEqual(Set(payload.memories.compactMap(\.roleID)), [RoleScope.legacyRoleID, secondRoleID])
        XCTAssertEqual(payload.memories.map(\.canonicalKey), ["user.favorite_drink", "user.favorite_drink"])
    }

    func testFileDocumentKeepsExactExportBytes() throws {
        let bytes = Data("{\n  \"ok\": true\n}\n".utf8)
        let document = AyaneDataExportDocument(data: bytes)
        XCTAssertEqual(document.data, bytes)
    }

    func testFreshModelsUseSameDeterministicPrimaryConversationID() {
        let first = AppModel(
            bootstrap: PersistenceController.makeContainer(inMemory: true, preferCloud: false),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true)
        )
        let second = AppModel(
            bootstrap: PersistenceController.makeContainer(inMemory: true, preferCloud: false),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true)
        )

        XCTAssertEqual(first.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertEqual(second.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertEqual(first.currentConversation.id, second.currentConversation.id)
    }

    func testSingleLegacyConversationMigratesItsEventForeignKeys() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let legacy = ConversationRecord(title: "旧会话")
        let event = ConversationEvent(
            conversationID: legacy.id,
            deviceID: "legacy-device",
            deviceSequence: 1,
            logicalTimestamp: "1-legacy-device-1",
            role: .user,
            content: "旧消息",
            contentHash: ContentHasher.sha256("旧消息")
        )
        let summary = MemorySummaryRecord(
            conversationID: legacy.id,
            scope: "session",
            content: "旧摘要",
            firstEventID: event.id,
            lastEventID: event.id,
            coveredEventCount: 1,
            extractorID: "fixture"
        )
        context.insert(legacy)
        context.insert(event)
        context.insert(summary)
        try context.save()

        let appModel = AppModel(
            bootstrap: bootstrap,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true)
        )
        let migratedEvents = try context.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertEqual(appModel.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertEqual(migratedEvents.map(\.conversationID), [AppModel.defaultConversationID])
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<MemorySummaryRecord>()).map(\.conversationID),
            [AppModel.defaultConversationID]
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
    }

    func testClearRemovesAllDataAndCreatesFreshSession() async throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let conversation = ConversationRecord(title: "待清除")
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "test-device",
            deviceSequence: 1,
            logicalTimestamp: "1-test-device-1",
            role: .user,
            content: "待删除消息",
            contentHash: ContentHasher.sha256("待删除消息")
        )
        context.insert(conversation)
        context.insert(event)
        context.insert(MemoryAssertionRecord(
            kind: .profile,
            subject: "user",
            predicate: "name",
            value: "测试者",
            canonicalKey: "user.name",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 300,
            extractorID: "fixture",
            deviceID: "test-device"
        ))
        try context.save()

        let memoryIndex = LocalMemorySearchIndex(inMemory: true)
        let conversationIndex = LocalConversationSearchIndex(inMemory: true)
        await memoryIndex.upsert(.init(id: UUID(), text: "stale memory index"))
        await conversationIndex.upsert(.init(id: event.id, role: "user", body: event.content))
        let appModel = AppModel(
            bootstrap: bootstrap,
            memoryIndex: memoryIndex,
            conversationIndex: conversationIndex
        )
        try await appModel.clearAllLocalData()

        XCTAssertEqual(appModel.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertTrue(appModel.messages.isEmpty)
        XCTAssertEqual(appModel.memoryCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).first?.id, AppModel.defaultConversationID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryAssertionRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryEvidenceRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemorySummaryRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MemoryTombstoneRecord>()), 0)
        let clearedMemoryIndexCount = await memoryIndex.count()
        let clearedConversationIndexCount = await conversationIndex.count()
        XCTAssertEqual(clearedMemoryIndexCount, 0)
        XCTAssertEqual(clearedConversationIndexCount, 0)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AyaneTests.DataExport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
