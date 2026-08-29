import CryptoKit
import Foundation
import SwiftData

/// Shared v11-v15 wire/storage helpers. Keeping the newer rows in one small
/// value layer makes export, restore, merge and duplicate reconciliation use
/// exactly the same logical identities without adding SwiftData relationships.
enum SchemaV11DataSupport {
    static let maxTextLength = 32_000
    /// Keep imported image messages bounded before their bytes reach SwiftData
    /// external storage or a merge transaction.
    static let maxImageDataBytes = 20 * 1024 * 1024
    /// Keep imported file messages bounded before their bytes reach SwiftData
    /// external storage or a merge transaction.
    static let maxFileDataBytes = 20 * 1024 * 1024
    static let maxFileNameLength = 255
    static let maxFileTypeIdentifierLength = 256
    static let maxGroupNameLength = 200
    static let maxDisplayNameLength = 200
    static let maxDeviceIDLength = 256
    static let maxIdempotencyKeyLength = 512

    /// Hashes media bytes without first materializing a base64 string. The
    /// digest is used only in deterministic ordering/stable keys; identity
    /// checks still compare the original `Data` values directly.
    static func imageDataHash(_ data: Data?) -> String {
        guard let data else { return "" }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func fileDataHash(_ data: Data?) -> String {
        imageDataHash(data)
    }

    struct MergeReport: Equatable, Sendable {
        var worldProfile: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
        var groupConversations: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
        var groupParticipants: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
        var chatTurnPresentations: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
        var proactiveMessageTasks: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
        var friendApplications: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)

        var total: DataMergeEntityReport {
            DataMergeEntityReport(
                inserted: worldProfile.inserted + groupConversations.inserted
                    + groupParticipants.inserted + chatTurnPresentations.inserted
                    + proactiveMessageTasks.inserted + friendApplications.inserted,
                updated: worldProfile.updated + groupConversations.updated
                    + groupParticipants.updated + chatTurnPresentations.updated
                    + proactiveMessageTasks.updated + friendApplications.updated,
                unchanged: worldProfile.unchanged + groupConversations.unchanged
                    + groupParticipants.unchanged + chatTurnPresentations.unchanged
                    + proactiveMessageTasks.unchanged + friendApplications.unchanged
            )
        }
    }

    struct DuplicateSummary: Equatable, Sendable {
        var worldProfiles: Int = 0
        var groupConversations: Int = 0
        var groupParticipants: Int = 0
        var chatTurnPresentations: Int = 0
        var proactiveMessageTasks: Int = 0
        var friendApplications: Int = 0

        var total: Int {
            worldProfiles + groupConversations + groupParticipants
                + chatTurnPresentations + proactiveMessageTasks + friendApplications
        }
    }

    // MARK: Canonical export projections

    static func canonicalWorldProfile(
        _ values: [AyaneWorldProfileExport]
    ) -> AyaneWorldProfileExport {
        let worlds = canonicalWorldProfiles(values)
        return worlds.first(where: { $0.id == WorldProfileRecord.realityID })
            ?? worlds.first
            ?? .realityDefault
    }

    /// Canonicalizes reusable worlds by their logical ID. Different IDs are
    /// intentionally retained; only physical copies of the same ID converge
    /// to one deterministic winner.
    static func canonicalWorldProfiles(
        _ values: [AyaneWorldProfileExport]
    ) -> [AyaneWorldProfileExport] {
        var winners: [UUID: AyaneWorldProfileExport] = [:]
        for value in values {
            let normalized = normalizeWorld(value)
            if let current = winners[normalized.id] {
                if isOlder(current, than: normalized) {
                    winners[normalized.id] = normalized
                }
            } else {
                winners[normalized.id] = normalized
            }
        }
        return winners.keys
            .sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
            .compactMap { winners[$0] }
    }

    private static func normalizeWorld(
        _ value: AyaneWorldProfileExport
    ) -> AyaneWorldProfileExport {
        var normalized = value
        normalized.displayName = normalized.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.displayName.isEmpty {
            normalized.displayName = normalized.id == WorldProfileRecord.realityID
                ? "现实世界"
                : "世界观"
        }
        normalized.worldKind = normalized.worldKind.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.worldKind.isEmpty { normalized.worldKind = "reality" }
        normalized.timezoneIdentifier = normalized.timezoneIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.timezoneIdentifier.isEmpty {
            normalized.timezoneIdentifier = TimeZone.current.identifier
        }
        normalized.locationContext = normalized.locationContext
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.commonFacts = normalized.commonFacts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        normalized.revision = max(0, normalized.revision)
        return normalized
    }

    static func canonicalGroupConversations(
        _ values: [AyaneGroupConversationExport]
    ) -> [AyaneGroupConversationExport] {
        canonical(values, key: { $0.conversationID.uuidString.lowercased() })
            .sorted { ($0.conversationID.uuidString, $0.id.uuidString) < ($1.conversationID.uuidString, $1.id.uuidString) }
    }

    static func canonicalGroupParticipants(
        _ values: [AyaneGroupParticipantExport]
    ) -> [AyaneGroupParticipantExport] {
        canonical(values, key: participantKey)
            .sorted { participantKey($0) < participantKey($1) }
    }

    static func canonicalChatTurnPresentations(
        _ values: [AyaneChatTurnPresentationExport]
    ) -> [AyaneChatTurnPresentationExport] {
        canonical(values, key: presentationKey)
            .sorted { presentationKey($0) < presentationKey($1) }
    }

    static func canonicalProactiveMessageTasks(
        _ values: [AyaneProactiveMessageTaskExport]
    ) -> [AyaneProactiveMessageTaskExport] {
        canonical(values, key: proactiveKey)
            .sorted { proactiveKey($0) < proactiveKey($1) }
    }

