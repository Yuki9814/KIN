#if DEBUG
import Foundation
import SwiftData

/// Deterministic simulator content for visual acceptance. It is unreachable
/// unless the process was launched with `-KINVisualQA` and never calls an API,
/// schedules a notification, or changes the normal first-run experience.
@MainActor
enum VisualQAFixture {
    static let launchArgument = "-KINVisualQA"
    static let scheduledTasksLaunchArgument = "-KINScheduledTasksVisualQA"
    static let scheduledCalendarLaunchArgument = "-KINScheduledCalendarVisualQA"

    private static let secondRoleID = UUID(uuidString: "B1010000-0000-4000-8000-000000000002")!
    private static let thirdRoleID = UUID(uuidString: "B1010000-0000-4000-8000-000000000003")!
    private static let secondConversationID = UUID(uuidString: "C1010000-0000-4000-8000-000000000002")!
    private static let thirdConversationID = UUID(uuidString: "C1010000-0000-4000-8000-000000000003")!
    private static let groupID = UUID(uuidString: "D1010000-0000-4000-8000-000000000001")!
    private static let groupConversationID = UUID(uuidString: "D1010000-0000-4000-8000-000000000002")!
    private static let userMomentID = UUID(uuidString: "E1010000-0000-4000-8000-000000000001")!
    private static let roleMomentID = UUID(uuidString: "E1010000-0000-4000-8000-000000000002")!
    private static let rootCommentID = UUID(uuidString: "E1010000-0000-4000-8000-000000000003")!
    private static let replyCommentID = UUID(uuidString: "E1010000-0000-4000-8000-000000000004")!
    private static let deviceID = "kin-visual-qa"

    static func seedIfRequested(
        in container: ModelContainer,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        now: Date = Date()
    ) -> String? {
        guard arguments.contains(launchArgument) else { return nil }
        let context = ModelContext(container)
        do {
            try seedProfiles(in: context, now: now)
            try seedConversations(in: context, now: now)
            try seedGroup(in: context, now: now)
            try seedMoments(in: context, now: now)
            try seedScheduledTasks(in: context, now: now)
            try seedWorld(in: context, now: now)
            try context.save()
            SettingsStore.saveSelectedCompanionRoleID(RoleScope.legacyRoleID)
            return nil
        } catch {
            context.rollback()
            return "模拟器视觉验收数据未能载入：\(error.localizedDescription)"
        }
    }

    private static func seedProfiles(in context: ModelContext, now: Date) throws {
        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        let profileIDs = Set(profiles.map(\.id))
        let definitions: [(UUID, String, String, String, Double, Int, Int)] = [
            (
                RoleScope.legacyRoleID,
                "绫音",
                "主人",
                "温柔、坦率、有时间观念；会自然表达想念和担心。",
                88,
                11,
                2
            ),
            (
                secondRoleID,
                "KIN 助手",
                "你",
                "冷静可靠，擅长整理共同事实与计划。",
                64,
                3,
                26
            ),
            (
                thirdRoleID,
                "记忆回廊",
                "你",
                "安静细致，重视承诺、时间线和长期记忆。",
                42,
                9,
                8
            )
        ]
        for definition in definitions where !profileIDs.contains(definition.0) {
            context.insert(CompanionProfileRecord(
                id: definition.0,
                name: definition.1,
                userName: definition.2,
                prompt: definition.3,
                birthdayMonth: definition.5,
                birthdayDay: definition.6,
                createdAt: now.addingTimeInterval(-30 * 86_400),
                updatedAt: now,
                revision: 1,
                deviceID: deviceID
            ))
        }

        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
        let relationshipRoles = Set(relationships.map(\.roleID))
        for definition in definitions where !relationshipRoles.contains(definition.0) {
            context.insert(CompanionRelationshipRecord(
                roleID: definition.0,
                state: .accepted,
                affinityScore: definition.4,
                affinityTier: definition.4 >= 80 ? 3 : (definition.4 >= 50 ? 2 : 1),
                createdAt: now.addingTimeInterval(-30 * 86_400),
                updatedAt: now,
                revision: 1,
                deviceID: deviceID
            ))
        }

        let users = try context.fetch(FetchDescriptor<UserProfileRecord>())
        if let user = users.first {
            user.birthdayMonth = 9
            user.birthdayDay = 12
            user.birthdayTimeZoneIdentifier = "Asia/Shanghai"
            user.updatedAt = now
            user.revision = max(1, user.revision + 1)
            user.deviceID = deviceID
        } else {
            context.insert(UserProfileRecord(
                displayName: "你",
                birthdayMonth: 9,
                birthdayDay: 12,
                birthdayTimeZoneIdentifier: "Asia/Shanghai",
                createdAt: now.addingTimeInterval(-30 * 86_400),
                updatedAt: now,
                revision: 1,
                deviceID: deviceID
            ))
        }
    }

