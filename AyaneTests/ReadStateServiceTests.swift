import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class ReadStateServiceTests: XCTestCase {
    private let roleA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let roleB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testUnreadChatIsRoleScopedAndCountsOnlyCompleteNonRedactedAssistantEvents() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let relationshipA = CompanionRelationshipRecord(roleID: roleA, state: .accepted)
        let relationshipB = CompanionRelationshipRecord(roleID: roleB, state: .accepted)
        let conversationA = ConversationRecord(title: "A", roleID: roleA)
        let secondConversationA = ConversationRecord(title: "A-2", roleID: roleA)
        let conversationB = ConversationRecord(title: "B", roleID: roleB)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        let included = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "included",
            date: base,
            logical: "001"
        )
        let streaming = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .assistant,
            state: .streaming,
            content: "streaming",
            date: base.addingTimeInterval(1),
            logical: "002"
        )
        let failed = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .assistant,
            state: .failed,
            content: "failed",
            date: base.addingTimeInterval(2),
            logical: "003"
        )
        let redacted = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "redacted",
            date: base.addingTimeInterval(3),
            logical: "004"
        )
        redacted.redacted = true
        let userEvent = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .user,
            state: .complete,
            content: "user",
            date: base.addingTimeInterval(4),
            logical: "005"
        )
        let secondIncluded = makeEvent(
            conversation: secondConversationA,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "included second",
            date: base.addingTimeInterval(5),
            logical: "006"
        )
        let otherRole = makeEvent(
            conversation: conversationB,
            roleID: roleB,
            role: .assistant,
            state: .complete,
            content: "included B",
            date: base.addingTimeInterval(6),
            logical: "007"
        )

        context.insert(relationshipA)
        context.insert(relationshipB)
        context.insert(conversationA)
        context.insert(secondConversationA)
        context.insert(conversationB)
        for event in [included, streaming, failed, redacted, userEvent, secondIncluded, otherRole] {
            context.insert(event)
        }
        try context.save()

        let service = ReadStateService(context: context, deviceID: "test-device")
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversationA.id, roleID: roleA), 1)
        XCTAssertEqual(try service.unreadConversationCount(conversationID: secondConversationA.id, roleID: roleA), 1)
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversationB.id, roleID: roleB), 1)
        XCTAssertEqual(try service.unreadConversationCount(roleID: roleA), 2)
        XCTAssertEqual(try service.unreadConversationCount(), 3)

        try service.markConversationRead(
            conversationID: conversationA.id,
            roleID: roleA,
            now: base.addingTimeInterval(10)
        )
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversationA.id, roleID: roleA), 0)

        let newReply = makeEvent(
            conversation: conversationA,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "new reply",
            date: base.addingTimeInterval(11),
            logical: "011"
        )
        context.insert(newReply)
        try context.save()
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversationA.id, roleID: roleA), 1)

        secondConversationA.archived = true
        try context.save()
        XCTAssertEqual(try service.unreadConversationCount(roleID: roleA), 1)
        XCTAssertEqual(try service.unreadConversationCounts(roleID: roleA), [conversationA.id: 1])
    }

    func testUnreadChatCountsDisplayedBubblesInsideOneLogicalReply() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let relationship = CompanionRelationshipRecord(roleID: roleA, state: .accepted)
        let conversation = ConversationRecord(title: "A", roleID: roleA)
        let reply = makeEvent(
            conversation: conversation,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "第一条。\n\n第二条。\n\n第三条。",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            logical: "001"
        )
        let presentation = ChatTurnPresentationRecord(
            conversationID: conversation.id,
            roleID: roleA,
            logicalReplyEventID: reply.id,
            segments: ["第一条。", "第二条。", "第三条。"],
            displayProgress: 1,
            displayedSegmentCount: 3,
            state: .completed,
            completedAt: Date(timeIntervalSince1970: 1_700_000_003),
            idempotencyKey: "assistant-reply:test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_003),
            revision: 4,
            deviceID: "test-device"
        )
        context.insert(relationship)
        context.insert(conversation)
        context.insert(reply)
        context.insert(presentation)
        try context.save()

        let service = ReadStateService(context: context, deviceID: "test-device")
        XCTAssertEqual(
            try service.unreadConversationCount(
                conversationID: conversation.id,
                roleID: roleA
            ),
            3
        )

        try service.markConversationRead(
            conversationID: conversation.id,
            roleID: roleA,
            now: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(
            try service.unreadConversationCount(
                conversationID: conversation.id,
                roleID: roleA
            ),
            0
        )
    }

    func testMarkReadDoesNotConsumeAReplyThatIsStillStreaming() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let relationship = CompanionRelationshipRecord(roleID: roleA, state: .accepted)
        let conversation = ConversationRecord(title: "A", roleID: roleA)
        let reply = makeEvent(
            conversation: conversation,
            roleID: roleA,
            role: .assistant,
            state: .streaming,
            content: "第一条。",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            logical: "001"
        )
        let presentation = ChatTurnPresentationRecord(
            conversationID: conversation.id,
            roleID: roleA,
            logicalReplyEventID: reply.id,
            segments: ["第一条。", "第二条。", "第三条。"],
            displayProgress: 1.0 / 3.0,
            displayedSegmentCount: 1,
            state: .delivering,
            idempotencyKey: "assistant-reply:streaming-test",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            revision: 2,
            deviceID: "test-device"
        )
        context.insert(relationship)
        context.insert(conversation)
        context.insert(reply)
        context.insert(presentation)
        try context.save()

        let service = ReadStateService(context: context, deviceID: "test-device")
        try service.markConversationRead(
            conversationID: conversation.id,
            roleID: roleA,
            now: Date(timeIntervalSince1970: 1_700_000_010)
        )

        reply.content = "第一条。\n\n第二条。\n\n第三条。"
        reply.deliveryStateRaw = EventDeliveryState.complete.rawValue
        presentation.displayedSegmentCount = 3
        presentation.displayProgress = 1
        presentation.state = .completed
        presentation.completedAt = Date(timeIntervalSince1970: 1_700_000_012)
        presentation.updatedAt = Date(timeIntervalSince1970: 1_700_000_012)
        presentation.revision += 1
        try context.save()

        XCTAssertEqual(
            try service.unreadConversationCount(
                conversationID: conversation.id,
                roleID: roleA
            ),
            3
        )
    }

    func testMomentsUnreadCoversRolePublicationRepliesAndIgnoresUserInteractions() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let accepted = CompanionRelationshipRecord(roleID: roleA, state: .accepted)
        let pending = CompanionRelationshipRecord(roleID: roleB, state: .pending)
        let userPost = MomentPostRecord(
            authorKind: .user,
            body: "mine",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let companionPost = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: roleA,
            body: "theirs",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let acceptedLike = MomentInteractionRecord(
            postID: userPost.id,
            kind: .like,
            actorKind: .companion,
            actorRoleID: roleA,
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let acceptedComment = MomentInteractionRecord(
            postID: userPost.id,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleA,
            body: "comment",
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        let pendingLike = MomentInteractionRecord(
            postID: userPost.id,
            kind: .like,
            actorKind: .companion,
            actorRoleID: roleB,
            createdAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
        let userLike = MomentInteractionRecord(
            postID: userPost.id,
            kind: .like,
            actorKind: .user,
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        let userCommentOnCompanionPost = MomentInteractionRecord(
            postID: companionPost.id,
            kind: .comment,
            actorKind: .user,
            body: "question",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )

        context.insert(accepted)
        context.insert(pending)
        context.insert(userPost)
        context.insert(companionPost)
        for interaction in [
            acceptedLike,
            acceptedComment,
            pendingLike,
            userLike,
            userCommentOnCompanionPost
        ] {
            context.insert(interaction)
        }
        try context.save()

        let service = ReadStateService(context: context, deviceID: "test-device")
        // Pending-role and user-authored interactions are not companion
        // notifications; only accepted, visible role interactions count.
        XCTAssertEqual(try service.unreadMomentCount(postID: userPost.id), 2)
        // A companion publication is one virtual unread event. The user's
        // own comment is not an unread notification for either post.
        XCTAssertEqual(try service.unreadMomentCount(postID: companionPost.id), 1)
        XCTAssertEqual(try service.unreadMomentsCount(), 3)

        try service.markMomentsRead(
            postIDs: [companionPost.id],
            now: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(try service.unreadMomentCount(postID: companionPost.id), 0)
        let rolePostMarker = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MomentReadStateRecord>())
                .first { $0.postID == companionPost.id }
        )
        XCTAssertEqual(rolePostMarker.lastReadCreatedAt, companionPost.publishedAt)
        XCTAssertNil(rolePostMarker.lastReadInteractionID)

        let companionReply = MomentInteractionRecord(
            postID: companionPost.id,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleA,
            parentInteractionID: userCommentOnCompanionPost.id,
            rootInteractionID: userCommentOnCompanionPost.id,
            body: "reply",
            createdAt: Date(timeIntervalSince1970: 1_700_000_011)
        )
        context.insert(companionReply)
        try context.save()
        XCTAssertEqual(try service.unreadMomentCount(postID: companionPost.id), 1)

        try service.markMomentsRead(
            postIDs: [userPost.id],
            now: Date(timeIntervalSince1970: 1_700_000_010)
        )
        XCTAssertEqual(try service.unreadMomentCount(postID: userPost.id), 0)

        let newComment = MomentInteractionRecord(
            postID: userPost.id,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleA,
            body: "later",
            createdAt: Date(timeIntervalSince1970: 1_700_000_011)
        )
        context.insert(newComment)
        try context.save()
        XCTAssertEqual(try service.unreadMomentCount(postID: userPost.id), 1)
    }

    func testLegacyBaselineSuppressesExistingHistoryButLeavesLaterRepliesUnread() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let relationship = CompanionRelationshipRecord(roleID: roleA, state: .accepted)
        let conversation = ConversationRecord(title: "history", roleID: roleA)
        let oldReply = makeEvent(
            conversation: conversation,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "old",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            logical: "old"
        )
        context.insert(relationship)
        context.insert(conversation)
        context.insert(oldReply)
        try context.save()

        let service = ReadStateService(context: context, deviceID: "test-device")
        try service.establishInitialReadBaseline(now: Date(timeIntervalSince1970: 1_700_000_010))
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversation.id, roleID: roleA), 0)

        let laterReply = makeEvent(
            conversation: conversation,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "later",
            date: Date(timeIntervalSince1970: 1_700_000_011),
            logical: "later"
        )
        context.insert(laterReply)
        try context.save()
        XCTAssertEqual(try service.unreadConversationCount(conversationID: conversation.id, roleID: roleA), 1)
    }

    func testEmptyStoreBaselineDoesNotConsumeFirstAssistantReply() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let service = ReadStateService(context: context, deviceID: "test-device")

        try service.establishInitialReadBaseline(now: Date(timeIntervalSince1970: 1_700_000_000))

        let conversation = ConversationRecord(title: "first conversation", roleID: roleA)
        let firstReply = makeEvent(
            conversation: conversation,
            roleID: roleA,
            role: .assistant,
            state: .complete,
            content: "first reply",
            date: Date(timeIntervalSince1970: 1_700_000_001),
            logical: "first"
        )
        context.insert(conversation)
        context.insert(firstReply)
        try context.save()

        XCTAssertEqual(
            try service.unreadConversationCount(
                conversationID: conversation.id,
                roleID: roleA
            ),
            1
        )
    }

    func testTypingIndicatorFallbackAndExplicitFalse() throws {
        let suiteName = "AyaneTests.ReadState.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(SettingsStore.typingIndicatorEnabled(defaults: defaults))
        defaults.set(false, forKey: SettingsKeys.typingIndicatorEnabled)
        SettingsStore.registerDefaults(defaults: defaults)
        XCTAssertFalse(SettingsStore.typingIndicatorEnabled(defaults: defaults))
        defaults.removeObject(forKey: SettingsKeys.typingIndicatorEnabled)
        XCTAssertTrue(SettingsStore.typingIndicatorEnabled(defaults: defaults))
    }

    func testNewInstallEnablesMemoryHumanizedDelayAndProactiveMessages() throws {
        let suiteName = "AyaneTests.ReadState.NewDefaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(SettingsStore.autoExtractMemory(defaults: defaults))
        XCTAssertTrue(SettingsStore.humanizedReplyDelayEnabled(defaults: defaults))
        XCTAssertTrue(SettingsStore.proactiveMessagesEnabled(defaults: defaults))
        XCTAssertEqual(SettingsStore.proactiveQuietHours(defaults: defaults).start, 23)
        XCTAssertEqual(SettingsStore.proactiveQuietHours(defaults: defaults).end, 8)

        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        SettingsStore.registerDefaults(defaults: defaults)

        XCTAssertFalse(SettingsStore.autoExtractMemory(defaults: defaults))
        XCTAssertFalse(SettingsStore.humanizedReplyDelayEnabled(defaults: defaults))
        XCTAssertFalse(SettingsStore.proactiveMessagesEnabled(defaults: defaults))
    }

    func testRoleProactiveOverrideDoesNotChangeGlobalPreference() throws {
        let suiteName = "AyaneTests.ReadState.RoleProactive.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let roleID = UUID()

        XCTAssertTrue(SettingsStore.proactiveMessagesEnabled(roleID: roleID, defaults: defaults))
        SettingsStore.setProactiveMessagesEnabled(false, roleID: roleID, defaults: defaults)
        XCTAssertFalse(SettingsStore.proactiveMessagesEnabled(roleID: roleID, defaults: defaults))
        XCTAssertTrue(SettingsStore.proactiveMessagesEnabled(defaults: defaults))
    }

    private func makeEvent(
        conversation: ConversationRecord,
        roleID: UUID,
        role: EventRole,
        state: EventDeliveryState,
        content: String,
        date: Date,
        logical: String
    ) -> ConversationEvent {
        ConversationEvent(
            conversationID: conversation.id,
            deviceID: "test-device",
            deviceSequence: Int(date.timeIntervalSince1970),
            logicalTimestamp: logical,
            occurredAt: date,
            role: role,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: state,
            roleID: roleID
        )
    }
}
