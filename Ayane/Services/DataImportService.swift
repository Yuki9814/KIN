import Foundation
import SwiftData

/// The group metadata is stored beside (rather than through a SwiftData
/// relationship with) the ordinary conversation/event rows.  Import and merge
/// therefore need the same small, value-only view when checking role-owned
/// references.  A group conversation keeps the ordinary conversation role as
/// its compatibility/owner scope (normally the legacy role), while assistant
/// rows are owned by their actual speaking companion.
struct GroupBackupValidationIndex {
    let groupConversationIDs: Set<UUID>
    let activeCompanionRoleIDsByConversation: [UUID: Set<UUID>]

    init(_ payload: AyaneDataExport) {
        self.init(
            groupConversations: payload.groupConversations,
            groupParticipants: payload.groupParticipants
        )
    }

    init(
        groupConversations: [AyaneGroupConversationExport],
        groupParticipants: [AyaneGroupParticipantExport]
    ) {
        groupConversationIDs = Set(groupConversations.map(\.conversationID))
        let grouped = Dictionary(grouping: groupParticipants, by: \.conversationID)
        activeCompanionRoleIDsByConversation = grouped.mapValues { participants in
            Set(participants.compactMap { participant in
                guard participant.participantKind == .companion,
                      GroupConversationLifecycle(rawValue: participant.lifecycleRaw) == .active,
                      participant.leftAt == nil,
                      let roleID = participant.participantRoleID else {
                    return nil
                }
                return RoleScope.resolve(roleID)
            })
        }
    }

    func isGroupConversation(_ conversationID: UUID) -> Bool {
        groupConversationIDs.contains(conversationID)
    }

    func isActiveCompanion(_ roleID: UUID, in conversationID: UUID) -> Bool {
        activeCompanionRoleIDsByConversation[conversationID]?.contains(
            RoleScope.resolve(roleID)
        ) ?? false
    }

    /// Checks the event's persisted identity against its conversation.  In a
    /// group, user/system/manual rows retain the conversation owner scope,
    /// while assistant rows carry the actual sender role in both role fields.
    func eventMatchesConversation(
        _ event: AyaneEventExport,
        conversation: AyaneConversationExport
    ) -> Bool {
        let eventRoleID = RoleScope.resolve(event.roleID)
        let conversationRoleID = RoleScope.resolve(conversation.roleID)
        guard isGroupConversation(conversation.id) else {
            return eventRoleID == conversationRoleID
        }

        guard let eventRole = EventRole(rawValue: event.roleRaw) else { return false }
        switch eventRole {
        case .assistant:
            guard let senderRoleID = event.senderRoleID.map(RoleScope.resolve) else {
                return false
            }
            return eventRoleID == senderRoleID
                && isActiveCompanion(senderRoleID, in: conversation.id)
        case .user, .system, .manual:
            return eventRoleID == conversationRoleID && event.senderRoleID == nil
        }
    }

    /// Checks whether an event may be used by a role-owned relation (memory
    /// evidence, summaries, relationship cursors, and tombstones).  A group
    /// user/system/manual event belongs to the shared conversation scope and
    /// may therefore support a memory owned by any active companion; assistant
    /// events belong only to their matching sender.
    func eventMatchesRole(
        _ event: AyaneEventExport,
        roleID: UUID,
        conversation: AyaneConversationExport
    ) -> Bool {
        guard event.conversationID == conversation.id,
              eventMatchesConversation(event, conversation: conversation) else {
            return false
        }
        guard isGroupConversation(conversation.id) else {
            return RoleScope.resolve(event.roleID) == RoleScope.resolve(roleID)
        }
        guard let eventRole = EventRole(rawValue: event.roleRaw) else { return false }
        if eventRole == .assistant {
            return RoleScope.resolve(event.roleID) == RoleScope.resolve(roleID)
                && event.senderRoleID.map(RoleScope.resolve) == Optional(RoleScope.resolve(roleID))
        }
        return RoleScope.resolve(event.roleID) == RoleScope.resolve(conversation.roleID)
    }
}

struct DataImportSummary: Equatable, Sendable {
    let exportedAt: Date
    let profiles: Int
    let conversations: Int
    let events: Int
    let memories: Int
    let evidence: Int
    let summaries: Int
    let tombstones: Int
    let relationships: Int
    let transitions: Int
    let momentTasks: Int
    let momentAIInteractionTasks: Int
    let userProfiles: Int
    let momentPosts: Int
    let momentInteractions: Int
    let conversationReadStates: Int
    let momentReadStates: Int
    let worldProfiles: Int
    let groupConversations: Int
    let groupParticipants: Int
    let chatTurnPresentations: Int
    let proactiveMessageTasks: Int
    let friendApplications: Int

    /// Backward-compatible count used by the existing restore UI. Relationship
    /// audit rows have their own explicit counts and are also available via
    /// `totalIncludingRelationships`.
    var totalRecords: Int {
        profiles + conversations + events + memories + evidence + summaries + tombstones
            + momentTasks + userProfiles + momentPosts + momentInteractions
            + momentAIInteractionTasks
            + conversationReadStates + momentReadStates
    }

    var totalIncludingSchemaV11: Int {
        totalRecords + worldProfiles + groupConversations + groupParticipants
            + chatTurnPresentations + proactiveMessageTasks + friendApplications
    }

    var totalIncludingRelationships: Int {
        totalRecords + relationships + transitions
    }
}

enum DataImportError: LocalizedError, Equatable {
    case invalidDocument
    case unsupportedSchema(Int)
    case duplicateRecord(String)
    case invalidReference(String)
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "这不是可读取的 KIN JSON 备份。"
        case .unsupportedSchema(let version):
            "备份格式版本 \(version) 与当前应用不兼容。"
        case .duplicateRecord(let description):
            "备份包含重复记录：\(description)。"
        case .invalidReference(let description):
            "备份中的关联不完整：\(description)。"
        case .invalidValue(let description):
            "备份中的数据未通过完整性校验：\(description)。"
        }
    }
}

/// Validates and restores a complete Ayane export without ever reading or
/// writing the API key. Validation finishes before the ModelContext is mutated.
struct DataImportService {
    // Keep validation usable from nonisolated inspection and merge callers;
    // these values mirror CompanionProfileService's canonical limits.
    private static let profileNameMaximumLength = 80
    private static let profileUserNameMaximumLength = 80
    private static let profilePromptMaximumLength = 32_000
    private static let userProfileDisplayNameMaximumLength = 40
    private static let userProfileDeviceIDMaximumLength = 256
    private static let momentPostBodyMaximumLength = 4_000
    private static let momentBundledImageNameMaximumLength = 256
    private static let momentInteractionBodyMaximumLength = 500

    static func inspect(_ data: Data) throws -> DataImportSummary {
        let decoded = try decode(data)
        try requireSupportedSchema(decoded.schemaVersion)
        let payload = normalizedPayload(decoded)
        try validateNormalized(payload)
        return summary(for: payload)
    }