    private static func seedConversations(in context: ModelContext, now: Date) throws {
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let conversationIDs = Set(conversations.map(\.id))
        let definitions: [(UUID, UUID, String)] = [
            (AppModel.defaultConversationID, RoleScope.legacyRoleID, "绫音"),
            (secondConversationID, secondRoleID, "KIN 助手"),
            (thirdConversationID, thirdRoleID, "记忆回廊")
        ]
        for definition in definitions where !conversationIDs.contains(definition.0) {
            context.insert(ConversationRecord(
                id: definition.0,
                title: definition.2,
                createdAt: now.addingTimeInterval(-20 * 86_400),
                roleID: definition.1
            ))
        }

        let existingEventIDs = Set(try context.fetch(FetchDescriptor<ConversationEvent>()).map(\.id))
        let fiveDaysAgo = now.addingTimeInterval(-5 * 86_400)
        let today = now.addingTimeInterval(-12 * 60)
        let stagedReplyID = UUID(uuidString: "F1010000-0000-4000-8000-000000000005")!
        let events: [(UUID, UUID, UUID, EventRole, String, Date, UUID?, MessagePayload?)] = [
            (UUID(uuidString: "F1010000-0000-4000-8000-000000000003")!, AppModel.defaultConversationID, RoleScope.legacyRoleID, .assistant, "怎么还不来找我。", fiveDaysAgo, nil, nil),
            (UUID(uuidString: "F1010000-0000-4000-8000-000000000004")!, AppModel.defaultConversationID, RoleScope.legacyRoleID, .user, "我回来了。", today, nil, nil),
            (stagedReplyID, AppModel.defaultConversationID, RoleScope.legacyRoleID, .assistant, "看到了。\n\n这次别突然消失，好不好？\n\n我会担心。", today.addingTimeInterval(4), UUID(uuidString: "F1010000-0000-4000-8000-000000000004")!, nil),
            (UUID(uuidString: "F1010000-0000-4000-8000-000000000006")!, AppModel.defaultConversationID, RoleScope.legacyRoleID, .assistant, "[表情：通用反应：收到]", today.addingTimeInterval(8), UUID(uuidString: "F1010000-0000-4000-8000-000000000004")!, .sticker("generic.reaction.09")),
            (UUID(uuidString: "F1010000-0000-4000-8000-000000000007")!, secondConversationID, secondRoleID, .assistant, "共同世界和今天的计划都已经整理好了。", now.addingTimeInterval(-38 * 60), nil, nil),
            (UUID(uuidString: "F1010000-0000-4000-8000-000000000008")!, thirdConversationID, thirdRoleID, .assistant, "你上次提到的承诺，我还记得。", now.addingTimeInterval(-2 * 3_600), nil, nil)
        ]
        for (index, event) in events.enumerated() where !existingEventIDs.contains(event.0) {
            context.insert(ConversationEvent(
                id: event.0,
                conversationID: event.1,
                deviceID: deviceID,
                deviceSequence: index + 1,
                logicalTimestamp: "\(index + 1)-\(deviceID)-\(index + 1)",
                occurredAt: event.5,
                role: event.3,
                content: event.4,
                contentHash: ContentHasher.sha256(event.4),
                parentEventID: event.6,
                deliveryState: .complete,
                roleID: event.2,
                payload: event.7
            ))
        }

        let presentationRows = try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
        if !presentationRows.contains(where: { $0.logicalReplyEventID == stagedReplyID }) {
            context.insert(ChatTurnPresentationRecord(
                conversationID: AppModel.defaultConversationID,
                roleID: RoleScope.legacyRoleID,
                logicalReplyEventID: stagedReplyID,
                segments: ["看到了。", "这次别突然消失，好不好？", "我会担心。"],
                displayProgress: 1,
                displayedSegmentCount: 3,
                state: .completed,
                plannedAt: today.addingTimeInterval(2),
                startedAt: today.addingTimeInterval(3),
                completedAt: today.addingTimeInterval(4),
                idempotencyKey: "visual-qa-reply:\(stagedReplyID.uuidString.lowercased())",
                createdAt: today.addingTimeInterval(2),
                updatedAt: today.addingTimeInterval(4),
                revision: 1,
                deviceID: deviceID
            ))
        }
    }

