import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class BuiltInCompanionCatalogTests: XCTestCase {
    func testReleaseCatalogContainsOnlyAyane() {
        XCTAssertEqual(BuiltInCompanionCatalog.companions.count, 1)
        XCTAssertEqual(BuiltInCompanionCatalog.companions[0].id, RoleScope.legacyRoleID)
        XCTAssertEqual(BuiltInCompanionCatalog.companions[0].name, "绫音")
        XCTAssertTrue(BuiltInCompanionCatalog.companions[0].legacyPromptHashes.isEmpty)
        XCTAssertEqual(
            BuiltInCompanionAvatarCatalog.assetNameByDisplayName,
            ["绫音": "AyaneAvatar"]
        )
        XCTAssertEqual(BuiltInCompanionAvatarCatalog.assetName(for: " 绫音\n"), "AyaneAvatar")
    }

    func testFreshSeedCreatesExactlyOneBuiltInWithInfiniteAffinity() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(try BuiltInCompanionCatalog.seedIfNeeded(
            in: context,
            defaults: defaults,
            deviceID: "test-device"
        ))
        XCTAssertFalse(try BuiltInCompanionCatalog.seedIfNeeded(
            in: context,
            defaults: defaults,
            deviceID: "test-device"
        ))

        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, RoleScope.legacyRoleID)
        XCTAssertEqual(profiles[0].name, "绫音")
        XCTAssertEqual(profiles[0].userName, "主人")
        XCTAssertTrue(profiles[0].prompt.contains("【统一用户资料】"))

        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
        XCTAssertEqual(relationships.count, 1)
        XCTAssertEqual(relationships[0].affinityScore, 100)
        XCTAssertEqual(relationships[0].state, .accepted)
        XCTAssertEqual(defaults.integer(forKey: SettingsKeys.builtInCompanionCatalogMigrationVersion), 3)
    }

    func testCustomRoleAndExistingUserProfileAreNotOverwritten() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let customID = UUID()
        context.insert(CompanionProfileRecord(
            id: customID,
            name: "用户自建角色",
            userName: "陛下",
            prompt: "保留这段用户角色设定。",
            revision: 7,
            deviceID: "custom-device"
        ))
        context.insert(UserProfileRecord(
            displayName: "已有显示名",
            birthdayMonth: 4,
            birthdayDay: 5,
            deviceID: "custom-device"
        ))
        try context.save()

        _ = try BuiltInCompanionCatalog.seedIfNeeded(
            in: context,
            defaults: defaults,
            deviceID: "seed-device"
        )

        let profile = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>())
                .first { $0.id == customID }
        )
        XCTAssertEqual(profile.name, "用户自建角色")
        XCTAssertEqual(profile.userName, "陛下")
        XCTAssertEqual(profile.prompt, "保留这段用户角色设定。")
        XCTAssertEqual(profile.revision, 7)
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfileRecord>()).first).displayName,
            "已有显示名"
        )
    }

    func testRetiredRoleMigrationArchivesLifecycleOnlyAndIsIdempotent() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldRoleID = try XCTUnwrap(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let retiredRoleDigests = Set([ContentHasher.sha256(oldRoleID.uuidString.lowercased())])
        let conversationID = UUID()
        let eventID = UUID()
        let postID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = Data([1, 2, 3, 4])
        let memoryID = UUID()

        context.insert(CompanionProfileRecord(
            id: oldRoleID,
            name: "已停用角色",
            userName: "主人",
            prompt: "历史角色设定",
            revision: 4,
            deviceID: "old-device"
        ))
        context.insert(CompanionRelationshipRecord(
            roleID: oldRoleID,
            state: .accepted,
            affinityScore: 82,
            revision: 4,
            deviceID: "old-device"
        ))
        context.insert(ConversationRecord(
            id: conversationID,
            title: "旧会话",
            createdAt: now,
            roleID: oldRoleID
        ))
        context.insert(ConversationEvent(
            id: eventID,
            conversationID: conversationID,
            deviceID: "old-device",
            deviceSequence: 1,
            logicalTimestamp: "1-old-device-1",
            occurredAt: now,
            role: .assistant,
            content: "历史正文",
            contentHash: ContentHasher.sha256("历史正文"),
            roleID: oldRoleID,
            payload: .image(image, accessibilityText: "历史正文")
        ))
        context.insert(MemoryAssertionRecord(
            id: memoryID,
            kind: .profile,
            subject: "user",
            predicate: "保留",
            value: "历史记忆",
            canonicalKey: "legacy-memory",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 1,
            extractorID: "test",
            deviceID: "old-device",
            roleID: oldRoleID
        ))
        context.insert(MemoryEvidenceRecord(
            memoryID: memoryID,
            eventID: eventID,
            startUTF16: 0,
            endUTF16: 4,
            relation: .supports,
            quoteHash: ContentHasher.sha256("历史正文"),
            confidence: 1,
            roleID: oldRoleID
        ))
        context.insert(GroupConversationRecord(
            conversationID: conversationID,
            groupName: "旧群聊"
        ))
        context.insert(GroupParticipantRecord(
            conversationID: conversationID,
            groupConversationID: conversationID,
            participantRoleID: oldRoleID,
            displayName: "已停用角色"
        ))
        context.insert(CompanionMomentTaskRecord(
            roleID: oldRoleID,
            instruction: "旧任务"
        ))
        context.insert(MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "用户动态"
        ))
        context.insert(MomentAIInteractionTaskRecord(
            postID: postID,
            roleID: oldRoleID
        ))
        context.insert(ChatTurnPresentationRecord(
            conversationID: conversationID,
            roleID: oldRoleID
        ))
        context.insert(ProactiveMessageTaskRecord(
            roleID: oldRoleID,
            conversationID: conversationID
        ))
        context.insert(FriendApplicationRecord(
            roleID: oldRoleID,
            status: .pending
        ))
        try context.save()

        let result = try BuiltInCompanionCatalog.retireLegacyCompanions(
            in: context,
            deviceID: "migration-device",
            now: now,
            retiredRoleDigests: retiredRoleDigests
        )
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.retiredRelationships, 1)
        XCTAssertEqual(result.archivedConversations, 2)
        XCTAssertEqual(result.archivedGroupParticipants, 1)
        XCTAssertEqual(result.cancelledMomentTasks, 1)
        XCTAssertEqual(result.cancelledMomentAIInteractionTasks, 1)
        XCTAssertEqual(result.cancelledPresentations, 1)
        XCTAssertEqual(result.cancelledProactiveTasks, 1)
        XCTAssertEqual(result.cancelledFriendApplications, 1)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CompanionProfileRecord>()).count, 1)
        let event = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>()).first { $0.id == eventID }
        )
        XCTAssertEqual(event.content, "历史正文")
        XCTAssertEqual(event.imageData, image)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()).count, 1)
        XCTAssertTrue(try XCTUnwrap(
            context.fetch(FetchDescriptor<ConversationRecord>()).first
        ).archived)
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<GroupConversationRecord>()).first).lifecycle,
            .archived
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first).state,
            .deleted
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first).contactMembership,
            .archivedByUser
        )

        let second = try BuiltInCompanionCatalog.retireLegacyCompanions(
            in: context,
            deviceID: "another-device",
            now: now.addingTimeInterval(60),
            retiredRoleDigests: retiredRoleDigests
        )
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.retiredRelationships, 0)
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first).revision,
            5
        )
    }

    func testRetiredRoleMigrationDiscoversOrphanTasksAndPreservesSourceData() throws {
        let (context, defaults, suiteName) = try makeContext()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let oldRoleID = try XCTUnwrap(UUID(uuidString: "22222222-3333-4444-8555-666666666666"))
        let retiredRoleDigests = Set([ContentHasher.sha256(oldRoleID.uuidString.lowercased())])
        let conversationID = UUID()
        let eventID = UUID()
        let memoryID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let attachment = Data([9, 8, 7, 6])

        context.insert(ConversationEvent(
            id: eventID,
            conversationID: conversationID,
            deviceID: "orphan-device",
            deviceSequence: 1,
            logicalTimestamp: "1-orphan-device-1",
            occurredAt: now,
            role: .assistant,
            content: "孤儿历史正文",
            contentHash: ContentHasher.sha256("孤儿历史正文"),
            roleID: oldRoleID,
            payload: .image(attachment, accessibilityText: "孤儿历史正文")
        ))
        context.insert(MemoryAssertionRecord(
            id: memoryID,
            kind: .profile,
            subject: "user",
            predicate: "保留",
            value: "孤儿历史记忆",
            canonicalKey: "orphan-memory",
            state: .active,
            confidence: 1,
            importance: 1,
            sensitive: false,
            sourceRank: 1,
            extractorID: "test",
            deviceID: "orphan-device",
            roleID: oldRoleID
        ))
        context.insert(GroupParticipantRecord(
            conversationID: conversationID,
            participantRoleID: oldRoleID,
            displayName: "已停用角色"
        ))
        context.insert(CompanionMomentTaskRecord(
            roleID: oldRoleID,
            instruction: "孤儿任务"
        ))
        context.insert(MomentAIInteractionTaskRecord(
            postID: UUID(),
            roleID: oldRoleID
        ))
        context.insert(ChatTurnPresentationRecord(
            conversationID: conversationID,
            roleID: oldRoleID
        ))
        context.insert(ProactiveMessageTaskRecord(
            roleID: oldRoleID,
            conversationID: conversationID
        ))
        context.insert(FriendApplicationRecord(
            roleID: oldRoleID,
            status: .pending
        ))
        context.insert(ConversationReadStateRecord(
            roleID: oldRoleID,
            conversationID: conversationID
        ))
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CompanionProfileRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ConversationRecord>()).isEmpty)

        let result = try BuiltInCompanionCatalog.retireLegacyCompanions(
            in: context,
            deviceID: "migration-device",
            now: now,
            retiredRoleDigests: retiredRoleDigests
        )

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.matchedProfiles, 0)
        XCTAssertEqual(result.retiredRelationships, 1)
        XCTAssertEqual(result.archivedConversations, 0)
        XCTAssertEqual(result.archivedGroupParticipants, 1)
        XCTAssertEqual(result.cancelledMomentTasks, 1)
        XCTAssertEqual(result.cancelledMomentAIInteractionTasks, 1)
        XCTAssertEqual(result.cancelledPresentations, 1)
        XCTAssertEqual(result.cancelledProactiveTasks, 1)
        XCTAssertEqual(result.cancelledFriendApplications, 1)

        let event = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ConversationEvent>()).first { $0.id == eventID }
        )
        XCTAssertEqual(event.content, "孤儿历史正文")
        XCTAssertEqual(event.imageData, attachment)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).count, 1)
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == oldRoleID }
        )
        XCTAssertEqual(relationship.state, .deleted)
        XCTAssertEqual(relationship.contactMembership, .archivedByUser)
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<GroupParticipantRecord>()).first).lifecycle,
            .archived
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>()).first).state,
            .cancelled
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>()).first).state,
            .cancelled
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()).first).state,
            .cancelled
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()).first).state,
            .cancelled
        )
        XCTAssertEqual(
            try XCTUnwrap(try context.fetch(FetchDescriptor<FriendApplicationRecord>()).first).status,
            .cancelled
        )

        let second = try BuiltInCompanionCatalog.retireLegacyCompanions(
            in: context,
            deviceID: "another-device",
            now: now.addingTimeInterval(60),
            retiredRoleDigests: retiredRoleDigests
        )
        XCTAssertFalse(second.changed)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).count, 1)
    }

    private func makeContext() throws -> (ModelContext, UserDefaults, String) {
        let suiteName = "BuiltInCompanionCatalogTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        return (ModelContext(bootstrap.container), defaults, suiteName)
    }
}