    @discardableResult
    @MainActor
    static func replaceAll(
        with data: Data,
        context: ModelContext,
        defaults: UserDefaults = .standard
    ) throws -> DataImportSummary {
        let decoded = try decode(data)
        try requireSupportedSchema(decoded.schemaVersion)
        let payload = normalizedPayload(decoded)
        try validateNormalized(payload)

        let conversations = payload.conversations.map(makeConversation)
        let events = payload.events.map(makeEvent)
        let memories = try payload.memories.map(makeMemory)
        let evidence = payload.evidence.map(makeEvidence)
        let summaries = payload.summaries.map(makeSummary)
        let tombstones = payload.tombstones.map(makeTombstone)
        let profiles = try payload.profiles.map { makeProfile(try normalizedPersona(from: $0)) }
        let relationships = try payload.relationships.map(makeRelationship)
        let transitions = try payload.transitions.map(makeTransition)
        let momentTasks = try payload.momentTasks.map(makeMomentTask)
        let momentAIInteractionTasks = try payload.momentAIInteractionTasks.map(makeMomentAIInteractionTask)
        let userProfile = payload.userProfile.map(makeUserProfile)
        let momentPosts = try payload.momentPosts.map(makeMomentPost)
        let momentInteractions = try payload.momentInteractions.map(makeMomentInteraction)
        let conversationReadStates = try payload.conversationReadStates.map(makeConversationReadState)
        let momentReadStates = try payload.momentReadStates.map(makeMomentReadState)
        let worldProfiles = payload.worldProfiles.map(SchemaV11DataSupport.makeWorldProfile)
        let groupConversations = payload.groupConversations.map(SchemaV11DataSupport.makeGroupConversation)
        let groupParticipants = payload.groupParticipants.map(SchemaV11DataSupport.makeGroupParticipant)
        let chatTurnPresentations = payload.chatTurnPresentations.map(SchemaV11DataSupport.makeChatTurnPresentation)
        let proactiveMessageTasks = payload.proactiveMessageTasks.map(SchemaV11DataSupport.makeProactiveMessageTask)
        let friendApplications = payload.friendApplications.map(SchemaV11DataSupport.makeFriendApplication)

        do {
            for record in try context.fetch(FetchDescriptor<CompanionRelationshipTransitionRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<CompanionProfileRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MomentInteractionRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ConversationReadStateRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MomentReadStateRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<WorldProfileRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<GroupConversationRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<GroupParticipantRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<FriendApplicationRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MomentPostRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<UserProfileRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ConversationEvent>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ConversationRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryAssertionRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemorySummaryRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()) {
                context.delete(record)
            }

            for profile in profiles { context.insert(profile) }
            for record in relationships { context.insert(record) }
            for record in transitions { context.insert(record) }
            for record in momentTasks { context.insert(record) }
            for record in momentAIInteractionTasks { context.insert(record) }
            if let userProfile { context.insert(userProfile) }
            for record in momentPosts { context.insert(record) }
            for record in momentInteractions { context.insert(record) }
            for record in conversationReadStates { context.insert(record) }
            for record in momentReadStates { context.insert(record) }
            for record in worldProfiles { context.insert(record) }
            for record in groupConversations { context.insert(record) }
            for record in groupParticipants { context.insert(record) }
            for record in chatTurnPresentations { context.insert(record) }
            for record in proactiveMessageTasks { context.insert(record) }
            for record in friendApplications { context.insert(record) }
            for record in conversations { context.insert(record) }
            for record in events { context.insert(record) }
            for record in memories { context.insert(record) }
            for record in evidence { context.insert(record) }
            for record in summaries { context.insert(record) }
            for record in tombstones { context.insert(record) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        restoreNonSecretSettings(payload, defaults: defaults)
        // Legacy payloads have no read markers, so AppModel must establish a
        // one-time baseline after replacement. A v10 payload is authoritative:
        // an empty marker collection intentionally means all qualifying source
        // records are unread and must not be silently baselined.
        if payload.schemaVersion < AyaneDataExport.readStateSchemaVersion {
            defaults.removeObject(forKey: SettingsKeys.readStateStorageMigrationVersion)
        } else {
            defaults.set(
                SettingsStore.readStateStorageMigrationVersion,
                forKey: SettingsKeys.readStateStorageMigrationVersion
            )
        }
        return summary(for: payload)
    }

    private static func decode(_ data: Data) throws -> AyaneDataExport {
        guard !data.isEmpty else { throw DataImportError.invalidDocument }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(AyaneDataExport.self, from: data)
        } catch {
            throw DataImportError.invalidDocument
        }
    }

    static func validate(_ payload: AyaneDataExport) throws {
        try requireSupportedSchema(payload.schemaVersion)
        try validateNormalized(normalizedPayload(payload))
    }

    private static func requireSupportedSchema(_ version: Int) throws {
        guard version == AyaneDataExport.currentSchemaVersion
                || version == AyaneDataExport.legacySchemaVersion
                || version == 5
                || version == 6
                || version == 7
                || version == 8
                || version == 9
                || version == 10
                || version == 11
                || version == 12
                || version == 13
                || version == 14
                || version == 15 else {
            throw DataImportError.unsupportedSchema(version)
        }
    }

    /// v4/v5 had one implicit persona and no role scope. v6 had role scope but
    /// no relationship collections. Every pre-v7 profile therefore receives
    /// one accepted relationship, while v4/v5 rows are still deliberately
    /// assigned to the single stable legacy role.
    private static func normalizedPayload(_ payload: AyaneDataExport) -> AyaneDataExport {
        var normalized = payload
        let legacyOnly = payload.schemaVersion == AyaneDataExport.legacySchemaVersion
            || payload.schemaVersion == 5
        let normalizedRoleID: (UUID?) -> UUID = { roleID in
            legacyOnly ? RoleScope.legacyRoleID : RoleScope.resolve(roleID)
        }

        normalized.profiles = payload.profiles.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.persona.roleID = normalizedRoleID(payload.persona.roleID)
        normalized.conversations = payload.conversations.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.events = payload.events.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            copy.senderRoleID = item.senderRoleID.map(normalizedRoleID)
            return copy
        }
        normalized.memories = payload.memories.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.evidence = payload.evidence.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.summaries = payload.summaries.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.tombstones = payload.tombstones.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.momentTasks = payload.momentTasks.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.momentAIInteractionTasks = payload.momentAIInteractionTasks.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.momentPosts = payload.momentPosts.map { item in
            var copy = item
            copy.authorRoleID = item.authorRoleID.map(normalizedRoleID)
            return copy
        }
        normalized.momentInteractions = payload.momentInteractions.map { item in
            var copy = item
            copy.actorRoleID = item.actorRoleID.map(normalizedRoleID)
            return copy
        }
        normalized.conversationReadStates = payload.conversationReadStates.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        normalized.momentReadStates = payload.momentReadStates
        normalized.worldProfiles = SchemaV11DataSupport.canonicalWorldProfiles(
            payload.worldProfiles.isEmpty ? [payload.worldProfile] : payload.worldProfiles
        )
        if normalized.worldProfiles.isEmpty {
            normalized.worldProfiles = [.realityDefault]
        }
        normalized.worldProfile = normalized.worldProfiles.first(where: {
            $0.id == WorldProfileRecord.realityID
        }) ?? normalized.worldProfiles[0]
        normalized.groupConversations = SchemaV11DataSupport.canonicalGroupConversations(
            payload.groupConversations
        )
        normalized.groupParticipants = SchemaV11DataSupport.canonicalGroupParticipants(
            payload.groupParticipants.map { item in
                var copy = item
                copy.participantRoleID = item.participantRoleID.map(normalizedRoleID)
                return copy
            }
        )
        normalized.chatTurnPresentations = SchemaV11DataSupport.canonicalChatTurnPresentations(
            payload.chatTurnPresentations.map { item in
                var copy = item
                copy.roleID = item.roleID.map(normalizedRoleID)
                return copy
            }
        )
        normalized.proactiveMessageTasks = SchemaV11DataSupport.canonicalProactiveMessageTasks(
            payload.proactiveMessageTasks.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
        )
        normalized.friendApplications = SchemaV11DataSupport.canonicalFriendApplications(
            payload.friendApplications.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
        )

        // v7 introduced relationship collections; only v4-v6 need the
        // compatibility relationship synthesized from profiles. v7 remains
        // a fully valid pre-task payload and simply receives no tasks.
        if payload.schemaVersion <= 6 {
            normalized.relationships = normalized.profiles.map { profile in
                let roleID = normalizedRoleID(profile.roleID)
                return AyaneRelationshipExport(
                    id: roleID,
                    roleID: roleID,
                    stateRaw: CompanionRelationshipState.accepted.rawValue,
                    harmStreak: 0,
                    hurtScore: 0,
                    harmThreshold: 3,
                    forgivenessScore: 0,
                    forgivenessThreshold: 2,
                    dignity: 0.5,
                    independence: 0.5,
                    boundarySensitivity: 0.5,
                    apologyAttempts: 0,
                    policyVersion: CompanionRelationshipRecord.currentPolicyVersion,
                    lastProcessedEventID: nil,
                    lastTransitionID: nil,
                    createdAt: profile.createdAt,
                    updatedAt: profile.updatedAt,
                    revision: profile.revision,
                    deviceID: profile.deviceID,
                    retiredAt: nil,
                    resetAt: nil
                )
            }
            normalized.transitions = []
        }
        return normalized
    }