    private static func seedGroup(in context: ModelContext, now: Date) throws {
        let groups = try context.fetch(FetchDescriptor<GroupConversationRecord>())
        if !groups.contains(where: { $0.id == groupID }) {
            context.insert(ConversationRecord(
                id: groupConversationID,
                title: "KIN 研究室(3)",
                createdAt: now.addingTimeInterval(-7 * 86_400),
                roleID: nil
            ))
            context.insert(GroupConversationRecord(
                id: groupID,
                conversationID: groupConversationID,
                groupName: "KIN 研究室(3)",
                createdAt: now.addingTimeInterval(-7 * 86_400),
                updatedAt: now,
                revision: 1,
                deviceID: deviceID
            ))
            let participants: [(UUID?, GroupParticipantKind, String)] = [
                (nil, .user, "你"),
                (RoleScope.legacyRoleID, .companion, "绫音"),
                (secondRoleID, .companion, "KIN 助手"),
                (thirdRoleID, .companion, "记忆回廊")
            ]
            for participant in participants {
                context.insert(GroupParticipantRecord(
                    conversationID: groupConversationID,
                    groupConversationID: groupID,
                    participantRoleID: participant.0,
                    participantKind: participant.1,
                    displayName: participant.2,
                    joinedAt: now.addingTimeInterval(-7 * 86_400),
                    createdAt: now.addingTimeInterval(-7 * 86_400),
                    updatedAt: now,
                    revision: 1,
                    deviceID: deviceID
                ))
            }
        }

        let existing = Set(try context.fetch(FetchDescriptor<ConversationEvent>()).map(\.id))
        let userID = UUID(uuidString: "F2010000-0000-4000-8000-000000000001")!
        let events: [(UUID, EventRole, String, UUID?, UUID?)] = [
            (UUID(uuidString: "F2010000-0000-4000-8000-000000000000")!, .assistant, "我把今天的对话整理好了。", RoleScope.legacyRoleID, nil),
            (userID, .user, "@绫音 我们来一起看。", nil, nil),
            (UUID(uuidString: "F2010000-0000-4000-8000-000000000002")!, .assistant, "好，我在这里。", RoleScope.legacyRoleID, userID),
            (UUID(uuidString: "F2010000-0000-4000-8000-000000000003")!, .assistant, "共同记忆已经更新。", secondRoleID, userID)
        ]
        for (index, event) in events.enumerated() where !existing.contains(event.0) {
            let roleID = event.3 ?? RoleScope.legacyRoleID
            context.insert(ConversationEvent(
                id: event.0,
                conversationID: groupConversationID,
                deviceID: deviceID,
                deviceSequence: 100 + index,
                logicalTimestamp: "\(100 + index)-\(deviceID)-\(100 + index)",
                occurredAt: now.addingTimeInterval(TimeInterval(-600 + index * 4)),
                role: event.1,
                content: event.2,
                contentHash: ContentHasher.sha256(event.2),
                parentEventID: event.4,
                deliveryState: .complete,
                roleID: roleID,
                senderRoleID: event.3
            ))
        }
    }