    /// Friend applications converge by their idempotency key. Empty keys are
    /// retained as a stable UUID fallback for legacy/in-process callers.
    static func canonicalFriendApplications(
        _ values: [AyaneFriendApplicationExport]
    ) -> [AyaneFriendApplicationExport] {
        var winners: [String: AyaneFriendApplicationExport] = [:]
        for value in values {
            var normalized = value
            normalized.roleID = RoleScope.resolve(value.roleID)
            let key = friendApplicationKey(normalized)
            if let current = winners[key] {
                if isOlder(current, than: normalized) { winners[key] = normalized }
            } else {
                winners[key] = normalized
            }
        }
        return winners.values.sorted {
            (friendApplicationKey($0), $0.createdAt, $0.revision, $0.id.uuidString)
                < (friendApplicationKey($1), $1.createdAt, $1.revision, $1.id.uuidString)
        }
    }

    private static func canonical<Value>(
        _ values: [Value],
        key: (Value) -> String
    ) -> [Value] where Value: AnyObject {
        // Kept for reference types only; the DTOs below are value types and use
        // the specialized overloads to avoid accidental existential boxing.
        values
    }

    private static func canonical(
        _ values: [AyaneGroupConversationExport],
        key: (AyaneGroupConversationExport) -> String
    ) -> [AyaneGroupConversationExport] {
        var winners: [String: AyaneGroupConversationExport] = [:]
        for value in values {
            if let current = winners[key(value)] {
                if isOlder(current, than: value) { winners[key(value)] = value }
            } else {
                winners[key(value)] = value
            }
        }
        return Array(winners.values)
    }

    private static func canonical(
        _ values: [AyaneGroupParticipantExport],
        key: (AyaneGroupParticipantExport) -> String
    ) -> [AyaneGroupParticipantExport] {
        var winners: [String: AyaneGroupParticipantExport] = [:]
        for value in values {
            if let current = winners[key(value)] {
                if isOlder(current, than: value) { winners[key(value)] = value }
            } else {
                winners[key(value)] = value
            }
        }
        return Array(winners.values)
    }

    private static func canonical(
        _ values: [AyaneChatTurnPresentationExport],
        key: (AyaneChatTurnPresentationExport) -> String
    ) -> [AyaneChatTurnPresentationExport] {
        var winners: [String: AyaneChatTurnPresentationExport] = [:]
        for value in values {
            if let current = winners[key(value)] {
                if isOlder(current, than: value) { winners[key(value)] = value }
            } else {
                winners[key(value)] = value
            }
        }
        return Array(winners.values)
    }

    private static func canonical(
        _ values: [AyaneProactiveMessageTaskExport],
        key: (AyaneProactiveMessageTaskExport) -> String
    ) -> [AyaneProactiveMessageTaskExport] {
        var winners: [String: AyaneProactiveMessageTaskExport] = [:]
        for value in values {
            if let current = winners[key(value)] {
                if isOlder(current, than: value) { winners[key(value)] = value }
            } else {
                winners[key(value)] = value
            }
        }
        return Array(winners.values)
    }

    // MARK: Validation