    /// Performs all checks on a payload whose legacy roles and profile values
    /// have already been normalized. Keeping this separate prevents callers
    /// of `validate` from accidentally bypassing the v4/v5 migration rule.
    private static func validateNormalized(_ payload: AyaneDataExport) throws {
        guard payload.schemaVersion == AyaneDataExport.currentSchemaVersion
                || payload.schemaVersion == AyaneDataExport.legacySchemaVersion
                || payload.schemaVersion == 5
                || payload.schemaVersion == 6
                || payload.schemaVersion == 7
                || payload.schemaVersion == 8
                || payload.schemaVersion == 9
                || payload.schemaVersion == 10
                || payload.schemaVersion == 11
                || payload.schemaVersion == 12
                || payload.schemaVersion == 13
                || payload.schemaVersion == 14
                || payload.schemaVersion == 15 else {
            throw DataImportError.unsupportedSchema(payload.schemaVersion)
        }
        guard !payload.conversations.isEmpty else {
            throw DataImportError.invalidValue("至少需要一个会话")
        }

        guard !payload.profiles.isEmpty else {
            throw DataImportError.invalidValue("至少需要一个角色")
        }

        if payload.schemaVersion == AyaneDataExport.currentSchemaVersion,
           payload.profiles.contains(where: { $0.roleID == nil }) {
            throw DataImportError.invalidValue("角色缺少 role_id")
        }
        let normalizedProfiles = try payload.profiles.map {
            try normalizedPersona(from: $0)
        }
        let profileRoleIDs = try normalizedProfiles.map { profile -> UUID in
            guard let roleID = profile.roleID else {
                throw DataImportError.invalidValue("角色 \(profile.id) 缺少 role_id")
            }
            guard profile.id == roleID else {
                throw DataImportError.invalidValue("角色 \(profile.id) 的 ID 与 role_id 不一致")
            }
            return roleID
        }
        try requireUnique(profileRoleIDs, label: "角色 ID")
        let normalizedCompatibilityPersona = try normalizedPersona(from: payload.persona)
        guard let compatibilityRoleID = normalizedCompatibilityPersona.roleID,
              profileRoleIDs.contains(compatibilityRoleID) else {
            throw DataImportError.invalidReference("兼容 persona 未指向备份中的角色")
        }

        try requireUnique(payload.conversations.map(\.id), label: "会话 ID")
        try requireUnique(payload.events.map(\.id), label: "事件 ID")
        try requireUnique(payload.memories.map(\.id), label: "记忆 ID")
        try requireUnique(payload.evidence.map(\.id), label: "证据 ID")
        try requireUnique(payload.summaries.map(\.id), label: "摘要 ID")
        try requireUnique(payload.tombstones.map(\.id), label: "墓碑 ID")
        try requireUnique(payload.momentTasks.map(\.id), label: "朋友圈任务 ID")
        try requireUnique(payload.momentAIInteractionTasks.map(\.id), label: "朋友圈互动任务 ID")
        try requireUniqueStrings(
            payload.momentAIInteractionTasks.map { $0.idempotencyKey.lowercased() },
            label: "朋友圈互动任务幂等键"
        )
        try requireUnique(payload.relationships.map(\.id), label: "关系 ID")
        try requireUnique(payload.transitions.map(\.id), label: "关系变更 ID")
        try requireUnique(payload.relationships.map(\.roleID), label: "关系角色 ID")
        if let userProfile = payload.userProfile {
            guard userProfile.id == UserProfileRecord.singletonID,
                  !userProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  userProfile.displayName.count <= userProfileDisplayNameMaximumLength,
                  userProfile.createdAt.timeIntervalSince1970.isFinite,
                  userProfile.updatedAt.timeIntervalSince1970.isFinite,
                  userProfile.updatedAt >= userProfile.createdAt,
                  userProfile.revision >= 0,
                  userProfile.deviceID.count <= userProfileDeviceIDMaximumLength else {
                throw DataImportError.invalidValue("用户资料的单例 ID、内容或时间无效")
            }
            try validateBirthday(
                month: userProfile.birthdayMonth,
                day: userProfile.birthdayDay,
                label: "用户资料生日"
            )
            guard !userProfile.birthdayTimeZoneIdentifier.isEmpty,
                  userProfile.birthdayTimeZoneIdentifier.count <= 128,
                  TimeZone(identifier: userProfile.birthdayTimeZoneIdentifier) != nil else {
                throw DataImportError.invalidValue("用户资料生日时区无效")
            }
        }
        try requireUnique(payload.momentPosts.map(\.id), label: "朋友圈 ID")
        try requireUnique(payload.momentInteractions.map(\.id), label: "朋友圈互动 ID")
        try requireUnique(payload.conversationReadStates.map(\.id), label: "会话已读状态 ID")
        try requireUnique(payload.momentReadStates.map(\.id), label: "朋友圈已读状态 ID")
        try requireUniqueStrings(
            payload.conversationReadStates.map {
                "\(RoleScope.resolve($0.roleID).uuidString.lowercased()):\($0.conversationID.uuidString.lowercased())"
            },
            label: "会话已读状态作用域"
        )
        try requireUnique(payload.momentReadStates.map(\.postID), label: "朋友圈已读状态作用域")

        let conversationsByID = Dictionary(uniqueKeysWithValues: payload.conversations.map { ($0.id, $0) })
        let eventsByID = Dictionary(uniqueKeysWithValues: payload.events.map { ($0.id, $0) })
        let memoriesByID = Dictionary(uniqueKeysWithValues: payload.memories.map { ($0.id, $0) })
        let transitionsByID = Dictionary(uniqueKeysWithValues: payload.transitions.map { ($0.id, $0) })
        let relationshipRoleIDs = Set(payload.relationships.map(\.roleID))
        let momentPostsByID = Dictionary(uniqueKeysWithValues: payload.momentPosts.map { ($0.id, $0) })
        let conversationsByRoleKey = Set(payload.conversations.map {
            "\(RoleScope.resolve($0.roleID).uuidString.lowercased()):\($0.id.uuidString.lowercased())"
        })
        let groupIndex = GroupBackupValidationIndex(payload)

        func requireKnownRole(_ roleID: UUID?, description: String) throws -> UUID {
            guard let roleID, profileRoleIDs.contains(roleID) else {
                throw DataImportError.invalidReference(description)
            }
            return roleID
        }

        for transition in payload.transitions {
            let roleID = try requireKnownRole(
                transition.roleID,
                description: "关系变更 \(transition.id) 的角色不存在"
            )
            guard relationshipRoleIDs.contains(roleID),
                  CompanionRelationshipState(rawValue: transition.from) != nil,
                  CompanionRelationshipState(rawValue: transition.to) != nil,
                  !transition.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  transition.scoreAfter.isFinite,
                  transition.scoreAfter >= 0,
                  transition.policyVersion > 0,
                  transition.revision >= 0,
                  transition.occurredAt.timeIntervalSince1970.isFinite else {
                throw DataImportError.invalidValue("关系变更 \(transition.id) 的状态、数值或时间无效")
            }
            if let sourceEventID = transition.sourceEventID {
                // Hard reset may intentionally remove chat events while
                // retaining the append-only relationship audit row. If the
                // source event is present, still enforce its role; absence is
                // therefore not itself an invalid reference.
                if let event = eventsByID[sourceEventID],
                   let conversation = conversationsByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: roleID,
                       conversation: conversation
                   ) {
                    throw DataImportError.invalidReference("关系变更 \(transition.id) 的来源事件跨角色")
                }
            }
        }

