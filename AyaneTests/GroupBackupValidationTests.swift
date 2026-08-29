import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class GroupBackupValidationTests: XCTestCase {
    func testTwoRoleGroupBackupImportsWithSpeakerScopedReferences() throws {
        let source = try makeFixture()
        let data = try DataExportService.export(
            context: source.context,
            defaults: source.defaults,
            now: source.now.addingTimeInterval(20)
        )

        let payload = try decode(data)
        XCTAssertEqual(payload.groupConversations.count, 1)
        XCTAssertEqual(payload.groupParticipants.filter {
            $0.participantKind == .companion && $0.leftAt == nil
        }.count, 2)
        XCTAssertEqual(
            Set(payload.events.filter { $0.role == EventRole.assistant.rawValue }
                .compactMap(\.senderRoleID)),
            Set([source.firstRoleID, source.secondRoleID])
        )

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let summary = try DataImportService.replaceAll(
            with: data,
            context: destinationContext,
            defaults: try makeDefaults()
        )

        XCTAssertEqual(summary.events, 3)
        XCTAssertEqual(summary.groupConversations, 1)
        XCTAssertEqual(summary.groupParticipants, 3)
        XCTAssertEqual(summary.evidence, 1)
        XCTAssertEqual(summary.summaries, 1)
        XCTAssertEqual(summary.conversationReadStates, 1)

        let restoredEvents = try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
        let firstReply = try XCTUnwrap(restoredEvents.first { $0.id == source.firstReplyID })
        let secondReply = try XCTUnwrap(restoredEvents.first { $0.id == source.secondReplyID })
        XCTAssertEqual(firstReply.roleID, source.firstRoleID)
        XCTAssertEqual(firstReply.senderRoleID, source.firstRoleID)
        XCTAssertEqual(secondReply.roleID, source.secondRoleID)
        XCTAssertEqual(secondReply.senderRoleID, source.secondRoleID)

        let evidence = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>()).first
        )
        XCTAssertEqual(evidence.roleID, source.firstRoleID)
        XCTAssertEqual(evidence.eventID, source.userEventID)
        let readState = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<ConversationReadStateRecord>()).first
        )
        XCTAssertEqual(readState.roleID, RoleScope.legacyRoleID)
        XCTAssertEqual(readState.lastReadEventID, source.secondReplyID)
    }

    func testTwoRoleGroupBackupMergesAndRetainsSpeakerScopedReferences() throws {
        let source = try makeFixture()
        let payload = try decode(
            try DataExportService.export(
                context: source.context,
                defaults: source.defaults,
                now: source.now.addingTimeInterval(20)
            )
        )
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)

        let report = try DataMergeService.merge(payload, into: destinationContext)

        XCTAssertEqual(report.events.inserted, 3)
        XCTAssertEqual(report.evidence.inserted, 1)
        XCTAssertEqual(report.summaries.inserted, 1)
        XCTAssertEqual(report.conversationReadStates.inserted, 1)
        XCTAssertEqual(report.groupConversations.inserted, 1)
        XCTAssertEqual(report.groupParticipants.inserted, 3)

        let events = try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
        XCTAssertEqual(
            events.first(where: { $0.id == source.firstReplyID })?.senderRoleID,
            source.firstRoleID
        )
        XCTAssertEqual(
            events.first(where: { $0.id == source.secondReplyID })?.senderRoleID,
            source.secondRoleID
        )
        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationReadStateRecord>()).first?.lastReadEventID,
            source.secondReplyID
        )
    }

    func testGroupAssistantMustMatchAnActiveParticipantAndBothRoleFields() throws {
        let source = try makeFixture()
        let payload = try decode(
            try DataExportService.export(
                context: source.context,
                defaults: source.defaults,
                now: source.now.addingTimeInterval(20)
            )
        )
        var invalid = payload
        invalid.events = payload.events.map { event in
            guard event.id == source.firstReplyID else { return event }
            var copy = event
            copy.roleID = source.secondRoleID
            return copy
        }

        XCTAssertThrowsError(try DataImportService.validate(invalid)) { error in
            guard case DataImportError.invalidReference = error else {
                return XCTFail("Unexpected import error: \(error)")
            }
        }
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        XCTAssertThrowsError(try DataMergeService.merge(invalid, into: destinationContext)) { error in
            guard case DataMergeError.invalidValue = error else {
                return XCTFail("Unexpected merge error: \(error)")
            }
        }
    }

    private struct Fixture {
        let context: ModelContext
        let defaults: UserDefaults
        let now: Date
        let firstRoleID: UUID
        let secondRoleID: UUID
        let userEventID: UUID
        let firstReplyID: UUID
        let secondReplyID: UUID
    }

    private func makeFixture() throws -> Fixture {
        let now = Date(timeIntervalSince1970: 1_900_400_000)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let defaults = try makeDefaults()
        configureDefaults(defaults)

        let firstRoleID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondRoleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let conversationID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let groupID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let userEventID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let firstReplyID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
        let secondReplyID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let memoryID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!

        for (roleID, name) in [
            (RoleScope.legacyRoleID, "旧角色"),
            (firstRoleID, "甲"),
            (secondRoleID, "乙")
        ] {
            context.insert(CompanionProfileRecord(
                id: roleID,
                name: name,
                userName: "你",
                prompt: "保持自然、清醒地回应。",
                createdAt: now,
                updatedAt: now,
                revision: 1,
                deviceID: "group-fixture"
            ))
        }

        let conversation = ConversationRecord(
            id: conversationID,
            title: "夜话群",
            createdAt: now,
            roleID: nil
        )
        conversation.updatedAt = now.addingTimeInterval(1)
        context.insert(conversation)
        context.insert(GroupConversationRecord(
            id: groupID,
            conversationID: conversationID,
            groupName: "夜话群",
            lifecycle: .active,
            createdAt: now,
            updatedAt: now.addingTimeInterval(2),
            revision: 1,
            deviceID: "group-fixture"
        ))
        context.insert(GroupParticipantRecord(
            conversationID: conversationID,
            groupConversationID: groupID,
            participantKind: .user,
            displayName: "我",
            joinedAt: now,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "group-fixture"
        ))
        for (roleID, name) in [(firstRoleID, "甲"), (secondRoleID, "乙")] {
            context.insert(GroupParticipantRecord(
                conversationID: conversationID,
                groupConversationID: groupID,
                participantRoleID: roleID,
                participantKind: .companion,
                displayName: name,
                joinedAt: now,
                createdAt: now,
                updatedAt: now,
                revision: 1,
                deviceID: "group-fixture"
            ))
        }

        let userContent = "今晚群里聊聊。"
        let userEvent = ConversationEvent(
            id: userEventID,
            conversationID: conversationID,
            deviceID: "group-fixture",
            deviceSequence: 1,
            logicalTimestamp: "1900400000000-group-fixture-1",
            occurredAt: now.addingTimeInterval(3),
            role: .user,
            content: userContent,
            contentHash: ContentHasher.sha256(userContent),
            roleID: nil
        )
        let firstContent = "甲先说一句。"
        let firstReply = ConversationEvent(
            id: firstReplyID,
            conversationID: conversationID,
            deviceID: "group-fixture",
            deviceSequence: 2,
            logicalTimestamp: "1900400000000-group-fixture-2",
            occurredAt: now.addingTimeInterval(4),
            role: .assistant,
            content: firstContent,
            contentHash: ContentHasher.sha256(firstContent),
            parentEventID: userEventID,
            roleID: firstRoleID,
            senderRoleID: firstRoleID
        )
        let secondContent = "乙也在听。"
        let secondReply = ConversationEvent(
            id: secondReplyID,
            conversationID: conversationID,
            deviceID: "group-fixture",
            deviceSequence: 3,
            logicalTimestamp: "1900400000000-group-fixture-3",
            occurredAt: now.addingTimeInterval(5),
            role: .assistant,
            content: secondContent,
            contentHash: ContentHasher.sha256(secondContent),
            parentEventID: userEventID,
            roleID: secondRoleID,
            senderRoleID: secondRoleID
        )
        context.insert(userEvent)
        context.insert(firstReply)
        context.insert(secondReply)

        let memory = MemoryAssertionRecord(
            id: memoryID,
            kind: .preference,
            subject: "user",
            predicate: "group_topic",
            value: "今晚群里聊聊",
            canonicalKey: "user.group_topic",
            state: .active,
            confidence: 0.9,
            importance: 0.8,
            sensitive: false,
            sourceRank: 100,
            observedAt: userEvent.occurredAt,
            extractorID: "group-fixture",
            deviceID: "group-fixture",
            roleID: firstRoleID
        )
        context.insert(memory)
        context.insert(MemoryEvidenceRecord(
            memoryID: memoryID,
            eventID: userEventID,
            startUTF16: 0,
            endUTF16: userContent.utf16.count,
            relation: .supports,
            quoteHash: ContentHasher.sha256(userContent),
            confidence: 0.9,
            roleID: firstRoleID
        ))
        let summary = MemorySummaryRecord(
            conversationID: conversationID,
            scope: "rolling",
            content: "群里今晚开始聊天。",
            firstEventID: userEventID,
            lastEventID: firstReplyID,
            coveredEventCount: 2,
            extractorID: "group-fixture",
            roleID: firstRoleID
        )
        summary.createdAt = now.addingTimeInterval(6)
        summary.updatedAt = now.addingTimeInterval(6)
        context.insert(summary)
        context.insert(ConversationReadStateRecord(
            roleID: RoleScope.legacyRoleID,
            conversationID: conversationID,
            lastReadOccurredAt: secondReply.occurredAt,
            lastReadLogicalTimestamp: secondReply.logicalTimestamp,
            lastReadEventID: secondReplyID,
            updatedAt: now.addingTimeInterval(7),
            revision: 1,
            deviceID: "group-fixture"
        ))
        try context.save()

        return Fixture(
            context: context,
            defaults: defaults,
            now: now,
            firstRoleID: firstRoleID,
            secondRoleID: secondRoleID,
            userEventID: userEventID,
            firstReplyID: firstReplyID,
            secondReplyID: secondReplyID
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
        defaults.set("旧角色", forKey: SettingsKeys.personaName)
        defaults.set("你", forKey: SettingsKeys.userName)
        defaults.set("保持自然、清醒地回应。", forKey: SettingsKeys.personaPrompt)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "GroupBackupValidationTests.\(UUID().uuidString)"
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
}