    /// Validates only the v11-v15 additions. Existing import/merge validation keeps
    /// ownership of the older entities and their compatibility rules.
    static func validate(_ payload: AyaneDataExport) throws {
        // Build lookup dictionaries only after rejecting duplicate source IDs.
        // `Dictionary(uniqueKeysWithValues:)` traps on duplicates, which would
        // otherwise turn a malformed import into a process crash instead of a
        // typed validation error.
        try requireUnique(
            payload.events.map(\.id),
            entity: .event,
            description: "事件 ID 重复"
        )
        let profileIDs = Set(payload.profiles.compactMap { $0.roleID })
        let worlds = canonicalWorldProfiles(
            payload.worldProfiles.isEmpty ? [payload.worldProfile] : payload.worldProfiles
        )
        let worldIDs = Set(worlds.map(\.id))
        let conversationIDs = Set(payload.conversations.map(\.id))
        let eventByID = Dictionary(uniqueKeysWithValues: payload.events.map { ($0.id, $0) })
        let groupByConversation = Dictionary(
            uniqueKeysWithValues: canonicalGroupConversations(payload.groupConversations)
                .map { ($0.conversationID, $0) }
        )
        guard !worlds.isEmpty else {
            throw DataMergeError.invalidValue("世界观记录不能为空")
        }
        for world in worlds {
            guard !world.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  world.displayName.count <= maxDisplayNameLength,
                  !world.worldKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !world.timezoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  world.revision >= 0,
                  world.createdAt.timeIntervalSince1970.isFinite,
                  world.updatedAt.timeIntervalSince1970.isFinite,
                  world.updatedAt >= world.createdAt,
                  world.deviceID.count <= maxDeviceIDLength,
                  world.locationContext.count <= maxTextLength,
                  world.commonFacts.count <= 2_000,
                  world.commonFacts.allSatisfy({ $0.count <= maxTextLength }) else {
                throw DataMergeError.invalidValue("世界观记录的内容或时间无效")
            }
        }

        for profile in payload.profiles where !worldIDs.contains(profile.worldProfileID) {
            throw DataMergeError.invalidReference(
                "角色 \(profile.id) 的 world_profile_id 不存在"
            )
        }

        try requireUnique(
            payload.groupConversations.map(\.conversationID),
            entity: .groupConversation,
            description: "群会话作用域重复"
        )
        try requireUnique(
            payload.groupParticipants.map(\.id),
            entity: .groupParticipant,
            description: "群成员 ID 重复"
        )
        try requireUnique(
            payload.chatTurnPresentations.map(\.id),
            entity: .chatTurnPresentation,
            description: "回复展示 ID 重复"
        )
        try requireUnique(
            payload.proactiveMessageTasks.map(\.id),
            entity: .proactiveMessageTask,
            description: "主动消息任务 ID 重复"
        )
        try requireUniqueKeys(payload.groupParticipants.map(participantKey), entity: .groupParticipant)
        try requireUniqueKeys(payload.chatTurnPresentations.map(presentationKey), entity: .chatTurnPresentation)
        try requireUniqueKeys(payload.proactiveMessageTasks.map(proactiveKey), entity: .proactiveMessageTask)
        try requireUnique(
            payload.friendApplications.map(\.id),
            entity: .friendApplication,
            description: "好友申请 ID 重复"
        )
        try requireUniqueKeys(
            payload.friendApplications.map(friendApplicationKey),
            entity: .friendApplication
        )

        for group in payload.groupConversations {
            guard conversationIDs.contains(group.conversationID),
                  GroupConversationLifecycle(rawValue: group.lifecycleRaw) != nil,
                  group.groupName.count <= maxGroupNameLength,
                  group.revision >= 0,
                  group.createdAt.timeIntervalSince1970.isFinite,
                  group.updatedAt.timeIntervalSince1970.isFinite,
                  group.updatedAt >= group.createdAt,
                  group.deviceID.count <= maxDeviceIDLength else {
                throw DataMergeError.invalidReference("群会话 (group.id) 的会话不存在或字段无效")
            }
        }

        for participant in payload.groupParticipants {
            guard let group = groupByConversation[participant.conversationID],
                  conversationIDs.contains(participant.conversationID),
                  participant.groupConversationID == participant.conversationID
                    || participant.groupConversationID == group.id,
                  GroupParticipantKind(rawValue: participant.participantKindRaw) != nil,
                  GroupConversationLifecycle(rawValue: participant.lifecycleRaw) != nil,
                  participant.displayName.count <= maxDisplayNameLength,
                  participant.revision >= 0,
                  participant.createdAt.timeIntervalSince1970.isFinite,
                  participant.updatedAt.timeIntervalSince1970.isFinite,
                  participant.updatedAt >= participant.createdAt,
                  participant.joinedAt.timeIntervalSince1970.isFinite,
                  participant.leftAt?.timeIntervalSince1970.isFinite ?? true,
                  participant.deviceID.count <= maxDeviceIDLength else {
                throw DataMergeError.invalidReference("群成员 (participant.id) 的群会话或字段无效")
            }
            if let roleID = participant.participantRoleID,
               !profileIDs.contains(RoleScope.resolve(roleID)) {
                throw DataMergeError.invalidReference("群成员 (participant.id) 的角色不存在")
            }
            if let leftAt = participant.leftAt, leftAt < participant.joinedAt {
                throw DataMergeError.invalidValue("群成员 (participant.id) 的离开时间早于加入时间")
            }
        }

        for event in payload.events {
            try validateEventPayload(event)
            if let senderRoleID = event.senderRoleID,
               !profileIDs.contains(RoleScope.resolve(senderRoleID)) {
                throw DataMergeError.invalidReference("事件 \(event.id) 的 sender_role_id 不存在")
            }
        }

        for presentation in payload.chatTurnPresentations {
            guard conversationIDs.contains(presentation.conversationID),
                  ChatTurnPresentationState(rawValue: presentation.stateRaw) != nil,
                  presentation.segments.count <= 1_000,
                  presentation.displayProgress.isFinite,
                  (0...1).contains(presentation.displayProgress),
                  presentation.displayedSegmentCount >= 0,
                  presentation.displayedSegmentCount <= presentation.segments.count,
                  presentation.failureMessage.count <= maxTextLength,
                  presentation.idempotencyKey.count <= maxIdempotencyKeyLength,
                  presentation.revision >= 0,
                  presentation.createdAt.timeIntervalSince1970.isFinite,
                  presentation.updatedAt.timeIntervalSince1970.isFinite,
                  presentation.updatedAt >= presentation.createdAt,
                  presentation.plannedAt?.timeIntervalSince1970.isFinite ?? true,
                  presentation.startedAt?.timeIntervalSince1970.isFinite ?? true,
                  presentation.completedAt?.timeIntervalSince1970.isFinite ?? true,
                  presentation.cancelledAt?.timeIntervalSince1970.isFinite ?? true,
                  presentation.deviceID.count <= maxDeviceIDLength else {
                throw DataMergeError.invalidValue("回复展示 (presentation.id) 的状态或时间无效")
            }
            if let roleID = presentation.roleID,
               !profileIDs.contains(RoleScope.resolve(roleID)) {
                throw DataMergeError.invalidReference("回复展示 (presentation.id) 的角色不存在")
            }
            if let replyEventID = presentation.logicalReplyEventID {
                guard let event = eventByID[replyEventID], event.conversationID == presentation.conversationID else {
                    throw DataMergeError.invalidReference("回复展示 (presentation.id) 的逻辑回复事件不存在")
                }
            }
        }

        for task in payload.proactiveMessageTasks {
            guard conversationIDs.contains(task.conversationID),
                  ProactiveMessageTaskState(rawValue: task.stateRaw) != nil,
                  task.scheduledAt.timeIntervalSince1970.isFinite,
                  task.createdAt.timeIntervalSince1970.isFinite,
                  task.updatedAt.timeIntervalSince1970.isFinite,
                  task.updatedAt >= task.createdAt,
                  task.followUpCount >= 0,
                  task.revision >= 0,
                  task.generatedText.count <= maxTextLength,
                  task.lastError.count <= maxTextLength,
                  task.idempotencyKey.count <= maxIdempotencyKeyLength,
                  task.silentDeferredUntil?.timeIntervalSince1970.isFinite ?? true,
                  task.leaseExpiresAt?.timeIntervalSince1970.isFinite ?? true,
                  task.scheduledFromUserAt?.timeIntervalSince1970.isFinite ?? true,
                  task.deviceID.count <= maxDeviceIDLength else {
                throw DataMergeError.invalidValue("主动消息任务 (task.id) 的状态或时间无效")
            }
            if let roleID = task.roleID,
               !profileIDs.contains(RoleScope.resolve(roleID)) {
                throw DataMergeError.invalidReference("主动消息任务 (task.id) 的角色不存在")
            }
            if let userEventID = task.lastUserEventID {
                guard let event = eventByID[userEventID], event.conversationID == task.conversationID else {
                    throw DataMergeError.invalidReference("主动消息任务 (task.id) 的用户基准事件不存在")
                }
            }
        }

        for application in payload.friendApplications {
            guard profileIDs.contains(RoleScope.resolve(application.roleID)),
                  FriendApplicationDirection(rawValue: application.directionRaw) != nil,
                  FriendApplicationPurpose(rawValue: application.purposeRaw) != nil,
                  FriendApplicationStatus(rawValue: application.statusRaw) != nil,
                  application.message.count <= maxTextLength,
                  application.idempotencyKey.count <= maxIdempotencyKeyLength,
                  !application.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  application.scheduledAt.timeIntervalSince1970.isFinite,
                  application.createdAt.timeIntervalSince1970.isFinite,
                  application.resolvedAt?.timeIntervalSince1970.isFinite ?? true,
                  application.createdAt <= application.scheduledAt,
                  application.revision >= 0,
                  application.deviceID.count <= maxDeviceIDLength else {
                throw DataMergeError.invalidValue("好友申请的角色、状态、内容或时间无效")
            }
            if let resolvedAt = application.resolvedAt {
                guard resolvedAt >= application.createdAt else {
                    throw DataMergeError.invalidValue("好友申请的解决时间早于创建时间")
                }
            }
            if application.status == .scheduled {
                guard application.scheduledAt >= application.createdAt else {
                    throw DataMergeError.invalidValue("已排期好友申请的时间无效")
                }
            }
            if application.status.isTerminal {
                guard application.resolvedAt != nil else {
                    throw DataMergeError.invalidValue("已结束好友申请缺少解决时间")
                }
            }
        }
    }