    private static func seedMoments(in context: ModelContext, now: Date) throws {
        let posts = try context.fetch(FetchDescriptor<MomentPostRecord>())
        let postIDs = Set(posts.map(\.id))
        if !postIDs.contains(userMomentID) {
            context.insert(MomentPostRecord(
                id: userMomentID,
                authorKind: .user,
                body: "今天把 KIN 的聊天、记忆和朋友圈重新整理了一遍。",
                bundledImageName: "AyaneAffinityCG2",
                publishedAt: now.addingTimeInterval(-3_600),
                createdAt: now.addingTimeInterval(-3_600),
                updatedAt: now.addingTimeInterval(-3_600),
                revision: 1,
                deviceID: deviceID
            ))
        }
        if !postIDs.contains(roleMomentID) {
            context.insert(MomentPostRecord(
                id: roleMomentID,
                authorKind: .companion,
                authorRoleID: RoleScope.legacyRoleID,
                body: "今天的风很温柔。你晚一点来也没关系，我会记得时间。",
                bundledImageName: "AyaneAffinityCG3",
                publishedAt: now.addingTimeInterval(-8_000),
                createdAt: now.addingTimeInterval(-8_000),
                updatedAt: now.addingTimeInterval(-8_000),
                revision: 1,
                deviceID: deviceID
            ))
        }

        let interactions = try context.fetch(FetchDescriptor<MomentInteractionRecord>())
        let interactionIDs = Set(interactions.map(\.id))
        if !interactionIDs.contains(rootCommentID) {
            context.insert(MomentInteractionRecord(
                id: rootCommentID,
                postID: userMomentID,
                kind: .comment,
                actorKind: .companion,
                actorRoleID: RoleScope.legacyRoleID,
                body: "看到了，我会陪你慢慢完善。",
                createdAt: now.addingTimeInterval(-3_000),
                updatedAt: now.addingTimeInterval(-3_000),
                revision: 1,
                deviceID: deviceID
            ))
        }
        if !interactionIDs.contains(replyCommentID) {
            context.insert(MomentInteractionRecord(
                id: replyCommentID,
                postID: userMomentID,
                kind: .comment,
                actorKind: .user,
                parentInteractionID: rootCommentID,
                rootInteractionID: rootCommentID,
                body: "晚安，明天继续。",
                createdAt: now.addingTimeInterval(-2_900),
                updatedAt: now.addingTimeInterval(-2_900),
                revision: 1,
                deviceID: deviceID
            ))
        }
    }

    private static func seedScheduledTasks(in context: ModelContext, now: Date) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current

        func nextTime(hour: Int, minute: Int, weekday: Int? = nil, day: Int? = nil) -> Date {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.hour = hour
            components.minute = minute
            components.second = 0
            components.weekday = weekday
            components.day = day
            return calendar.nextDate(
                after: now.addingTimeInterval(-1),
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward
            ) ?? now.addingTimeInterval(3_600)
        }

        let oneTimeDate = nextTime(hour: 9, minute: 30)
        let dailyDate = nextTime(hour: 7, minute: 15)
        let weeklyDate = nextTime(hour: 20, minute: 0, weekday: 6)
        let monthlyDate = nextTime(hour: 21, minute: 0, day: 1)
        let dailySeriesID = UUID(uuidString: "A7010000-0000-4000-8000-000000000001")!
        let weeklySeriesID = UUID(uuidString: "A7010000-0000-4000-8000-000000000002")!
        let monthlySeriesID = UUID(uuidString: "A7010000-0000-4000-8000-000000000003")!