        for relationship in payload.relationships {
            let roleID = try requireKnownRole(
                relationship.roleID,
                description: "关系 \(relationship.id) 的角色不存在"
            )
            guard CompanionRelationshipState(rawValue: relationship.stateRaw) != nil,
                  relationship.harmStreak >= 0,
                  relationship.hurtScore.isFinite,
                  relationship.hurtScore >= 0,
                  relationship.harmThreshold > 0,
                  relationship.forgivenessScore.isFinite,
                  relationship.forgivenessScore >= 0,
                  relationship.forgivenessThreshold.isFinite,
                  relationship.forgivenessThreshold > 0,
                  relationship.affinityScore.isFinite,
                  (0...100).contains(relationship.affinityScore),
                  (0...3).contains(relationship.affinityTier),
                  relationship.affinityPolicyVersion > 0,
                  relationship.dignity.isFinite,
                  (0...1).contains(relationship.dignity),
                  relationship.independence.isFinite,
                  (0...1).contains(relationship.independence),
                  relationship.boundarySensitivity.isFinite,
                  (0...1).contains(relationship.boundarySensitivity),
                  relationship.apologyAttempts >= 0,
                  relationship.policyVersion > 0,
                  relationship.createdAt.timeIntervalSince1970.isFinite,
                  relationship.updatedAt.timeIntervalSince1970.isFinite,
                  relationship.updatedAt >= relationship.createdAt,
                  relationship.revision >= 0 else {
                throw DataImportError.invalidValue("关系 \(relationship.id) 的状态、数值或时间无效")
            }
            if let eventID = relationship.lastProcessedEventID {
                // A hard reset removes the old chat events but retains the
                // relationship row. As with transition.sourceEventID, an
                // absent historical event is therefore allowed; when present
                // its role must still match.
                if let event = eventsByID[eventID],
                   let conversation = conversationsByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: roleID,
                       conversation: conversation
                   ) {
                    throw DataImportError.invalidReference("关系 \(relationship.id) 的最近事件跨角色")
                }
            }
            if let eventID = relationship.lastAffinityEventID,
               let event = eventsByID[eventID],
               let conversation = conversationsByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: roleID,
                   conversation: conversation
               ) {
                throw DataImportError.invalidReference("关系 \(relationship.id) 的最近亲密度事件跨角色")
            }
            if let transitionID = relationship.lastTransitionID {
                guard let transition = transitionsByID[transitionID] else {
                    throw DataImportError.invalidReference("关系 \(relationship.id) 的最近变更不存在")
                }
                guard transition.roleID == roleID else {
                    throw DataImportError.invalidReference("关系 \(relationship.id) 的最近变更跨角色")
                }
            }
        }

        for conversation in payload.conversations {
            let roleID = try requireKnownRole(
                conversation.roleID,
                description: "会话 \(conversation.id) 的角色不存在"
            )
            guard !conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DataImportError.invalidValue("会话标题为空")
            }
            guard conversation.updatedAt >= conversation.createdAt else {
                throw DataImportError.invalidValue("会话时间顺序错误")
            }
            guard roleID == RoleScope.resolve(conversation.roleID) else {
                throw DataImportError.invalidValue("会话 \(conversation.id) 的角色无效")
            }
        }

        for event in payload.events {
            // Validate payload bytes and metadata here as well as in the
            // shared v11-v15 pass below. This keeps the normalized event loop
            // fail-closed for image/file imports before any references are
            // inspected or records are materialized.
            do {
                try SchemaV11DataSupport.validateEventPayload(event)
            } catch let error as DataMergeError {
                throw mapSchemaV11Error(error)
            }
            guard let conversation = conversationsByID[event.conversationID] else {
                throw DataImportError.invalidReference("事件 \(event.id) 指向不存在的会话")
            }
            let roleID = try requireKnownRole(
                event.roleID,
                description: "事件 \(event.id) 的角色不存在"
            )
            guard groupIndex.eventMatchesConversation(event, conversation: conversation) else {
                throw DataImportError.invalidReference("事件 \(event.id) 与会话的角色不一致")
            }
            guard EventRole(rawValue: event.roleRaw) != nil,
                  event.role == event.roleRaw else {
                throw DataImportError.invalidValue("事件 \(event.id) 的角色无效")
            }
            guard EventDeliveryState(rawValue: event.deliveryStateRaw) != nil,
                  event.deliveryState == event.deliveryStateRaw else {
                throw DataImportError.invalidValue("事件 \(event.id) 的投递状态无效")
            }
            guard event.deviceSequence >= 0,
                  !event.deviceID.isEmpty,
                  !event.logicalTimestamp.isEmpty else {
                throw DataImportError.invalidValue("事件 \(event.id) 的设备顺序无效")
            }
            guard event.contentHash.lowercased() == ContentHasher.sha256(event.content).lowercased() else {
                throw DataImportError.invalidValue("事件 \(event.id) 的原文哈希不匹配")
            }
            if let parent = event.parentEventID {
                guard let parentEvent = eventsByID[parent] else {
                    throw DataImportError.invalidReference("事件 \(event.id) 的父事件不存在")
                }
                guard groupIndex.eventMatchesRole(
                    parentEvent,
                    roleID: roleID,
                    conversation: conversation
                ) else {
                    throw DataImportError.invalidReference("事件 \(event.id) 的父事件跨角色")
                }
            }
        }

        for state in payload.conversationReadStates {
            let roleID = try requireKnownRole(
                state.roleID,
                description: "会话已读状态 (state.id) 的角色不存在"
            )
            let scopeKey = "\(roleID.uuidString.lowercased()):\(state.conversationID.uuidString.lowercased())"
            guard conversationsByRoleKey.contains(scopeKey),
                  state.updatedAt.timeIntervalSince1970.isFinite,
                  state.revision >= 0,
                  state.deviceID.count <= userProfileDeviceIDMaximumLength else {
                throw DataImportError.invalidReference("会话已读状态 (state.id) 的会话或字段无效")
            }
            if let occurredAt = state.lastReadOccurredAt {
                guard occurredAt.timeIntervalSince1970.isFinite else {
                    throw DataImportError.invalidValue("会话已读状态 (state.id) 的游标时间无效")
                }
            }
            if let eventID = state.lastReadEventID {
                guard !state.lastReadLogicalTimestamp.isEmpty,
                      let event = eventsByID[eventID] else {
                    throw DataImportError.invalidReference("会话已读状态 (state.id) 的游标事件不存在")
                }
                guard let conversation = conversationsByID[state.conversationID],
                      groupIndex.eventMatchesConversation(event, conversation: conversation),
                      (groupIndex.isGroupConversation(state.conversationID)
                          ? roleID == RoleScope.resolve(conversation.roleID)
                          : RoleScope.resolve(event.roleID) == roleID) else {
                    throw DataImportError.invalidReference("会话已读状态 (state.id) 的游标跨角色或会话")
                }
            }
        }

        let interactionsByID = Dictionary(uniqueKeysWithValues: payload.momentInteractions.map { ($0.id, $0) })
        for state in payload.momentReadStates {
            guard let post = momentPostsByID[state.postID],
                  (post.authorKind == .user || post.authorKind == .companion),
                  state.updatedAt.timeIntervalSince1970.isFinite,
                  state.revision >= 0,
                  state.deviceID.count <= userProfileDeviceIDMaximumLength else {
                throw DataImportError.invalidReference("朋友圈已读状态 (state.id) 的帖子或字段无效")
            }
            if let createdAt = state.lastReadCreatedAt {
                guard createdAt.timeIntervalSince1970.isFinite else {
                    throw DataImportError.invalidValue("朋友圈已读状态 (state.id) 的游标时间无效")
                }
            }
            if let interactionID = state.lastReadInteractionID {
                guard let interaction = interactionsByID[interactionID],
                      interaction.postID == state.postID else {
                    throw DataImportError.invalidReference("朋友圈已读状态 (state.id) 的游标互动不存在")
                }
            }
        }

        var activeMemoryCanonicalKeys = Set<String>()
        for memory in payload.memories {
            let roleID = try requireKnownRole(
                memory.roleID,
                description: "记忆 \(memory.id) 的角色不存在"
            )
            let normalizedCanonicalKey = MemoryTombstoneRecord.normalizedCanonicalKey(
                memory.canonicalKey
            )
            guard MemoryKind(rawValue: memory.kindRaw) != nil,
                  memory.kind == memory.kindRaw,
                  MemoryState(rawValue: memory.stateRaw) != nil,
                  memory.state == memory.stateRaw else {
                throw DataImportError.invalidValue("记忆 \(memory.id) 的类型或状态无效")
            }
            guard !normalizedCanonicalKey.isEmpty,
                  memory.confidence.isFinite,
                  (0...1).contains(memory.confidence),
                  memory.importance.isFinite,
                  (0...1).contains(memory.importance),
                  memory.sourceRank >= 0,
                  memory.schemaVersion > 0 else {
                throw DataImportError.invalidValue("记忆 \(memory.id) 的数值或键无效")
            }
            guard memory.updatedAt >= memory.createdAt else {
                throw DataImportError.invalidValue("记忆 \(memory.id) 的时间顺序错误")
            }
            if memory.stateRaw == MemoryState.active.rawValue,
               !activeMemoryCanonicalKeys.insert(
                   scopedCanonicalKey(roleID: roleID, canonicalKey: normalizedCanonicalKey)
               ).inserted {
                // Restore is a replacement operation. It must not leave two
                // active facts that become the same logical memory after
                // trimming/case/format normalization; PromptAssembler would
                // otherwise see both rows after a successful restore.
                throw DataImportError.duplicateRecord("活动记忆规范键")
            }
            if let supersedesID = memory.supersedesID {
                guard let superseded = memoriesByID[supersedesID] else {
                    throw DataImportError.invalidReference("记忆 \(memory.id) 的被替代版本不存在")
                }
                guard superseded.roleID == roleID else {
                    throw DataImportError.invalidReference("记忆 \(memory.id) 的被替代版本跨角色")
                }
            }
            if let base64 = memory.embeddingBase64 {
                guard let bytes = Data(base64Encoded: base64),
                      let vector = MemoryEmbeddingCodec.decode(bytes),
                      !vector.isEmpty,
                      vector.allSatisfy(\.isFinite) else {
                    throw DataImportError.invalidValue("记忆 \(memory.id) 的向量数据损坏")
                }
            }
        }

        for item in payload.evidence {
            guard let memory = memoriesByID[item.memoryID],
                  let event = eventsByID[item.eventID] else {
                throw DataImportError.invalidReference("证据 \(item.id) 的记忆或事件不存在")
            }
            let roleID = try requireKnownRole(
                item.roleID,
                description: "证据 \(item.id) 的角色不存在"
            )
            guard let conversation = conversationsByID[event.conversationID],
                  memory.roleID == roleID,
                  groupIndex.eventMatchesRole(
                      event,
                      roleID: roleID,
                      conversation: conversation
                  ) else {
                throw DataImportError.invalidReference("证据 \(item.id) 跨角色引用")
            }
            guard EvidenceRelation(rawValue: item.relationRaw) != nil,
                  item.relation == item.relationRaw,
                  item.confidence.isFinite,
                  (0...1).contains(item.confidence),
                  let quote = quote(
                    in: event.content,
                    startUTF16: item.startUTF16,
                    endUTF16: item.endUTF16
                  ),
                  ContentHasher.sha256(quote).lowercased() == item.quoteHash.lowercased() else {
                throw DataImportError.invalidValue("证据 \(item.id) 的原文范围或哈希无效")
            }
        }

        for summary in payload.summaries {
            guard let conversation = conversationsByID[summary.conversationID] else {
                throw DataImportError.invalidReference("摘要 \(summary.id) 的会话不存在")
            }
            let roleID = try requireKnownRole(
                summary.roleID,
                description: "摘要 \(summary.id) 的角色不存在"
            )
            guard groupIndex.isGroupConversation(summary.conversationID)
                ? groupIndex.isActiveCompanion(
                    roleID,
                    in: summary.conversationID
                )
                : RoleScope.resolve(conversation.roleID) == roleID else {
                throw DataImportError.invalidReference("摘要 \(summary.id) 与会话的角色不一致")
            }
            guard summary.coveredEventCount >= 0,
                  summary.updatedAt >= summary.createdAt else {
                throw DataImportError.invalidValue("摘要 \(summary.id) 的范围或时间无效")
            }
            for endpoint in [summary.firstEventID, summary.lastEventID].compactMap({ $0 }) {
                guard let event = eventsByID[endpoint],
                      event.conversationID == summary.conversationID,
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: roleID,
                          conversation: conversation
                      ) else {
                    throw DataImportError.invalidReference("摘要 \(summary.id) 的边界事件不存在")
                }
            }
        }

        for tombstone in payload.tombstones {
            let roleID = try requireKnownRole(
                tombstone.roleID,
                description: "墓碑 \(tombstone.id) 的角色不存在"
            )
            guard !tombstone.entityType.isEmpty,
                  !tombstone.deviceID.isEmpty,
                  !tombstone.reason.isEmpty else {
                throw DataImportError.invalidValue("墓碑 \(tombstone.id) 的必要字段为空")
            }
            for sourceEventID in tombstone.sourceEventIDs {
                guard let sourceEvent = eventsByID[sourceEventID] else {
                    throw DataImportError.invalidReference("墓碑 \(tombstone.id) 的来源事件不存在")
                }
                guard let conversation = conversationsByID[sourceEvent.conversationID],
                      groupIndex.eventMatchesRole(
                          sourceEvent,
                          roleID: roleID,
                          conversation: conversation
                      ) else {
                    throw DataImportError.invalidReference("墓碑 \(tombstone.id) 的来源事件跨角色")
                }
            }
            if tombstone.entityType == "memory", let memory = memoriesByID[tombstone.entityID] {
                guard memory.roleID == roleID else {
                    throw DataImportError.invalidReference("墓碑 \(tombstone.id) 的目标记忆跨角色")
                }
            }
            if tombstone.entityType == "conversation",
               let conversation = conversationsByID[tombstone.entityID] {
                guard RoleScope.resolve(conversation.roleID) == roleID else {
                    throw DataImportError.invalidReference("墓碑 \(tombstone.id) 的目标会话跨角色")
                }
            }
            if tombstone.entityType == "event", let event = eventsByID[tombstone.entityID] {
                guard let conversation = conversationsByID[event.conversationID],
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: roleID,
                          conversation: conversation
                      ) else {
                    throw DataImportError.invalidReference("墓碑 \(tombstone.id) 的目标事件跨角色")
                }
            }
        }

        for post in payload.momentPosts {
            let resolvedAuthorRoleID = post.authorRoleID.map(RoleScope.resolve)
            guard MomentAuthorKind(rawValue: post.authorKindRaw) != nil,
                  post.authorKind.rawValue == post.authorKindRaw,
                  post.body.count <= momentPostBodyMaximumLength,
                  post.bundledImageName.count <= momentBundledImageNameMaximumLength,
                  post.publishedAt.timeIntervalSince1970.isFinite,
                  post.createdAt.timeIntervalSince1970.isFinite,
                  post.updatedAt.timeIntervalSince1970.isFinite,
                  post.updatedAt >= post.createdAt,
                  post.revision >= 0 else {
                throw DataImportError.invalidValue("朋友圈 \(post.id) 的作者、内容或时间无效")
            }
            if let deletedAt = post.deletedAt {
                guard deletedAt.timeIntervalSince1970.isFinite else {
                    throw DataImportError.invalidValue("朋友圈 \(post.id) 的删除时间无效")
                }
            }
            if post.authorKind == .companion {
                guard let resolvedAuthorRoleID,
                      profileRoleIDs.contains(resolvedAuthorRoleID) else {
                    throw DataImportError.invalidReference("朋友圈 \(post.id) 的作者角色不存在")
                }
            } else if let resolvedAuthorRoleID {
                guard profileRoleIDs.contains(resolvedAuthorRoleID) else {
                    throw DataImportError.invalidReference("朋友圈 \(post.id) 的用户作者角色不存在")
                }
            }
        }

        for interaction in payload.momentInteractions {
            let resolvedActorRoleID = interaction.actorRoleID.map(RoleScope.resolve)
            guard momentPostsByID[interaction.postID] != nil,
                  MomentInteractionKind(rawValue: interaction.kindRaw) != nil,
                  interaction.kind.rawValue == interaction.kindRaw,
                  MomentAuthorKind(rawValue: interaction.actorKindRaw) != nil,
                  interaction.actorKind.rawValue == interaction.actorKindRaw,
                  interaction.body.count <= momentInteractionBodyMaximumLength,
                  interaction.createdAt.timeIntervalSince1970.isFinite,
                  interaction.updatedAt.timeIntervalSince1970.isFinite,
                  interaction.updatedAt >= interaction.createdAt,
                  interaction.revision >= 0 else {
                throw DataImportError.invalidReference("朋友圈互动 \(interaction.id) 的帖子、作者或字段无效")
            }
            if interaction.actorKind == .companion {
                guard let resolvedActorRoleID,
                      profileRoleIDs.contains(resolvedActorRoleID) else {
                    throw DataImportError.invalidReference("朋友圈互动 \(interaction.id) 的作者角色不存在")
                }
            } else if let resolvedActorRoleID {
                guard profileRoleIDs.contains(resolvedActorRoleID) else {
                    throw DataImportError.invalidReference("朋友圈互动 \(interaction.id) 的用户作者角色不存在")
                }
            }
        }

        for task in payload.momentTasks {
            let roleID = try requireKnownRole(
                task.roleID,
                description: "朋友圈任务的角色不存在"
            )
            guard roleID == task.roleID,
                  !task.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  task.instruction.count <= AyaneMomentTaskValidationLimits.instruction,
                  task.resultText.count <= AyaneMomentTaskValidationLimits.resultText,
                  task.lastError.count <= AyaneMomentTaskValidationLimits.lastError,
                  task.leaseOwner.count <= AyaneMomentTaskValidationLimits.leaseOwner,
                  task.deviceID.count <= AyaneMomentTaskValidationLimits.deviceID,
                  task.scheduledAt.timeIntervalSince1970.isFinite,
                  task.createdAt.timeIntervalSince1970.isFinite,
                  task.updatedAt.timeIntervalSince1970.isFinite,
                  task.updatedAt >= task.createdAt,
                  task.attemptCount >= 0,
                  task.revision >= 0,
                  MomentTaskState(rawValue: task.stateRaw) != nil else {
                throw DataImportError.invalidValue("朋友圈任务的状态、指令或时间无效")
            }
            guard task.publishedAt?.timeIntervalSince1970.isFinite ?? true,
                  task.leaseExpiresAt?.timeIntervalSince1970.isFinite ?? true,
                  task.nextAttemptAt?.timeIntervalSince1970.isFinite ?? true else {
                throw DataImportError.invalidValue("朋友圈任务的发布或租约时间无效")
            }
            try validateMomentTaskRecurrence(task)
            if task.stateRaw == "published" {
                guard !task.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      task.publishedAt != nil else {
                    throw DataImportError.invalidValue("已发布朋友圈任务缺少结果或发布时间")
                }
            }
        }

        let momentInteractionsByID = Dictionary(uniqueKeysWithValues: payload.momentInteractions.map { ($0.id, $0) })
        for task in payload.momentAIInteractionTasks {
            let roleID = try requireKnownRole(
                task.roleID,
                description: "朋友圈互动任务 \(task.id) 的角色不存在"
            )
            guard roleID == task.roleID,
                  let post = momentPostsByID[task.postID],
                  MomentAIInteractionTaskKind(rawValue: task.kindRaw) != nil,
                  task.kind.rawValue == task.kindRaw,
                  MomentAIInteractionTaskState(rawValue: task.stateRaw) != nil,
                  task.state.rawValue == task.stateRaw,
                  !task.idempotencyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  task.idempotencyKey.count <= AyaneMomentAIInteractionTaskValidationLimits.idempotencyKey,
                  task.inputText.count <= AyaneMomentAIInteractionTaskValidationLimits.inputText,
                  task.generatedText.count <= AyaneMomentAIInteractionTaskValidationLimits.generatedText,
                  task.lastError.count <= AyaneMomentAIInteractionTaskValidationLimits.lastError,
                  task.timezoneIdentifier.count <= AyaneMomentAIInteractionTaskValidationLimits.timezoneIdentifier,
                  task.leaseOwner.count <= AyaneMomentAIInteractionTaskValidationLimits.leaseOwner,
                  task.deviceID.count <= AyaneMomentAIInteractionTaskValidationLimits.deviceID,
                  task.attemptCount >= 0,
                  task.revision >= 0,
                  task.createdAt.timeIntervalSince1970.isFinite,
                  task.updatedAt.timeIntervalSince1970.isFinite,
                  task.nextAttemptAt.timeIntervalSince1970.isFinite,
                  task.updatedAt >= task.createdAt,
                  task.leaseExpiresAt?.timeIntervalSince1970.isFinite ?? true else {
                throw DataImportError.invalidValue("朋友圈互动任务 \(task.id) 的状态、内容或时间无效")
            }
            if let parentID = task.parentInteractionID {
                guard let parent = momentInteractionsByID[parentID],
                      parent.postID == task.postID,
                      parent.kind == .comment else {
                    throw DataImportError.invalidReference("朋友圈互动任务 \(task.id) 的父评论不存在")
                }
            }
            if let rootID = task.rootInteractionID {
                guard let root = momentInteractionsByID[rootID],
                      root.postID == task.postID,
                      root.kind == .comment else {
                    throw DataImportError.invalidReference("朋友圈互动任务 \(task.id) 的根评论不存在")
                }
            }
            if let resultID = task.resultInteractionID {
                guard let result = momentInteractionsByID[resultID],
                      result.postID == task.postID,
                      result.kind == .comment,
                      result.actorKind == .companion,
                      result.actorRoleID.map(RoleScope.resolve) == roleID else {
                    throw DataImportError.invalidReference("朋友圈互动任务 \(task.id) 的结果互动不存在或跨角色")
                }
            }
            switch task.kind {
            case .reactionLike, .reactionComment:
                guard task.targetInteractionID == nil,
                      task.parentInteractionID == nil,
                      task.rootInteractionID == nil,
                      post.authorKind == .user else {
                    throw DataImportError.invalidValue("反应任务不应带评论父子引用")
                }
            case .replyLike:
                guard post.authorKind == .companion,
                      post.authorRoleID.map(RoleScope.resolve) == roleID,
                      let targetID = task.targetInteractionID,
                      let target = momentInteractionsByID[targetID],
                      target.postID == task.postID,
                      target.kind == .like,
                      target.actorKind == .user,
                      task.parentInteractionID == nil,
                      task.rootInteractionID == nil else {
                    throw DataImportError.invalidReference("点赞回复任务的帖子作者或用户点赞来源无效")
                }
            case .replyComment:
                guard let parentID = task.parentInteractionID,
                      let parent = momentInteractionsByID[parentID],
                      parent.postID == task.postID,
                      parent.kind == .comment,
                      parent.actorKind == .user else {
                    throw DataImportError.invalidValue("回复任务缺少有效的用户父评论")
                }
                if post.authorKind == .companion {
                    guard post.authorRoleID.map(RoleScope.resolve) == roleID else {
                        throw DataImportError.invalidReference("AI 朋友圈回复任务不是由动态作者处理")
                    }
                }
                if let targetID = task.targetInteractionID {
                    guard let target = momentInteractionsByID[targetID],
                          target.postID == task.postID,
                          target.kind == .comment,
                          target.actorKind == .companion,
                          target.actorRoleID.map(RoleScope.resolve) == roleID else {
                        throw DataImportError.invalidReference("朋友圈互动任务 \(task.id) 的目标评论不存在或跨角色")
                    }
                }
            }
        }

        let settings = payload.settings
        guard settings.provider.temperature.isFinite,
              (0...2).contains(settings.provider.temperature),
              (400...8_000).contains(settings.memory.tokenBudget),
              (4...80).contains(settings.memory.recentMessageLimit),
              (200...1_000).contains(settings.memory.rawHistoryTokenBudget) else {
            throw DataImportError.invalidValue("设置值超出当前应用支持范围")
        }

        do {
            try SchemaV11DataSupport.validate(payload)
        } catch let error as DataMergeError {
            throw mapSchemaV11Error(error)
        }
    }

    private static func mapSchemaV11Error(_ error: DataMergeError) -> DataImportError {
        switch error {
        case .duplicateSourceIDs(let entity):
            return .duplicateRecord(entity.rawValue)
        case .invalidReference(let description):
            return .invalidReference(description)
        case .invalidValue(let description):
            return .invalidValue(description)
        default:
            return .invalidValue(error.localizedDescription)
        }
    }

    private static func requireUnique(_ values: [UUID], label: String) throws {
        guard Set(values).count == values.count else {
            throw DataImportError.duplicateRecord(label)
        }
    }

    private static func requireUniqueStrings(_ values: [String], label: String) throws {
        guard Set(values).count == values.count else {
            throw DataImportError.duplicateRecord(label)
        }
    }

    private static func quote(in content: String, startUTF16: Int, endUTF16: Int) -> String? {
        let utf16 = content.utf16
        guard startUTF16 >= 0,
              endUTF16 > startUTF16,
              endUTF16 <= utf16.count,
              let start = utf16.index(utf16.startIndex, offsetBy: startUTF16).samePosition(in: content),
              let end = utf16.index(utf16.startIndex, offsetBy: endUTF16).samePosition(in: content) else {
            return nil
        }
        return String(content[start..<end])
    }

    private static func summary(for payload: AyaneDataExport) -> DataImportSummary {
        DataImportSummary(
            exportedAt: payload.exportedAt,
            profiles: payload.profiles.count,
            conversations: payload.conversations.count,
            events: payload.events.count,
            memories: payload.memories.count,
            evidence: payload.evidence.count,
            summaries: payload.summaries.count,
            tombstones: payload.tombstones.count,
            relationships: payload.relationships.count,
            transitions: payload.transitions.count,
            momentTasks: payload.momentTasks.count,
            momentAIInteractionTasks: payload.momentAIInteractionTasks.count,
            userProfiles: payload.userProfile == nil ? 0 : 1,
            momentPosts: payload.momentPosts.count,
            momentInteractions: payload.momentInteractions.count,
            conversationReadStates: payload.conversationReadStates.count,
            momentReadStates: payload.momentReadStates.count,
            worldProfiles: payload.worldProfiles.count,
            groupConversations: payload.groupConversations.count,
            groupParticipants: payload.groupParticipants.count,
            chatTurnPresentations: payload.chatTurnPresentations.count,
            proactiveMessageTasks: payload.proactiveMessageTasks.count,
            friendApplications: payload.friendApplications.count
        )
    }

    private static func normalizedPersona(
        from persona: AyanePersonaExport
    ) throws -> AyanePersonaExport {
        let roleID: UUID
        if let explicitRoleID = persona.roleID {
            guard persona.id == explicitRoleID else {
                throw DataImportError.invalidValue("人物设定的 ID 与 role_id 不一致")
            }
            roleID = explicitRoleID
        } else {
            guard persona.id == AyanePersonaExport.singletonID else {
                throw DataImportError.invalidValue("人物设定的固定 ID 无效")
            }
            roleID = RoleScope.legacyRoleID
        }
        let name = persona.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let userName = persona.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = persona.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= profileNameMaximumLength else {
            throw DataImportError.invalidValue("人物名称为空或过长")
        }
        guard !userName.isEmpty, userName.count <= profileUserNameMaximumLength else {
            throw DataImportError.invalidValue("用户称呼为空或过长")
        }
        guard !prompt.isEmpty, prompt.count <= profilePromptMaximumLength else {
            throw DataImportError.invalidValue("人物提示词为空或过长")
        }
        try validateBirthday(
            month: persona.birthdayMonth,
            day: persona.birthdayDay,
            label: "人物设定生日"
        )
        guard persona.revision >= 0 else {
            throw DataImportError.invalidValue("人物设定 revision 无效")
        }
        guard persona.createdAt <= persona.updatedAt else {
            throw DataImportError.invalidValue("人物设定时间顺序错误")
        }
        return AyanePersonaExport(
            name: name,
            userName: userName,
            prompt: prompt,
            id: roleID,
            createdAt: persona.createdAt,
            updatedAt: persona.updatedAt,
            revision: persona.revision,
            deviceID: persona.deviceID,
            roleID: roleID,
            worldProfileID: persona.worldProfileID,
            birthdayMonth: persona.birthdayMonth,
            birthdayDay: persona.birthdayDay,
            avatarImageData: persona.avatarImageData,
            chatBackgroundImageData: persona.chatBackgroundImageData
        )
    }

    private static func validateBirthday(
        month: Int?,
        day: Int?,
        label: String
    ) throws {
        guard (month == nil) == (day == nil) else {
            throw DataImportError.invalidValue(label + "必须同时填写月份和日期")
        }
        guard let month, let day else { return }
        guard (1...12).contains(month), (1...31).contains(day) else {
            throw DataImportError.invalidValue(label + "日期无效")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = calendar.date(
            from: DateComponents(year: 2000, month: month, day: day)
        ),
        calendar.component(.month, from: date) == month,
        calendar.component(.day, from: date) == day else {
            throw DataImportError.invalidValue(label + "日期无效")
        }
    }

    private static func validateMomentTaskRecurrence(
        _ task: AyaneMomentTaskExport
    ) throws {
        guard MomentTaskRecurrenceFrequency(rawValue: task.recurrenceRaw) != nil,
              task.recurrenceInterval >= 1,
              (0...23).contains(task.recurrenceHour),
              (0...59).contains(task.recurrenceMinute),
              !task.timezoneIdentifier.isEmpty,
              task.timezoneIdentifier.count <= AyaneMomentTaskValidationLimits.timezoneIdentifier,
              TimeZone(identifier: task.timezoneIdentifier) != nil,
              task.occurrenceKey.count <= AyaneMomentTaskValidationLimits.occurrenceKey else {
            throw DataImportError.invalidValue("朋友圈任务的重复规则无效")
        }
        if let weekday = task.recurrenceWeekday,
           !(1...7).contains(weekday) {
            throw DataImportError.invalidValue("朋友圈任务的星期无效")
        }
        if let dayOfMonth = task.recurrenceDayOfMonth,
           !(1...31).contains(dayOfMonth) {
            throw DataImportError.invalidValue("朋友圈任务的月份日期无效")
        }
        switch MomentTaskRecurrenceFrequency(rawValue: task.recurrenceRaw) {
        case .weekly where task.recurrenceWeekday == nil:
            throw DataImportError.invalidValue("每周任务缺少星期")
        case .monthly where task.recurrenceDayOfMonth == nil:
            throw DataImportError.invalidValue("每月任务缺少日期")
        default:
            break
        }
    }

    private static func scopedCanonicalKey(roleID: UUID, canonicalKey: String) -> String {
        roleID.uuidString.lowercased() + "\u{001F}" + canonicalKey
    }

    private static func makeConversation(_ item: AyaneConversationExport) -> ConversationRecord {
        let record = ConversationRecord(
            id: item.id,
            title: item.title,
            createdAt: item.createdAt,
            roleID: item.roleID
        )
        record.updatedAt = item.updatedAt
        record.archived = item.archived
        return record
    }

    private static func makeEvent(_ item: AyaneEventExport) -> ConversationEvent {
        let role = EventRole(rawValue: item.roleRaw) ?? .user
        let state = EventDeliveryState(rawValue: item.deliveryStateRaw) ?? .complete
        let record = ConversationEvent(
            id: item.id,
            conversationID: item.conversationID,
            deviceID: item.deviceID,
            deviceSequence: item.deviceSequence,
            logicalTimestamp: item.logicalTimestamp,
            occurredAt: item.occurredAt,
            role: role,
            content: item.content,
            contentHash: item.contentHash,
            parentEventID: item.parentEventID,
            deliveryState: state,
            roleID: item.roleID,
            payloadKind: MessagePayloadKind(rawValue: item.payloadKindRaw) ?? .text,
            stickerID: item.stickerID,
            senderRoleID: item.senderRoleID,
            imageData: item.imageData,
            fileName: item.fileName,
            fileTypeIdentifier: item.fileTypeIdentifier,
            fileData: item.fileData
        )
        record.recordedAt = item.recordedAt
        record.redacted = item.redacted
        record.memoryProcessedAt = item.memoryProcessedAt
        record.memoryProcessingVersion = item.memoryProcessingVersion
        return record
    }

    private static func makeMemory(_ item: AyaneMemoryExport) throws -> MemoryAssertionRecord {
        let canonicalKey = MemoryTombstoneRecord.normalizedCanonicalKey(item.canonicalKey)
        guard !canonicalKey.isEmpty else {
            throw DataImportError.invalidValue("记忆 \(item.id) 的规范键不能为空")
        }
        let record = MemoryAssertionRecord(
            id: item.id,
            kind: MemoryKind(rawValue: item.kindRaw) ?? .profile,
            subject: item.subject,
            predicate: item.predicate,
            value: item.value,
            canonicalKey: canonicalKey,
            state: MemoryState(rawValue: item.stateRaw) ?? .candidate,
            confidence: item.confidence,
            importance: item.importance,
            sensitive: item.sensitive,
            sourceRank: item.sourceRank,
            validFrom: item.validFrom,
            validTo: item.validTo,
            observedAt: item.observedAt,
            supersedesID: item.supersedesID,
            extractorID: item.extractorID,
            deviceID: item.deviceID,
            roleID: item.roleID
        )
        record.schemaVersion = item.schemaVersion
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.isPinned = item.isPinned
        record.userVerified = item.userVerified
        if let base64 = item.embeddingBase64 {
            guard let data = Data(base64Encoded: base64) else {
                throw DataImportError.invalidValue("记忆 \(item.id) 的向量数据损坏")
            }
            record.embeddingData = data
        }
        record.embeddingModelID = item.embeddingModelID
        return record
    }

    private static func makeEvidence(_ item: AyaneEvidenceExport) -> MemoryEvidenceRecord {
        let record = MemoryEvidenceRecord(
            id: item.id,
            memoryID: item.memoryID,
            eventID: item.eventID,
            startUTF16: item.startUTF16,
            endUTF16: item.endUTF16,
            relation: EvidenceRelation(rawValue: item.relationRaw) ?? .supports,
            quoteHash: item.quoteHash,
            confidence: item.confidence,
            roleID: item.roleID
        )
        record.createdAt = item.createdAt
        return record
    }

    private static func makeSummary(_ item: AyaneSummaryExport) -> MemorySummaryRecord {
        let record = MemorySummaryRecord(
            conversationID: item.conversationID,
            scope: item.scope,
            content: item.content,
            firstEventID: item.firstEventID,
            lastEventID: item.lastEventID,
            coveredEventCount: item.coveredEventCount,
            extractorID: item.extractorID,
            roleID: item.roleID
        )
        record.id = item.id
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        return record
    }

    private static func makeTombstone(_ item: AyaneTombstoneExport) -> MemoryTombstoneRecord {
        let record = MemoryTombstoneRecord(
            entityID: item.entityID,
            entityType: item.entityType,
            canonicalKey: item.canonicalKey,
            sourceEventIDs: item.sourceEventIDs,
            deviceID: item.deviceID,
            reason: item.reason,
            roleID: item.roleID
        )
        record.id = item.id
        record.deletedAt = item.deletedAt
        return record
    }

    private static func makeRelationship(
        _ item: AyaneRelationshipExport
    ) throws -> CompanionRelationshipRecord {
        guard CompanionRelationshipState(rawValue: item.stateRaw) != nil else {
            throw DataImportError.invalidValue("关系 \(item.id) 的状态无效")
        }
        return CompanionRelationshipRecord(
            id: item.id,
            roleID: item.roleID,
            stateRaw: item.stateRaw,
            harmStreak: item.harmStreak,
            hurtScore: item.hurtScore,
            harmThreshold: item.harmThreshold,
            forgivenessScore: item.forgivenessScore,
            forgivenessThreshold: item.forgivenessThreshold,
            affinityScore: item.affinityScore,
            affinityTier: item.affinityTier,
            affinityPolicyVersion: item.affinityPolicyVersion,
            lastAffinityEventID: item.lastAffinityEventID,
            dignity: item.dignity,
            independence: item.independence,
            boundarySensitivity: item.boundarySensitivity,
            apologyAttempts: item.apologyAttempts,
            policyVersion: item.policyVersion,
            lastProcessedEventID: item.lastProcessedEventID,
            lastTransitionID: item.lastTransitionID,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID,
            retiredAt: item.retiredAt,
            resetAt: item.resetAt,
            contactMembershipRaw: item.contactMembershipRaw,
            contactStateUpdatedAt: item.contactStateUpdatedAt,
            lastUserRemovalID: item.lastUserRemovalID
        )
    }

    private static func makeTransition(
        _ item: AyaneRelationshipTransitionExport
    ) throws -> CompanionRelationshipTransitionRecord {
        guard CompanionRelationshipState(rawValue: item.from) != nil,
              CompanionRelationshipState(rawValue: item.to) != nil else {
            throw DataImportError.invalidValue("关系变更 \(item.id) 的状态无效")
        }
        return CompanionRelationshipTransitionRecord(
            id: item.id,
            roleID: item.roleID,
            from: item.from,
            to: item.to,
            reason: item.reason,
            sourceEventID: item.sourceEventID,
            scoreAfter: item.scoreAfter,
            policyVersion: item.policyVersion,
            occurredAt: item.occurredAt,
            deviceID: item.deviceID,
            revision: item.revision
        )
    }

    private static func makeMomentTask(
        _ item: AyaneMomentTaskExport
    ) throws -> CompanionMomentTaskRecord {
        guard MomentTaskState(rawValue: item.stateRaw) != nil else {
            throw DataImportError.invalidValue("朋友圈任务状态无效")
        }
        return CompanionMomentTaskRecord(
            id: item.id,
            roleID: RoleScope.resolve(item.roleID),
            instruction: item.instruction,
            scheduledAt: item.scheduledAt,
            seriesID: item.seriesID,
            occurrenceKey: item.occurrenceKey,
            recurrenceRaw: item.recurrenceRaw,
            recurrenceInterval: item.recurrenceInterval,
            recurrenceWeekday: item.recurrenceWeekday,
            recurrenceDayOfMonth: item.recurrenceDayOfMonth,
            recurrenceHour: item.recurrenceHour,
            recurrenceMinute: item.recurrenceMinute,
            timezoneIdentifier: item.timezoneIdentifier,
            nextAttemptAt: item.nextAttemptAt,
            stateRaw: item.stateRaw,
            resultText: item.resultText,
            publishedAt: item.publishedAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            attemptCount: item.attemptCount,
            lastError: item.lastError,
            leaseOwner: item.leaseOwner,
            leaseExpiresAt: item.leaseExpiresAt,
            deviceID: item.deviceID,
            revision: item.revision
        )
    }

    private static func makeMomentAIInteractionTask(
        _ item: AyaneMomentAIInteractionTaskExport
    ) throws -> MomentAIInteractionTaskRecord {
        guard let kind = MomentAIInteractionTaskKind(rawValue: item.kindRaw),
              let state = MomentAIInteractionTaskState(rawValue: item.stateRaw) else {
            throw DataImportError.invalidValue("朋友圈互动任务状态无效")
        }
        return MomentAIInteractionTaskRecord(
            id: item.id,
            kind: kind,
            postID: item.postID,
            targetInteractionID: item.targetInteractionID,
            parentInteractionID: item.parentInteractionID,
            rootInteractionID: item.rootInteractionID,
            roleID: item.roleID,
            state: state,
            attemptCount: item.attemptCount,
            nextAttemptAt: item.nextAttemptAt,
            lastError: item.lastError,
            idempotencyKey: item.idempotencyKey,
            timezoneIdentifier: item.timezoneIdentifier,
            inputText: item.inputText,
            generatedText: item.generatedText,
            generatedLike: item.generatedLike,
            resultInteractionID: item.resultInteractionID,
            leaseOwner: item.leaseOwner,
            leaseExpiresAt: item.leaseExpiresAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeProfile(_ item: AyanePersonaExport) -> CompanionProfileRecord {
        CompanionProfileRecord(
            id: item.id,
            worldProfileID: item.worldProfileID,
            name: item.name,
            userName: item.userName,
            prompt: item.prompt,
            birthdayMonth: item.birthdayMonth,
            birthdayDay: item.birthdayDay,
            avatarImageData: item.avatarImageData,
            chatBackgroundImageData: item.chatBackgroundImageData,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeUserProfile(_ item: AyaneUserProfileExport) -> UserProfileRecord {
        UserProfileRecord(
            id: item.id,
            displayName: item.displayName,
            birthdayMonth: item.birthdayMonth,
            birthdayDay: item.birthdayDay,
            birthdayTimeZoneIdentifier: item.birthdayTimeZoneIdentifier,
            avatarImageData: item.avatarImageData,
            momentsCoverImageData: item.momentsCoverImageData,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeMomentPost(
        _ item: AyaneMomentPostExport
    ) throws -> MomentPostRecord {
        guard MomentAuthorKind(rawValue: item.authorKindRaw) != nil else {
            throw DataImportError.invalidValue("朋友圈作者类型无效")
        }
        return MomentPostRecord(
            id: item.id,
            authorKind: item.authorKind,
            authorRoleID: item.authorRoleID,
            body: item.body,
            imageData: item.imageData,
            bundledImageName: item.bundledImageName,
            sourceTaskID: item.sourceTaskID,
            publishedAt: item.publishedAt,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            deletedAt: item.deletedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeMomentInteraction(
        _ item: AyaneMomentInteractionExport
    ) throws -> MomentInteractionRecord {
        guard MomentInteractionKind(rawValue: item.kindRaw) != nil,
              MomentAuthorKind(rawValue: item.actorKindRaw) != nil else {
            throw DataImportError.invalidValue("朋友圈互动类型或作者无效")
        }
        return MomentInteractionRecord(
            id: item.id,
            postID: item.postID,
            kind: item.kind,
            actorKind: item.actorKind,
            actorRoleID: item.actorRoleID,
            parentInteractionID: item.parentInteractionID,
            rootInteractionID: item.rootInteractionID,
            body: item.body,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeConversationReadState(
        _ item: AyaneConversationReadStateExport
    ) throws -> ConversationReadStateRecord {
        guard let roleID = item.roleID else {
            throw DataImportError.invalidReference("会话已读状态缺少角色")
        }
        return ConversationReadStateRecord(
            id: item.id,
            roleID: roleID,
            conversationID: item.conversationID,
            lastReadOccurredAt: item.lastReadOccurredAt,
            lastReadLogicalTimestamp: item.lastReadLogicalTimestamp,
            lastReadEventID: item.lastReadEventID,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeMomentReadState(
        _ item: AyaneMomentReadStateExport
    ) throws -> MomentReadStateRecord {
        MomentReadStateRecord(
            id: item.id,
            postID: item.postID,
            lastReadCreatedAt: item.lastReadCreatedAt,
            lastReadInteractionID: item.lastReadInteractionID,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    /// The storage backend toggle deliberately stays local. Restoring a backup
    /// must not silently opt a device into or out of CloudKit on its next launch.
    private static func restoreNonSecretSettings(
        _ payload: AyaneDataExport,
        defaults: UserDefaults
    ) {
        let provider = payload.settings.provider
        let declaredProvider = provider.providerID.flatMap(ProviderPreset.init(rawValue:))
        let matchingProvider = ProviderPreset.matching(baseURL: provider.baseURL)
        let restoredProvider: ProviderPreset
        if declaredProvider == .custom {
            restoredProvider = .custom
        } else if let declaredProvider, declaredProvider == matchingProvider {
            restoredProvider = declaredProvider
        } else {
            // Old backups have no provider_id. Derive the namespace from the
            // restored address so a key for the device's previous provider can
            // never be sent to the newly restored host.
            restoredProvider = matchingProvider ?? .custom
        }
        defaults.set(restoredProvider.rawValue, forKey: SettingsKeys.providerID)
        defaults.set(1, forKey: SettingsKeys.providerSelectionMigrationVersion)
        defaults.set(provider.baseURL, forKey: SettingsKeys.baseURL)
        defaults.set(provider.model, forKey: SettingsKeys.model)
        defaults.set(provider.embeddingModel, forKey: SettingsKeys.embeddingModel)
        defaults.set(provider.temperature, forKey: SettingsKeys.temperature)
        defaults.set(provider.streamsResponses, forKey: SettingsKeys.streamResponses)

        let memory = payload.settings.memory
        defaults.set(memory.autoExtractMemory, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(memory.tokenBudget, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(memory.recentMessageLimit, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(memory.rawHistoryRecallEnabled, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(memory.rawHistoryTokenBudget, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(
            payload.settings.humanizedReplyDelayEnabled,
            forKey: SettingsKeys.humanizedReplyDelayEnabled
        )
        defaults.set(
            payload.settings.proactiveMessagesEnabled,
            forKey: SettingsKeys.proactiveMessagesEnabled
        )
        defaults.set(
            payload.settings.proactiveQuietStartHour,
            forKey: SettingsKeys.proactiveQuietStartHour
        )
        defaults.set(
            payload.settings.proactiveQuietEndHour,
            forKey: SettingsKeys.proactiveQuietEndHour
        )
        defaults.set(
            payload.settings.worldviewAutoMatchEnabled,
            forKey: SettingsKeys.worldviewAutoMatchEnabled
        )
    }
}
