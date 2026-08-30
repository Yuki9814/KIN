import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelStickerAndGroupTests: XCTestCase {
    func testSendStickerPersistsPayloadAndReceivesAssistantReply() async throws {
        let fixture = try makeFixture(responses: ["表情收到啦。"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let sticker = try XCTUnwrap(StickerCatalog.item(for: "generic.reaction.02"))
        let context = ModelContext(fixture.bootstrap.container)

        fixture.appModel.sendSticker(stickerID: sticker.stickerID)
        try await waitUntil {
            fixture.client.chatRequests == 1 && !fixture.appModel.isGenerating
        }

        let events = try events(
            in: fixture.appModel.currentConversation.id,
            context: context
        )
        let userEvent = try XCTUnwrap(events.first { $0.role == .user })
        let assistantEvent = try XCTUnwrap(events.first { $0.role == .assistant })

        XCTAssertEqual(userEvent.payloadKind, .sticker)
        XCTAssertEqual(userEvent.stickerID, sticker.stickerID)
        XCTAssertEqual(userEvent.payload, .sticker(sticker.stickerID))
        XCTAssertEqual(
            userEvent.content,
            "[表情：\(sticker.alternativeText)]"
        )
        XCTAssertEqual(userEvent.deliveryState, .complete)
        XCTAssertEqual(assistantEvent.content, "表情收到啦。")
        XCTAssertEqual(assistantEvent.deliveryState, .complete)
        XCTAssertEqual(fixture.client.chatRequests, 1)
    }

    func testPokeCurrentCompanionPersistsSystemEventAndContinuesWithoutUserTurn() async throws {
        let fixture = try makeFixture(responses: ["我刚才还想告诉你一件事。"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let context = ModelContext(fixture.bootstrap.container)
        fixture.appModel.pokeCurrentCompanion()
        try await waitUntil {
            fixture.client.chatRequests == 1 && !fixture.appModel.isGenerating
        }

        let events = try events(
            in: fixture.appModel.currentConversation.id,
            context: context
        )
        let pokeEvent = try XCTUnwrap(events.first { $0.role == .system })
        let assistantEvent = try XCTUnwrap(events.first { $0.role == .assistant })

        XCTAssertEqual(
            pokeEvent.content,
            "你拍了拍「\(fixture.appModel.persona.name)」"
        )
        XCTAssertTrue(events.filter { $0.role == .user }.isEmpty)
        XCTAssertEqual(assistantEvent.content, "我刚才还想告诉你一件事。")
        XCTAssertEqual(assistantEvent.parentEventID, pokeEvent.id)
        XCTAssertEqual(assistantEvent.deliveryState, .complete)

        let prompt = try XCTUnwrap(fixture.client.chatMessageSnapshots.last)
        XCTAssertEqual(prompt.last?.role, "user")
        XCTAssertTrue(prompt.last?.content.contains("拍一拍") == true)
        XCTAssertFalse(prompt.contains { $0.content == pokeEvent.content })

        let presentation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
                .first { $0.idempotencyKey == "assistant-reply:\(pokeEvent.id.uuidString.lowercased())" }
        )
        XCTAssertEqual(presentation.state, .completed)
    }

    func testDirectImageAndFilePersistDurablePayloadsAndUseTextFallbacksForAI() async throws {
        let fixture = try makeFixture(responses: ["图片收到。", "文件收到。"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let fileData = Data("attachment-body".utf8)
        let context = ModelContext(fixture.bootstrap.container)

        fixture.appModel.sendImage(imageData: imageData)
        try await waitUntil {
            fixture.client.chatRequests == 1 && !fixture.appModel.isGenerating
        }

        fixture.appModel.sendFile(
            fileData: fileData,
            fileName: "../reports/summary.pdf",
            fileTypeIdentifier: "com.adobe.pdf"
        )
        try await waitUntil {
            fixture.client.chatRequests == 2 && !fixture.appModel.isGenerating
        }

        let userEvents = try events(
            in: fixture.appModel.currentConversation.id,
            context: context
        ).filter { $0.role == .user }
        let imageEvent = try XCTUnwrap(userEvents.first { $0.payloadKind == .image })
        let fileEvent = try XCTUnwrap(userEvents.first { $0.payloadKind == .file })

        XCTAssertEqual(imageEvent.content, "[图片]")
        XCTAssertEqual(imageEvent.imageData, imageData)
        XCTAssertNil(imageEvent.fileData)
        XCTAssertEqual(fileEvent.content, "[文件]")
        XCTAssertEqual(fileEvent.fileName, "summary.pdf")
        XCTAssertEqual(fileEvent.fileTypeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(fileEvent.fileData, fileData)
        XCTAssertNil(fileEvent.imageData)

        let requestContents = fixture.client.chatMessageSnapshots
            .flatMap { $0 }
            .map(\.content)
        XCTAssertTrue(requestContents.contains {
            $0.contains("【本地消息时间：") && $0.hasSuffix("[图片]")
        })
        XCTAssertTrue(requestContents.contains {
            $0.contains("【本地消息时间：") && $0.hasSuffix("[文件]")
        })
        XCTAssertFalse(requestContents.contains { $0.contains("summary.pdf") })
        XCTAssertFalse(requestContents.contains { $0.contains(fileData.base64EncodedString()) })
    }

    func testGroupImageAndFilePersistDurablePayloadsAndReceiveReplies() async throws {
        let fixture = try makeFixture(
            responses: ["看到图片了。", "图片收到。", "看到文件了。", "文件收到。"]
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstRoleID = try fixture.appModel.createCompanion(
            name: "附件测试成员甲",
            userName: "你",
            prompt: "确认群聊附件"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "附件测试成员乙",
            userName: "你",
            prompt: "确认群聊附件"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "附件测试群",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        fixture.appModel.openGroup(conversationID: groupID)
        let context = ModelContext(fixture.bootstrap.container)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let fileData = Data("group-file".utf8)

        fixture.appModel.sendGroupImage(imageData: imageData, conversationID: groupID)
        try await waitUntil {
            fixture.client.chatRequests >= 1 && !fixture.appModel.isGeneratingGroupReply
        }
        let imageReplyCount = fixture.client.chatRequests
        fixture.appModel.sendGroupFile(
            fileData: fileData,
            fileName: "notes.txt",
            fileTypeIdentifier: "public.plain-text",
            conversationID: groupID
        )
        try await waitUntil {
            fixture.client.chatRequests > imageReplyCount
                && !fixture.appModel.isGeneratingGroupReply
        }

        let groupEvents = try events(in: groupID, context: context)
        let imageEvent = try XCTUnwrap(
            groupEvents.first { $0.role == .user && $0.payloadKind == .image }
        )
        let fileEvent = try XCTUnwrap(
            groupEvents.first { $0.role == .user && $0.payloadKind == .file }
        )
        XCTAssertEqual(imageEvent.imageData, imageData)
        XCTAssertEqual(imageEvent.content, "[图片]")
        XCTAssertEqual(fileEvent.fileData, fileData)
        XCTAssertEqual(fileEvent.fileName, "notes.txt")
        XCTAssertEqual(fileEvent.fileTypeIdentifier, "public.plain-text")
        XCTAssertEqual(fileEvent.content, "[文件]")
        XCTAssertEqual(
            groupEvents.filter { $0.role == .assistant }.count,
            fixture.client.chatRequests
        )
        XCTAssertGreaterThanOrEqual(fixture.client.chatRequests, 2)
        XCTAssertFalse(
            fixture.client.chatMessageSnapshots
                .flatMap { $0 }
                .contains { $0.content.contains("notes.txt") }
        )
    }

    func testGroupPromptExcludesEventsOrderedAfterTheCurrentUserTurn() async throws {
        let fixture = try makeFixture(responses: ["当前消息收到。"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let roleID = try fixture.appModel.createCompanion(
            name: "甲",
            userName: "你",
            prompt: "只回应当前消息"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "乙",
            userName: "你",
            prompt: "未被点名时保持安静"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "时间边界测试群",
            participantRoleIDs: [roleID, secondRoleID]
        )
        fixture.appModel.openGroup(conversationID: groupID)

        let context = ModelContext(fixture.bootstrap.container)
        let currentText = "@甲 只回答现在这条消息。"
        fixture.appModel.sendGroupMessage(currentText, conversationID: groupID)
        let currentEvent = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>()).first {
                $0.conversationID == groupID
                    && $0.role == .user
                    && $0.content == currentText
            }
        )

        let laterText = "这条稍后同步的消息绝不能进入当前请求"
        context.insert(ConversationEvent(
            conversationID: groupID,
            deviceID: "later-group-fixture",
            deviceSequence: 9_999,
            logicalTimestamp: currentEvent.logicalTimestamp + "-later",
            occurredAt: currentEvent.occurredAt,
            role: .user,
            content: laterText,
            contentHash: ContentHasher.sha256(laterText),
            roleID: nil
        ))
        try context.save()

        try await waitUntil {
            fixture.client.chatRequests == 1 && !fixture.appModel.isGeneratingGroupReply
        }

        XCTAssertFalse(
            fixture.client.chatMessageSnapshots
                .flatMap { $0 }
                .contains { $0.content.contains(laterText) }
        )
        XCTAssertTrue(
            fixture.client.chatMessageSnapshots
                .flatMap { $0 }
                .contains {
                    $0.content.contains("【消息发送者：用户】")
                        && $0.content.contains(currentText)
                }
        )
    }

    func testGroupPromptFailsClosedForConflictingDuplicateEventIDs() async throws {
        let fixture = try makeFixture(responses: ["不应请求回复"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstRoleID = try fixture.appModel.createCompanion(
            name: "甲",
            userName: "你",
            prompt: "检测冲突"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "乙",
            userName: "你",
            prompt: "检测冲突"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "冲突测试群",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        fixture.appModel.openGroup(conversationID: groupID)

        let context = ModelContext(fixture.bootstrap.container)
        let currentText = "这条消息存在冲突副本"
        fixture.appModel.sendGroupMessage(currentText, conversationID: groupID)
        let currentEvent = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>()).first {
                $0.conversationID == groupID
                    && $0.role == .user
                    && $0.content == currentText
            }
        )
        context.insert(ConversationEvent(
            id: currentEvent.id,
            conversationID: groupID,
            deviceID: "conflicting-group-fixture",
            deviceSequence: currentEvent.deviceSequence,
            logicalTimestamp: currentEvent.logicalTimestamp,
            occurredAt: currentEvent.occurredAt,
            role: .user,
            content: "冲突副本正文",
            contentHash: ContentHasher.sha256("冲突副本正文"),
            roleID: nil
        ))
        try context.save()

        try await waitUntil {
            fixture.appModel.hasIntegrityConflict
                && !fixture.appModel.isGeneratingGroupReply
        }

        XCTAssertEqual(fixture.client.chatRequests, 0)
        XCTAssertTrue(fixture.appModel.conflictedEventIDs.contains(currentEvent.id))
    }

    func testDirectAttachmentRejectsStaleConversationTarget() throws {
        let fixture = try makeFixture(responses: [])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let targetRoleID = fixture.appModel.currentRoleID
        let targetConversationID = fixture.appModel.currentConversation.id
        let otherRoleID = try fixture.appModel.createCompanion(
            name: "切换后的角色",
            userName: "你",
            prompt: "验证附件不会串会话"
        )
        try fixture.appModel.selectCompanion(id: otherRoleID)

        fixture.appModel.sendFile(
            fileData: Data("stale".utf8),
            fileName: "stale.txt",
            fileTypeIdentifier: "public.plain-text",
            targetRoleID: targetRoleID,
            targetConversationID: targetConversationID
        )

        XCTAssertEqual(fixture.client.chatRequests, 0)
        XCTAssertEqual(fixture.appModel.errorMessage, "聊天已切换，请在当前对话中重新选择附件。")
        let context = ModelContext(fixture.bootstrap.container)
        XCTAssertFalse(
            try events(in: fixture.appModel.currentConversation.id, context: context)
                .contains { $0.payloadKind == .file }
        )
    }

    func testGroupTextCoordinatesTwoMentionedRolesThenGroupStickerReceivesReply() async throws {
        let fixture = try makeFixture(
            responses: ["角色回应一。", "角色回应二。", "群内贴图也收到啦。"]
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstRoleID = try fixture.appModel.createCompanion(
            name: "甲",
            userName: "你",
            prompt: "负责认真回答"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "乙",
            userName: "你",
            prompt: "负责温柔回答"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "双角色测试群",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        fixture.appModel.openGroup(conversationID: groupID)

        let context = ModelContext(fixture.bootstrap.container)
        fixture.appModel.sendGroupMessage(
            "@甲 @乙 请按顺序回答这条消息。",
            conversationID: groupID
        )
        try await waitUntil {
            fixture.client.chatRequests == 2
                && !fixture.appModel.isGeneratingGroupReply
        }

        var groupEvents = try events(in: groupID, context: context)
        let firstUserEvent = try XCTUnwrap(groupEvents.first { $0.role == .user })
        let firstAssistantEvents = groupEvents.filter { $0.role == .assistant }
        XCTAssertEqual(firstUserEvent.content, "@甲 @乙 请按顺序回答这条消息。")
        XCTAssertEqual(firstAssistantEvents.count, 2)
        XCTAssertEqual(
            firstAssistantEvents.map(\.content),
            ["角色回应一。", "角色回应二。"]
        )
        XCTAssertEqual(
            Set(firstAssistantEvents.compactMap(\.senderRoleID)),
            Set([firstRoleID, secondRoleID])
        )
        XCTAssertTrue(firstAssistantEvents.allSatisfy { $0.deliveryState == .complete })
        XCTAssertTrue(
            zip(firstAssistantEvents, firstAssistantEvents.dropFirst()).allSatisfy {
                $0.deviceSequence < $1.deviceSequence
            }
        )

        let sticker = try XCTUnwrap(StickerCatalog.item(for: "generic.reaction.01"))
        fixture.appModel.sendGroupSticker(
            stickerID: sticker.stickerID,
            conversationID: groupID
        )
        try await waitUntil {
            fixture.client.chatRequests == 3
                && !fixture.appModel.isGeneratingGroupReply
        }

        groupEvents = try events(in: groupID, context: context)
        let stickerUserEvent = try XCTUnwrap(
            groupEvents.last {
                $0.role == .user && $0.payloadKind == .sticker
            }
        )
        XCTAssertEqual(stickerUserEvent.stickerID, sticker.stickerID)
        XCTAssertEqual(
            stickerUserEvent.content,
            "[表情：\(sticker.alternativeText)]"
        )
        XCTAssertEqual(stickerUserEvent.deliveryState, .complete)

        let allAssistantEvents = groupEvents.filter { $0.role == .assistant }
        XCTAssertEqual(allAssistantEvents.count, 3)
        XCTAssertEqual(allAssistantEvents.last?.content, "群内贴图也收到啦。")
        XCTAssertEqual(fixture.client.chatRequests, 3)
        let requestContents = fixture.client.chatMessageSnapshots.flatMap { $0 }.map(\.content)
        for event in firstAssistantEvents {
            let senderName = event.senderRoleID == firstRoleID ? "甲" : "乙"
            XCTAssertTrue(requestContents.contains {
                $0.contains("【消息发送者：\(senderName)】")
                    && $0.contains(event.content)
            })
        }
    }

    func testPokeGroupCompanionTargetsOnlyTappedRoleWithoutUserOrAffinityTurn() async throws {
        let fixture = try makeFixture(responses: ["甲继续说。"])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstRoleID = try fixture.appModel.createCompanion(
            name: "甲",
            userName: "你",
            prompt: "自然承接群聊"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "乙",
            userName: "你",
            prompt: "保持群聊在场"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "拍一拍测试群",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        fixture.appModel.openGroup(conversationID: groupID)

        let context = ModelContext(fixture.bootstrap.container)
        let relationshipRowsBefore: [CompanionRelationshipRecord] = try context.fetch(
            FetchDescriptor<CompanionRelationshipRecord>()
        )
        let affinityBefore = try XCTUnwrap(
            relationshipRowsBefore.first(where: { $0.roleID == firstRoleID })
        ).affinityScore
        fixture.appModel.pokeGroupCompanion(
            roleID: firstRoleID,
            conversationID: groupID
        )
        try await waitUntil {
            fixture.client.chatRequests == 1
                && !fixture.appModel.isGeneratingGroupReply
        }

        let groupEvents = try events(in: groupID, context: context)
        let pokeEvent = try XCTUnwrap(groupEvents.first { $0.role == .system })
        let assistantEvent = try XCTUnwrap(groupEvents.first { $0.role == .assistant })

        XCTAssertEqual(pokeEvent.content, "你拍了拍「甲」")
        XCTAssertTrue(groupEvents.filter { $0.role == .user }.isEmpty)
        XCTAssertEqual(assistantEvent.content, "甲继续说。")
        XCTAssertEqual(assistantEvent.senderRoleID, firstRoleID)
        XCTAssertEqual(assistantEvent.parentEventID, pokeEvent.id)
        XCTAssertFalse(
            groupEvents.contains {
                $0.role == .assistant && $0.senderRoleID == secondRoleID
            }
        )
        let relationshipRowsAfter: [CompanionRelationshipRecord] = try context.fetch(
            FetchDescriptor<CompanionRelationshipRecord>()
        )
        let affinityAfter = try XCTUnwrap(
            relationshipRowsAfter.first(where: { $0.roleID == firstRoleID })
        ).affinityScore
        XCTAssertEqual(affinityAfter, affinityBefore)

        let prompt = try XCTUnwrap(fixture.client.chatMessageSnapshots.last)
        XCTAssertEqual(prompt.last?.role, "user")
        XCTAssertTrue(prompt.last?.content.contains("拍一拍") == true)
        XCTAssertFalse(prompt.contains { $0.content == pokeEvent.content })
    }

    func testGroupCreatorCanRemoveMemberAndDissolveWithoutDeletingHistory() throws {
        let fixture = try makeFixture(responses: [])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let firstRoleID = try fixture.appModel.createCompanion(
            name: "甲",
            userName: "你",
            prompt: "群成员甲"
        )
        let secondRoleID = try fixture.appModel.createCompanion(
            name: "乙",
            userName: "你",
            prompt: "群成员乙"
        )
        let thirdRoleID = try fixture.appModel.createCompanion(
            name: "丙",
            userName: "你",
            prompt: "群成员丙"
        )
        let groupID = try fixture.appModel.createGroup(
            name: "群主管理测试",
            participantRoleIDs: [firstRoleID, secondRoleID]
        )
        let context = ModelContext(fixture.bootstrap.container)
        let retainedEvent = ConversationEvent(
            conversationID: groupID,
            deviceID: "group-admin-test",
            deviceSequence: 1,
            logicalTimestamp: "1-group-admin-test-1",
            role: .user,
            content: "解散后仍应保留",
            contentHash: ContentHasher.sha256("解散后仍应保留"),
            roleID: nil
        )
        context.insert(retainedEvent)
        try context.save()

        XCTAssertTrue(fixture.appModel.isGroupOwner(conversationID: groupID))
        XCTAssertEqual(fixture.appModel.groupParticipants(conversationID: groupID).count, 3)
        XCTAssertEqual(
            fixture.appModel.groupParticipants(conversationID: groupID).filter {
                $0.kind == .user
            }.count,
            1
        )

        try fixture.appModel.addGroupParticipants(
            roleIDs: [thirdRoleID],
            conversationID: groupID
        )
        XCTAssertEqual(fixture.appModel.groupParticipants(conversationID: groupID).count, 4)
        XCTAssertTrue(
            fixture.appModel.groupParticipants(conversationID: groupID).contains {
                $0.roleID == thirdRoleID
            }
        )

        try fixture.appModel.removeGroupParticipant(
            roleID: firstRoleID,
            conversationID: groupID
        )

        XCTAssertFalse(
            fixture.appModel.groupParticipants(conversationID: groupID).contains {
                $0.roleID == firstRoleID
            }
        )
        XCTAssertTrue(
            fixture.appModel.groupParticipants(conversationID: groupID).contains {
                $0.roleID == secondRoleID
            }
        )
        let removedRows = try context.fetch(FetchDescriptor<GroupParticipantRecord>()).filter {
            $0.conversationID == groupID && $0.participantRoleID == firstRoleID
        }
        XCTAssertFalse(removedRows.isEmpty)
        XCTAssertTrue(removedRows.allSatisfy { $0.lifecycle == .deleted && $0.leftAt != nil })

        fixture.appModel.openGroup(conversationID: groupID)
        fixture.appModel.setConversationPinned(groupID, pinned: true)
        fixture.appModel.markConversationUnread(conversationID: groupID)
        try fixture.appModel.dissolveGroup(conversationID: groupID)

        XCTAssertFalse(fixture.appModel.groupConversations.contains { $0.conversationID == groupID })
        XCTAssertFalse(fixture.appModel.isGroupOwner(conversationID: groupID))
        XCTAssertNil(fixture.appModel.activeGroupConversationID)
        XCTAssertFalse(fixture.appModel.isConversationPinned(groupID))
        XCTAssertFalse(fixture.appModel.manuallyUnreadConversationIDs.contains(groupID))
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<GroupConversationRecord>())
                .filter { $0.conversationID == groupID }
                .allSatisfy { $0.lifecycle == .deleted }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<GroupParticipantRecord>())
                .filter { $0.conversationID == groupID }
                .allSatisfy { $0.lifecycle == .deleted && $0.leftAt != nil }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ConversationRecord>())
                .filter { $0.id == groupID }
                .allSatisfy(\.archived)
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ConversationEvent>())
                .contains { $0.id == retainedEvent.id && $0.content == "解散后仍应保留" }
        )
        XCTAssertThrowsError(
            try fixture.appModel.removeGroupParticipant(
                roleID: secondRoleID,
                conversationID: groupID
            )
        )
    }

    func testChatListPreferencesAndDirectConversationRemovalPreserveArchivedSession() throws {
        let fixture = try makeFixture(responses: [])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let roleID = try fixture.appModel.createCompanion(
            name: "列表测试",
            userName: "你",
            prompt: "验证消息列表操作"
        )
        let conversationID = try XCTUnwrap(
            fixture.appModel.activeDirectConversationID(roleID: roleID)
        )
        fixture.appModel.setConversationPinned(conversationID, pinned: true)
        fixture.appModel.markConversationUnread(conversationID: conversationID)

        XCTAssertTrue(fixture.appModel.isConversationPinned(conversationID))
        XCTAssertEqual(fixture.appModel.unreadCount(forConversationID: conversationID), 1)
        XCTAssertEqual(fixture.appModel.chatUnreadCount, 1)
        XCTAssertTrue(
            SettingsStore.pinnedConversationIDs(defaults: fixture.defaults).contains(conversationID)
        )
        XCTAssertTrue(
            SettingsStore.manuallyUnreadConversationIDs(defaults: fixture.defaults)
                .contains(conversationID)
        )

        try fixture.appModel.removeDirectConversationFromChatList(roleID: roleID)

        XCTAssertNil(fixture.appModel.activeDirectConversationID(roleID: roleID))
        XCTAssertNil(fixture.appModel.directConversationActivity(roleID: roleID))
        XCTAssertFalse(fixture.appModel.isConversationPinned(conversationID))
        XCTAssertFalse(fixture.appModel.manuallyUnreadConversationIDs.contains(conversationID))
        let context = ModelContext(fixture.bootstrap.container)
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ConversationRecord>())
                .contains { $0.id == conversationID && $0.archived }
        )

        try fixture.appModel.selectCompanion(id: roleID)
        let replacementID = try XCTUnwrap(
            fixture.appModel.activeDirectConversationID(roleID: roleID)
        )
        XCTAssertNotEqual(replacementID, conversationID)
    }

    func testStoppingAfterFirstDisplayedSegmentCancelsPresentationWithoutCompletingHiddenText() async throws {
        let firstPart = String(repeating: "第一段内容", count: 10) + "。"
        let secondPart = "第二段仍然没有显示。"
        let fullReply = firstPart + secondPart
        let fixture = try makeFixture(responses: [fullReply])
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let plannedSegments = ChatTurnPresentationService().segments(for: fullReply)
        XCTAssertEqual(plannedSegments, [firstPart, secondPart])

        let context = ModelContext(fixture.bootstrap.container)
        fixture.appModel.send("请给我两段回复，然后在中途停止。")
        try await waitUntil {
            guard fixture.client.chatRequests == 1 else { return false }
            let presentations = (try? context.fetch(
                FetchDescriptor<ChatTurnPresentationRecord>()
            )) ?? []
            return presentations.contains {
                $0.conversationID == fixture.appModel.currentConversation.id
                    && $0.state == .delivering
                    && $0.displayedSegmentCount == 1
            }
        }

        fixture.appModel.stopGenerating()
        try await waitUntil { !fixture.appModel.isGenerating }

        let events = try events(
            in: fixture.appModel.currentConversation.id,
            context: context
        )
        let assistantEvent = try XCTUnwrap(events.first { $0.role == .assistant })
        XCTAssertEqual(assistantEvent.content, plannedSegments[0])
        XCTAssertFalse(assistantEvent.content.contains(plannedSegments[1]))
        XCTAssertEqual(assistantEvent.deliveryState, .complete)

        let presentation = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
                .first {
                    $0.conversationID == fixture.appModel.currentConversation.id
                        && $0.idempotencyKey.hasPrefix("assistant-reply:")
                }
        )
        XCTAssertEqual(presentation.state, .cancelled)
        XCTAssertEqual(presentation.displayedSegmentCount, 1)
        XCTAssertLessThan(presentation.displayProgress, 1)
        XCTAssertNil(presentation.completedAt)
    }

    private func makeFixture(responses: [String]) throws -> AppModelFixture {
        let suiteName = "AppModelStickerAndGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.8, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(600, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(24, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)

        let bootstrap = PersistenceController.makeContainer(
            inMemory: true,
            preferCloud: false
        )
        let client = SequencedFixtureAIClient(responses: responses)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )
        return AppModelFixture(
            appModel: appModel,
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName,
            client: client
        )
    }

    private func events(
        in conversationID: UUID,
        context: ModelContext
    ) throws -> [ConversationEvent] {
        try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == conversationID && !$0.redacted }
            .sorted {
                if $0.deviceSequence != $1.deviceSequence {
                    return $0.deviceSequence < $1.deviceSequence
                }
                return $0.id.uuidString < $1.id.uuidString
            }
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
        XCTFail("Timed out waiting for AppModel state")
        throw WaitError.timedOut
    }

    private enum WaitError: Error {
        case timedOut
    }
}

@MainActor
private struct AppModelFixture {
    let appModel: AppModel
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
    let client: SequencedFixtureAIClient
}

private final class SequencedFixtureAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String]
    private var storedChatRequests = 0
    private var storedChatMessageSnapshots: [[APIChatMessage]] = []

    init(responses: [String]) {
        self.responses = responses
    }

    var chatRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedChatRequests
    }

    var chatMessageSnapshots: [[APIChatMessage]] {
        lock.lock()
        defer { lock.unlock() }
        return storedChatMessageSnapshots
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        record(messages: messages)
        return AsyncThrowingStream { continuation in
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
        record(messages: messages)
        return nextResponse()
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
        storedChatRequests += 1
        if responses.isEmpty { return "默认测试回复。" }
        return responses.removeFirst()
    }

    private func record(messages: [APIChatMessage]) {
        lock.lock()
        storedChatMessageSnapshots.append(messages)
        lock.unlock()
    }
}