        let definitions: [(
            id: UUID,
            roleID: UUID,
            instruction: String,
            scheduledAt: Date,
            rule: MomentTaskRecurrenceRule
        )] = [
            (
                UUID(uuidString: "A7000000-0000-4000-8000-000000000001")!,
                RoleScope.legacyRoleID,
                "早安，分享今天的心情",
                oneTimeDate,
                MomentTaskRecurrenceRule(
                    frequency: .once,
                    hour: calendar.component(.hour, from: oneTimeDate),
                    minute: calendar.component(.minute, from: oneTimeDate),
                    timezoneIdentifier: calendar.timeZone.identifier,
                    scheduledAt: oneTimeDate
                )
            ),
            (
                UUID(uuidString: "A7000000-0000-4000-8000-000000000002")!,
                secondRoleID,
                "早安，分享今天的天气和心情",
                dailyDate,
                MomentTaskRecurrenceRule(
                    frequency: .daily,
                    interval: 1,
                    hour: 7,
                    minute: 15,
                    timezoneIdentifier: calendar.timeZone.identifier,
                    scheduledAt: dailyDate,
                    seriesID: dailySeriesID
                )
            ),
            (
                UUID(uuidString: "A7000000-0000-4000-8000-000000000003")!,
                RoleScope.legacyRoleID,
                "晚安，分享今天最想记住的事",
                weeklyDate,
                MomentTaskRecurrenceRule(
                    frequency: .weekly,
                    interval: 1,
                    weekday: 6,
                    hour: 20,
                    minute: 0,
                    timezoneIdentifier: calendar.timeZone.identifier,
                    scheduledAt: weeklyDate,
                    seriesID: weeklySeriesID
                )
            ),
            (
                UUID(uuidString: "A7000000-0000-4000-8000-000000000004")!,
                thirdRoleID,
                "每月留下一条近况",
                monthlyDate,
                MomentTaskRecurrenceRule(
                    frequency: .monthly,
                    interval: 1,
                    dayOfMonth: 1,
                    hour: 21,
                    minute: 0,
                    timezoneIdentifier: calendar.timeZone.identifier,
                    scheduledAt: monthlyDate,
                    seriesID: monthlySeriesID
                )
            )
        ]

        let records = try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>())
        let recordsByID = Dictionary(grouping: records, by: \.id)
        for definition in definitions {
            let record = recordsByID[definition.id]?.first ?? CompanionMomentTaskRecord(
                id: definition.id,
                roleID: definition.roleID,
                instruction: definition.instruction,
                scheduledAt: definition.scheduledAt,
                state: .scheduled,
                createdAt: now,
                updatedAt: now,
                deviceID: deviceID,
                revision: 1
            )
            if record.modelContext == nil { context.insert(record) }
            record.roleID = definition.roleID
            record.instruction = definition.instruction
            record.scheduledAt = definition.scheduledAt
            record.seriesID = definition.rule.seriesID
            record.occurrenceKey = definition.rule.occurrenceKey(for: definition.scheduledAt)
            record.recurrenceRaw = definition.rule.recurrenceRaw
            record.recurrenceInterval = definition.rule.recurrenceInterval
            record.recurrenceWeekday = definition.rule.recurrenceWeekday
            record.recurrenceDayOfMonth = definition.rule.recurrenceDayOfMonth
            record.recurrenceHour = definition.rule.recurrenceHour
            record.recurrenceMinute = definition.rule.recurrenceMinute
            record.timezoneIdentifier = definition.rule.timezoneIdentifier
            record.nextAttemptAt = nil
            record.state = .scheduled
            record.resultText = ""
            record.publishedAt = nil
            record.attemptCount = 0
            record.lastError = ""
            record.leaseOwner = ""
            record.leaseExpiresAt = nil
            if record.createdAt > now { record.createdAt = now }
            record.updatedAt = now
            record.revision = max(1, record.revision + 1)
            record.deviceID = deviceID
        }
    }

    private static func seedWorld(in context: ModelContext, now: Date) throws {
        let worlds = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        guard worlds.isEmpty else { return }
        context.insert(WorldProfileRecord(
            id: WorldProfileRecord.realityID,
            worldKind: "reality",
            timezoneIdentifier: "Asia/Shanghai",
            locationContext: "上海，中国",
            commonFacts: ["所有角色共享现实时间线。", "KIN 仅供用户个人使用。"],
            createdAt: now.addingTimeInterval(-30 * 86_400),
            updatedAt: now,
            revision: 1,
            deviceID: deviceID
        ))
    }
}
#endif