    /// Validates the payload-specific portion of one exported event. Keeping
    /// this check standalone lets merge finalization and duplicate cleanup
    /// enforce the same invariant for destination rows as import does.
    static func validateEventPayload(_ event: AyaneEventExport) throws {
        guard MessagePayloadKind(rawValue: event.payloadKindRaw) != nil,
              MessagePayloadKind(rawValue: event.payloadKind) != nil,
              event.payloadKindRaw == event.payloadKind,
              event.stickerID.count <= maxTextLength,
              (event.imageData?.count ?? 0) <= maxImageDataBytes,
              event.fileName.count <= maxFileNameLength,
              event.fileTypeIdentifier.count <= maxFileTypeIdentifierLength,
              (event.fileData?.count ?? 0) <= maxFileDataBytes else {
            throw DataMergeError.invalidValue("事件 \(event.id) 的消息 payload 无效")
        }
        if event.payloadKindRaw == MessagePayloadKind.sticker.rawValue {
            guard !event.stickerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DataMergeError.invalidValue("贴纸事件 \(event.id) 缺少 sticker_id")
            }
        }
        if event.payloadKindRaw == MessagePayloadKind.image.rawValue {
            guard let imageData = event.imageData, !imageData.isEmpty else {
                throw DataMergeError.invalidValue("图片事件 \(event.id) 缺少 image_data")
            }
        } else if event.imageData != nil {
            throw DataMergeError.invalidValue("非图片事件 \(event.id) 不应带 image_data")
        }
        if event.payloadKindRaw == MessagePayloadKind.file.rawValue {
            guard !event.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !event.fileTypeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let fileData = event.fileData,
                  !fileData.isEmpty else {
                throw DataMergeError.invalidValue("文件事件 \(event.id) 缺少文件名、类型或字节")
            }
        } else if !event.fileName.isEmpty || !event.fileTypeIdentifier.isEmpty || event.fileData != nil {
            throw DataMergeError.invalidValue("非文件事件 \(event.id) 不应带文件字段或字节")
        }
    }

    private static func requireUnique(
        _ values: [UUID],
        entity: DataMergeEntity,
        description: String
    ) throws {
        guard Set(values).count == values.count else {
            throw DataMergeError.duplicateSourceIDs(entity: entity)
        }
        _ = description
    }

    private static func requireUniqueKeys(
        _ values: [String],
        entity: DataMergeEntity
    ) throws {
        guard Set(values).count == values.count else {
            throw DataMergeError.duplicateSourceIDs(entity: entity)
        }
    }

    // MARK: Record conversion

    static func makeWorldProfile(_ item: AyaneWorldProfileExport) -> WorldProfileRecord {
        WorldProfileRecord(
            id: item.id,
            displayName: item.displayName,
            worldKindRaw: item.worldKind,
            timezoneIdentifier: item.timezoneIdentifier,
            locationContext: item.locationContext,
            commonFactsRaw: encodeStrings(item.commonFacts),
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    static func makeGroupConversation(_ item: AyaneGroupConversationExport) -> GroupConversationRecord {
        GroupConversationRecord(
            id: item.id,
            conversationID: item.conversationID,
            groupName: item.groupName,
            avatarImageData: item.avatarImageData,
            lifecycleRaw: item.lifecycleRaw,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    static func makeGroupParticipant(_ item: AyaneGroupParticipantExport) -> GroupParticipantRecord {
        GroupParticipantRecord(
            id: item.id,
            conversationID: item.conversationID,
            groupConversationID: item.groupConversationID,
            participantRoleID: item.participantRoleID.map(RoleScope.resolve),
            participantKindRaw: item.participantKindRaw,
            displayName: item.displayName,
            avatarImageData: item.avatarImageData,
            joinedAt: item.joinedAt,
            leftAt: item.leftAt,
            lifecycleRaw: item.lifecycleRaw,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    static func makeChatTurnPresentation(_ item: AyaneChatTurnPresentationExport) -> ChatTurnPresentationRecord {
        ChatTurnPresentationRecord(
            id: item.id,
            conversationID: item.conversationID,
            roleID: item.roleID.map(RoleScope.resolve),
            logicalReplyEventID: item.logicalReplyEventID,
            segments: item.segments,
            displayProgress: item.displayProgress,
            displayedSegmentCount: item.displayedSegmentCount,
            state: item.state,
            plannedAt: item.plannedAt,
            startedAt: item.startedAt,
            completedAt: item.completedAt,
            cancelledAt: item.cancelledAt,
            failureMessage: item.failureMessage,
            idempotencyKey: item.idempotencyKey,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    static func makeProactiveMessageTask(_ item: AyaneProactiveMessageTaskExport) -> ProactiveMessageTaskRecord {
        ProactiveMessageTaskRecord(
            id: item.id,
            roleID: item.roleID.map(RoleScope.resolve),
            conversationID: item.conversationID,
            scheduledAt: item.scheduledAt,
            followUpCount: item.followUpCount,
            stateRaw: item.stateRaw,
            silentDeferredUntil: item.silentDeferredUntil,
            leaseOwner: item.leaseOwner,
            leaseExpiresAt: item.leaseExpiresAt,
            idempotencyKey: item.idempotencyKey,
            lastError: item.lastError,
            generatedText: item.generatedText,
            lastUserEventID: item.lastUserEventID,
            scheduledFromUserAt: item.scheduledFromUserAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    static func makeFriendApplication(_ item: AyaneFriendApplicationExport) -> FriendApplicationRecord {
        FriendApplicationRecord(
            id: item.id,
            roleID: RoleScope.resolve(item.roleID),
            directionRaw: item.directionRaw,
            purposeRaw: item.purposeRaw,
            statusRaw: item.statusRaw,
            message: item.message,
            scheduledAt: item.scheduledAt,
            createdAt: item.createdAt,
            resolvedAt: item.resolvedAt,
            idempotencyKey: item.idempotencyKey,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    // MARK: Context merge

    @MainActor
    static func merge(_ payload: AyaneDataExport, into context: ModelContext) throws -> MergeReport {
        try validate(payload)
        var result = MergeReport()

        let existingWorld = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        let incomingWorlds = canonicalWorldProfiles(
            payload.worldProfiles.isEmpty ? [payload.worldProfile] : payload.worldProfiles
        )
        let existingByID = Dictionary(grouping: existingWorld, by: \.id)
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for incoming in incomingWorlds {
            if let current = existingByID[incoming.id]?.max(by: {
                isOlder(AyaneWorldProfileExport($0), than: AyaneWorldProfileExport($1))
            }) {
                if isOlder(AyaneWorldProfileExport(current), than: incoming) {
                    apply(incoming, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                context.insert(makeWorldProfile(incoming))
                inserted += 1
            }
        }
        result.worldProfile = .init(inserted: inserted, updated: updated, unchanged: unchanged)

        result.groupConversations = mergeGroupConversations(payload.groupConversations, context: context)
        result.groupParticipants = mergeGroupParticipants(payload.groupParticipants, context: context)
        result.chatTurnPresentations = mergePresentations(payload.chatTurnPresentations, context: context)
        result.proactiveMessageTasks = mergeTasks(payload.proactiveMessageTasks, context: context)
        result.friendApplications = mergeFriendApplications(payload.friendApplications, context: context)
        return result
    }

    @MainActor
    private static func mergeFriendApplications(
        _ incoming: [AyaneFriendApplicationExport],
        context: ModelContext
    ) -> DataMergeEntityReport {
        let existing = (try? context.fetch(FetchDescriptor<FriendApplicationRecord>())) ?? []
        var byKey = Dictionary(grouping: existing, by: friendApplicationKey)
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for item in incoming {
            let key = friendApplicationKey(item)
            if let current = byKey[key]?.max(by: { isOlder(AyaneFriendApplicationExport($0), than: AyaneFriendApplicationExport($1)) }) {
                if isOlder(AyaneFriendApplicationExport(current), than: item) {
                    apply(item, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let record = makeFriendApplication(item)
                context.insert(record)
                byKey[key, default: []].append(record)
                inserted += 1
            }
        }
        return .init(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    @MainActor
    private static func mergeGroupConversations(
        _ incoming: [AyaneGroupConversationExport],
        context: ModelContext
    ) -> DataMergeEntityReport {
        let existing = (try? context.fetch(FetchDescriptor<GroupConversationRecord>())) ?? []
        var byKey = Dictionary(grouping: existing, by: { $0.conversationID.uuidString.lowercased() })
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for item in incoming {
            let key = item.conversationID.uuidString.lowercased()
            if let current = byKey[key]?.max(by: { isOlder(AyaneGroupConversationExport($0), than: AyaneGroupConversationExport($1)) }) {
                if isOlder(AyaneGroupConversationExport(current), than: item) {
                    apply(item, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let record = makeGroupConversation(item)
                context.insert(record)
                byKey[key, default: []].append(record)
                inserted += 1
            }
        }
        return .init(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    @MainActor
    private static func mergeGroupParticipants(
        _ incoming: [AyaneGroupParticipantExport],
        context: ModelContext
    ) -> DataMergeEntityReport {
        let existing = (try? context.fetch(FetchDescriptor<GroupParticipantRecord>())) ?? []
        var byKey = Dictionary(grouping: existing, by: participantKey)
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for item in incoming {
            let key = participantKey(item)
            if let current = byKey[key]?.max(by: { isOlder(AyaneGroupParticipantExport($0), than: AyaneGroupParticipantExport($1)) }) {
                if isOlder(AyaneGroupParticipantExport(current), than: item) {
                    apply(item, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let record = makeGroupParticipant(item)
                context.insert(record)
                byKey[key, default: []].append(record)
                inserted += 1
            }
        }
        return .init(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    @MainActor
    private static func mergePresentations(
        _ incoming: [AyaneChatTurnPresentationExport],
        context: ModelContext
    ) -> DataMergeEntityReport {
        let existing = (try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())) ?? []
        var byKey = Dictionary(grouping: existing, by: presentationKey)
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for item in incoming {
            let key = presentationKey(item)
            if let current = byKey[key]?.max(by: { isOlder(AyaneChatTurnPresentationExport($0), than: AyaneChatTurnPresentationExport($1)) }) {
                if isOlder(AyaneChatTurnPresentationExport(current), than: item) {
                    apply(item, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let record = makeChatTurnPresentation(item)
                context.insert(record)
                byKey[key, default: []].append(record)
                inserted += 1
            }
        }
        return .init(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    @MainActor
    private static func mergeTasks(
        _ incoming: [AyaneProactiveMessageTaskExport],
        context: ModelContext
    ) -> DataMergeEntityReport {
        let existing = (try? context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())) ?? []
        var byKey = Dictionary(grouping: existing, by: proactiveKey)
        var inserted = 0
        var updated = 0
        var unchanged = 0
        for item in incoming {
            let key = proactiveKey(item)
            if let current = byKey[key]?.max(by: { isOlder(AyaneProactiveMessageTaskExport($0), than: AyaneProactiveMessageTaskExport($1)) }) {
                if isOlder(AyaneProactiveMessageTaskExport(current), than: item) {
                    apply(item, to: current)
                    updated += 1
                } else {
                    unchanged += 1
                }
            } else {
                let record = makeProactiveMessageTask(item)
                context.insert(record)
                byKey[key, default: []].append(record)
                inserted += 1
            }
        }
        return .init(inserted: inserted, updated: updated, unchanged: unchanged)
    }

    // MARK: Duplicate reconciliation

    @MainActor
    static func duplicateSummary(context: ModelContext) -> DuplicateSummary {
        var summary = DuplicateSummary()
        if let rows = try? context.fetch(FetchDescriptor<WorldProfileRecord>()) {
            summary.worldProfiles = duplicateCount(rows.map { $0.id.uuidString.lowercased() })
        }
        if let rows = try? context.fetch(FetchDescriptor<GroupConversationRecord>()) {
            summary.groupConversations = duplicateCount(rows.map { $0.conversationID.uuidString.lowercased() })
        }
        if let rows = try? context.fetch(FetchDescriptor<GroupParticipantRecord>()) {
            summary.groupParticipants = duplicateCount(rows.map(participantKey))
        }
        if let rows = try? context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()) {
            summary.chatTurnPresentations = duplicateCount(rows.map(presentationKey))
        }
        if let rows = try? context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()) {
            summary.proactiveMessageTasks = duplicateCount(rows.map(proactiveKey))
        }
        if let rows = try? context.fetch(FetchDescriptor<FriendApplicationRecord>()) {
            summary.friendApplications = duplicateCount(rows.map(friendApplicationKey))
        }
        return summary
    }

    @MainActor
    static func reconcileDuplicates(
        context: ModelContext,
        save: Bool = true
    ) throws -> DuplicateSummary {
        let before = duplicateSummary(context: context)
        try reconcileWorld(context: context)
        try reconcileGroups(context: context)
        try reconcileParticipants(context: context)
        try reconcilePresentations(context: context)
        try reconcileTasks(context: context)
        try reconcileFriendApplications(context: context)
        if save, before.total > 0 { try context.save() }
        return before
    }

    private static func duplicateCount(_ keys: [String]) -> Int {
        keys.count - Set(keys).count
    }

    @MainActor
    private static func reconcileWorld(context: ModelContext) throws {
        let rows = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        var winners: [UUID: WorldProfileRecord] = [:]
        for row in rows {
            if let current = winners[row.id] {
                if isOlder(AyaneWorldProfileExport(current), than: AyaneWorldProfileExport(row)) {
                    winners[row.id] = row
                    context.delete(current)
                } else {
                    context.delete(row)
                }
            } else {
                winners[row.id] = row
            }
        }
    }

    @MainActor
    private static func reconcileGroups(context: ModelContext) throws {
        try reconcile(
            try context.fetch(FetchDescriptor<GroupConversationRecord>()),
            key: { $0.conversationID.uuidString.lowercased() },
            value: AyaneGroupConversationExport.init,
            delete: context.delete
        )
    }

    @MainActor
    private static func reconcileParticipants(context: ModelContext) throws {
        try reconcile(
            try context.fetch(FetchDescriptor<GroupParticipantRecord>()),
            key: participantKey,
            value: AyaneGroupParticipantExport.init,
            delete: context.delete
        )
    }

    @MainActor
    private static func reconcilePresentations(context: ModelContext) throws {
        try reconcile(
            try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()),
            key: presentationKey,
            value: AyaneChatTurnPresentationExport.init,
            delete: context.delete
        )
    }

    @MainActor
    private static func reconcileTasks(context: ModelContext) throws {
        try reconcile(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()),
            key: proactiveKey,
            value: AyaneProactiveMessageTaskExport.init,
            delete: context.delete
        )
    }

    @MainActor
    private static func reconcileFriendApplications(context: ModelContext) throws {
        try reconcile(
            try context.fetch(FetchDescriptor<FriendApplicationRecord>()),
            key: friendApplicationKey,
            value: AyaneFriendApplicationExport.init,
            delete: context.delete
        )
    }

    private static func reconcile<Record, Value>(
        _ rows: [Record],
        key: (Record) -> String,
        value: (Record) -> Value,
        delete: (Record) -> Void
    ) throws where Record: AnyObject {
        var winners: [String: Record] = [:]
        for row in rows {
            let rowKey = key(row)
            if let current = winners[rowKey] {
                if isOlder(value(current), than: value(row)) { winners[rowKey] = row; delete(current) }
                else { delete(row) }
            } else { winners[rowKey] = row }
        }
    }

    // MARK: Keys, ordering, and mutation

    private static func participantKey(_ item: AyaneGroupParticipantExport) -> String {
        let identity = item.participantRoleID?.uuidString.lowercased() ?? item.id.uuidString.lowercased()
        return "\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func participantKey(_ item: GroupParticipantRecord) -> String {
        let identity = item.participantRoleID?.uuidString.lowercased() ?? item.id.uuidString.lowercased()
        return "\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func presentationKey(_ item: AyaneChatTurnPresentationExport) -> String {
        let identity = item.logicalReplyEventID?.uuidString.lowercased()
            ?? (item.idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : item.idempotencyKey)
        return "\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func presentationKey(_ item: ChatTurnPresentationRecord) -> String {
        let identity = item.logicalReplyEventID?.uuidString.lowercased()
            ?? (item.idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : item.idempotencyKey)
        return "\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func proactiveKey(_ item: AyaneProactiveMessageTaskExport) -> String {
        let role = RoleScope.resolve(item.roleID).uuidString.lowercased()
        let identity = item.idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : item.idempotencyKey
        return "\(role):\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func proactiveKey(_ item: ProactiveMessageTaskRecord) -> String {
        let role = RoleScope.resolve(item.roleID).uuidString.lowercased()
        let identity = item.idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : item.idempotencyKey
        return "\(role):\(item.conversationID.uuidString.lowercased()):\(identity)"
    }

    private static func friendApplicationKey(_ item: AyaneFriendApplicationExport) -> String {
        let role = RoleScope.resolve(item.roleID).uuidString.lowercased()
        let idempotencyKey = item.idempotencyKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let identity = idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : idempotencyKey
        return "\(role):\(item.directionRaw.lowercased()):\(item.purposeRaw.lowercased()):\(identity)"
    }

    private static func friendApplicationKey(_ item: FriendApplicationRecord) -> String {
        let role = RoleScope.resolve(item.roleID).uuidString.lowercased()
        let idempotencyKey = item.idempotencyKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let identity = idempotencyKey.isEmpty ? item.id.uuidString.lowercased() : idempotencyKey
        return "\(role):\(item.directionRaw.lowercased()):\(item.purposeRaw.lowercased()):\(identity)"
    }

    private static func isOlder<Value>(_ lhs: Value, than rhs: Value) -> Bool {
        func metadata(_ value: Value) -> (Int, Date, String, String) {
            switch value {
            case let value as AyaneWorldProfileExport:
                return (value.revision, value.updatedAt, value.deviceID, worldFingerprint(value))
            case let value as AyaneGroupConversationExport:
                return (value.revision, value.updatedAt, value.deviceID, groupFingerprint(value))
            case let value as AyaneGroupParticipantExport:
                return (value.revision, value.updatedAt, value.deviceID, participantFingerprint(value))
            case let value as AyaneChatTurnPresentationExport:
                return (value.revision, value.updatedAt, value.deviceID, presentationFingerprint(value))
            case let value as AyaneProactiveMessageTaskExport:
                return (value.revision, value.updatedAt, value.deviceID, taskFingerprint(value))
            case let value as AyaneFriendApplicationExport:
                return (value.revision, value.createdAt, value.deviceID, friendApplicationFingerprint(value))
            case let value as WorldProfileRecord:
                return (value.revision, value.updatedAt, value.deviceID, worldFingerprint(AyaneWorldProfileExport(value)))
            case let value as GroupConversationRecord:
                return (value.revision, value.updatedAt, value.deviceID, groupFingerprint(AyaneGroupConversationExport(value)))
            case let value as GroupParticipantRecord:
                return (value.revision, value.updatedAt, value.deviceID, participantFingerprint(AyaneGroupParticipantExport(value)))
            case let value as ChatTurnPresentationRecord:
                return (value.revision, value.updatedAt, value.deviceID, presentationFingerprint(AyaneChatTurnPresentationExport(value)))
            case let value as ProactiveMessageTaskRecord:
                return (value.revision, value.updatedAt, value.deviceID, taskFingerprint(AyaneProactiveMessageTaskExport(value)))
            case let value as FriendApplicationRecord:
                return (value.revision, value.createdAt, value.deviceID, friendApplicationFingerprint(AyaneFriendApplicationExport(value)))
            default:
                return (0, .distantPast, "", "")
            }
        }
        let left = metadata(lhs)
        let right = metadata(rhs)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        if left.2 != right.2 { return left.2 < right.2 }
        return left.3 < right.3
    }

    private static func worldFingerprint(_ value: AyaneWorldProfileExport) -> String {
        [value.displayName, value.worldKind, value.timezoneIdentifier, value.locationContext, value.commonFacts.joined(separator: "\u{001F}")].joined(separator: "\u{001E}")
    }

    private static func groupFingerprint(_ value: AyaneGroupConversationExport) -> String {
        [value.groupName, value.lifecycleRaw, value.avatarImageData?.base64EncodedString() ?? ""].joined(separator: "\u{001F}")
    }

    private static func participantFingerprint(_ value: AyaneGroupParticipantExport) -> String {
        [value.displayName, value.participantKindRaw, value.lifecycleRaw, value.avatarImageData?.base64EncodedString() ?? "", value.joinedAt.description, value.leftAt?.description ?? ""].joined(separator: "\u{001F}")
    }

    private static func presentationFingerprint(_ value: AyaneChatTurnPresentationExport) -> String {
        [value.segments.joined(separator: "\u{001F}"), String(value.displayProgress), String(value.displayedSegmentCount), value.stateRaw, value.failureMessage, value.idempotencyKey].joined(separator: "\u{001F}")
    }

    private static func taskFingerprint(_ value: AyaneProactiveMessageTaskExport) -> String {
        [value.stateRaw, value.generatedText, String(value.followUpCount), value.idempotencyKey, value.lastError, value.leaseOwner].joined(separator: "\u{001F}")
    }

    private static func friendApplicationFingerprint(_ value: AyaneFriendApplicationExport) -> String {
        [
            value.id.uuidString.lowercased(),
            value.roleID.uuidString.lowercased(),
            value.directionRaw,
            value.purposeRaw,
            value.statusRaw,
            value.message,
            value.scheduledAt.description,
            value.createdAt.description,
            value.resolvedAt?.description ?? "",
            value.idempotencyKey,
            String(value.revision),
            value.deviceID
        ].joined(separator: "\u{001F}")
    }

    private static func encodeStrings(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private static func apply(_ item: AyaneWorldProfileExport, to record: WorldProfileRecord) {
        record.id = item.id
        record.displayName = item.displayName
        record.worldKindRaw = item.worldKind
        record.timezoneIdentifier = item.timezoneIdentifier
        record.locationContext = item.locationContext
        record.commonFacts = item.commonFacts
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneGroupConversationExport, to record: GroupConversationRecord) {
        record.id = item.id
        record.conversationID = item.conversationID
        record.groupName = item.groupName
        record.avatarImageData = item.avatarImageData
        record.lifecycleRaw = item.lifecycleRaw
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneGroupParticipantExport, to record: GroupParticipantRecord) {
        record.id = item.id
        record.conversationID = item.conversationID
        record.groupConversationID = item.groupConversationID
        record.participantRoleID = item.participantRoleID.map(RoleScope.resolve)
        record.participantKindRaw = item.participantKindRaw
        record.displayName = item.displayName
        record.avatarImageData = item.avatarImageData
        record.joinedAt = item.joinedAt
        record.leftAt = item.leftAt
        record.lifecycleRaw = item.lifecycleRaw
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneChatTurnPresentationExport, to record: ChatTurnPresentationRecord) {
        record.id = item.id
        record.conversationID = item.conversationID
        record.roleID = item.roleID.map(RoleScope.resolve)
        record.logicalReplyEventID = item.logicalReplyEventID
        record.segments = item.segments
        record.displayProgress = item.displayProgress
        record.displayedSegmentCount = item.displayedSegmentCount
        record.stateRaw = item.stateRaw
        record.plannedAt = item.plannedAt
        record.startedAt = item.startedAt
        record.completedAt = item.completedAt
        record.cancelledAt = item.cancelledAt
        record.failureMessage = item.failureMessage
        record.idempotencyKey = item.idempotencyKey
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneProactiveMessageTaskExport, to record: ProactiveMessageTaskRecord) {
        record.id = item.id
        record.roleID = item.roleID.map(RoleScope.resolve)
        record.conversationID = item.conversationID
        record.scheduledAt = item.scheduledAt
        record.followUpCount = item.followUpCount
        record.stateRaw = item.stateRaw
        record.silentDeferredUntil = item.silentDeferredUntil
        record.leaseOwner = item.leaseOwner
        record.leaseExpiresAt = item.leaseExpiresAt
        record.idempotencyKey = item.idempotencyKey
        record.lastError = item.lastError
        record.generatedText = item.generatedText
        record.lastUserEventID = item.lastUserEventID
        record.scheduledFromUserAt = item.scheduledFromUserAt
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneFriendApplicationExport, to record: FriendApplicationRecord) {
        record.id = item.id
        record.roleID = RoleScope.resolve(item.roleID)
        record.directionRaw = item.directionRaw
        record.purposeRaw = item.purposeRaw
        record.statusRaw = item.statusRaw
        record.message = item.message
        record.scheduledAt = item.scheduledAt
        record.createdAt = item.createdAt
        record.resolvedAt = item.resolvedAt
        record.idempotencyKey = item.idempotencyKey
        record.revision = item.revision
        record.deviceID = item.deviceID
    }
}

/// v12 keeps the established v11 helper name for source compatibility while
/// exposing an explicit schema-version spelling to new callers.
typealias SchemaV12DataSupport = SchemaV11DataSupport
