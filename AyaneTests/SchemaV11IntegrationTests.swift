import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class SchemaV11IntegrationTests: XCTestCase {
    func testV10BackupDefaultsToRealityWorldAndKeepsLegacyTextEvents() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(bootstrap.container)
        let sourceDefaults = try makeDefaults()
        configureDefaults(sourceDefaults)

        let createdAt = Date(timeIntervalSince1970: 1_900_000_000)
        sourceContext.insert(CompanionProfileRecord(
            id: RoleScope.legacyRoleID,
            name: "旧角色",
            userName: "你",
            prompt: "保留旧备份中的人物设定。",
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 2,
            deviceID: "legacy-device"
        ))
        let conversation = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "旧会话",
            createdAt: createdAt,
            roleID: RoleScope.legacyRoleID
        )
        conversation.updatedAt = createdAt.addingTimeInterval(10)
        let content = "旧文本消息"
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "legacy-device",
            deviceSequence: 1,
            logicalTimestamp: "1900000000000-legacy-device-1",
            occurredAt: createdAt.addingTimeInterval(1),
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            roleID: RoleScope.legacyRoleID
        )
        event.recordedAt = createdAt.addingTimeInterval(2)
        sourceContext.insert(conversation)
        sourceContext.insert(event)
        try sourceContext.save()

        let currentData = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults,
            now: createdAt.addingTimeInterval(20)
        )
        let legacyData = try changingJSON(currentData) { root in
            root["schema_version"] = 10
            for key in [
                "world_profile",
                "group_conversations",
                "group_participants",
                "chat_turn_presentations",
                "proactive_message_tasks"
            ] {
                root.removeValue(forKey: key)
            }
            var events = try XCTUnwrap(root["events"] as? [[String: Any]])
            events = events.map { event in
                var copy = event
                copy.removeValue(forKey: "payload_kind")
                copy.removeValue(forKey: "payload_kind_raw")
                copy.removeValue(forKey: "sticker_id")
                return copy
            }
            root["events"] = events
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults()
        configureDefaults(destinationDefaults)
        let summary = try DataImportService.replaceAll(
            with: legacyData,
            context: destinationContext,
            defaults: destinationDefaults
        )

        XCTAssertEqual(summary.worldProfiles, 1)
        XCTAssertEqual(summary.groupConversations, 0)
        XCTAssertEqual(summary.chatTurnPresentations, 0)
        XCTAssertEqual(summary.proactiveMessageTasks, 0)

        let world = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<WorldProfileRecord>()).first
        )
        XCTAssertEqual(world.id, WorldProfileRecord.realityID)
        XCTAssertEqual(world.worldKind, "reality")
        XCTAssertFalse(world.timezoneIdentifier.isEmpty)
        XCTAssertEqual(world.locationContext, "")
        XCTAssertEqual(world.commonFacts, [])

        let restoredEvent = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<ConversationEvent>()).first
        )
        XCTAssertEqual(restoredEvent.content, content)
        XCTAssertEqual(restoredEvent.payloadKind, .text)
        XCTAssertEqual(restoredEvent.payloadKindRaw, MessagePayloadKind.text.rawValue)
        XCTAssertEqual(restoredEvent.stickerID, "")
        XCTAssertEqual(restoredEvent.payload, .text(content))
    }

    func testV11ExportImportPreservesWorldGroupStickerPresentationProactiveAndMomentThread() throws {
        let now = Date(timeIntervalSince1970: 1_900_100_000)
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        configureDefaults(sourceDefaults)
        let fixture = try insertV11Fixture(into: sourceContext, now: now)

        let data = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults,
            now: now.addingTimeInterval(600)
        )
        let sourcePayload = try decode(data)
        XCTAssertEqual(sourcePayload.schemaVersion, AyaneDataExport.currentSchemaVersion)
        XCTAssertEqual(sourcePayload.worldProfile.locationContext, "上海")
        XCTAssertEqual(sourcePayload.groupConversations.count, 1)
        XCTAssertEqual(sourcePayload.groupParticipants.count, 3)
        XCTAssertEqual(sourcePayload.chatTurnPresentations.count, 1)
        XCTAssertEqual(sourcePayload.proactiveMessageTasks.count, 1)
        XCTAssertEqual(sourcePayload.momentInteractions.count, 2)

        let sticker = try XCTUnwrap(
            sourcePayload.events.first { $0.id == fixture.stickerEventID }
        )
        XCTAssertEqual(sticker.payloadKind, MessagePayloadKind.sticker.rawValue)
        XCTAssertEqual(sticker.payloadKindRaw, MessagePayloadKind.sticker.rawValue)
        XCTAssertEqual(sticker.stickerID, "generic.reaction.02")
        XCTAssertEqual(sticker.senderRoleID, fixture.firstRoleID)

        let child = try XCTUnwrap(
            sourcePayload.momentInteractions.first { $0.id == fixture.childInteractionID }
        )
        XCTAssertEqual(child.parentInteractionID, fixture.rootInteractionID)
        XCTAssertEqual(child.rootInteractionID, fixture.rootInteractionID)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults()
        configureDefaults(destinationDefaults)
        let summary = try DataImportService.replaceAll(
            with: data,
            context: destinationContext,
            defaults: destinationDefaults
        )

        XCTAssertEqual(summary.worldProfiles, 1)
        XCTAssertEqual(summary.groupConversations, 1)
        XCTAssertEqual(summary.groupParticipants, 3)
        XCTAssertEqual(summary.chatTurnPresentations, 1)
        XCTAssertEqual(summary.proactiveMessageTasks, 1)

        let restoredData = try DataExportService.export(
            context: destinationContext,
            defaults: destinationDefaults,
            now: now.addingTimeInterval(600)
        )
        let restoredPayload = try decode(restoredData)
        XCTAssertEqual(restoredPayload.worldProfile, sourcePayload.worldProfile)
        XCTAssertEqual(restoredPayload.groupConversations, sourcePayload.groupConversations)
        XCTAssertEqual(restoredPayload.groupParticipants, sourcePayload.groupParticipants)
        XCTAssertEqual(restoredPayload.events, sourcePayload.events)
        XCTAssertEqual(restoredPayload.chatTurnPresentations, sourcePayload.chatTurnPresentations)
        XCTAssertEqual(restoredPayload.proactiveMessageTasks, sourcePayload.proactiveMessageTasks)
        XCTAssertEqual(restoredPayload.momentPosts, sourcePayload.momentPosts)
        XCTAssertEqual(restoredPayload.momentInteractions, sourcePayload.momentInteractions)

        let restoredPresentation = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).first
        )
        XCTAssertEqual(restoredPresentation.state, .delivering)
        XCTAssertEqual(restoredPresentation.displayedSegmentCount, 1)
        XCTAssertEqual(restoredPresentation.logicalReplyEventID, fixture.stickerEventID)

        let restoredTask = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).first
        )
        XCTAssertEqual(restoredTask.state, .scheduled)
        XCTAssertEqual(restoredTask.followUpCount, 1)
        XCTAssertEqual(restoredTask.generatedText, "{\"initial\":\"先去喝水\",\"followUp\":\"晚点再聊\"}")
        XCTAssertEqual(restoredTask.lastUserEventID, fixture.userEventID)
    }

    func testAppModelClearAndRestoreRebindsV11GroupPresentationAndProactiveRuntimeState() async throws {
        let now = Date(timeIntervalSince1970: 1_900_200_000)
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        configureDefaults(sourceDefaults)
        let fixture = try insertV11Fixture(into: sourceContext, now: now)
        let data = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults,
            now: now.addingTimeInterval(600)
        )

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationDefaults = try makeDefaults()
        configureDefaults(destinationDefaults)
        let appModel = AppModel(
            bootstrap: destination,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: destinationDefaults,
            apiKeyLoader: { "fixture-key" }
        )
        let context = ModelContext(destination.container)

        try await appModel.restoreData(from: data)
        XCTAssertEqual(appModel.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertEqual(appModel.groupConversations.count, 1)
        XCTAssertEqual(appModel.momentTasks.count, 1)
        XCTAssertFalse(appModel.isGeneratingGroupReply)
        appModel.openGroup(conversationID: fixture.groupConversationID)
        XCTAssertEqual(appModel.activeGroupConversationID, fixture.groupConversationID)
        XCTAssertEqual(appModel.groupMessages.count, 2)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).count,
            1
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).count,
            1
        )

        try await appModel.clearAllLocalData()
        XCTAssertTrue(appModel.groupConversations.isEmpty)
        XCTAssertTrue(appModel.momentTasks.isEmpty)
        XCTAssertNil(appModel.activeGroupConversationID)
        XCTAssertTrue(appModel.groupMessages.isEmpty)
        XCTAssertFalse(appModel.isGeneratingGroupReply)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GroupConversationRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GroupParticipantRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).count, 0)

        try await appModel.restoreData(from: data)
        XCTAssertEqual(appModel.currentConversation.id, AppModel.defaultConversationID)
        XCTAssertEqual(appModel.groupConversations.count, 1)
        XCTAssertEqual(appModel.momentTasks.count, 1)
        let groupSummary = try XCTUnwrap(appModel.groupConversations.first)
        XCTAssertEqual(groupSummary.conversationID, fixture.groupConversationID)
        XCTAssertEqual(groupSummary.name, "夜话群")
        XCTAssertEqual(Set(groupSummary.participantRoleIDs), Set([fixture.firstRoleID, fixture.secondRoleID]))
        appModel.openGroup(conversationID: fixture.groupConversationID)
        XCTAssertEqual(appModel.activeGroupConversationID, fixture.groupConversationID)
        XCTAssertEqual(appModel.groupMessages.count, 2)

        let presentation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).first
        )
        XCTAssertEqual(presentation.state, .delivering)
        let proactive = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).first
        )
        XCTAssertEqual(proactive.state, .scheduled)
        XCTAssertEqual(proactive.idempotencyKey, "proactive-v11-fixture")
    }

    func testStickerRecentStorePersistsDeduplicatesAndCapsAtTwelve() throws {
        let suiteName = "SchemaV11IntegrationTests.StickerRecent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let ids = StickerCatalog.all.prefix(13).map(\.stickerID)
        var expected = [String]()
        for id in ids {
            expected = StickerRecentStore.remember(id, defaults: defaults)
        }

        XCTAssertEqual(expected.count, 12)
        XCTAssertEqual(expected, Array(ids.reversed().prefix(12)))
        XCTAssertEqual(StickerRecentStore.load(defaults: defaults), expected)

        let duplicateID = ids[4]
        let afterDuplicate = StickerRecentStore.remember(duplicateID, defaults: defaults)
        XCTAssertEqual(afterDuplicate.first, duplicateID)
        XCTAssertEqual(afterDuplicate.count, 12)
        XCTAssertEqual(Set(afterDuplicate).count, afterDuplicate.count)
        XCTAssertEqual(StickerRecentStore.load(defaults: defaults), afterDuplicate)
        XCTAssertEqual(
            StickerRecentStore.remember("unknown.sticker", defaults: defaults),
            afterDuplicate
        )
    }

    private struct V11FixtureIDs {
        let firstRoleID: UUID
        let secondRoleID: UUID
        let groupConversationID: UUID
        let userEventID: UUID
        let stickerEventID: UUID
        let rootInteractionID: UUID
        let childInteractionID: UUID
    }

    private func insertV11Fixture(
        into context: ModelContext,
        now: Date
    ) throws -> V11FixtureIDs {
        let firstRoleID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondRoleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let groupConversationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let groupID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let userEventID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let stickerEventID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let presentationID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let proactiveTaskID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        let momentTaskID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
        let postID = UUID(uuidString: "AAAAAAA1-AAAA-4AAA-8AAA-AAAAAAAAAAA1")!
        let rootInteractionID = UUID(uuidString: "BBBBBBB1-BBBB-4BBB-8BBB-BBBBBBBBBBB1")!
        let childInteractionID = UUID(uuidString: "CCCCCCC1-CCCC-4CCC-8CCC-CCCCCCCCCCC1")!

        context.insert(CompanionProfileRecord(
            id: RoleScope.legacyRoleID,
            name: "绫音",
            userName: "你",
            prompt: "默认角色保持自然、清醒地回应。",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "v11-device"
        ))
        context.insert(CompanionProfileRecord(
            id: firstRoleID,
            name: "甲",
            userName: "你",
            prompt: "甲负责认真回应。",
            createdAt: now,
            updatedAt: now.addingTimeInterval(1),
            revision: 2,
            deviceID: "v11-device"
        ))
        context.insert(CompanionProfileRecord(
            id: secondRoleID,
            name: "乙",
            userName: "你",
            prompt: "乙负责温柔回应。",
            createdAt: now,
            updatedAt: now.addingTimeInterval(2),
            revision: 2,
            deviceID: "v11-device"
        ))

        let primary = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "主会话",
            createdAt: now,
            roleID: RoleScope.legacyRoleID
        )
        primary.updatedAt = now.addingTimeInterval(3)
        let groupConversation = ConversationRecord(
            id: groupConversationID,
            title: "夜话群",
            createdAt: now,
            roleID: nil
        )
        groupConversation.updatedAt = now.addingTimeInterval(4)
        context.insert(primary)
        context.insert(groupConversation)

        context.insert(WorldProfileRecord(
            id: WorldProfileRecord.realityID,
            worldKind: "reality",
            timezoneIdentifier: "Asia/Shanghai",
            locationContext: "上海",
            commonFacts: ["今天下雨", "周末"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(5),
            revision: 7,
            deviceID: "v11-device"
        ))
        context.insert(GroupConversationRecord(
            id: groupID,
            conversationID: groupConversationID,
            groupName: "夜话群",
            lifecycle: .active,
            createdAt: now,
            updatedAt: now.addingTimeInterval(6),
            revision: 3,
            deviceID: "v11-device"
        ))
        context.insert(GroupParticipantRecord(
            id: UUID(uuidString: "D1111111-1111-4111-8111-111111111111")!,
            conversationID: groupConversationID,
            groupConversationID: groupID,
            participantKind: .user,
            displayName: "我",
            joinedAt: now,
            createdAt: now,
            updatedAt: now.addingTimeInterval(7),
            revision: 1,
            deviceID: "v11-device"
        ))
        context.insert(GroupParticipantRecord(
            id: UUID(uuidString: "D2222222-2222-4222-8222-222222222222")!,
            conversationID: groupConversationID,
            groupConversationID: groupID,
            participantRoleID: firstRoleID,
            participantKind: .companion,
            displayName: "甲",
            joinedAt: now,
            createdAt: now,
            updatedAt: now.addingTimeInterval(8),
            revision: 1,
            deviceID: "v11-device"
        ))
        context.insert(GroupParticipantRecord(
            id: UUID(uuidString: "D3333333-3333-4333-8333-333333333333")!,
            conversationID: groupConversationID,
            groupConversationID: groupID,
            participantRoleID: secondRoleID,
            participantKind: .companion,
            displayName: "乙",
            joinedAt: now,
            createdAt: now,
            updatedAt: now.addingTimeInterval(9),
            revision: 1,
            deviceID: "v11-device"
        ))

        let userContent = "今晚群里聊聊。"
        let userEvent = ConversationEvent(
            id: userEventID,
            conversationID: groupConversationID,
            deviceID: "v11-device",
            deviceSequence: 10,
            logicalTimestamp: "1900100000000-v11-device-10",
            occurredAt: now.addingTimeInterval(10),
            role: .user,
            content: userContent,
            contentHash: ContentHasher.sha256(userContent),
            roleID: RoleScope.legacyRoleID
        )
        userEvent.recordedAt = now.addingTimeInterval(10)
        let stickerContent = "[表情：通用反应：微笑]"
        let stickerEvent = ConversationEvent(
            id: stickerEventID,
            conversationID: groupConversationID,
            deviceID: "v11-device",
            deviceSequence: 11,
            logicalTimestamp: "1900100001000-v11-device-11",
            occurredAt: now.addingTimeInterval(11),
            role: .assistant,
            content: stickerContent,
            contentHash: ContentHasher.sha256(stickerContent),
            parentEventID: userEventID,
            deliveryState: .complete,
            roleID: firstRoleID,
            payload: .sticker("generic.reaction.02"),
            senderRoleID: firstRoleID
        )
        stickerEvent.recordedAt = now.addingTimeInterval(11)
        context.insert(userEvent)
        context.insert(stickerEvent)
        context.insert(ChatTurnPresentationRecord(
            id: presentationID,
            conversationID: groupConversationID,
            roleID: firstRoleID,
            logicalReplyEventID: stickerEventID,
            segments: ["第一句", "第二句"],
            displayProgress: 0.5,
            displayedSegmentCount: 1,
            state: .delivering,
            plannedAt: now.addingTimeInterval(12),
            startedAt: now.addingTimeInterval(13),
            failureMessage: "",
            idempotencyKey: "v11-fixture",
            createdAt: now.addingTimeInterval(12),
            updatedAt: now.addingTimeInterval(13),
            revision: 4,
            deviceID: "v11-device"
        ))
        context.insert(ProactiveMessageTaskRecord(
            id: proactiveTaskID,
            roleID: secondRoleID,
            conversationID: groupConversationID,
            scheduledAt: now.addingTimeInterval(7_200),
            followUpCount: 1,
            state: .scheduled,
            idempotencyKey: "proactive-v11-fixture",
            generatedText: "{\"initial\":\"先去喝水\",\"followUp\":\"晚点再聊\"}",
            lastUserEventID: userEventID,
            scheduledFromUserAt: now.addingTimeInterval(14),
            createdAt: now.addingTimeInterval(14),
            updatedAt: now.addingTimeInterval(15),
            revision: 2,
            deviceID: "v11-device"
        ))
        context.insert(CompanionMomentTaskRecord(
            id: momentTaskID,
            roleID: firstRoleID,
            instruction: "发一条雨天朋友圈",
            scheduledAt: now.addingTimeInterval(7_300),
            state: .scheduled,
            createdAt: now.addingTimeInterval(16),
            updatedAt: now.addingTimeInterval(17),
            deviceID: "v11-device",
            revision: 1
        ))

        let post = MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "今天的雨很安静。",
            publishedAt: now.addingTimeInterval(18),
            createdAt: now.addingTimeInterval(18),
            updatedAt: now.addingTimeInterval(19),
            revision: 1,
            deviceID: "v11-device"
        )
        context.insert(post)
        context.insert(MomentInteractionRecord(
            id: rootInteractionID,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: firstRoleID,
            rootInteractionID: rootInteractionID,
            body: "确实很安静。",
            createdAt: now.addingTimeInterval(20),
            updatedAt: now.addingTimeInterval(20),
            revision: 1,
            deviceID: "v11-device"
        ))
        context.insert(MomentInteractionRecord(
            id: childInteractionID,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: secondRoleID,
            parentInteractionID: rootInteractionID,
            rootInteractionID: rootInteractionID,
            body: "我也喜欢这样的天气。",
            createdAt: now.addingTimeInterval(21),
            updatedAt: now.addingTimeInterval(21),
            revision: 1,
            deviceID: "v11-device"
        ))
        try context.save()

        return V11FixtureIDs(
            firstRoleID: firstRoleID,
            secondRoleID: secondRoleID,
            groupConversationID: groupConversationID,
            userEventID: userEventID,
            stickerEventID: stickerEventID,
            rootInteractionID: rootInteractionID,
            childInteractionID: childInteractionID
        )
    }

    private func configureDefaults(_ defaults: UserDefaults) {
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
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
        defaults.set(false, forKey: SettingsKeys.cloudSyncEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set("绫音测试", forKey: SettingsKeys.personaName)
        defaults.set("测试者", forKey: SettingsKeys.userName)
        defaults.set("保持清醒", forKey: SettingsKeys.personaPrompt)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SchemaV11IntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func decode(_ data: Data) throws -> AyaneDataExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AyaneDataExport.self, from: data)
    }

    private func changingJSON(
        _ data: Data,
        change: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
