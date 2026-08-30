import CryptoKit
import Foundation
import SwiftData

enum DataMergeEntity: String, CaseIterable, Codable, Sendable {
    case profile
    case userProfile
    case momentPost
    case momentInteraction
    case momentAIInteractionTask
    case relationship
    case transition
    case momentTask
    case conversation
    case event
    case conversationReadState
    case momentReadState
    case memory
    case evidence
    case summary
    case tombstone
    case worldProfile
    case groupConversation
    case groupParticipant
    case chatTurnPresentation
    case proactiveMessageTask
    case friendApplication
}

struct DataMergeEntityReport: Equatable, Sendable {
    let inserted: Int
    let updated: Int
    let unchanged: Int

    var total: Int { inserted + updated + unchanged }
}

struct DataMergeReport: Equatable, Sendable {
    let profiles: DataMergeEntityReport
    let userProfiles: DataMergeEntityReport
    let momentPosts: DataMergeEntityReport
    let momentInteractions: DataMergeEntityReport
    let momentAIInteractionTasks: DataMergeEntityReport
    let relationships: DataMergeEntityReport
    let transitions: DataMergeEntityReport
    let momentTasks: DataMergeEntityReport
    let conversations: DataMergeEntityReport
    let events: DataMergeEntityReport
    let conversationReadStates: DataMergeEntityReport
    let momentReadStates: DataMergeEntityReport
    let memories: DataMergeEntityReport
    let evidence: DataMergeEntityReport
    let summaries: DataMergeEntityReport
    let tombstones: DataMergeEntityReport
    let worldProfile: DataMergeEntityReport
    let groupConversations: DataMergeEntityReport
    let groupParticipants: DataMergeEntityReport
    let chatTurnPresentations: DataMergeEntityReport
    let proactiveMessageTasks: DataMergeEntityReport
    let friendApplications: DataMergeEntityReport

    init(
        profiles: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        userProfiles: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        momentPosts: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        momentInteractions: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        momentAIInteractionTasks: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        relationships: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        transitions: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        momentTasks: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        conversations: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        events: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        conversationReadStates: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        momentReadStates: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        memories: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        evidence: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        summaries: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        tombstones: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        worldProfile: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        groupConversations: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        groupParticipants: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        chatTurnPresentations: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        proactiveMessageTasks: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0),
        friendApplications: DataMergeEntityReport = .init(inserted: 0, updated: 0, unchanged: 0)
    ) {
        self.profiles = profiles
        self.userProfiles = userProfiles
        self.momentPosts = momentPosts
        self.momentInteractions = momentInteractions
        self.momentAIInteractionTasks = momentAIInteractionTasks
        self.relationships = relationships
        self.transitions = transitions
        self.momentTasks = momentTasks
        self.conversations = conversations
        self.events = events
        self.conversationReadStates = conversationReadStates
        self.momentReadStates = momentReadStates
        self.memories = memories
        self.evidence = evidence
        self.summaries = summaries
        self.tombstones = tombstones
        self.worldProfile = worldProfile
        self.groupConversations = groupConversations
        self.groupParticipants = groupParticipants
        self.chatTurnPresentations = chatTurnPresentations
        self.proactiveMessageTasks = proactiveMessageTasks
        self.friendApplications = friendApplications
    }

    var total: DataMergeEntityReport {
        DataMergeEntityReport(
            inserted: profiles.inserted
                + userProfiles.inserted
                + momentPosts.inserted
                + momentInteractions.inserted
                + momentAIInteractionTasks.inserted
                + relationships.inserted
                + transitions.inserted
                + momentTasks.inserted
                + conversations.inserted
                + events.inserted
                + conversationReadStates.inserted
                + momentReadStates.inserted
                + memories.inserted
                + evidence.inserted
                + summaries.inserted
                + tombstones.inserted
                + worldProfile.inserted
                + groupConversations.inserted
                + groupParticipants.inserted
                + chatTurnPresentations.inserted
                + proactiveMessageTasks.inserted
                + friendApplications.inserted,
            updated: profiles.updated
                + userProfiles.updated
                + momentPosts.updated
                + momentInteractions.updated
                + momentAIInteractionTasks.updated
                + relationships.updated
                + transitions.updated
                + momentTasks.updated
                + conversations.updated
                + events.updated
                + conversationReadStates.updated
                + momentReadStates.updated
                + memories.updated
                + evidence.updated
                + summaries.updated
                + tombstones.updated
                + worldProfile.updated
                + groupConversations.updated
                + groupParticipants.updated
                + chatTurnPresentations.updated
                + proactiveMessageTasks.updated
                + friendApplications.updated,
            unchanged: profiles.unchanged
                + userProfiles.unchanged
                + momentPosts.unchanged
                + momentInteractions.unchanged
                + momentAIInteractionTasks.unchanged
                + relationships.unchanged
                + transitions.unchanged
                + momentTasks.unchanged
                + conversations.unchanged
                + events.unchanged
                + conversationReadStates.unchanged
                + momentReadStates.unchanged
                + memories.unchanged
                + evidence.unchanged
                + summaries.unchanged
                + tombstones.unchanged
                + worldProfile.unchanged
                + groupConversations.unchanged
                + groupParticipants.unchanged
                + chatTurnPresentations.unchanged
                + proactiveMessageTasks.unchanged
                + friendApplications.unchanged
        )
    }

    var totalRecords: Int { total.total }
    var totalInserted: Int { total.inserted }
    var totalUpdated: Int { total.updated }
    var totalUnchanged: Int { total.unchanged }

    // Migration callers can consume the aggregate with the conventional
    // inserted/updated/unchanged names while entity-level detail remains
    // available above.
    var inserted: Int { totalInserted }
    var updated: Int { totalUpdated }
    var unchanged: Int { totalUnchanged }
}

enum DataMergeError: LocalizedError, Equatable {
    case invalidSource(String)
    case duplicateSourceIDs(entity: DataMergeEntity)
    case duplicateTargetIDs(entity: DataMergeEntity, ids: [UUID])
    case identityConflict(entity: DataMergeEntity, id: UUID)
    case invalidReference(String)
    case invalidValue(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource(let description):
            return "合并源数据无效：\(description)"
        case .duplicateSourceIDs(let entity):
            return "合并源数据包含重复的\(entity.rawValue) ID。"
        case .duplicateTargetIDs(let entity, let ids):
            return "目标存储包含重复的\(entity.rawValue) ID：\(ids.map(\.uuidString).joined(separator: ", "))。"
        case .identityConflict(let entity, let id):
            return "\(entity.rawValue) \(id.uuidString) 的身份或内容冲突，未执行合并。"
        case .invalidReference(let description):
            return "合并结果引用不完整：\(description)"
        case .invalidValue(let description):
            return "合并结果完整性校验失败：\(description)"
        case .saveFailed(let description):
            return "合并保存失败：\(description)"
        }
    }
}

/// Performs an additive, idempotent merge into one ModelContext.
///
/// The service deliberately never touches UserDefaults or Keychain. Source
/// validation and merge planning happen before ordinary destination writes.
/// The bounded legacy-tombstone migration is committed independently first so
/// each page is durable and a later merge rollback cannot revive an unsafe key.
@MainActor
struct DataMergeService {
    private struct ScopedCanonicalSearchKey: Hashable {
        let roleID: UUID
        let value: String
    }

    /// Read-state identity is a logical scope rather than the physical row
    /// UUID. CloudKit/import races may materialize more than one row for the
    /// same scope, so merge planning must compare `(roleID, conversationID)`
    /// instead of treating the marker UUID as the identity.
    private struct ConversationReadStateScope: Hashable {
        let roleID: UUID
        let conversationID: UUID
    }

    static func merge(
        _ payload: AyaneDataExport,
        into destination: ModelContext
    ) throws -> DataMergeReport {
        do {
            // Legacy tombstones are normalized in durable bounded batches
            // before canonical keys participate in merge identity planning.
            try MemoryTombstoneNormalizer.normalizePending(context: destination)

            // Canonical keys are part of the logical identity used by the
            // merge planner. Normalize them before validation and planning so
            // padded/case-variant imports cannot create a second identity,
            // while whitespace-only memory keys are rejected up front.
            let normalizedPayload = try normalizePayload(payload)
            try SchemaV11DataSupport.validate(normalizedPayload)
            let target = try TargetSnapshot(
                context: destination,
                payload: normalizedPayload,
                canonicalKeySearchValues: Set(
                    normalizedPayload.memories.map {
                        ScopedCanonicalSearchKey(
                            roleID: resolvedRoleID($0.roleID),
                            value: $0.canonicalKey
                        )
                    }
                        + normalizedPayload.tombstones
                            .filter { $0.entityType == "memory" }
                            .map {
                                ScopedCanonicalSearchKey(
                                    roleID: resolvedRoleID($0.roleID),
                                    value: $0.canonicalKey
                                )
                            }
                )
            )
            let plan = try MergePlan(payload: normalizedPayload, target: target)
            try plan.apply(to: destination)
            let schemaV11Report = try SchemaV11DataSupport.merge(
                normalizedPayload,
                into: destination
            )
            try destination.save()
            return DataMergeReport(
                profiles: plan.report.profiles,
                userProfiles: plan.report.userProfiles,
                momentPosts: plan.report.momentPosts,
                momentInteractions: plan.report.momentInteractions,
                momentAIInteractionTasks: plan.report.momentAIInteractionTasks,
                relationships: plan.report.relationships,
                transitions: plan.report.transitions,
                momentTasks: plan.report.momentTasks,
                conversations: plan.report.conversations,
                events: plan.report.events,
                conversationReadStates: plan.report.conversationReadStates,
                momentReadStates: plan.report.momentReadStates,
                memories: plan.report.memories,
                evidence: plan.report.evidence,
                summaries: plan.report.summaries,
                tombstones: plan.report.tombstones,
                worldProfile: schemaV11Report.worldProfile,
                groupConversations: schemaV11Report.groupConversations,
                groupParticipants: schemaV11Report.groupParticipants,
                chatTurnPresentations: schemaV11Report.chatTurnPresentations,
                proactiveMessageTasks: schemaV11Report.proactiveMessageTasks,
                friendApplications: schemaV11Report.friendApplications
            )
        } catch let error as DataMergeError {
            destination.rollback()
            throw error
        } catch {
            destination.rollback()
            throw DataMergeError.saveFailed(error.localizedDescription)
        }
    }

    static func merge(
        payload: AyaneDataExport,
        into destination: ModelContext
    ) throws -> DataMergeReport {
        try merge(payload, into: destination)
    }

    static func merge(
        from source: ModelContext,
        into destination: ModelContext
    ) throws -> DataMergeReport {
        // Keep the established source-export contract. The destination side
        // is now bounded by the payload's IDs/keys/references; making this
        // overload stream the complete source would require a streaming
        // export API and a separate source snapshot/consistency contract.
        let payload = try DataExportService.makePayload(context: source)
        return try merge(payload, into: destination)
    }

    private static func normalizePayload(_ payload: AyaneDataExport) throws -> AyaneDataExport {
        // v4/v5 had one implicit persona.  Keep that migration rule explicit
        // even when a hand-edited legacy payload happens to contain role_id
        // fields.  v6 writers already carry role IDs; a missing value remains
        // a legacy row for compatibility with in-process callers that still
        // construct the DTOs directly.
        let legacyOnly = payload.schemaVersion == AyaneDataExport.legacySchemaVersion
            || payload.schemaVersion == 5
        let normalizedRoleID: (UUID?) -> UUID = { roleID in
            legacyOnly ? RoleScope.legacyRoleID : RoleScope.resolve(roleID)
        }

        let profiles = payload.profiles.map { item -> AyanePersonaExport in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        var persona = payload.persona
        persona.roleID = normalizedRoleID(payload.persona.roleID)

        let conversations = payload.conversations.map { item -> AyaneConversationExport in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let events = payload.events.map { item -> AyaneEventExport in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            copy.senderRoleID = item.senderRoleID.map(normalizedRoleID)
            return copy
        }
        let memories = try payload.memories.map { item -> AyaneMemoryExport in
            let canonicalKey = normalizeKey(item.canonicalKey)
            guard !canonicalKey.isEmpty else {
                throw DataMergeError.invalidValue("记忆 \(item.id) 的规范键不能为空。")
            }
            let normalized = AyaneMemoryExport(
                mergeID: item.id,
                kind: item.kind,
                kindRaw: item.kindRaw,
                subject: item.subject,
                predicate: item.predicate,
                value: item.value,
                canonicalKey: canonicalKey,
                state: item.state,
                stateRaw: item.stateRaw,
                confidence: item.confidence,
                importance: item.importance,
                sensitive: item.sensitive,
                sourceRank: item.sourceRank,
                validFrom: item.validFrom,
                validTo: item.validTo,
                observedAt: item.observedAt,
                supersedesID: item.supersedesID,
                extractorID: item.extractorID,
                schemaVersion: item.schemaVersion,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                isPinned: item.isPinned,
                userVerified: item.userVerified,
                embeddingBase64: item.embeddingBase64,
                embeddingModelID: item.embeddingModelID,
                deviceID: item.deviceID,
                roleID: normalizedRoleID(item.roleID)
            )
            return erasedMemoryExportIfForgotten(normalized)
        }
        let evidence = payload.evidence.map { item -> AyaneEvidenceExport in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let summaries = payload.summaries.map { item -> AyaneSummaryExport in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let tombstones = payload.tombstones.map { item in
            AyaneTombstoneExport(
                mergeID: item.id,
                entityID: item.entityID,
                entityType: item.entityType,
                canonicalKey: normalizeTombstoneKey(item.canonicalKey),
                sourceEventIDs: item.sourceEventIDs,
                deletedAt: item.deletedAt,
                deviceID: item.deviceID,
                reason: item.reason,
                roleID: normalizedRoleID(item.roleID)
            )
        }
        let momentTasks = payload.momentTasks.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let userProfile = payload.userProfile
        let momentPosts = payload.momentPosts.map { item in
            var copy = item
            copy.authorRoleID = item.authorRoleID.map(normalizedRoleID)
            return copy
        }
        let momentInteractions = payload.momentInteractions.map { item in
            var copy = item
            copy.actorRoleID = item.actorRoleID.map(normalizedRoleID)
            return copy
        }
        let momentAIInteractionTasks = payload.momentAIInteractionTasks.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let conversationReadStates = payload.conversationReadStates.map { item in
            var copy = item
            copy.roleID = normalizedRoleID(item.roleID)
            return copy
        }
        let momentReadStates = payload.momentReadStates
        let worldProfiles = SchemaV11DataSupport.canonicalWorldProfiles(
            payload.worldProfiles.isEmpty ? [payload.worldProfile] : payload.worldProfiles
        )
        let worldProfile = worldProfiles.first(where: {
            $0.id == WorldProfileRecord.realityID
        }) ?? worldProfiles.first ?? .realityDefault
        let groupConversations = SchemaV11DataSupport.canonicalGroupConversations(payload.groupConversations)
        let groupParticipants = SchemaV11DataSupport.canonicalGroupParticipants(
            payload.groupParticipants.map { item in
                var copy = item
                copy.participantRoleID = item.participantRoleID.map(normalizedRoleID)
                return copy
            }
        )
        let chatTurnPresentations = SchemaV11DataSupport.canonicalChatTurnPresentations(
            payload.chatTurnPresentations.map { item in
                var copy = item
                copy.roleID = item.roleID.map(normalizedRoleID)
                return copy
            }
        )
        let proactiveMessageTasks = SchemaV11DataSupport.canonicalProactiveMessageTasks(
            payload.proactiveMessageTasks.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
        )
        let friendApplications = SchemaV11DataSupport.canonicalFriendApplications(
            payload.friendApplications.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
        )
        let relationships: [AyaneRelationshipExport]
        let transitions: [AyaneRelationshipTransitionExport]
        // v7 already carries relationship collections; only v4-v6 need the
        // compatibility relationship synthesized from profiles.
        if payload.schemaVersion <= 6 {
            relationships = profiles.map { profile in
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
                    resetAt: nil,
                    contactMembershipRaw: ContactMembershipState.active.rawValue,
                    contactStateUpdatedAt: profile.updatedAt,
                    lastUserRemovalID: nil
                )
            }
            transitions = []
        } else {
            relationships = payload.relationships.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
            transitions = payload.transitions.map { item in
                var copy = item
                copy.roleID = normalizedRoleID(item.roleID)
                return copy
            }
        }
        return AyaneDataExport(
            schemaVersion: payload.schemaVersion,
            exportedAt: payload.exportedAt,
            conversations: conversations,
            events: events,
            memories: memories,
            evidence: evidence,
            summaries: summaries,
            tombstones: tombstones,
            persona: persona,
            settings: payload.settings,
            profiles: profiles,
            relationships: relationships,
            friendApplications: friendApplications,
            transitions: transitions,
            momentTasks: momentTasks,
            userProfile: userProfile,
            momentPosts: momentPosts,
            momentInteractions: momentInteractions,
            conversationReadStates: conversationReadStates,
            momentReadStates: momentReadStates,
            momentAIInteractionTasks: momentAIInteractionTasks,
            worldProfile: worldProfile,
            worldProfiles: worldProfiles,
            groupConversations: groupConversations,
            groupParticipants: groupParticipants,
            chatTurnPresentations: chatTurnPresentations,
            proactiveMessageTasks: proactiveMessageTasks
        )
    }

    @MainActor
    private struct TargetSnapshot {
        private static let maximumActiveMemoriesPerCanonicalKey = 512

        let profiles: [AyanePersonaExport]
        let userProfile: AyaneUserProfileExport?
        let momentPosts: [AyaneMomentPostExport]
        let momentInteractions: [AyaneMomentInteractionExport]
        let momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport]
        let relationships: [AyaneRelationshipExport]
        let transitions: [AyaneRelationshipTransitionExport]
        let momentTasks: [AyaneMomentTaskExport]
        let conversations: [AyaneConversationExport]
        let events: [AyaneEventExport]
        let conversationReadStates: [AyaneConversationReadStateExport]
        let momentReadStates: [AyaneMomentReadStateExport]
        let memories: [AyaneMemoryExport]
        let evidence: [AyaneEvidenceExport]
        let summaries: [AyaneSummaryExport]
        let tombstones: [AyaneTombstoneExport]
        let groupConversations: [AyaneGroupConversationExport]
        let groupParticipants: [AyaneGroupParticipantExport]

        let profileObjects: [UUID: CompanionProfileRecord]
        let userProfileObject: UserProfileRecord?
        let momentPostObjects: [UUID: MomentPostRecord]
        let momentInteractionObjects: [UUID: MomentInteractionRecord]
        let momentAIInteractionTaskObjects: [UUID: MomentAIInteractionTaskRecord]
        let relationshipObjects: [UUID: CompanionRelationshipRecord]
        let transitionObjects: [UUID: CompanionRelationshipTransitionRecord]
        let momentTaskObjects: [UUID: CompanionMomentTaskRecord]
        let conversationObjects: [UUID: ConversationRecord]
        let eventObjects: [UUID: ConversationEvent]
        let conversationReadStateObjects: [ConversationReadStateScope: ConversationReadStateRecord]
        let momentReadStateObjects: [UUID: MomentReadStateRecord]
        let conversationReadStateIdentityByID: [UUID: ConversationReadStateScope]
        let momentReadStateIdentityByID: [UUID: UUID]
        let memoryObjects: [UUID: MemoryAssertionRecord]
        let evidenceObjects: [UUID: MemoryEvidenceRecord]
        let summaryObjects: [UUID: MemorySummaryRecord]
        let tombstoneObjects: [UUID: MemoryTombstoneRecord]

        init(
            context: ModelContext,
            payload: AyaneDataExport,
            canonicalKeySearchValues: Set<ScopedCanonicalSearchKey>
        ) throws {
            // A merge only needs the destination rows which can participate in
            // an identity comparison, canonical-memory convergence, or final
            // reference validation. Fetching by scalar equality keeps this
            // translatable on the minimum SwiftData runtime; importantly, no
            // captured collection is put inside a predicate (which can turn
            // into an unbounded scan on older stores).
            let profileRecords = try Self.fetchProfiles(context: context)
            let userProfileRecords = try Self.fetchUserProfiles(context: context)
            let userProfileRecord = DataMergeService.canonicalUserProfileRecord(from: userProfileRecords)
            let momentPostRecords = try Self.fetchMomentPosts(context: context)
            let momentInteractionRecords = try Self.fetchMomentInteractions(context: context)
            let momentAIInteractionTaskRecords = try context.fetch(
                FetchDescriptor<MomentAIInteractionTaskRecord>()
            )
            let relationshipRecords = try context.fetch(
                FetchDescriptor<CompanionRelationshipRecord>()
            )
            let transitionRecords = try context.fetch(
                FetchDescriptor<CompanionRelationshipTransitionRecord>()
            )
            let momentTaskRecords = try context.fetch(
                FetchDescriptor<CompanionMomentTaskRecord>()
            )
            let groupConversationRecords = try context.fetch(
                FetchDescriptor<GroupConversationRecord>()
            )
            let groupParticipantRecords = try context.fetch(
                FetchDescriptor<GroupParticipantRecord>()
            )
            let allConversationReadStateRecords = try context.fetch(
                FetchDescriptor<ConversationReadStateRecord>()
            )
            let allMomentReadStateRecords = try context.fetch(
                FetchDescriptor<MomentReadStateRecord>()
            )

            // A marker's physical UUID is not its logical identity. Keep the
            // full ID-to-scope map for fail-closed validation, then retain
            // only scopes explicitly present in this payload. This preserves
            // unrelated read-state rows without broadening a small merge.
            var conversationReadStateIdentityByID: [UUID: ConversationReadStateScope] = [:]
            for record in allConversationReadStateRecords {
                let scope = ConversationReadStateScope(
                    roleID: record.resolvedRoleID,
                    conversationID: record.conversationID
                )
                if let existing = conversationReadStateIdentityByID[record.id], existing != scope {
                    throw DataMergeError.identityConflict(
                        entity: .conversationReadState,
                        id: record.id
                    )
                }
                conversationReadStateIdentityByID[record.id] = scope
            }
            var momentReadStateIdentityByID: [UUID: UUID] = [:]
            for record in allMomentReadStateRecords {
                if let existing = momentReadStateIdentityByID[record.id], existing != record.postID {
                    throw DataMergeError.identityConflict(
                        entity: .momentReadState,
                        id: record.id
                    )
                }
                momentReadStateIdentityByID[record.id] = record.postID
            }
            let requestedConversationReadStateScopes = Set(
                payload.conversationReadStates.map {
                    ConversationReadStateScope(
                        roleID: DataMergeService.resolvedRoleID($0.roleID),
                        conversationID: $0.conversationID
                    )
                }
            )
            let requestedMomentReadStatePostIDs = Set(
                payload.momentReadStates.map(\.postID)
            )
            let scopedConversationReadStateRecords = allConversationReadStateRecords.filter {
                requestedConversationReadStateScopes.contains(
                    ConversationReadStateScope(
                        roleID: $0.resolvedRoleID,
                        conversationID: $0.conversationID
                    )
                )
            }
            let scopedMomentReadStateRecords = allMomentReadStateRecords.filter {
                requestedMomentReadStatePostIDs.contains($0.postID)
            }
            let conversationReadStateRecords = try Self.canonicalConversationReadStateRecords(
                scopedConversationReadStateRecords
            )
            let momentReadStateRecords = try Self.canonicalMomentReadStateRecords(
                scopedMomentReadStateRecords
            )

            var conversationIDs = Set(payload.conversations.map(\.id))
            conversationIDs.formUnion(payload.summaries.map(\.conversationID))
            conversationIDs.formUnion(payload.conversationReadStates.map(\.conversationID))
            var eventIDs = Set(payload.events.map(\.id))
            eventIDs.formUnion(payload.events.compactMap(\.parentEventID))
            eventIDs.formUnion(payload.evidence.map(\.eventID))
            eventIDs.formUnion(payload.relationships.compactMap(\.lastProcessedEventID))
            eventIDs.formUnion(payload.transitions.compactMap(\.sourceEventID))
            eventIDs.formUnion(payload.summaries.flatMap {
                [$0.firstEventID, $0.lastEventID].compactMap { $0 }
            })
            eventIDs.formUnion(payload.tombstones.flatMap(\.sourceEventIDs))
            eventIDs.formUnion(payload.conversationReadStates.compactMap(\.lastReadEventID))
            eventIDs.formUnion(conversationReadStateRecords.compactMap(\.lastReadEventID))
            var memoryIDs = Set(payload.memories.map(\.id))
            memoryIDs.formUnion(payload.memories.compactMap(\.supersedesID))
            memoryIDs.formUnion(payload.evidence.map(\.memoryID))
            let evidenceIDs = Set(payload.evidence.map(\.id))
            let summaryIDs = Set(payload.summaries.map(\.id))
            let tombstoneIDs = Set(payload.tombstones.map(\.id))
            let roleIDs = Set(payload.profiles.map { DataMergeService.resolvedRoleID($0.roleID) })

            // MemoryAssertionRecord predates the normalized-key column, so an
            // old destination row can still contain a legacy spelling. Expand
            // only normalized keys explicitly present in this merge; never
            // scan unrelated canonical groups.
            var memoryCanonicalKeys = Set<ScopedCanonicalSearchKey>()
            for value in canonicalKeySearchValues {
                for variant in DataMergeService.canonicalKeyVariants(value.value) {
                    memoryCanonicalKeys.insert(
                        ScopedCanonicalSearchKey(roleID: value.roleID, value: variant)
                    )
                }
            }
            var tombstoneCanonicalKeys = Set<ScopedCanonicalSearchKey>()
            for item in payload.memories {
                let value = DataMergeService.normalizeTombstoneKey(item.canonicalKey)
                if !value.isEmpty {
                    tombstoneCanonicalKeys.insert(
                        ScopedCanonicalSearchKey(
                            roleID: DataMergeService.resolvedRoleID(item.roleID),
                            value: value
                        )
                    )
                }
            }
            for item in payload.tombstones {
                let value = DataMergeService.normalizeTombstoneKey(item.canonicalKey)
                if !value.isEmpty {
                    tombstoneCanonicalKeys.insert(
                        ScopedCanonicalSearchKey(
                            roleID: DataMergeService.resolvedRoleID(item.roleID),
                            value: value
                        )
                    )
                }
            }

            var conversationRecords = RecordCollector<ConversationRecord>()
            var eventRecords = RecordCollector<ConversationEvent>()
            var memoryRecords = RecordCollector<MemoryAssertionRecord>()
            var evidenceRecords = RecordCollector<MemoryEvidenceRecord>()
            var summaryRecords = RecordCollector<MemorySummaryRecord>()
            var tombstoneRecords = RecordCollector<MemoryTombstoneRecord>()

            var queriedConversationIDs = Set<UUID>()
            var queriedEventIDs = Set<UUID>()
            var queriedMemoryIDs = Set<UUID>()
            var queriedEvidenceIDs = Set<UUID>()
            var queriedSummaryIDs = Set<UUID>()
            var queriedTombstoneIDs = Set<UUID>()
            var queriedMemoryCanonicalKeys = Set<ScopedCanonicalSearchKey>()
            var queriedTombstoneCanonicalKeys = Set<ScopedCanonicalSearchKey>()
            var queriedLegacyGlobalTombstoneRoles = Set<UUID>()
            var processedEvents = Set<ObjectIdentifier>()
            var processedMemories = Set<ObjectIdentifier>()
            var processedEvidence = Set<ObjectIdentifier>()
            var processedSummaries = Set<ObjectIdentifier>()
            var processedTombstones = Set<ObjectIdentifier>()

            while true {
                var progress = false

                for id in conversationIDs where queriedConversationIDs.insert(id).inserted {
                    progress = true
                    conversationRecords.append(contentsOf: try Self.fetchConversations(
                        ids: [id],
                        context: context
                    ))
                }
                for id in eventIDs where queriedEventIDs.insert(id).inserted {
                    progress = true
                    eventRecords.append(contentsOf: try Self.fetchEvents(
                        ids: [id],
                        context: context
                    ))
                }
                for id in memoryIDs where queriedMemoryIDs.insert(id).inserted {
                    progress = true
                    memoryRecords.append(contentsOf: try Self.fetchMemories(
                        ids: [id],
                        context: context
                    ))
                }
                for id in evidenceIDs where queriedEvidenceIDs.insert(id).inserted {
                    progress = true
                    evidenceRecords.append(contentsOf: try Self.fetchEvidence(
                        ids: [id],
                        context: context
                    ))
                }
                for id in summaryIDs where queriedSummaryIDs.insert(id).inserted {
                    progress = true
                    summaryRecords.append(contentsOf: try Self.fetchSummaries(
                        ids: [id],
                        context: context
                    ))
                }
                for id in tombstoneIDs where queriedTombstoneIDs.insert(id).inserted {
                    progress = true
                    tombstoneRecords.append(contentsOf: try Self.fetchTombstones(
                        ids: [id],
                        context: context
                    ))
                }

                // Incoming memory canonical keys and every newly discovered
                // target spelling are searched independently. This catches a
                // legacy target row such as " User.Favorite " while keeping
                // unrelated canonical groups out of the snapshot.
                for key in memoryCanonicalKeys
                    where queriedMemoryCanonicalKeys.insert(key).inserted {
                    progress = true
                    memoryRecords.append(contentsOf: try Self.fetchMemories(
                        canonicalKey: key.value,
                        roleID: key.roleID,
                        context: context
                    ))
                }

                for key in tombstoneCanonicalKeys
                    where queriedTombstoneCanonicalKeys.insert(key).inserted {
                    progress = true
                    tombstoneRecords.append(contentsOf: try Self.fetchTombstones(
                        canonicalKey: key.value,
                        roleID: key.roleID,
                        context: context
                    ))
                }

                // An empty canonical key is the legacy global deletion
                // barrier. Only the newest such row can affect suppression, so
                // this remains bounded even if a store has many old markers.
                for roleID in roleIDs where queriedLegacyGlobalTombstoneRoles.insert(roleID).inserted {
                    progress = true
                    tombstoneRecords.append(contentsOf: try Self.fetchNewestGlobalTombstone(
                        roleID: roleID,
                        context: context
                    ))
                }

                // Close over references from target rows. These rows are
                // included in final validation because a payload may point at
                // an object which already exists only in the destination.
                for record in eventRecords.values
                    where processedEvents.insert(ObjectIdentifier(record)).inserted {
                    eventIDs.formUnion(record.parentEventID.map { [$0] } ?? [])
                    conversationIDs.insert(record.conversationID)
                }
                for record in memoryRecords.values
                    where processedMemories.insert(ObjectIdentifier(record)).inserted {
                    memoryIDs.formUnion(record.supersedesID.map { [$0] } ?? [])
                    let rawKey = record.canonicalKey
                    let normalizedKey = DataMergeService.normalizeKey(rawKey)
                    if !normalizedKey.isEmpty {
                        memoryCanonicalKeys.formUnion(
                            DataMergeService.canonicalKeyVariants(rawKey).map {
                                ScopedCanonicalSearchKey(
                                    roleID: record.resolvedRoleID,
                                    value: $0
                                )
                            }
                        )
                        tombstoneCanonicalKeys.insert(
                            ScopedCanonicalSearchKey(
                                roleID: record.resolvedRoleID,
                                value: normalizedKey
                            )
                        )
                    }
                }
                for record in evidenceRecords.values
                    where processedEvidence.insert(ObjectIdentifier(record)).inserted {
                    memoryIDs.insert(record.memoryID)
                    eventIDs.insert(record.eventID)
                }
                for record in summaryRecords.values
                    where processedSummaries.insert(ObjectIdentifier(record)).inserted {
                    conversationIDs.insert(record.conversationID)
                    eventIDs.formUnion(
                        [record.firstEventID, record.lastEventID].compactMap { $0 }
                    )
                }
                for record in tombstoneRecords.values
                    where processedTombstones.insert(ObjectIdentifier(record)).inserted {
                    eventIDs.formUnion(record.sourceEventIDs)
                    if record.entityType == "memory" {
                        memoryIDs.insert(record.entityID)
                    }
                    let normalizedKey = DataMergeService.normalizeTombstoneKey(record.canonicalKey)
                    if !normalizedKey.isEmpty {
                        tombstoneCanonicalKeys.insert(
                            ScopedCanonicalSearchKey(
                                roleID: record.resolvedRoleID,
                                value: normalizedKey
                            )
                        )
                    }
                }

                if !progress {
                    break
                }
            }

            let profileValues = profileRecords
            let userProfileValue = userProfileRecord.map(AyaneUserProfileExport.init)
            let momentPostValues = momentPostRecords.map(AyaneMomentPostExport.init)
            let momentInteractionValues = momentInteractionRecords.map(AyaneMomentInteractionExport.init)
            let momentAIInteractionTaskValues = momentAIInteractionTaskRecords.map(
                AyaneMomentAIInteractionTaskExport.init
            )
            let conversationValues = conversationRecords.values
            let eventValues = eventRecords.values
            let conversationReadStateValues = conversationReadStateRecords.map(
                AyaneConversationReadStateExport.init
            )
            let momentReadStateValues = momentReadStateRecords.map(
                AyaneMomentReadStateExport.init
            )
            let memoryValues = memoryRecords.values
            let evidenceValues = evidenceRecords.values
            let summaryValues = summaryRecords.values
            let tombstoneValues = tombstoneRecords.values
            let groupConversationValues = SchemaV11DataSupport.canonicalGroupConversations(
                groupConversationRecords.map(AyaneGroupConversationExport.init)
            )
            let groupParticipantValues = SchemaV11DataSupport.canonicalGroupParticipants(
                groupParticipantRecords.map(AyaneGroupParticipantExport.init)
            )

            // Relationship rows have one logical identity per role rather
            // than one UUID. A CloudKit/import race can still materialize
            // several physical rows; keep the safest deterministic winner in
            // the merge snapshot and let the duplicate reconciler collapse
            // the remaining physical rows later.
            var relationshipByRole: [UUID: CompanionRelationshipRecord] = [:]
            for record in relationshipRecords {
                let roleID = record.roleID
                guard CompanionRelationshipState(rawValue: record.stateRaw) != nil else {
                    throw DataMergeError.invalidValue("目标关系 \(record.id) 的状态无效。")
                }
                if let current = relationshipByRole[roleID] {
                    if DataMergeService.preferredRelationship(record, over: current) {
                        relationshipByRole[roleID] = record
                    }
                } else {
                    relationshipByRole[roleID] = record
                }
            }
            let relationshipValues = relationshipByRole.values
            var transitionByID: [UUID: CompanionRelationshipTransitionRecord] = [:]
            for record in transitionRecords {
                guard CompanionRelationshipState(rawValue: record.from) != nil,
                      CompanionRelationshipState(rawValue: record.to) != nil else {
                    throw DataMergeError.invalidValue("目标关系变更 \(record.id) 的状态无效。")
                }
                if let current = transitionByID[record.id] {
                    guard DataMergeService.sameTransitionIdentity(current, record) else {
                        throw DataMergeError.identityConflict(entity: .transition, id: record.id)
                    }
                    if DataMergeService.preferredTransition(record, over: current) {
                        transitionByID[record.id] = record
                    }
                } else {
                    transitionByID[record.id] = record
                }
            }
            let transitionValues = transitionByID.values
            let momentTaskValues = momentTaskRecords

            try Self.ensureUnique(profileValues.map(\.id), entity: .profile, target: true)
            try Self.ensureUnique(momentPostValues.map(\.id), entity: .momentPost, target: true)
            try Self.ensureUnique(momentInteractionValues.map(\.id), entity: .momentInteraction, target: true)
            try Self.ensureUnique(
                momentAIInteractionTaskValues.map(\.id),
                entity: .momentAIInteractionTask,
                target: true
            )
            try Self.ensureUnique(
                momentAIInteractionTaskValues.map(DataMergeService.momentAIInteractionTaskKey),
                entity: .momentAIInteractionTask,
                target: true
            )
            try Self.ensureUnique(conversationValues.map(\.id), entity: .conversation, target: true)
            try Self.ensureUnique(eventValues.map(\.id), entity: .event, target: true)
            try Self.ensureUnique(
                conversationReadStateValues.map(\.id),
                entity: .conversationReadState,
                target: true
            )
            try Self.ensureUnique(
                momentReadStateValues.map(\.id),
                entity: .momentReadState,
                target: true
            )
            try Self.ensureUnique(
                conversationReadStateValues.map {
                    ConversationReadStateScope(
                        roleID: DataMergeService.resolvedRoleID($0.roleID),
                        conversationID: $0.conversationID
                    )
                },
                entity: .conversationReadState,
                target: true
            )
            try Self.ensureUnique(
                momentReadStateValues.map(\.postID),
                entity: .momentReadState,
                target: true
            )
            try Self.ensureUnique(memoryValues.map(\.id), entity: .memory, target: true)
            try Self.ensureUnique(evidenceValues.map(\.id), entity: .evidence, target: true)
            try Self.ensureUnique(summaryValues.map(\.id), entity: .summary, target: true)
            try Self.ensureUnique(tombstoneValues.map(\.id), entity: .tombstone, target: true)
            try Self.ensureUnique(momentTaskValues.map(\.id), entity: .momentTask, target: true)

            for profile in profileValues {
                try DataMergeService.validateProfile(AyanePersonaExport(profile))
            }
            if let userProfileValue {
                try DataMergeService.validateUserProfile(userProfileValue)
            }
            for post in momentPostValues {
                try DataMergeService.validateMomentPost(post)
            }
            for interaction in momentInteractionValues {
                try DataMergeService.validateMomentInteraction(interaction)
            }
            for task in momentAIInteractionTaskValues {
                try DataMergeService.validateMomentAIInteractionTask(task)
            }
            for task in momentTaskValues {
                try DataMergeService.validateMomentTask(AyaneMomentTaskExport(task))
            }

            profiles = profileValues.map(AyanePersonaExport.init)
            userProfile = userProfileValue
            momentPosts = momentPostValues
            momentInteractions = momentInteractionValues
            momentAIInteractionTasks = momentAIInteractionTaskValues
            relationships = relationshipValues.map(AyaneRelationshipExport.init)
            transitions = transitionValues.map(AyaneRelationshipTransitionExport.init)
            momentTasks = momentTaskValues.map(AyaneMomentTaskExport.init)
            conversations = conversationValues.map(AyaneConversationExport.init)
            events = eventValues.map(AyaneEventExport.init)
            conversationReadStates = conversationReadStateValues
            momentReadStates = momentReadStateValues
            let normalizedMemoryValues = memoryValues.map {
                DataMergeService.normalizedMemoryExport(AyaneMemoryExport($0))
            }
            let activeMemoryGroups = Dictionary(
                grouping: normalizedMemoryValues.filter {
                    $0.stateRaw == MemoryState.active.rawValue
                },
                by: { scopedCanonicalKey($0) }
            )
            for (scopedKey, records) in activeMemoryGroups
                where !scopedKey.isEmpty && records.count > Self.maximumActiveMemoriesPerCanonicalKey {
                throw DataMergeError.invalidValue(
                    "目标存储的规范键 \(scopedKey) 同时存在过多有效版本，请先完成重复协调。"
                )
            }
            memories = normalizedMemoryValues
            evidence = evidenceValues.map(AyaneEvidenceExport.init)
            summaries = summaryValues.map(AyaneSummaryExport.init)
            tombstones = tombstoneValues.map(AyaneTombstoneExport.init)
            groupConversations = groupConversationValues
            groupParticipants = groupParticipantValues

            profileObjects = Dictionary(uniqueKeysWithValues: profileValues.map { ($0.id, $0) })
            userProfileObject = userProfileRecord
            momentPostObjects = Dictionary(uniqueKeysWithValues: momentPostRecords.map { ($0.id, $0) })
            momentInteractionObjects = Dictionary(uniqueKeysWithValues: momentInteractionRecords.map { ($0.id, $0) })
            momentAIInteractionTaskObjects = Dictionary(
                uniqueKeysWithValues: momentAIInteractionTaskRecords.map { ($0.id, $0) }
            )
            relationshipObjects = Dictionary(uniqueKeysWithValues: relationshipValues.map { ($0.roleID, $0) })
            transitionObjects = Dictionary(uniqueKeysWithValues: transitionValues.map { ($0.id, $0) })
            momentTaskObjects = Dictionary(uniqueKeysWithValues: momentTaskValues.map { ($0.id, $0) })
            conversationObjects = Dictionary(uniqueKeysWithValues: conversationValues.map { ($0.id, $0) })
            eventObjects = Dictionary(uniqueKeysWithValues: eventValues.map { ($0.id, $0) })
            conversationReadStateObjects = Dictionary(uniqueKeysWithValues: conversationReadStateRecords.map {
                (
                    ConversationReadStateScope(
                        roleID: $0.resolvedRoleID,
                        conversationID: $0.conversationID
                    ),
                    $0
                )
            })
            momentReadStateObjects = Dictionary(uniqueKeysWithValues: momentReadStateRecords.map {
                ($0.postID, $0)
            })
            self.conversationReadStateIdentityByID = conversationReadStateIdentityByID
            self.momentReadStateIdentityByID = momentReadStateIdentityByID
            memoryObjects = Dictionary(uniqueKeysWithValues: memoryValues.map { ($0.id, $0) })
            evidenceObjects = Dictionary(uniqueKeysWithValues: evidenceValues.map { ($0.id, $0) })
            summaryObjects = Dictionary(uniqueKeysWithValues: summaryValues.map { ($0.id, $0) })
            tombstoneObjects = Dictionary(uniqueKeysWithValues: tombstoneValues.map { ($0.id, $0) })
        }

        private struct RecordCollector<Record: AnyObject> {
            private var objectIDs = Set<ObjectIdentifier>()
            private(set) var values: [Record] = []

            mutating func append(contentsOf records: [Record]) {
                for record in records where objectIDs.insert(ObjectIdentifier(record)).inserted {
                    values.append(record)
                }
            }
        }

        private static let profileProperties: [PartialKeyPath<CompanionProfileRecord>] = [
            \CompanionProfileRecord.id,
            \CompanionProfileRecord.worldProfileID,
            \CompanionProfileRecord.name,
            \CompanionProfileRecord.userName,
            \CompanionProfileRecord.prompt,
            \CompanionProfileRecord.birthdayMonth,
            \CompanionProfileRecord.birthdayDay,
            \CompanionProfileRecord.createdAt,
            \CompanionProfileRecord.updatedAt,
            \CompanionProfileRecord.revision,
            \CompanionProfileRecord.deviceID
        ]

        private static let conversationProperties: [PartialKeyPath<ConversationRecord>] = [
            \ConversationRecord.id,
            \ConversationRecord.roleID,
            \ConversationRecord.title,
            \ConversationRecord.createdAt,
            \ConversationRecord.updatedAt,
            \ConversationRecord.archived
        ]

        private static let eventProperties: [PartialKeyPath<ConversationEvent>] = [
            \ConversationEvent.id,
            \ConversationEvent.roleID,
            \ConversationEvent.conversationID,
            \ConversationEvent.deviceID,
            \ConversationEvent.deviceSequence,
            \ConversationEvent.logicalTimestamp,
            \ConversationEvent.occurredAt,
            \ConversationEvent.recordedAt,
            \ConversationEvent.roleRaw,
            \ConversationEvent.content,
            \ConversationEvent.contentHash,
            \ConversationEvent.payloadKindRaw,
            \ConversationEvent.stickerID,
            \ConversationEvent.imageData,
            \ConversationEvent.fileName,
            \ConversationEvent.fileTypeIdentifier,
            \ConversationEvent.fileData,
            \ConversationEvent.senderRoleID,
            \ConversationEvent.parentEventID,
            \ConversationEvent.deliveryStateRaw,
            \ConversationEvent.redacted,
            \ConversationEvent.memoryProcessedAt,
            \ConversationEvent.memoryProcessingVersion
        ]

        // A memory canonical group is explicitly in the merge scope. Fetch
        // its full scalar state so a canonical convergence update can preserve
        // embeddings; unrelated groups are never fetched at all.
        private static let memoryProperties: [PartialKeyPath<MemoryAssertionRecord>] = [
            \MemoryAssertionRecord.id,
            \MemoryAssertionRecord.roleID,
            \MemoryAssertionRecord.kindRaw,
            \MemoryAssertionRecord.subject,
            \MemoryAssertionRecord.predicate,
            \MemoryAssertionRecord.value,
            \MemoryAssertionRecord.canonicalKey,
            \MemoryAssertionRecord.stateRaw,
            \MemoryAssertionRecord.confidence,
            \MemoryAssertionRecord.importance,
            \MemoryAssertionRecord.sensitive,
            \MemoryAssertionRecord.sourceRank,
            \MemoryAssertionRecord.validFrom,
            \MemoryAssertionRecord.validTo,
            \MemoryAssertionRecord.observedAt,
            \MemoryAssertionRecord.supersedesID,
            \MemoryAssertionRecord.extractorID,
            \MemoryAssertionRecord.schemaVersion,
            \MemoryAssertionRecord.createdAt,
            \MemoryAssertionRecord.updatedAt,
            \MemoryAssertionRecord.isPinned,
            \MemoryAssertionRecord.userVerified,
            \MemoryAssertionRecord.embeddingData,
            \MemoryAssertionRecord.embeddingModelID,
            \MemoryAssertionRecord.deviceID
        ]

        private static let evidenceProperties: [PartialKeyPath<MemoryEvidenceRecord>] = [
            \MemoryEvidenceRecord.id,
            \MemoryEvidenceRecord.roleID,
            \MemoryEvidenceRecord.memoryID,
            \MemoryEvidenceRecord.eventID,
            \MemoryEvidenceRecord.startUTF16,
            \MemoryEvidenceRecord.endUTF16,
            \MemoryEvidenceRecord.relationRaw,
            \MemoryEvidenceRecord.quoteHash,
            \MemoryEvidenceRecord.confidence,
            \MemoryEvidenceRecord.createdAt
        ]

        private static let summaryProperties: [PartialKeyPath<MemorySummaryRecord>] = [
            \MemorySummaryRecord.id,
            \MemorySummaryRecord.roleID,
            \MemorySummaryRecord.conversationID,
            \MemorySummaryRecord.scope,
            \MemorySummaryRecord.content,
            \MemorySummaryRecord.firstEventID,
            \MemorySummaryRecord.lastEventID,
            \MemorySummaryRecord.coveredEventCount,
            \MemorySummaryRecord.extractorID,
            \MemorySummaryRecord.createdAt,
            \MemorySummaryRecord.updatedAt
        ]

        private static let tombstoneProperties: [PartialKeyPath<MemoryTombstoneRecord>] = [
            \MemoryTombstoneRecord.id,
            \MemoryTombstoneRecord.roleID,
            \MemoryTombstoneRecord.entityID,
            \MemoryTombstoneRecord.entityType,
            \MemoryTombstoneRecord.canonicalKey,
            \MemoryTombstoneRecord.canonicalKeyNormalizationVersion,
            \MemoryTombstoneRecord.sourceEventIDsRaw,
            \MemoryTombstoneRecord.deletedAt,
            \MemoryTombstoneRecord.deviceID,
            \MemoryTombstoneRecord.reason
        ]

        private static func fetchProfiles(
            context: ModelContext
        ) throws -> [CompanionProfileRecord] {
            // v6 stores one profile row per logical role.  The old singleton
            // predicate silently dropped every non-legacy profile.
            var descriptor = FetchDescriptor<CompanionProfileRecord>()
            descriptor.propertiesToFetch = profileProperties
            return try context.fetch(descriptor)
        }

        private static func fetchUserProfiles(
            context: ModelContext
        ) throws -> [UserProfileRecord] {
            try context.fetch(FetchDescriptor<UserProfileRecord>())
        }

        private static func fetchMomentPosts(
            context: ModelContext
        ) throws -> [MomentPostRecord] {
            try context.fetch(FetchDescriptor<MomentPostRecord>())
        }

        private static func fetchMomentInteractions(
            context: ModelContext
        ) throws -> [MomentInteractionRecord] {
            try context.fetch(FetchDescriptor<MomentInteractionRecord>())
        }

        private static func fetchConversations(
            ids: [UUID],
            context: ModelContext
        ) throws -> [ConversationRecord] {
            var records: [ConversationRecord] = []
            for id in ids {
                var descriptor = FetchDescriptor<ConversationRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = conversationProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchEvents(
            ids: [UUID],
            context: ModelContext
        ) throws -> [ConversationEvent] {
            var records: [ConversationEvent] = []
            for id in ids {
                var descriptor = FetchDescriptor<ConversationEvent>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = eventProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchMemories(
            ids: [UUID],
            context: ModelContext
        ) throws -> [MemoryAssertionRecord] {
            var records: [MemoryAssertionRecord] = []
            for id in ids {
                var descriptor = FetchDescriptor<MemoryAssertionRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = memoryProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchMemories(
            canonicalKey: String,
            roleID: UUID,
            context: ModelContext
        ) throws -> [MemoryAssertionRecord] {
            let activeState = MemoryState.active.rawValue
            let legacyRoleID = RoleScope.legacyRoleID
            let includeLegacyNilRows = roleID == legacyRoleID
            var descriptor = FetchDescriptor<MemoryAssertionRecord>(
                predicate: #Predicate {
                    $0.canonicalKey == canonicalKey
                        && $0.stateRaw == activeState
                        && ($0.roleID == roleID
                            || (includeLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\MemoryAssertionRecord.updatedAt, order: .reverse),
                    SortDescriptor(\MemoryAssertionRecord.id, order: .reverse)
                ]
            )
            // Canonical convergence can only change currently active rows.
            // Superseded/forgotten history remains durable but its potentially
            // large embedding blobs never enter a small merge snapshot.
            descriptor.fetchLimit = maximumActiveMemoriesPerCanonicalKey + 1
            descriptor.propertiesToFetch = memoryProperties
            let records = try context.fetch(descriptor)
            guard records.count <= maximumActiveMemoriesPerCanonicalKey else {
                throw DataMergeError.invalidValue(
                    "目标存储的规范键 \(canonicalKey) 同时存在过多有效版本，请先完成重复协调。"
                )
            }
            return records
        }

        private static func fetchEvidence(
            ids: [UUID],
            context: ModelContext
        ) throws -> [MemoryEvidenceRecord] {
            var records: [MemoryEvidenceRecord] = []
            for id in ids {
                var descriptor = FetchDescriptor<MemoryEvidenceRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = evidenceProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchSummaries(
            ids: [UUID],
            context: ModelContext
        ) throws -> [MemorySummaryRecord] {
            var records: [MemorySummaryRecord] = []
            for id in ids {
                var descriptor = FetchDescriptor<MemorySummaryRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = summaryProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchTombstones(
            ids: [UUID],
            context: ModelContext
        ) throws -> [MemoryTombstoneRecord] {
            var records: [MemoryTombstoneRecord] = []
            for id in ids {
                var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                    predicate: #Predicate { $0.id == id }
                )
                descriptor.propertiesToFetch = tombstoneProperties
                records.append(contentsOf: try context.fetch(descriptor))
            }
            return records
        }

        private static func fetchTombstones(
            canonicalKey: String,
            roleID: UUID,
            context: ModelContext
        ) throws -> [MemoryTombstoneRecord] {
            let entityType = "memory"
            let legacyRoleID = RoleScope.legacyRoleID
            let includeLegacyNilRows = roleID == legacyRoleID
            var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.entityType == entityType
                        && $0.canonicalKey == canonicalKey
                        && ($0.roleID == roleID
                            || (includeLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [
                    SortDescriptor(\MemoryTombstoneRecord.deletedAt, order: .reverse),
                    SortDescriptor(\MemoryTombstoneRecord.id, order: .reverse)
                ]
            )
            // For canonical-key suppression the newest barrier dominates all
            // older markers. Incoming/identity-linked tombstones are fetched
            // separately by UUID and therefore are not hidden by this bound.
            descriptor.fetchLimit = 1
            descriptor.propertiesToFetch = tombstoneProperties
            return try context.fetch(descriptor)
        }

        private static func fetchNewestGlobalTombstone(
            roleID: UUID,
            context: ModelContext
        ) throws -> [MemoryTombstoneRecord] {
            let entityType = "memory"
            let emptyKey = ""
            let legacyRoleID = RoleScope.legacyRoleID
            let includeLegacyNilRows = roleID == legacyRoleID
            var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                predicate: #Predicate {
                    $0.entityType == entityType
                        && $0.canonicalKey == emptyKey
                        && ($0.roleID == roleID
                            || (includeLegacyNilRows && $0.roleID == nil))
                },
                sortBy: [SortDescriptor(\MemoryTombstoneRecord.deletedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            descriptor.propertiesToFetch = tombstoneProperties
            return try context.fetch(descriptor)
        }

        private static func canonicalConversationReadStateRecords(
            _ records: [ConversationReadStateRecord]
        ) throws -> [ConversationReadStateRecord] {
            var winners: [ConversationReadStateScope: ConversationReadStateRecord] = [:]
            for record in records {
                let scope = ConversationReadStateScope(
                    roleID: record.resolvedRoleID,
                    conversationID: record.conversationID
                )
                if let current = winners[scope] {
                    if ReadStateService.isNewer(record, than: current) {
                        winners[scope] = record
                    }
                } else {
                    winners[scope] = record
                }
            }
            return winners.values.sorted {
                let lhs = ConversationReadStateScope(
                    roleID: $0.resolvedRoleID,
                    conversationID: $0.conversationID
                )
                let rhs = ConversationReadStateScope(
                    roleID: $1.resolvedRoleID,
                    conversationID: $1.conversationID
                )
                if lhs.roleID != rhs.roleID {
                    return lhs.roleID.uuidString.lowercased() < rhs.roleID.uuidString.lowercased()
                }
                return lhs.conversationID.uuidString.lowercased()
                    < rhs.conversationID.uuidString.lowercased()
            }
        }

        private static func canonicalMomentReadStateRecords(
            _ records: [MomentReadStateRecord]
        ) throws -> [MomentReadStateRecord] {
            var winners: [UUID: MomentReadStateRecord] = [:]
            for record in records {
                if let current = winners[record.postID] {
                    if ReadStateService.isNewer(record, than: current) {
                        winners[record.postID] = record
                    }
                } else {
                    winners[record.postID] = record
                }
            }
            return winners.values.sorted {
                $0.postID.uuidString.lowercased() < $1.postID.uuidString.lowercased()
            }
        }

        private static func ensureUnique(
            _ ids: [UUID],
            entity: DataMergeEntity,
            target: Bool
        ) throws {
            let counts = Dictionary(grouping: ids, by: { $0 }).compactMapValues { values in
                values.count > 1 ? values.count : nil
            }
            guard counts.isEmpty else {
                if target {
                    throw DataMergeError.duplicateTargetIDs(
                        entity: entity,
                        ids: counts.keys.sorted(by: stableUUIDLess)
                    )
                }
                throw DataMergeError.duplicateSourceIDs(entity: entity)
            }
        }

        private static func ensureUnique<Key: Hashable>(
            _ ids: [Key],
            entity: DataMergeEntity,
            target: Bool
        ) throws {
            guard Set(ids).count == ids.count else {
                // Non-UUID logical keys are only used after their physical
                // rows have been canonicalized. Keep the failure typed as a
                // value error instead of manufacturing an unrelated UUID.
                throw DataMergeError.invalidValue(
                    "目标存储包含重复的\(entity.rawValue)逻辑作用域。"
                )
            }
        }
    }

    @MainActor
    private struct MergePlan {
        var profileInserts: [AyanePersonaExport] = []
        var profileUpdates: [(CompanionProfileRecord, AyanePersonaExport)] = []
        var userProfileInsert: AyaneUserProfileExport? = nil
        var userProfileUpdate: (UserProfileRecord, AyaneUserProfileExport)? = nil
        var momentPostInserts: [AyaneMomentPostExport] = []
        var momentPostUpdates: [(MomentPostRecord, AyaneMomentPostExport)] = []
        var momentInteractionInserts: [AyaneMomentInteractionExport] = []
        var momentInteractionUpdates: [(MomentInteractionRecord, AyaneMomentInteractionExport)] = []
        var momentAIInteractionTaskInserts: [AyaneMomentAIInteractionTaskExport] = []
        var momentAIInteractionTaskUpdates: [
            (MomentAIInteractionTaskRecord, AyaneMomentAIInteractionTaskExport)
        ] = []
        var relationshipInserts: [AyaneRelationshipExport] = []
        var relationshipUpdates: [(CompanionRelationshipRecord, AyaneRelationshipExport)] = []
        var transitionInserts: [AyaneRelationshipTransitionExport] = []
        var momentTaskInserts: [AyaneMomentTaskExport] = []
        var momentTaskUpdates: [(CompanionMomentTaskRecord, AyaneMomentTaskExport)] = []
        var conversationInserts: [AyaneConversationExport] = []
        var conversationUpdates: [(ConversationRecord, AyaneConversationExport)] = []
        var eventInserts: [AyaneEventExport] = []
        var eventUpdates: [(ConversationEvent, AyaneEventExport)] = []
        var conversationReadStateInserts: [AyaneConversationReadStateExport] = []
        var conversationReadStateUpdates: [(ConversationReadStateRecord, AyaneConversationReadStateExport)] = []
        var momentReadStateInserts: [AyaneMomentReadStateExport] = []
        var momentReadStateUpdates: [(MomentReadStateRecord, AyaneMomentReadStateExport)] = []
        var memoryInserts: [AyaneMemoryExport] = []
        var memoryUpdates: [(MemoryAssertionRecord, AyaneMemoryExport)] = []
        var evidenceInserts: [AyaneEvidenceExport] = []
        var evidenceUpdates: [(MemoryEvidenceRecord, AyaneEvidenceExport)] = []
        var summaryInserts: [AyaneSummaryExport] = []
        var summaryUpdates: [(MemorySummaryRecord, AyaneSummaryExport)] = []
        var tombstoneInserts: [AyaneTombstoneExport] = []
        var tombstoneUpdates: [(MemoryTombstoneRecord, AyaneTombstoneExport)] = []

        let report: DataMergeReport

        init(payload: AyaneDataExport, target: TargetSnapshot) throws {
            try DataMergeService.validateSource(payload)
            let groupIndex = GroupBackupValidationIndex(payload)

            var finalProfiles = Dictionary(
                uniqueKeysWithValues: target.profiles.map {
                    (DataMergeService.resolvedRoleID($0.roleID), $0)
                }
            )
            var finalUserProfile = target.userProfile
            var finalMomentPosts = Dictionary(
                uniqueKeysWithValues: target.momentPosts.map { ($0.id, $0) }
            )
            var finalMomentInteractions = Dictionary(
                uniqueKeysWithValues: target.momentInteractions.map { ($0.id, $0) }
            )
            var finalMomentAIInteractionTasks = Dictionary(
                uniqueKeysWithValues: target.momentAIInteractionTasks.map {
                    (DataMergeService.momentAIInteractionTaskKey($0), $0)
                }
            )
            var finalRelationships = Dictionary(
                uniqueKeysWithValues: target.relationships.map { ($0.roleID, $0) }
            )
            var finalTransitions = Dictionary(
                uniqueKeysWithValues: target.transitions.map { ($0.id, $0) }
            )
            var finalMomentTasks = Dictionary(
                uniqueKeysWithValues: target.momentTasks.map { ($0.id, $0) }
            )
            var finalConversations = Dictionary(
                uniqueKeysWithValues: target.conversations.map { ($0.id, $0) }
            )
            var finalEvents = Dictionary(uniqueKeysWithValues: target.events.map { ($0.id, $0) })
            var finalConversationReadStates = Dictionary(uniqueKeysWithValues: target.conversationReadStates.map {
                (
                    ConversationReadStateScope(
                        roleID: DataMergeService.resolvedRoleID($0.roleID),
                        conversationID: $0.conversationID
                    ),
                    $0
                )
            })
            var finalMomentReadStates = Dictionary(uniqueKeysWithValues: target.momentReadStates.map {
                ($0.postID, $0)
            })
            var finalMemories = Dictionary(uniqueKeysWithValues: target.memories.map { ($0.id, $0) })
            var finalEvidence = Dictionary(uniqueKeysWithValues: target.evidence.map { ($0.id, $0) })
            var finalSummaries = Dictionary(uniqueKeysWithValues: target.summaries.map { ($0.id, $0) })
            var finalTombstones = Dictionary(uniqueKeysWithValues: target.tombstones.map { ($0.id, $0) })

            var profileCounts = CountsBuilder()
            var userProfileCounts = CountsBuilder()
            var momentPostCounts = CountsBuilder()
            var momentInteractionCounts = CountsBuilder()
            var momentAIInteractionTaskCounts = CountsBuilder()
            var relationshipCounts = CountsBuilder()
            var transitionCounts = CountsBuilder()
            var momentTaskCounts = CountsBuilder()
            var conversationCounts = CountsBuilder()
            var eventCounts = CountsBuilder()
            var conversationReadStateCounts = CountsBuilder()
            var momentReadStateCounts = CountsBuilder()
            var memoryCounts = CountsBuilder()
            var evidenceCounts = CountsBuilder()
            var summaryCounts = CountsBuilder()
            var tombstoneCounts = CountsBuilder()

            // v6 carries one profile per role.  Profile identity is the
            // resolved role ID, not the compatibility `persona` projection.
            for incoming in payload.profiles {
                let roleID = DataMergeService.resolvedRoleID(incoming.roleID)
                if let current = finalProfiles[roleID] {
                    let selected = DataMergeService.newerProfile(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.profileObjects[roleID] else {
                            throw DataMergeError.invalidValue("目标角色对象索引不一致。")
                        }
                        finalProfiles[roleID] = selected
                        profileUpdates.append((object, selected))
                        profileCounts.updated += 1
                    } else {
                        profileCounts.unchanged += 1
                    }
                } else {
                    finalProfiles[roleID] = incoming
                    profileInserts.append(incoming)
                    profileCounts.inserted += 1
                }
            }

            if let incoming = payload.userProfile {
                if let current = finalUserProfile {
                    let selected = DataMergeService.newerUserProfile(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.userProfileObject else {
                            throw DataMergeError.invalidValue("目标用户资料对象索引不一致。")
                        }
                        finalUserProfile = selected
                        userProfileUpdate = (object, selected)
                        userProfileCounts.updated += 1
                    } else {
                        userProfileCounts.unchanged += 1
                    }
                } else {
                    finalUserProfile = incoming
                    userProfileInsert = incoming
                    userProfileCounts.inserted += 1
                }
            }

            for incoming in payload.momentPosts {
                let roleID = incoming.authorRoleID.map(DataMergeService.resolvedRoleID)
                if let roleID, finalProfiles[roleID] == nil {
                    throw DataMergeError.invalidReference("朋友圈 \(incoming.id) 的作者角色不存在。")
                }
                if let current = finalMomentPosts[incoming.id] {
                    guard DataMergeService.sameMomentPostIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .momentPost, id: incoming.id)
                    }
                    let selected = DataMergeService.newerMomentPost(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.momentPostObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标朋友圈对象索引不一致。")
                        }
                        finalMomentPosts[incoming.id] = selected
                        momentPostUpdates.append((object, selected))
                        momentPostCounts.updated += 1
                    } else {
                        momentPostCounts.unchanged += 1
                    }
                } else {
                    finalMomentPosts[incoming.id] = incoming
                    momentPostInserts.append(incoming)
                    momentPostCounts.inserted += 1
                }
            }

            for incoming in payload.momentInteractions {
                guard finalMomentPosts[incoming.postID] != nil else {
                    throw DataMergeError.invalidReference("朋友圈互动 \(incoming.id) 的帖子不存在。")
                }
                if let current = finalMomentInteractions[incoming.id] {
                    guard DataMergeService.sameMomentInteractionIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .momentInteraction, id: incoming.id)
                    }
                    let selected = DataMergeService.newerMomentInteraction(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.momentInteractionObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标朋友圈互动对象索引不一致。")
                        }
                        finalMomentInteractions[incoming.id] = selected
                        momentInteractionUpdates.append((object, selected))
                        momentInteractionCounts.updated += 1
                    } else {
                        momentInteractionCounts.unchanged += 1
                    }
                } else {
                    finalMomentInteractions[incoming.id] = incoming
                    momentInteractionInserts.append(incoming)
                    momentInteractionCounts.inserted += 1
                }
            }

            for incoming in payload.momentAIInteractionTasks {
                let key = DataMergeService.momentAIInteractionTaskKey(incoming)
                try DataMergeService.validateMomentAIInteractionTaskReferences(
                    incoming,
                    posts: finalMomentPosts,
                    interactions: finalMomentInteractions,
                    profiles: finalProfiles
                )

                if let targetByID = target.momentAIInteractionTaskObjects[incoming.id],
                   DataMergeService.momentAIInteractionTaskKey(
                       AyaneMomentAIInteractionTaskExport(targetByID)
                   ) != key {
                    throw DataMergeError.identityConflict(
                        entity: .momentAIInteractionTask,
                        id: incoming.id
                    )
                }

                if let current = finalMomentAIInteractionTasks[key] {
                    guard DataMergeService.sameMomentAIInteractionTaskIdentity(
                        current,
                        incoming
                    ) else {
                        throw DataMergeError.identityConflict(
                            entity: .momentAIInteractionTask,
                            id: incoming.id
                        )
                    }
                    let selected = try DataMergeService.mergeMomentAIInteractionTask(
                        current: current,
                        incoming: incoming
                    )
                    let applied = DataMergeService.withID(
                        selected,
                        id: current.id
                    )
                    if applied != current {
                        guard let object = target.momentAIInteractionTaskObjects[current.id] else {
                            throw DataMergeError.invalidValue(
                                "目标朋友圈互动任务对象索引不一致。"
                            )
                        }
                        finalMomentAIInteractionTasks[key] = applied
                        momentAIInteractionTaskUpdates.append((object, applied))
                        momentAIInteractionTaskCounts.updated += 1
                    } else {
                        momentAIInteractionTaskCounts.unchanged += 1
                    }
                } else {
                    finalMomentAIInteractionTasks[key] = incoming
                    momentAIInteractionTaskInserts.append(incoming)
                    momentAIInteractionTaskCounts.inserted += 1
                }
            }

            for incoming in payload.relationships {
                let roleID = incoming.roleID
                guard finalProfiles[roleID] != nil else {
                    throw DataMergeError.invalidReference("关系 \(incoming.id) 的角色不存在。")
                }
                if let current = finalRelationships[roleID] {
                    let selected = DataMergeService.newerRelationship(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.relationshipObjects[roleID] else {
                            throw DataMergeError.invalidValue("目标关系对象索引不一致。")
                        }
                        finalRelationships[roleID] = selected
                        relationshipUpdates.append((object, selected))
                        relationshipCounts.updated += 1
                    } else {
                        relationshipCounts.unchanged += 1
                    }
                } else {
                    finalRelationships[roleID] = incoming
                    relationshipInserts.append(incoming)
                    relationshipCounts.inserted += 1
                }
            }

            for incoming in payload.transitions {
                guard finalProfiles[incoming.roleID] != nil else {
                    throw DataMergeError.invalidReference("关系变更 \(incoming.id) 的角色不存在。")
                }
                if let current = finalTransitions[incoming.id] {
                    guard DataMergeService.sameTransitionIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .transition, id: incoming.id)
                    }
                    transitionCounts.unchanged += 1
                } else {
                    finalTransitions[incoming.id] = incoming
                    transitionInserts.append(incoming)
                    transitionCounts.inserted += 1
                }
            }

            for incoming in payload.momentTasks {
                let roleID = DataMergeService.resolvedRoleID(incoming.roleID)
                guard finalProfiles[roleID] != nil else {
                    throw DataMergeError.invalidReference("朋友圈任务的角色不存在。")
                }
                if let current = finalMomentTasks[incoming.id] {
                    guard current.roleID == roleID else {
                        throw DataMergeError.identityConflict(entity: .momentTask, id: incoming.id)
                    }
                    let selected = try DataMergeService.mergeMomentTask(
                        current: current,
                        incoming: incoming
                    )
                    if selected != current {
                        guard let object = target.momentTaskObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标朋友圈任务对象索引不一致。")
                        }
                        finalMomentTasks[incoming.id] = selected
                        momentTaskUpdates.append((object, selected))
                        momentTaskCounts.updated += 1
                    } else {
                        momentTaskCounts.unchanged += 1
                    }
                } else {
                    finalMomentTasks[incoming.id] = incoming
                    momentTaskInserts.append(incoming)
                    momentTaskCounts.inserted += 1
                }
            }

            for incoming in payload.conversations {
                if let current = finalConversations[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .conversation, id: incoming.id)
                    }
                    let selected = DataMergeService.newerConversation(current: current, incoming: incoming)
                    if selected != current {
                        guard let object = target.conversationObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标会话对象索引不一致。")
                        }
                        finalConversations[incoming.id] = selected
                        conversationUpdates.append((object, selected))
                        conversationCounts.updated += 1
                    } else {
                        conversationCounts.unchanged += 1
                    }
                } else {
                    finalConversations[incoming.id] = incoming
                    conversationInserts.append(incoming)
                    conversationCounts.inserted += 1
                }
            }

            for incoming in payload.events {
                if let current = finalEvents[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .event, id: incoming.id)
                    }
                    guard DataMergeService.sameEventIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .event, id: incoming.id)
                    }
                    let selected = DataMergeService.mergeEvent(current: current, incoming: incoming)
                    if selected != current {
                        guard let object = target.eventObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标事件对象索引不一致。")
                        }
                        finalEvents[incoming.id] = selected
                        eventUpdates.append((object, selected))
                        eventCounts.updated += 1
                    } else {
                        eventCounts.unchanged += 1
                    }
                } else {
                    finalEvents[incoming.id] = incoming
                    eventInserts.append(incoming)
                    eventCounts.inserted += 1
                }
            }

            for incoming in payload.conversationReadStates {
                guard let roleID = incoming.roleID.map(DataMergeService.resolvedRoleID) else {
                    throw DataMergeError.invalidReference(
                        "会话已读状态 \(incoming.id) 缺少角色。"
                    )
                }
                let scope = ConversationReadStateScope(
                    roleID: roleID,
                    conversationID: incoming.conversationID
                )
                if let targetScope = target.conversationReadStateIdentityByID[incoming.id],
                   targetScope != scope {
                    throw DataMergeError.identityConflict(
                        entity: .conversationReadState,
                        id: incoming.id
                    )
                }
                guard let conversation = finalConversations[incoming.conversationID],
                      DataMergeService.resolvedRoleID(conversation.roleID) == roleID else {
                    throw DataMergeError.invalidReference(
                        "会话已读状态 \(incoming.id) 的会话或角色不存在。"
                    )
                }
                if let eventID = incoming.lastReadEventID {
                    guard let event = finalEvents[eventID],
                          event.conversationID == incoming.conversationID,
                          groupIndex.eventMatchesConversation(
                              event,
                              conversation: conversation
                          ),
                          (groupIndex.isGroupConversation(incoming.conversationID)
                              ? DataMergeService.resolvedRoleID(conversation.roleID) == roleID
                              : DataMergeService.resolvedRoleID(event.roleID) == roleID) else {
                        throw DataMergeError.invalidReference(
                            "会话已读状态 \(incoming.id) 的游标事件不存在或跨角色。"
                        )
                    }
                }

                if let current = finalConversationReadStates[scope] {
                    guard DataMergeService.resolvedRoleID(current.roleID) == roleID,
                          current.conversationID == incoming.conversationID else {
                        throw DataMergeError.identityConflict(
                            entity: .conversationReadState,
                            id: incoming.id
                        )
                    }
                    let selected = DataMergeService.newerConversationReadState(
                        current: current,
                        incoming: incoming
                    )
                    // The logical identity is the destination scope. Keep
                    // the existing physical row UUID when a source marker
                    // from another device wins, so the merge cannot create a
                    // second row merely because its export UUID differs.
                    let applied = DataMergeService.withID(
                        selected,
                        id: current.id
                    )
                    if applied != current {
                        guard let object = target.conversationReadStateObjects[scope] else {
                            throw DataMergeError.invalidValue(
                                "目标会话已读状态对象索引不一致。"
                            )
                        }
                        finalConversationReadStates[scope] = applied
                        conversationReadStateUpdates.append((object, applied))
                        conversationReadStateCounts.updated += 1
                    } else {
                        conversationReadStateCounts.unchanged += 1
                    }
                } else {
                    finalConversationReadStates[scope] = incoming
                    conversationReadStateInserts.append(incoming)
                    conversationReadStateCounts.inserted += 1
                }
            }

            for incoming in payload.momentReadStates {
                if let targetPostID = target.momentReadStateIdentityByID[incoming.id],
                   targetPostID != incoming.postID {
                    throw DataMergeError.identityConflict(
                        entity: .momentReadState,
                        id: incoming.id
                    )
                }
                guard let post = finalMomentPosts[incoming.postID],
                      (post.authorKind == .user || post.authorKind == .companion) else {
                    throw DataMergeError.invalidReference(
                        "朋友圈已读状态 \(incoming.id) 的帖子不存在或类型无效。"
                    )
                }
                if let interactionID = incoming.lastReadInteractionID {
                    guard let interaction = finalMomentInteractions[interactionID],
                          interaction.postID == incoming.postID else {
                        throw DataMergeError.invalidReference(
                            "朋友圈已读状态 \(incoming.id) 的游标互动不存在或帖子不匹配。"
                        )
                    }
                }

                if let current = finalMomentReadStates[incoming.postID] {
                    guard current.postID == incoming.postID else {
                        throw DataMergeError.identityConflict(
                            entity: .momentReadState,
                            id: incoming.id
                        )
                    }
                    let selected = DataMergeService.newerMomentReadState(
                        current: current,
                        incoming: incoming
                    )
                    let applied = DataMergeService.withID(
                        selected,
                        id: current.id
                    )
                    if applied != current {
                        guard let object = target.momentReadStateObjects[incoming.postID] else {
                            throw DataMergeError.invalidValue(
                                "目标朋友圈已读状态对象索引不一致。"
                            )
                        }
                        finalMomentReadStates[incoming.postID] = applied
                        momentReadStateUpdates.append((object, applied))
                        momentReadStateCounts.updated += 1
                    } else {
                        momentReadStateCounts.unchanged += 1
                    }
                } else {
                    finalMomentReadStates[incoming.postID] = incoming
                    momentReadStateInserts.append(incoming)
                    momentReadStateCounts.inserted += 1
                }
            }

            for incoming in payload.memories {
                if let current = finalMemories[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .memory, id: incoming.id)
                    }
                    let selected = DataMergeService.newerMemory(current: current, incoming: incoming)
                    if selected != current {
                        finalMemories[incoming.id] = selected
                    }
                } else {
                    finalMemories[incoming.id] = incoming
                }
            }

            for incoming in payload.evidence {
                if let current = finalEvidence[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .evidence, id: incoming.id)
                    }
                    guard DataMergeService.sameEvidenceIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .evidence, id: incoming.id)
                    }
                    let selected = DataMergeService.mergeEvidence(current: current, incoming: incoming)
                    if selected != current {
                        guard let object = target.evidenceObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标证据对象索引不一致。")
                        }
                        finalEvidence[incoming.id] = selected
                        evidenceUpdates.append((object, selected))
                        evidenceCounts.updated += 1
                    } else {
                        evidenceCounts.unchanged += 1
                    }
                } else {
                    finalEvidence[incoming.id] = incoming
                    evidenceInserts.append(incoming)
                    evidenceCounts.inserted += 1
                }
            }

            for incoming in payload.summaries {
                if let current = finalSummaries[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .summary, id: incoming.id)
                    }
                    let selected = DataMergeService.newerSummary(current: current, incoming: incoming)
                    if selected != current {
                        guard let object = target.summaryObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标摘要对象索引不一致。")
                        }
                        finalSummaries[incoming.id] = selected
                        summaryUpdates.append((object, selected))
                        summaryCounts.updated += 1
                    } else {
                        summaryCounts.unchanged += 1
                    }
                } else {
                    finalSummaries[incoming.id] = incoming
                    summaryInserts.append(incoming)
                    summaryCounts.inserted += 1
                }
            }

            for incoming in payload.tombstones {
                if let current = finalTombstones[incoming.id] {
                    guard current.roleID == incoming.roleID else {
                        throw DataMergeError.identityConflict(entity: .tombstone, id: incoming.id)
                    }
                    guard DataMergeService.sameTombstoneIdentity(current, incoming) else {
                        throw DataMergeError.identityConflict(entity: .tombstone, id: incoming.id)
                    }
                    let selected = DataMergeService.mergeTombstone(current: current, incoming: incoming)
                    if selected != current {
                        guard let object = target.tombstoneObjects[incoming.id] else {
                            throw DataMergeError.invalidValue("目标墓碑对象索引不一致。")
                        }
                        finalTombstones[incoming.id] = selected
                        tombstoneUpdates.append((object, selected))
                        tombstoneCounts.updated += 1
                    } else {
                        tombstoneCounts.unchanged += 1
                    }
                } else {
                    finalTombstones[incoming.id] = incoming
                    tombstoneInserts.append(incoming)
                    tombstoneCounts.inserted += 1
                }
            }

            // A merge can bring together records with different UUIDs but the
            // same logical key.  Keep every record for audit/history, while
            // reducing the injectable active set to one deterministic winner
            // (or to contested when there is no safe winner).  Tombstone
            // barriers are evaluated against the post-merge tombstone union.
            DataMergeService.convergeCanonicalMemoryGroups(
                &finalMemories,
                tombstones: Array(finalTombstones.values)
            )

            // Canonical convergence can update an existing target memory that
            // was not itself present in the payload.  Rebuild memory actions
            // from the final plan so staged writes exactly match validation.
            memoryInserts.removeAll(keepingCapacity: true)
            memoryUpdates.removeAll(keepingCapacity: true)
            memoryCounts = CountsBuilder()
            let sourceMemoryIDs = Set(payload.memories.map(\.id))
            for id in finalMemories.keys.sorted(by: stableUUIDLess) {
                guard let item = finalMemories[id] else { continue }
                if let record = target.memoryObjects[id] {
                    let existing = AyaneMemoryExport(record)
                    if item != existing {
                        memoryUpdates.append((record, item))
                        memoryCounts.updated += 1
                    } else if sourceMemoryIDs.contains(id) {
                        memoryCounts.unchanged += 1
                    }
                } else {
                    memoryInserts.append(item)
                    memoryCounts.inserted += 1
                }
            }

            let final = FinalRecords(
                profiles: finalProfiles.values.sorted {
                    DataMergeService.resolvedRoleID($0.roleID).uuidString
                        < DataMergeService.resolvedRoleID($1.roleID).uuidString
                },
                userProfile: finalUserProfile,
                momentPosts: finalMomentPosts.values.sorted {
                    ($0.publishedAt, $0.updatedAt, $0.id.uuidString)
                        < ($1.publishedAt, $1.updatedAt, $1.id.uuidString)
                },
                momentInteractions: finalMomentInteractions.values.sorted {
                    ($0.createdAt, $0.updatedAt, $0.id.uuidString)
                        < ($1.createdAt, $1.updatedAt, $1.id.uuidString)
                },
                momentAIInteractionTasks: finalMomentAIInteractionTasks.values.sorted {
                    DataMergeService.stableMomentAIInteractionTaskLess($0, $1)
                },
                relationships: finalRelationships.values.sorted {
                    $0.roleID.uuidString < $1.roleID.uuidString
                },
                transitions: finalTransitions.values.sorted {
                    DataMergeService.stableTransitionLess($0, $1)
                },
                momentTasks: finalMomentTasks.values.sorted {
                    DataMergeService.stableMomentTaskLess($0, $1)
                },
                conversations: Array(finalConversations.values),
                events: Array(finalEvents.values),
                conversationReadStates: Array(finalConversationReadStates.values),
                momentReadStates: Array(finalMomentReadStates.values),
                memories: Array(finalMemories.values),
                evidence: Array(finalEvidence.values),
                summaries: Array(finalSummaries.values),
                tombstones: Array(finalTombstones.values),
                groupConversations: SchemaV11DataSupport.canonicalGroupConversations(
                    target.groupConversations + payload.groupConversations
                ),
                groupParticipants: SchemaV11DataSupport.canonicalGroupParticipants(
                    target.groupParticipants + payload.groupParticipants
                )
            )
            try DataMergeService.validateFinal(final)

            report = DataMergeReport(
                profiles: profileCounts.value,
                userProfiles: userProfileCounts.value,
                momentPosts: momentPostCounts.value,
                momentInteractions: momentInteractionCounts.value,
                momentAIInteractionTasks: momentAIInteractionTaskCounts.value,
                relationships: relationshipCounts.value,
                transitions: transitionCounts.value,
                momentTasks: momentTaskCounts.value,
                conversations: conversationCounts.value,
                events: eventCounts.value,
                conversationReadStates: conversationReadStateCounts.value,
                momentReadStates: momentReadStateCounts.value,
                memories: memoryCounts.value,
                evidence: evidenceCounts.value,
                summaries: summaryCounts.value,
                tombstones: tombstoneCounts.value
            )
        }

        func apply(to context: ModelContext) throws {
            for item in profileInserts { context.insert(DataMergeService.makeProfile(item)) }
            for (record, item) in profileUpdates { DataMergeService.apply(item, to: record) }
            if let item = userProfileInsert {
                context.insert(DataMergeService.makeUserProfile(item))
            }
            if let (record, item) = userProfileUpdate {
                DataMergeService.apply(item, to: record)
            }
            for item in momentPostInserts { context.insert(DataMergeService.makeMomentPost(item)) }
            for (record, item) in momentPostUpdates {
                DataMergeService.apply(item, to: record)
            }
            for item in momentInteractionInserts {
                context.insert(DataMergeService.makeMomentInteraction(item))
            }
            for (record, item) in momentInteractionUpdates {
                DataMergeService.apply(item, to: record)
            }
            for item in momentAIInteractionTaskInserts {
                context.insert(DataMergeService.makeMomentAIInteractionTask(item))
            }
            for (record, item) in momentAIInteractionTaskUpdates {
                DataMergeService.apply(item, to: record)
            }
            for item in relationshipInserts { context.insert(DataMergeService.makeRelationship(item)) }
            for (record, item) in relationshipUpdates { DataMergeService.apply(item, to: record) }
            for item in transitionInserts { context.insert(DataMergeService.makeTransition(item)) }
            for item in momentTaskInserts { context.insert(DataMergeService.makeMomentTask(item)) }
            for (record, item) in momentTaskUpdates { DataMergeService.apply(item, to: record) }
            for item in conversationInserts { context.insert(DataMergeService.makeConversation(item)) }
            for (record, item) in conversationUpdates { DataMergeService.apply(item, to: record) }
            for item in eventInserts { context.insert(DataMergeService.makeEvent(item)) }
            for (record, item) in eventUpdates { DataMergeService.apply(item, to: record) }
            for item in conversationReadStateInserts {
                context.insert(DataMergeService.makeConversationReadState(item))
            }
            for (record, item) in conversationReadStateUpdates {
                DataMergeService.apply(item, to: record)
            }
            for item in momentReadStateInserts {
                context.insert(DataMergeService.makeMomentReadState(item))
            }
            for (record, item) in momentReadStateUpdates {
                DataMergeService.apply(item, to: record)
            }
            for item in memoryInserts { context.insert(try DataMergeService.makeMemory(item)) }
            for (record, item) in memoryUpdates { try DataMergeService.apply(item, to: record) }
            for item in evidenceInserts { context.insert(DataMergeService.makeEvidence(item)) }
            for (record, item) in evidenceUpdates { DataMergeService.apply(item, to: record) }
            for item in summaryInserts { context.insert(DataMergeService.makeSummary(item)) }
            for (record, item) in summaryUpdates { DataMergeService.apply(item, to: record) }
            for item in tombstoneInserts { context.insert(DataMergeService.makeTombstone(item)) }
            for (record, item) in tombstoneUpdates { DataMergeService.apply(item, to: record) }
        }
    }

    private struct FinalRecords {
        let profiles: [AyanePersonaExport]
        let userProfile: AyaneUserProfileExport?
        let momentPosts: [AyaneMomentPostExport]
        let momentInteractions: [AyaneMomentInteractionExport]
        let momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport]
        let relationships: [AyaneRelationshipExport]
        let transitions: [AyaneRelationshipTransitionExport]
        let momentTasks: [AyaneMomentTaskExport]
        let conversations: [AyaneConversationExport]
        let events: [AyaneEventExport]
        let conversationReadStates: [AyaneConversationReadStateExport]
        let momentReadStates: [AyaneMomentReadStateExport]
        let memories: [AyaneMemoryExport]
        let evidence: [AyaneEvidenceExport]
        let summaries: [AyaneSummaryExport]
        let tombstones: [AyaneTombstoneExport]
        let groupConversations: [AyaneGroupConversationExport]
        let groupParticipants: [AyaneGroupParticipantExport]
    }

    private struct CountsBuilder {
        var inserted = 0
        var updated = 0
        var unchanged = 0

        var value: DataMergeEntityReport {
            DataMergeEntityReport(inserted: inserted, updated: updated, unchanged: unchanged)
        }
    }

    private static func validateSource(_ payload: AyaneDataExport) throws {
        guard (4...AyaneDataExport.currentSchemaVersion).contains(payload.schemaVersion) else {
            throw DataMergeError.invalidSource("不支持的 schema_version \(payload.schemaVersion)。")
        }
        guard !payload.conversations.isEmpty else {
            throw DataMergeError.invalidSource("至少需要一个会话。")
        }
        guard !payload.profiles.isEmpty else {
            throw DataMergeError.invalidSource("至少需要一个角色。")
        }
        for profile in payload.profiles {
            try validateProfile(profile)
        }
        try validateProfile(payload.persona)
        let profileRoleIDs = payload.profiles.map { resolvedRoleID($0.roleID) }
        try ensureSourceUnique(profileRoleIDs, entity: .profile)
        guard profileRoleIDs.contains(resolvedRoleID(payload.persona.roleID)) else {
            throw DataMergeError.invalidReference("兼容 persona 未指向源角色。")
        }
        try ensureSourceUnique(payload.conversations.map(\.id), entity: .conversation)
        try ensureSourceUnique(payload.events.map(\.id), entity: .event)
        try ensureSourceUnique(payload.memories.map(\.id), entity: .memory)
        try ensureSourceUnique(payload.evidence.map(\.id), entity: .evidence)
        try ensureSourceUnique(payload.summaries.map(\.id), entity: .summary)
        try ensureSourceUnique(payload.tombstones.map(\.id), entity: .tombstone)
        try ensureSourceUnique(payload.relationships.map(\.id), entity: .relationship)
        try ensureSourceUnique(payload.relationships.map(\.roleID), entity: .relationship)
        try ensureSourceUnique(payload.transitions.map(\.id), entity: .transition)
        try ensureSourceUnique(payload.momentTasks.map(\.id), entity: .momentTask)
        try ensureSourceUnique(
            payload.momentAIInteractionTasks.map(\.id),
            entity: .momentAIInteractionTask
        )
        try ensureSourceUnique(
            payload.momentAIInteractionTasks.map(DataMergeService.momentAIInteractionTaskKey),
            entity: .momentAIInteractionTask
        )
        try ensureSourceUnique(payload.momentPosts.map(\.id), entity: .momentPost)
        try ensureSourceUnique(payload.momentInteractions.map(\.id), entity: .momentInteraction)
        try ensureSourceUnique(payload.conversationReadStates.map(\.id), entity: .conversationReadState)
        try ensureSourceUnique(payload.momentReadStates.map(\.id), entity: .momentReadState)
        try ensureSourceUnique(
            payload.conversationReadStates.map {
                ConversationReadStateScope(
                    roleID: resolvedRoleID($0.roleID),
                    conversationID: $0.conversationID
                )
            },
            entity: .conversationReadState
        )
        try ensureSourceUnique(payload.momentReadStates.map(\.postID), entity: .momentReadState)

        let eventIDs = Set(payload.events.map(\.id))
        let memoryIDs = Set(payload.memories.map(\.id))
        let conversationByID = Dictionary(
            uniqueKeysWithValues: payload.conversations.map { ($0.id, $0) }
        )
        let eventByID = Dictionary(uniqueKeysWithValues: payload.events.map { ($0.id, $0) })
        let memoryByID = Dictionary(uniqueKeysWithValues: payload.memories.map { ($0.id, $0) })
        let transitionByID = Dictionary(uniqueKeysWithValues: payload.transitions.map { ($0.id, $0) })
        let relationshipRoleIDs = Set(payload.relationships.map(\.roleID))
        let groupIndex = GroupBackupValidationIndex(payload)

        if let userProfile = payload.userProfile {
            try validateUserProfile(userProfile)
        }
        for post in payload.momentPosts {
            try validateMomentPost(post)
            let roleID = post.authorRoleID.map(resolvedRoleID)
            if post.authorKind == .companion {
                guard let roleID, profileRoleIDs.contains(roleID) else {
                    throw DataMergeError.invalidReference("朋友圈 \(post.id) 的作者角色不存在。")
                }
            } else if let roleID, !profileRoleIDs.contains(roleID) {
                throw DataMergeError.invalidReference("朋友圈 \(post.id) 的用户作者角色不存在。")
            }
        }
        for interaction in payload.momentInteractions {
            try validateMomentInteraction(interaction)
            let roleID = interaction.actorRoleID.map(resolvedRoleID)
            if interaction.actorKind == .companion {
                guard let roleID, profileRoleIDs.contains(roleID) else {
                    throw DataMergeError.invalidReference("朋友圈互动 \(interaction.id) 的作者角色不存在。")
                }
            } else if let roleID, !profileRoleIDs.contains(roleID) {
                throw DataMergeError.invalidReference("朋友圈互动 \(interaction.id) 的用户作者角色不存在。")
            }
        }

        for item in payload.relationships {
            guard profileRoleIDs.contains(item.roleID),
                  CompanionRelationshipState(rawValue: item.stateRaw) != nil,
                  item.harmStreak >= 0,
                  item.hurtScore.isFinite,
                  item.hurtScore >= 0,
                  item.harmThreshold > 0,
                  item.forgivenessScore.isFinite,
                  item.forgivenessScore >= 0,
                  item.forgivenessThreshold.isFinite,
                  item.forgivenessThreshold > 0,
                  item.dignity.isFinite,
                  (0...1).contains(item.dignity),
                  item.independence.isFinite,
                  (0...1).contains(item.independence),
                  item.boundarySensitivity.isFinite,
                  (0...1).contains(item.boundarySensitivity),
                  item.apologyAttempts >= 0,
                  item.affinityScore.isFinite,
                  (0...100).contains(item.affinityScore),
                  (0...3).contains(item.affinityTier),
                  item.affinityPolicyVersion > 0,
                  item.policyVersion > 0,
                  item.revision >= 0,
                  item.createdAt.timeIntervalSince1970.isFinite,
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidValue("关系 \(item.id) 的状态、数值或时间无效。")
            }
            if let eventID = item.lastProcessedEventID,
               let event = eventByID[eventID],
               let conversation = conversationByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: item.roleID,
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("关系 \(item.id) 的最近事件跨角色。")
            }
            if let transitionID = item.lastTransitionID,
               let transition = transitionByID[transitionID], transition.roleID != item.roleID {
                throw DataMergeError.invalidReference("关系 \(item.id) 的最近变更跨角色。")
            }
            if let eventID = item.lastAffinityEventID,
               let event = eventByID[eventID],
               let conversation = conversationByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: item.roleID,
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("关系 \(item.id) 的最近亲密度事件跨角色。")
            }
        }
        for item in payload.transitions {
            guard profileRoleIDs.contains(item.roleID),
                  relationshipRoleIDs.contains(item.roleID),
                  CompanionRelationshipState(rawValue: item.from) != nil,
                  CompanionRelationshipState(rawValue: item.to) != nil,
                  !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.scoreAfter.isFinite,
                  item.scoreAfter >= 0,
                  item.policyVersion > 0,
                  item.revision >= 0,
                  item.occurredAt.timeIntervalSince1970.isFinite else {
                throw DataMergeError.invalidValue("关系变更 \(item.id) 的状态、数值或来源无效。")
            }
            if let eventID = item.sourceEventID,
               let event = payload.events.first(where: { $0.id == eventID }),
               let conversation = conversationByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: item.roleID,
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("关系变更 \(item.id) 的来源事件跨角色。")
            }
        }
        for item in payload.momentTasks {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)) else {
                throw DataMergeError.invalidReference("朋友圈任务的角色不存在。")
            }
            try validateMomentTask(item)
        }
        for item in payload.momentAIInteractionTasks {
            try validateMomentAIInteractionTask(item)
        }

        for item in payload.conversations {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidReference("会话 \(item.id) 的角色不存在或字段无效。")
            }
        }

        for item in payload.events {
            try SchemaV11DataSupport.validateEventPayload(item)
            guard let conversation = conversationByID[item.conversationID],
                  profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  groupIndex.eventMatchesConversation(item, conversation: conversation),
                  EventRole(rawValue: item.roleRaw) != nil,
                  item.role == item.roleRaw,
                  EventDeliveryState(rawValue: item.deliveryStateRaw) != nil,
                  item.deliveryState == item.deliveryStateRaw,
                  item.deviceSequence >= 0,
                  !item.deviceID.isEmpty,
                  !item.logicalTimestamp.isEmpty,
                  item.contentHash.lowercased() == ContentHasher.sha256(item.content).lowercased() else {
                throw DataMergeError.invalidValue("事件 \(item.id) 的身份、状态或原文哈希无效。")
            }
            if let parent = item.parentEventID,
               let parentEvent = eventByID[parent],
               !groupIndex.eventMatchesRole(
                   parentEvent,
                   roleID: resolvedRoleID(item.roleID),
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("事件 \(item.id) 的父事件跨角色。")
            }
            if let parent = item.parentEventID, !eventIDs.contains(parent) {
                // A source export may reference an event already present in the
                // destination. Final validation checks the union of both stores.
                continue
            }
        }

        for item in payload.conversationReadStates {
            let roleID = resolvedRoleID(item.roleID)
            guard let conversation = conversationByID[item.conversationID],
                  resolvedRoleID(conversation.roleID) == roleID,
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.revision >= 0,
                  item.deviceID.count <= 256 else {
                throw DataMergeError.invalidReference(
                    "会话已读状态 \(item.id) 的会话、角色或字段无效。"
                )
            }
            if let occurredAt = item.lastReadOccurredAt {
                guard occurredAt.timeIntervalSince1970.isFinite else {
                    throw DataMergeError.invalidValue(
                        "会话已读状态 \(item.id) 的游标时间无效。"
                    )
                }
            }
            if let eventID = item.lastReadEventID {
                guard !item.lastReadLogicalTimestamp.isEmpty else {
                    throw DataMergeError.invalidReference(
                        "会话已读状态 \(item.id) 的游标缺少逻辑时间戳。"
                    )
                }
                guard let event = eventByID[eventID],
                      event.conversationID == item.conversationID,
                      groupIndex.eventMatchesConversation(event, conversation: conversation),
                      (groupIndex.isGroupConversation(item.conversationID)
                          ? resolvedRoleID(conversation.roleID) == roleID
                          : resolvedRoleID(event.roleID) == roleID) else {
                    throw DataMergeError.invalidReference(
                        "会话已读状态 \(item.id) 的游标事件不存在或跨角色、会话。"
                    )
                }
            }
        }

        let interactionsByID = Dictionary(
            uniqueKeysWithValues: payload.momentInteractions.map { ($0.id, $0) }
        )
        let momentPostsByID = Dictionary(
            uniqueKeysWithValues: payload.momentPosts.map { ($0.id, $0) }
        )
        for item in payload.momentReadStates {
            guard let post = momentPostsByID[item.postID],
                  (post.authorKind == .user || post.authorKind == .companion),
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.revision >= 0,
                  item.deviceID.count <= 256 else {
                throw DataMergeError.invalidReference(
                    "朋友圈已读状态 \(item.id) 的帖子或字段无效。"
                )
            }
            if let createdAt = item.lastReadCreatedAt {
                guard createdAt.timeIntervalSince1970.isFinite else {
                    throw DataMergeError.invalidValue(
                        "朋友圈已读状态 \(item.id) 的游标时间无效。"
                    )
                }
            }
            if let interactionID = item.lastReadInteractionID {
                guard let interaction = interactionsByID[interactionID],
                      interaction.postID == item.postID else {
                    throw DataMergeError.invalidReference(
                        "朋友圈已读状态 \(item.id) 的游标互动不存在或不属于该帖子。"
                    )
                }
            }
        }

        for item in payload.memories {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  MemoryKind(rawValue: item.kindRaw) != nil,
                  item.kind == item.kindRaw,
                  MemoryState(rawValue: item.stateRaw) != nil,
                  item.state == item.stateRaw,
                  !normalizeKey(item.canonicalKey).isEmpty,
                  item.confidence.isFinite,
                  (0...1).contains(item.confidence),
                  item.importance.isFinite,
                  (0...1).contains(item.importance),
                  item.sourceRank >= 0,
                  item.schemaVersion > 0,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidValue("记忆 \(item.id) 的字段或数值无效。")
            }
            if let base64 = item.embeddingBase64 {
                guard let data = Data(base64Encoded: base64),
                      let vector = MemoryEmbeddingCodec.decode(data),
                      !vector.isEmpty,
                      vector.allSatisfy(\.isFinite) else {
                    throw DataMergeError.invalidValue("记忆 \(item.id) 的向量数据损坏。")
                }
            }
            if let supersedes = item.supersedesID,
               let superseded = memoryByID[supersedes],
               superseded.roleID != item.roleID {
                throw DataMergeError.invalidReference("记忆 \(item.id) 的被替代版本跨角色。")
            }
            if let supersedes = item.supersedesID, !memoryIDs.contains(supersedes) {
                // See the event parent comment above: the target may contain it.
                _ = supersedes
            }
        }

        for item in payload.evidence {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  EvidenceRelation(rawValue: item.relationRaw) != nil,
                  item.relation == item.relationRaw,
                  item.confidence.isFinite,
                  (0...1).contains(item.confidence) else {
                throw DataMergeError.invalidValue("证据 \(item.id) 的关系或置信度无效。")
            }
            if let event = payload.events.first(where: { $0.id == item.eventID }) {
                try validateQuote(item, in: event.content)
                guard let conversation = conversationByID[event.conversationID],
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: resolvedRoleID(item.roleID),
                          conversation: conversation
                      ) else {
                    throw DataMergeError.invalidReference("证据 \(item.id) 与事件跨角色。")
                }
            }
            if let memory = memoryByID[item.memoryID], memory.roleID != item.roleID {
                throw DataMergeError.invalidReference("证据 \(item.id) 与记忆跨角色。")
            }
            // Missing memory/event IDs are checked against the final union.
        }

        for item in payload.summaries {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  let conversation = conversationByID[item.conversationID],
                  (groupIndex.isGroupConversation(item.conversationID)
                      ? groupIndex.isActiveCompanion(
                          resolvedRoleID(item.roleID),
                          in: item.conversationID
                      )
                      : resolvedRoleID(conversation.roleID) == resolvedRoleID(item.roleID)),
                  item.coveredEventCount >= 0,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidReference("摘要 \(item.id) 的角色、会话或时间范围无效。")
            }
            for endpoint in [item.firstEventID, item.lastEventID].compactMap({ $0 }) {
                if let event = eventByID[endpoint],
                   let conversation = conversationByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: resolvedRoleID(item.roleID),
                       conversation: conversation
                   ) {
                    throw DataMergeError.invalidReference("摘要 \(item.id) 的边界事件跨角色。")
                }
            }
        }

        for item in payload.tombstones {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  !item.entityType.isEmpty,
                  !item.deviceID.isEmpty,
                  !item.reason.isEmpty,
                  Set(item.sourceEventIDs).count == item.sourceEventIDs.count else {
                throw DataMergeError.invalidValue("墓碑 \(item.id) 的必要字段或来源事件无效。")
            }
            for sourceEventID in item.sourceEventIDs {
                if let event = eventByID[sourceEventID],
                   let conversation = conversationByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: resolvedRoleID(item.roleID),
                       conversation: conversation
                   ) {
                    throw DataMergeError.invalidReference("墓碑 \(item.id) 的来源事件跨角色。")
                }
            }
            if item.entityType == "memory",
               let memory = memoryByID[item.entityID],
               memory.roleID != item.roleID {
                throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标记忆跨角色。")
            }
            if item.entityType == "conversation",
               let conversation = conversationByID[item.entityID],
               resolvedRoleID(conversation.roleID) != resolvedRoleID(item.roleID) {
                throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标会话跨角色。")
            }
            if item.entityType == "event",
               let event = eventByID[item.entityID],
               let conversation = conversationByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: resolvedRoleID(item.roleID),
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标事件跨角色。")
            }
        }
    }

    private static func ensureSourceUnique<Key: Hashable>(
        _ ids: [Key],
        entity: DataMergeEntity
    ) throws {
        guard Set(ids).count == ids.count else {
            throw DataMergeError.duplicateSourceIDs(entity: entity)
        }
    }

    private static func validateFinal(_ records: FinalRecords) throws {
        guard !records.profiles.isEmpty else {
            throw DataMergeError.invalidReference("最终结果缺少角色。")
        }
        for profile in records.profiles {
            try validateProfile(profile)
        }
        let profileRoleIDs = records.profiles.map { resolvedRoleID($0.roleID) }
        let profileByRoleID = Dictionary(
            uniqueKeysWithValues: records.profiles.map {
                (resolvedRoleID($0.roleID), $0)
            }
        )
        try ensureFinalUnique(profileRoleIDs, entity: .profile)
        try ensureFinalUnique(records.momentPosts.map(\.id), entity: .momentPost)
        try ensureFinalUnique(records.momentInteractions.map(\.id), entity: .momentInteraction)
        try ensureFinalUnique(
            records.momentAIInteractionTasks.map(\.id),
            entity: .momentAIInteractionTask
        )
        try ensureFinalUnique(
            records.momentAIInteractionTasks.map(DataMergeService.momentAIInteractionTaskKey),
            entity: .momentAIInteractionTask
        )
        try ensureFinalUnique(records.relationships.map(\.roleID), entity: .relationship)
        try ensureFinalUnique(records.transitions.map(\.id), entity: .transition)
        try ensureFinalUnique(records.momentTasks.map(\.id), entity: .momentTask)
        try ensureFinalUnique(records.conversations.map(\.id), entity: .conversation)
        try ensureFinalUnique(records.events.map(\.id), entity: .event)
        try ensureFinalUnique(records.conversationReadStates.map(\.id), entity: .conversationReadState)
        try ensureFinalUnique(records.momentReadStates.map(\.id), entity: .momentReadState)
        try ensureFinalUnique(
            records.conversationReadStates.map {
                ConversationReadStateScope(
                    roleID: resolvedRoleID($0.roleID),
                    conversationID: $0.conversationID
                )
            },
            entity: .conversationReadState
        )
        try ensureFinalUnique(records.momentReadStates.map(\.postID), entity: .momentReadState)
        try ensureFinalUnique(records.memories.map(\.id), entity: .memory)
        try ensureFinalUnique(records.evidence.map(\.id), entity: .evidence)
        try ensureFinalUnique(records.summaries.map(\.id), entity: .summary)
        try ensureFinalUnique(records.tombstones.map(\.id), entity: .tombstone)

        let conversationByID = Dictionary(
            uniqueKeysWithValues: records.conversations.map { ($0.id, $0) }
        )
        let eventByID = Dictionary(uniqueKeysWithValues: records.events.map { ($0.id, $0) })
        let eventIDs = Set(eventByID.keys)
        let transitionByID = Dictionary(
            uniqueKeysWithValues: records.transitions.map { ($0.id, $0) }
        )
        let relationshipRoleIDs = Set(records.relationships.map(\.roleID))
        let memoryByID = Dictionary(uniqueKeysWithValues: records.memories.map { ($0.id, $0) })
        let memoryIDs = Set(memoryByID.keys)
        let momentPostByID = Dictionary(uniqueKeysWithValues: records.momentPosts.map { ($0.id, $0) })
        let groupIndex = GroupBackupValidationIndex(
            groupConversations: records.groupConversations,
            groupParticipants: records.groupParticipants
        )

        if let userProfile = records.userProfile {
            try validateUserProfile(userProfile)
        }
        for post in records.momentPosts {
            try validateMomentPost(post)
            let roleID = post.authorRoleID.map(resolvedRoleID)
            if post.authorKind == .companion {
                guard let roleID, profileRoleIDs.contains(roleID) else {
                    throw DataMergeError.invalidReference("最终朋友圈 \(post.id) 的作者角色不存在。")
                }
            } else if let roleID, !profileRoleIDs.contains(roleID) {
                throw DataMergeError.invalidReference("最终朋友圈 \(post.id) 的用户作者角色不存在。")
            }
        }
        for interaction in records.momentInteractions {
            guard momentPostByID[interaction.postID] != nil else {
                throw DataMergeError.invalidReference("最终朋友圈互动 \(interaction.id) 的帖子不存在。")
            }
            try validateMomentInteraction(interaction)
            let roleID = interaction.actorRoleID.map(resolvedRoleID)
            if interaction.actorKind == .companion {
                guard let roleID, profileRoleIDs.contains(roleID) else {
                    throw DataMergeError.invalidReference("最终朋友圈互动 \(interaction.id) 的作者角色不存在。")
                }
            } else if let roleID, !profileRoleIDs.contains(roleID) {
                throw DataMergeError.invalidReference("最终朋友圈互动 \(interaction.id) 的用户作者角色不存在。")
            }
        }

        for item in records.momentTasks {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)) else {
                throw DataMergeError.invalidReference("最终朋友圈任务的角色不存在。")
            }
            try validateMomentTask(item)
        }

        let momentInteractionByID = Dictionary(
            uniqueKeysWithValues: records.momentInteractions.map { ($0.id, $0) }
        )
        for item in records.momentAIInteractionTasks {
            try validateMomentAIInteractionTask(item)
            try validateMomentAIInteractionTaskReferences(
                item,
                posts: momentPostByID,
                interactions: momentInteractionByID,
                profiles: profileByRoleID
            )
        }

        for item in records.relationships {
            guard profileRoleIDs.contains(item.roleID),
                  CompanionRelationshipState(rawValue: item.stateRaw) != nil,
                  item.harmStreak >= 0,
                  item.hurtScore.isFinite,
                  item.hurtScore >= 0,
                  item.harmThreshold > 0,
                  item.forgivenessScore.isFinite,
                  item.forgivenessScore >= 0,
                  item.forgivenessThreshold.isFinite,
                  item.forgivenessThreshold > 0,
                  item.dignity.isFinite,
                  (0...1).contains(item.dignity),
                  item.independence.isFinite,
                  (0...1).contains(item.independence),
                  item.boundarySensitivity.isFinite,
                  (0...1).contains(item.boundarySensitivity),
                  item.apologyAttempts >= 0,
                  item.affinityScore.isFinite,
                  (0...100).contains(item.affinityScore),
                  (0...3).contains(item.affinityTier),
                  item.affinityPolicyVersion > 0,
                  item.policyVersion > 0,
                  item.revision >= 0,
                  item.createdAt.timeIntervalSince1970.isFinite,
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidValue("最终关系 \(item.id) 的状态、数值或时间无效。")
            }
            if let eventID = item.lastProcessedEventID {
                if let event = eventByID[eventID],
                   let conversation = conversationByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: item.roleID,
                       conversation: conversation
                   ) {
                    throw DataMergeError.invalidReference("最终关系 \(item.id) 的最近事件跨角色。")
                }
            }
            if let transitionID = item.lastTransitionID {
                guard let transition = transitionByID[transitionID], transition.roleID == item.roleID else {
                    throw DataMergeError.invalidReference("最终关系 \(item.id) 的最近变更不存在或跨角色。")
                }
            }
            if let eventID = item.lastAffinityEventID,
               let event = eventByID[eventID],
               let conversation = conversationByID[event.conversationID],
               !groupIndex.eventMatchesRole(
                   event,
                   roleID: item.roleID,
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("最终关系 \(item.id) 的最近亲密度事件跨角色。")
            }
        }
        for item in records.transitions {
            guard profileRoleIDs.contains(item.roleID),
                  relationshipRoleIDs.contains(item.roleID),
                  CompanionRelationshipState(rawValue: item.from) != nil,
                  CompanionRelationshipState(rawValue: item.to) != nil,
                  !item.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.scoreAfter.isFinite,
                  item.scoreAfter >= 0,
                  item.policyVersion > 0,
                  item.revision >= 0,
                  item.occurredAt.timeIntervalSince1970.isFinite else {
                throw DataMergeError.invalidValue("最终关系变更 \(item.id) 的状态、数值或来源无效。")
            }
            if let eventID = item.sourceEventID {
                if let event = eventByID[eventID],
                   let conversation = conversationByID[event.conversationID],
                   !groupIndex.eventMatchesRole(
                       event,
                       roleID: item.roleID,
                       conversation: conversation
                   ) {
                    throw DataMergeError.invalidReference("最终关系变更 \(item.id) 的来源事件跨角色。")
                }
            }
        }

        for item in records.conversations {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidReference("会话 \(item.id) 的角色不存在或字段无效。")
            }
        }

        for item in records.events {
            try SchemaV11DataSupport.validateEventPayload(item)
            guard let conversation = conversationByID[item.conversationID],
                  profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  groupIndex.eventMatchesConversation(item, conversation: conversation),
                  EventRole(rawValue: item.roleRaw) != nil,
                  item.role == item.roleRaw,
                  EventDeliveryState(rawValue: item.deliveryStateRaw) != nil,
                  item.deliveryState == item.deliveryStateRaw,
                  item.deviceSequence >= 0,
                  !item.deviceID.isEmpty,
                  !item.logicalTimestamp.isEmpty,
                  item.contentHash.lowercased() == ContentHasher.sha256(item.content).lowercased() else {
                throw DataMergeError.invalidValue("最终事件 \(item.id) 的身份、状态、会话或原文哈希无效。")
            }
            if let parent = item.parentEventID, !eventIDs.contains(parent) {
                throw DataMergeError.invalidReference("事件 \(item.id) 的父事件不存在。")
            }
            if let parent = item.parentEventID,
               let parentEvent = eventByID[parent],
               !groupIndex.eventMatchesRole(
                   parentEvent,
                   roleID: resolvedRoleID(item.roleID),
                   conversation: conversation
               ) {
                throw DataMergeError.invalidReference("事件 \(item.id) 的父事件跨角色。")
            }
        }

        for item in records.conversationReadStates {
            guard let roleID = item.roleID.map(resolvedRoleID),
                  let conversation = conversationByID[item.conversationID],
                  resolvedRoleID(conversation.roleID) == roleID,
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.revision >= 0,
                  item.deviceID.count <= 256 else {
                throw DataMergeError.invalidReference(
                    "最终会话已读状态 \(item.id) 的会话、角色或字段无效。"
                )
            }
            if let occurredAt = item.lastReadOccurredAt {
                guard occurredAt.timeIntervalSince1970.isFinite else {
                    throw DataMergeError.invalidValue(
                        "最终会话已读状态 \(item.id) 的游标时间无效。"
                    )
                }
            }
            if let eventID = item.lastReadEventID {
                guard !item.lastReadLogicalTimestamp.isEmpty,
                      let event = eventByID[eventID],
                      event.conversationID == item.conversationID,
                      groupIndex.eventMatchesConversation(event, conversation: conversation),
                      (groupIndex.isGroupConversation(item.conversationID)
                          ? resolvedRoleID(conversation.roleID) == roleID
                          : resolvedRoleID(event.roleID) == roleID) else {
                    throw DataMergeError.invalidReference(
                        "最终会话已读状态 \(item.id) 的游标事件不存在或跨角色、会话。"
                    )
                }
            }
        }

        for item in records.momentReadStates {
            guard let post = momentPostByID[item.postID],
                  (post.authorKind == .user || post.authorKind == .companion),
                  item.updatedAt.timeIntervalSince1970.isFinite,
                  item.revision >= 0,
                  item.deviceID.count <= 256 else {
                throw DataMergeError.invalidReference(
                    "最终朋友圈已读状态 \(item.id) 的帖子或字段无效。"
                )
            }
            if let createdAt = item.lastReadCreatedAt {
                guard createdAt.timeIntervalSince1970.isFinite else {
                    throw DataMergeError.invalidValue(
                        "最终朋友圈已读状态 \(item.id) 的游标时间无效。"
                    )
                }
            }
            if let interactionID = item.lastReadInteractionID {
                guard let interaction = records.momentInteractions.first(where: {
                    $0.id == interactionID
                }), interaction.postID == item.postID else {
                    throw DataMergeError.invalidReference(
                        "最终朋友圈已读状态 \(item.id) 的游标互动不存在或不属于该帖子。"
                    )
                }
            }
        }

        for item in records.memories {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  MemoryKind(rawValue: item.kindRaw) != nil,
                  item.kind == item.kindRaw,
                  MemoryState(rawValue: item.stateRaw) != nil,
                  item.state == item.stateRaw,
                  !normalizeKey(item.canonicalKey).isEmpty,
                  item.confidence.isFinite,
                  (0...1).contains(item.confidence),
                  item.importance.isFinite,
                  (0...1).contains(item.importance),
                  item.sourceRank >= 0,
                  item.schemaVersion > 0,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidValue("最终记忆 \(item.id) 的字段、数值或时间无效。")
            }
            if let supersedes = item.supersedesID, !memoryIDs.contains(supersedes) {
                throw DataMergeError.invalidReference("记忆 \(item.id) 的被替代版本不存在。")
            }
            if let supersedes = item.supersedesID,
               let superseded = memoryByID[supersedes],
               superseded.roleID != item.roleID {
                throw DataMergeError.invalidReference("记忆 \(item.id) 的被替代版本跨角色。")
            }
            if let base64 = item.embeddingBase64 {
                guard let data = Data(base64Encoded: base64),
                      let vector = MemoryEmbeddingCodec.decode(data),
                      !vector.isEmpty,
                      vector.allSatisfy(\.isFinite) else {
                    throw DataMergeError.invalidValue("最终记忆 \(item.id) 的向量数据损坏。")
                }
            }
        }

        for item in records.evidence {
            guard let memory = memoryByID[item.memoryID],
                  let event = eventByID[item.eventID],
                  profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  memory.roleID == item.roleID,
                  let conversation = conversationByID[event.conversationID],
                  groupIndex.eventMatchesRole(
                      event,
                      roleID: resolvedRoleID(item.roleID),
                      conversation: conversation
                  ),
                  EvidenceRelation(rawValue: item.relationRaw) != nil,
                  item.relation == item.relationRaw,
                  item.confidence.isFinite,
                  (0...1).contains(item.confidence) else {
                throw DataMergeError.invalidReference("证据 \(item.id) 的记忆、事件或关系不存在。")
            }
            try validateQuote(item, in: event.content)
        }

        for item in records.summaries {
            guard let conversation = conversationByID[item.conversationID],
                  profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  (groupIndex.isGroupConversation(item.conversationID)
                      ? groupIndex.isActiveCompanion(
                          resolvedRoleID(item.roleID),
                          in: item.conversationID
                      )
                      : resolvedRoleID(conversation.roleID) == resolvedRoleID(item.roleID)),
                  item.coveredEventCount >= 0,
                  item.updatedAt >= item.createdAt else {
                throw DataMergeError.invalidReference("摘要 \(item.id) 的会话或时间范围无效。")
            }
            for endpoint in [item.firstEventID, item.lastEventID].compactMap({ $0 }) {
                guard let event = eventByID[endpoint],
                      event.conversationID == item.conversationID,
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: resolvedRoleID(item.roleID),
                          conversation: conversation
                      ) else {
                    throw DataMergeError.invalidReference("摘要 \(item.id) 的边界事件不存在或会话不匹配。")
                }
            }
        }

        for item in records.tombstones {
            guard profileRoleIDs.contains(resolvedRoleID(item.roleID)),
                  !item.entityType.isEmpty,
                  !item.deviceID.isEmpty,
                  !item.reason.isEmpty,
                  Set(item.sourceEventIDs).count == item.sourceEventIDs.count,
                  item.sourceEventIDs.allSatisfy(eventIDs.contains) else {
                throw DataMergeError.invalidReference("墓碑 \(item.id) 的来源事件不存在或重复。")
            }
            for sourceEventID in item.sourceEventIDs {
                guard let event = eventByID[sourceEventID],
                      let conversation = conversationByID[event.conversationID],
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: resolvedRoleID(item.roleID),
                          conversation: conversation
                      ) else {
                    throw DataMergeError.invalidReference("墓碑 \(item.id) 的来源事件跨角色。")
                }
            }
            if item.entityType == "memory", let memory = memoryByID[item.entityID] {
                guard memory.roleID == item.roleID else {
                    throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标记忆跨角色。")
                }
            }
            if item.entityType == "conversation", let conversation = conversationByID[item.entityID] {
                guard resolvedRoleID(conversation.roleID) == resolvedRoleID(item.roleID) else {
                    throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标会话跨角色。")
                }
            }
            if item.entityType == "event", let event = eventByID[item.entityID] {
                guard let conversation = conversationByID[event.conversationID],
                      groupIndex.eventMatchesRole(
                          event,
                          roleID: resolvedRoleID(item.roleID),
                          conversation: conversation
                      ) else {
                    throw DataMergeError.invalidReference("墓碑 \(item.id) 的目标事件跨角色。")
                }
            }
        }
    }

    private static func ensureFinalUnique<Key: Hashable>(
        _ ids: [Key],
        entity: DataMergeEntity
    ) throws {
        guard Set(ids).count == ids.count else {
            throw DataMergeError.invalidValue("最终结果包含重复的\(entity.rawValue) ID。")
        }
    }

    private static func validateQuote(_ evidence: AyaneEvidenceExport, in content: String) throws {
        guard let quote = quote(in: content, startUTF16: evidence.startUTF16, endUTF16: evidence.endUTF16),
              ContentHasher.sha256(quote).lowercased() == evidence.quoteHash.lowercased() else {
            throw DataMergeError.invalidValue("证据 \(evidence.id) 的 UTF-16 范围或 quote hash 无效。")
        }
    }

    private static func validateProfile(_ profile: AyanePersonaExport) throws {
        let roleID = resolvedRoleID(profile.roleID)
        guard profile.id == roleID,
              profile.createdAt.timeIntervalSince1970.isFinite,
              profile.updatedAt.timeIntervalSince1970.isFinite,
              profile.createdAt <= profile.updatedAt,
              profile.revision >= 0 else {
            throw DataMergeError.identityConflict(entity: .profile, id: profile.id)
        }
        try validateBirthday(
            month: profile.birthdayMonth,
            day: profile.birthdayDay,
            label: "人物设定生日"
        )
        do {
            _ = try CompanionProfileService.validatedConfiguration(
                PersonaConfiguration(
                    name: profile.name,
                    userName: profile.userName,
                    prompt: profile.prompt,
                    birthdayMonth: profile.birthdayMonth,
                    birthdayDay: profile.birthdayDay
                )
            )
        } catch {
            throw DataMergeError.identityConflict(entity: .profile, id: profile.id)
        }
    }

    private static func validateUserProfile(_ profile: AyaneUserProfileExport) throws {
        guard profile.id == UserProfileRecord.singletonID,
              !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.displayName.count <= 40,
              profile.createdAt.timeIntervalSince1970.isFinite,
              profile.updatedAt.timeIntervalSince1970.isFinite,
              profile.updatedAt >= profile.createdAt,
              profile.revision >= 0,
              profile.deviceID.count <= 256 else {
            throw DataMergeError.identityConflict(entity: .userProfile, id: profile.id)
        }
        try validateBirthday(
            month: profile.birthdayMonth,
            day: profile.birthdayDay,
            label: "用户资料生日"
        )
        guard !profile.birthdayTimeZoneIdentifier.isEmpty,
              profile.birthdayTimeZoneIdentifier.count <= 128,
              TimeZone(identifier: profile.birthdayTimeZoneIdentifier) != nil else {
            throw DataMergeError.identityConflict(entity: .userProfile, id: profile.id)
        }
    }

    private static func validateMomentPost(_ post: AyaneMomentPostExport) throws {
        guard MomentAuthorKind(rawValue: post.authorKindRaw) != nil,
              post.authorKind.rawValue == post.authorKindRaw,
              post.body.count <= 4_000,
              post.bundledImageName.count <= 256,
              post.publishedAt.timeIntervalSince1970.isFinite,
              post.createdAt.timeIntervalSince1970.isFinite,
              post.updatedAt.timeIntervalSince1970.isFinite,
              post.updatedAt >= post.createdAt,
              post.deletedAt?.timeIntervalSince1970.isFinite ?? true,
              post.revision >= 0,
              post.deviceID.count <= 256 else {
            throw DataMergeError.invalidValue("朋友圈 \(post.id) 的作者、内容或时间无效。")
        }
    }

    private static func validateMomentInteraction(
        _ interaction: AyaneMomentInteractionExport
    ) throws {
        guard MomentInteractionKind(rawValue: interaction.kindRaw) != nil,
              interaction.kind.rawValue == interaction.kindRaw,
              MomentAuthorKind(rawValue: interaction.actorKindRaw) != nil,
              interaction.actorKind.rawValue == interaction.actorKindRaw,
              interaction.body.count <= 500,
              interaction.createdAt.timeIntervalSince1970.isFinite,
              interaction.updatedAt.timeIntervalSince1970.isFinite,
              interaction.deletedAt?.timeIntervalSince1970.isFinite ?? true,
              interaction.updatedAt >= interaction.createdAt,
              interaction.revision >= 0,
              interaction.deviceID.count <= 256 else {
            throw DataMergeError.invalidValue("朋友圈互动 \(interaction.id) 的作者、类型或时间无效。")
        }
    }

    private static func validateMomentTask(_ task: AyaneMomentTaskExport) throws {
        guard MomentTaskState(rawValue: task.stateRaw) != nil,
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
              task.publishedAt?.timeIntervalSince1970.isFinite ?? true,
              task.leaseExpiresAt?.timeIntervalSince1970.isFinite ?? true,
              task.nextAttemptAt?.timeIntervalSince1970.isFinite ?? true,
              task.attemptCount >= 0,
              task.revision >= 0 else {
            throw DataMergeError.invalidValue("朋友圈任务的状态、指令或时间无效。")
        }
        try validateMomentTaskRecurrence(task)
        if task.stateRaw == MomentTaskState.published.rawValue {
            guard !task.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  task.publishedAt != nil else {
                throw DataMergeError.invalidValue("已发布朋友圈任务缺少结果或发布时间。")
            }
        }
    }

    private static func validateBirthday(
        month: Int?,
        day: Int?,
        label: String
    ) throws {
        guard (month == nil) == (day == nil) else {
            throw DataMergeError.invalidValue(label + "必须同时填写月份和日期。")
        }
        guard let month, let day else { return }
        guard (1...12).contains(month), (1...31).contains(day) else {
            throw DataMergeError.invalidValue(label + "日期无效。")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = calendar.date(
            from: DateComponents(year: 2000, month: month, day: day)
        ),
        calendar.component(.month, from: date) == month,
        calendar.component(.day, from: date) == day else {
            throw DataMergeError.invalidValue(label + "日期无效。")
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
            throw DataMergeError.invalidValue("朋友圈任务的重复规则无效。")
        }
        if let weekday = task.recurrenceWeekday,
           !(1...7).contains(weekday) {
            throw DataMergeError.invalidValue("朋友圈任务的星期无效。")
        }
        if let dayOfMonth = task.recurrenceDayOfMonth,
           !(1...31).contains(dayOfMonth) {
            throw DataMergeError.invalidValue("朋友圈任务的月份日期无效。")
        }
        switch MomentTaskRecurrenceFrequency(rawValue: task.recurrenceRaw) {
        case .weekly where task.recurrenceWeekday == nil:
            throw DataMergeError.invalidValue("每周任务缺少星期。")
        case .monthly where task.recurrenceDayOfMonth == nil:
            throw DataMergeError.invalidValue("每月任务缺少日期。")
        default:
            break
        }
    }

    private static func validateMomentAIInteractionTask(
        _ task: AyaneMomentAIInteractionTaskExport
    ) throws {
        guard let roleID = task.roleID,
              roleID == resolvedRoleID(task.roleID),
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
            throw DataMergeError.invalidValue(
                "朋友圈互动任务 (task.id) 的类型、状态、内容或时间无效。"
            )
        }
        _ = roleID
    }

    private static func validateMomentAIInteractionTaskReferences(
        _ task: AyaneMomentAIInteractionTaskExport,
        posts: [UUID: AyaneMomentPostExport],
        interactions: [UUID: AyaneMomentInteractionExport],
        profiles: [UUID: AyanePersonaExport]
    ) throws {
        let roleID = resolvedRoleID(task.roleID)
        guard profiles[roleID] != nil else {
            throw DataMergeError.invalidReference(
                "朋友圈互动任务 (task.id) 的角色不存在。"
            )
        }
        guard let post = posts[task.postID] else {
            throw DataMergeError.invalidReference(
                "朋友圈互动任务 (task.id) 的帖子不存在。"
            )
        }

        if let parentID = task.parentInteractionID {
            guard let parent = interactions[parentID],
                  parent.postID == task.postID,
                  parent.kind == .comment else {
                throw DataMergeError.invalidReference(
                    "朋友圈互动任务 (task.id) 的父评论不存在。"
                )
            }
        }
        if let rootID = task.rootInteractionID {
            guard let root = interactions[rootID],
                  root.postID == task.postID,
                  root.kind == .comment else {
                throw DataMergeError.invalidReference(
                    "朋友圈互动任务 (task.id) 的根评论不存在。"
                )
            }
        }
        if let resultID = task.resultInteractionID {
            guard let result = interactions[resultID],
                  result.postID == task.postID,
                  result.kind == .comment,
                  result.actorKind == .companion,
                  result.actorRoleID.map(resolvedRoleID) == roleID else {
                throw DataMergeError.invalidReference(
                    "朋友圈互动任务 (task.id) 的结果互动不存在或跨角色。"
                )
            }
        }

        switch task.kind {
        case .reactionLike, .reactionComment:
            guard task.targetInteractionID == nil,
                  task.parentInteractionID == nil,
                  task.rootInteractionID == nil,
                  post.authorKind == .user else {
                throw DataMergeError.invalidValue(
                    "反应任务 (task.id) 的帖子或评论引用无效。"
                )
            }
        case .replyLike:
            guard post.authorKind == .companion,
                  post.authorRoleID.map(resolvedRoleID) == roleID,
                  let targetID = task.targetInteractionID,
                  let target = interactions[targetID],
                  target.postID == task.postID,
                  target.kind == .like,
                  target.actorKind == .user,
                  task.parentInteractionID == nil,
                  task.rootInteractionID == nil else {
                throw DataMergeError.invalidReference(
                    "点赞回复任务 (task.id) 的帖子作者或用户点赞来源无效。"
                )
            }
        case .replyComment:
            guard let parentID = task.parentInteractionID,
                  let parent = interactions[parentID],
                  parent.postID == task.postID,
                  parent.kind == .comment,
                  parent.actorKind == .user else {
                throw DataMergeError.invalidValue(
                    "回复任务 (task.id) 缺少有效的用户父评论。"
                )
            }
            if post.authorKind == .companion,
               post.authorRoleID.map(resolvedRoleID) != roleID {
                throw DataMergeError.invalidReference(
                    "AI 朋友圈回复任务 (task.id) 不是由动态作者处理。"
                )
            }
            if let targetID = task.targetInteractionID {
                guard let target = interactions[targetID],
                      target.postID == task.postID,
                      target.kind == .comment,
                      target.actorKind == .companion,
                      target.actorRoleID.map(resolvedRoleID) == roleID else {
                    throw DataMergeError.invalidReference(
                        "朋友圈互动任务 (task.id) 的目标评论不存在或跨角色。"
                    )
                }
            }
        }
    }

    private static func resolvedRoleID(_ roleID: UUID?) -> UUID {
        RoleScope.resolve(roleID)
    }

    private static func canonicalUserProfileRecord(
        from profiles: [UserProfileRecord]
    ) -> UserProfileRecord? {
        profiles
            .filter { $0.id == UserProfileRecord.singletonID }
            .max { lhs, rhs in
                if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
                let left = userProfileFingerprint(lhs)
                let right = userProfileFingerprint(rhs)
                if left != right { return left < right }
                return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
            }
    }

    private static func userProfileFingerprint(_ profile: UserProfileRecord) -> String {
        [
            profile.id.uuidString.lowercased(),
            profile.displayName,
            String(profile.birthdayMonth ?? 0),
            String(profile.birthdayDay ?? 0),
            profile.birthdayTimeZoneIdentifier,
            profile.avatarImageData?.base64EncodedString() ?? "",
            profile.momentsCoverImageData?.base64EncodedString() ?? "",
            date(profile.createdAt),
            date(profile.updatedAt),
            String(profile.revision),
            profile.deviceID
        ].joined(separator: "\u{001F}")
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

    private static func newerConversation(
        current: AyaneConversationExport,
        incoming: AyaneConversationExport
    ) -> AyaneConversationExport {
        if incoming.updatedAt != current.updatedAt { return incoming.updatedAt > current.updatedAt ? incoming : current }
        return fingerprint(incoming) > fingerprint(current) ? incoming : current
    }

    /// Read progress is monotonic. Reuse the same cursor-first ordering as
    /// `ReadStateService.isNewer` so merge, export and duplicate reconciliation
    /// cannot disagree about which device's marker is ahead.
    private static func newerConversationReadState(
        current: AyaneConversationReadStateExport,
        incoming: AyaneConversationReadStateExport
    ) -> AyaneConversationReadStateExport {
        let currentRecord = makeConversationReadState(current)
        let incomingRecord = makeConversationReadState(incoming)
        return ReadStateService.isNewer(incomingRecord, than: currentRecord)
            ? incoming
            : current
    }

    private static func newerMomentReadState(
        current: AyaneMomentReadStateExport,
        incoming: AyaneMomentReadStateExport
    ) -> AyaneMomentReadStateExport {
        let currentRecord = makeMomentReadState(current)
        let incomingRecord = makeMomentReadState(incoming)
        return ReadStateService.isNewer(incomingRecord, than: currentRecord)
            ? incoming
            : current
    }

    private static func withID(
        _ item: AyaneConversationReadStateExport,
        id: UUID
    ) -> AyaneConversationReadStateExport {
        AyaneConversationReadStateExport(
            id: id,
            roleID: item.roleID,
            conversationID: item.conversationID,
            lastReadOccurredAt: item.lastReadOccurredAt,
            lastReadLogicalTimestamp: item.lastReadLogicalTimestamp,
            lastReadEventID: item.lastReadEventID,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func withID(
        _ item: AyaneMomentReadStateExport,
        id: UUID
    ) -> AyaneMomentReadStateExport {
        AyaneMomentReadStateExport(
            id: id,
            postID: item.postID,
            lastReadCreatedAt: item.lastReadCreatedAt,
            lastReadInteractionID: item.lastReadInteractionID,
            updatedAt: item.updatedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    /// Profile edits use an explicit, deterministic last-writer ordering. The
    /// revision is the primary application-level version; timestamps are the
    /// next signal for legacy/imported records, followed by the stable device
    /// ID and finally the canonical content fingerprint. Returning `current`
    /// for an exact tie keeps a repeated merge a no-op.
    private static func newerProfile(
        current: AyanePersonaExport,
        incoming: AyanePersonaExport
    ) -> AyanePersonaExport {
        guard incoming.id == current.id else { return current }
        return isPreferredProfile(incoming, over: current)
            ? incoming
            : current
    }

    /// Keep the export-side ordering identical to
    /// `CompanionProfileService.canonicalContentFingerprint` so local
    /// duplicate reduction and imported merges always converge on the same
    /// complete profile, including its media.
    private static func isPreferredProfile(
        _ lhs: AyanePersonaExport,
        over rhs: AyanePersonaExport
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision > rhs.revision
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID > rhs.deviceID
        }

        return profileContentFingerprint(lhs) > profileContentFingerprint(rhs)
    }

    private static func profileContentFingerprint(_ profile: AyanePersonaExport) -> String {
        func dataHash(_ data: Data?) -> String {
            guard let data else { return "" }
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        let content = [
            profile.worldProfileID.uuidString.lowercased(),
            profile.name,
            profile.userName,
            profile.prompt,
            String(profile.birthdayMonth ?? 0),
            String(profile.birthdayDay ?? 0),
            dataHash(profile.avatarImageData),
            dataHash(profile.chatBackgroundImageData)
        ].joined(separator: "\u{001F}")
        return SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func newerUserProfile(
        current: AyaneUserProfileExport,
        incoming: AyaneUserProfileExport
    ) -> AyaneUserProfileExport {
        if incoming.revision != current.revision {
            return incoming.revision > current.revision ? incoming : current
        }
        if incoming.updatedAt != current.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if incoming.deviceID != current.deviceID {
            return incoming.deviceID > current.deviceID ? incoming : current
        }
        return userProfileFingerprint(incoming) > userProfileFingerprint(current)
            ? incoming
            : current
    }

    private static func userProfileFingerprint(_ profile: AyaneUserProfileExport) -> String {
        [
            profile.id.uuidString.lowercased(),
            profile.displayName,
            String(profile.birthdayMonth ?? 0),
            String(profile.birthdayDay ?? 0),
            profile.birthdayTimeZoneIdentifier,
            profile.avatarImageData?.base64EncodedString() ?? "",
            profile.momentsCoverImageData?.base64EncodedString() ?? "",
            date(profile.createdAt),
            date(profile.updatedAt),
            String(profile.revision),
            profile.deviceID
        ].joined(separator: "\u{001F}")
    }

    private static func sameMomentPostIdentity(
        _ lhs: AyaneMomentPostExport,
        _ rhs: AyaneMomentPostExport
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.authorKindRaw == rhs.authorKindRaw
            && lhs.authorRoleID.map(resolvedRoleID) == rhs.authorRoleID.map(resolvedRoleID)
    }

    private static func newerMomentPost(
        current: AyaneMomentPostExport,
        incoming: AyaneMomentPostExport
    ) -> AyaneMomentPostExport {
        if incoming.revision != current.revision {
            return incoming.revision > current.revision ? incoming : current
        }
        if incoming.updatedAt != current.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if incoming.deviceID != current.deviceID {
            return incoming.deviceID > current.deviceID ? incoming : current
        }
        return momentPostFingerprint(incoming) > momentPostFingerprint(current)
            ? incoming
            : current
    }

    private static func momentPostFingerprint(_ post: AyaneMomentPostExport) -> String {
        [
            uuid(post.id), post.authorKindRaw,
            optionalUUID(post.authorRoleID), string(post.body),
            post.imageData?.base64EncodedString() ?? "", string(post.bundledImageName),
            optionalUUID(post.sourceTaskID), date(post.publishedAt), date(post.createdAt),
            date(post.updatedAt), optionalDate(post.deletedAt), String(post.revision),
            string(post.deviceID)
        ].joined(separator: "|")
    }

    private static func sameMomentInteractionIdentity(
        _ lhs: AyaneMomentInteractionExport,
        _ rhs: AyaneMomentInteractionExport
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.postID == rhs.postID
            && lhs.kindRaw == rhs.kindRaw
            && lhs.actorKindRaw == rhs.actorKindRaw
            && lhs.actorRoleID.map(resolvedRoleID) == rhs.actorRoleID.map(resolvedRoleID)
            && lhs.parentInteractionID == rhs.parentInteractionID
            && lhs.rootInteractionID == rhs.rootInteractionID
    }

    private static func newerMomentInteraction(
        current: AyaneMomentInteractionExport,
        incoming: AyaneMomentInteractionExport
    ) -> AyaneMomentInteractionExport {
        let versionWinner: AyaneMomentInteractionExport
        if incoming.revision != current.revision {
            versionWinner = incoming.revision > current.revision ? incoming : current
        } else if incoming.updatedAt != current.updatedAt {
            versionWinner = incoming.updatedAt > current.updatedAt ? incoming : current
        } else if incoming.deviceID != current.deviceID {
            versionWinner = incoming.deviceID > current.deviceID ? incoming : current
        } else {
            versionWinner = momentInteractionFingerprint(incoming) > momentInteractionFingerprint(current)
                ? incoming
                : current
        }

        // A deletion is a sticky field. Keep the existing revision/date/device
        // winner for conflict semantics, but carry the newest known tombstone
        // onto it so a stale live copy can never resurrect the interaction.
        guard let newestDeletion = [current.deletedAt, incoming.deletedAt]
            .compactMap({ $0 })
            .max() else {
            return versionWinner
        }
        var result = versionWinner
        if result.deletedAt == nil || result.deletedAt! < newestDeletion {
            result.deletedAt = newestDeletion
        }
        return result
    }

    private static func momentInteractionFingerprint(
        _ interaction: AyaneMomentInteractionExport
    ) -> String {
        [
            uuid(interaction.id), uuid(interaction.postID), interaction.kindRaw,
            interaction.actorKindRaw, optionalUUID(interaction.actorRoleID),
            optionalUUID(interaction.parentInteractionID), optionalUUID(interaction.rootInteractionID),
            string(interaction.body), date(interaction.createdAt), date(interaction.updatedAt),
            optionalDate(interaction.deletedAt),
            String(interaction.revision), string(interaction.deviceID)
        ].joined(separator: "|")
    }

    private static func newerSummary(
        current: AyaneSummaryExport,
        incoming: AyaneSummaryExport
    ) -> AyaneSummaryExport {
        if incoming.updatedAt != current.updatedAt { return incoming.updatedAt > current.updatedAt ? incoming : current }
        return fingerprint(incoming) > fingerprint(current) ? incoming : current
    }

    /// Merges one task by UUID while preserving terminal lifecycle decisions.
    /// A published result is an externally visible boundary: two different
    /// published texts for the same ID are never resolved by LWW, and a
    /// scheduled/running copy can never reopen a published or cancelled task.
    private static func mergeMomentTask(
        current: AyaneMomentTaskExport,
        incoming: AyaneMomentTaskExport
    ) throws -> AyaneMomentTaskExport {
        let currentState = MomentTaskState(rawValue: current.stateRaw)
        let incomingState = MomentTaskState(rawValue: incoming.stateRaw)
        guard currentState != nil, incomingState != nil else {
            throw DataMergeError.invalidValue("朋友圈任务状态无效。")
        }

        if currentState == .published,
           incomingState == .published,
           current.resultText != incoming.resultText {
            throw DataMergeError.identityConflict(entity: .momentTask, id: current.id)
        }

        let currentRank = momentTaskStateRank(current.stateRaw)
        let incomingRank = momentTaskStateRank(incoming.stateRaw)
        if currentRank != incomingRank {
            return incomingRank > currentRank ? incoming : current
        }
        if incoming.revision != current.revision {
            return incoming.revision > current.revision ? incoming : current
        }
        if incoming.updatedAt != current.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if incoming.deviceID != current.deviceID {
            return incoming.deviceID > current.deviceID ? incoming : current
        }
        return momentTaskFingerprint(incoming) > momentTaskFingerprint(current)
            ? incoming
            : current
    }

    private static func sameMomentAIInteractionTaskIdentity(
        _ lhs: AyaneMomentAIInteractionTaskExport,
        _ rhs: AyaneMomentAIInteractionTaskExport
    ) -> Bool {
        lhs.kindRaw == rhs.kindRaw
            && lhs.postID == rhs.postID
            && lhs.targetInteractionID == rhs.targetInteractionID
            && lhs.parentInteractionID == rhs.parentInteractionID
            && lhs.rootInteractionID == rhs.rootInteractionID
            && resolvedRoleID(lhs.roleID) == resolvedRoleID(rhs.roleID)
            && momentAIInteractionTaskKey(lhs) == momentAIInteractionTaskKey(rhs)
    }

    /// The idempotency key is the logical operation identity. Keep it
    /// case-insensitive to match task enqueueing and export canonicalization,
    /// while preserving the original spelling in the stored record.
    private static func momentAIInteractionTaskKey(
        _ task: AyaneMomentAIInteractionTaskExport
    ) -> String {
        task.idempotencyKey.lowercased()
    }

    private static func mergeMomentAIInteractionTask(
        current: AyaneMomentAIInteractionTaskExport,
        incoming: AyaneMomentAIInteractionTaskExport
    ) throws -> AyaneMomentAIInteractionTaskExport {
        guard MomentAIInteractionTaskState(rawValue: current.stateRaw) != nil,
              MomentAIInteractionTaskState(rawValue: incoming.stateRaw) != nil else {
            throw DataMergeError.invalidValue("朋友圈互动任务状态无效。")
        }

        let currentTerminal = current.state.isTerminal
        let incomingTerminal = incoming.state.isTerminal
        if currentTerminal != incomingTerminal {
            return incomingTerminal ? incoming : current
        }
        if current.revision != incoming.revision {
            return incoming.revision > current.revision ? incoming : current
        }
        if current.updatedAt != incoming.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if current.deviceID != incoming.deviceID {
            return incoming.deviceID > current.deviceID ? incoming : current
        }
        return momentAIInteractionTaskFingerprint(incoming)
                > momentAIInteractionTaskFingerprint(current)
            ? incoming
            : current
    }

    private static func momentAIInteractionTaskFingerprint(
        _ task: AyaneMomentAIInteractionTaskExport
    ) -> String {
        [
            uuid(task.id), string(task.kindRaw), uuid(task.postID),
            optionalUUID(task.targetInteractionID), optionalUUID(task.parentInteractionID),
            optionalUUID(task.rootInteractionID), uuid(resolvedRoleID(task.roleID)),
            string(task.stateRaw), String(task.attemptCount), date(task.nextAttemptAt),
            string(task.lastError), string(momentAIInteractionTaskKey(task)),
            string(task.timezoneIdentifier), string(task.inputText), string(task.generatedText),
            task.generatedLike.map(bool) ?? "-", optionalUUID(task.resultInteractionID),
            string(task.leaseOwner), optionalDate(task.leaseExpiresAt), date(task.createdAt),
            date(task.updatedAt), String(task.revision), string(task.deviceID)
        ].joined(separator: "|")
    }

    private static func stableMomentAIInteractionTaskLess(
        _ lhs: AyaneMomentAIInteractionTaskExport,
        _ rhs: AyaneMomentAIInteractionTaskExport
    ) -> Bool {
        (
            momentAIInteractionTaskKey(lhs),
            lhs.updatedAt,
            lhs.id.uuidString.lowercased()
        ) < (
            momentAIInteractionTaskKey(rhs),
            rhs.updatedAt,
            rhs.id.uuidString.lowercased()
        )
    }

    private static func withID(
        _ task: AyaneMomentAIInteractionTaskExport,
        id: UUID
    ) -> AyaneMomentAIInteractionTaskExport {
        AyaneMomentAIInteractionTaskExport(
            id: id,
            kind: task.kind,
            postID: task.postID,
            targetInteractionID: task.targetInteractionID,
            parentInteractionID: task.parentInteractionID,
            rootInteractionID: task.rootInteractionID,
            roleID: task.roleID,
            state: task.state,
            attemptCount: task.attemptCount,
            nextAttemptAt: task.nextAttemptAt,
            lastError: task.lastError,
            idempotencyKey: task.idempotencyKey,
            timezoneIdentifier: task.timezoneIdentifier,
            inputText: task.inputText,
            generatedText: task.generatedText,
            generatedLike: task.generatedLike,
            resultInteractionID: task.resultInteractionID,
            leaseOwner: task.leaseOwner,
            leaseExpiresAt: task.leaseExpiresAt,
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            revision: task.revision,
            deviceID: task.deviceID
        )
    }

    private static func momentTaskStateRank(_ rawValue: String) -> Int {
        switch rawValue {
        // scheduled and running are both non-terminal. Their ordering must
        // come from revision/timestamp below so a newer scheduled retry can
        // supersede a stale running lease without importing a lease reset.
        case MomentTaskState.scheduled.rawValue,
             MomentTaskState.running.rawValue: return 0
        case MomentTaskState.cancelled.rawValue: return 1
        case MomentTaskState.published.rawValue: return 2
        default: return -1
        }
    }

    private static func momentTaskFingerprint(_ item: AyaneMomentTaskExport) -> String {
        [
            uuid(item.id), uuid(resolvedRoleID(item.roleID)), string(item.instruction),
            date(item.scheduledAt), optionalUUID(item.seriesID), string(item.occurrenceKey),
            string(item.recurrenceRaw), String(item.recurrenceInterval),
            item.recurrenceWeekday.map(String.init) ?? "-",
            item.recurrenceDayOfMonth.map(String.init) ?? "-",
            String(item.recurrenceHour), String(item.recurrenceMinute),
            string(item.timezoneIdentifier), optionalDate(item.nextAttemptAt),
            string(item.stateRaw), string(item.resultText),
            optionalDate(item.publishedAt), date(item.createdAt), date(item.updatedAt),
            String(item.attemptCount), string(item.lastError), string(item.leaseOwner),
            optionalDate(item.leaseExpiresAt), string(item.deviceID), String(item.revision)
        ].joined(separator: "|")
    }

    private static func stableMomentTaskLess(
        _ lhs: AyaneMomentTaskExport,
        _ rhs: AyaneMomentTaskExport
    ) -> Bool {
        (lhs.scheduledAt, lhs.updatedAt, lhs.id.uuidString.lowercased())
            < (rhs.scheduledAt, rhs.updatedAt, rhs.id.uuidString.lowercased())
    }

    private static func newerMemory(
        current: AyaneMemoryExport,
        incoming: AyaneMemoryExport
    ) -> AyaneMemoryExport {
        // A deletion is a durable privacy decision, not an ordinary
        // last-writer-wins update.  A stale active export must never revive a
        // forgotten UUID merely because its wall-clock timestamp is newer.
        // Normalize both sides first as legacy exports may still carry a
        // deleted row's value or embedding.
        let current = erasedMemoryExportIfForgotten(current)
        let incoming = erasedMemoryExportIfForgotten(incoming)
        let currentForgotten = current.stateRaw == MemoryState.forgotten.rawValue
        let incomingForgotten = incoming.stateRaw == MemoryState.forgotten.rawValue
        if currentForgotten != incomingForgotten {
            return currentForgotten ? current : incoming
        }
        if incoming.updatedAt != current.updatedAt {
            return incoming.updatedAt > current.updatedAt ? incoming : current
        }
        if incoming.userVerified != current.userVerified {
            return incoming.userVerified ? incoming : current
        }
        if incoming.sourceRank != current.sourceRank {
            return incoming.sourceRank > current.sourceRank ? incoming : current
        }
        return fingerprint(incoming) > fingerprint(current) ? incoming : current
    }

    /// Converges only the records that could currently be injected as active
    /// memories.  Forgotten records and records behind a tombstone remain
    /// untouched, so an import cannot resurrect a deleted fact.  UUIDs are
    /// never discarded: losing versions are retained as superseded/contested
    /// history.
    private static func convergeCanonicalMemoryGroups(
        _ memories: inout [UUID: AyaneMemoryExport],
        tombstones: [AyaneTombstoneExport]
    ) {
        let groups = Dictionary(grouping: memories.values.filter { item in
            item.stateRaw == MemoryState.active.rawValue
                && !isSuppressedByTombstone(item, tombstones: tombstones)
                && !normalizeKey(item.canonicalKey).isEmpty
        }) { scopedCanonicalKey($0) }

        for group in groups.values where group.count > 1 {
            let values = Set(group.map { normalizeValue($0.value) })
            if values.count == 1 {
                let winner = group.sorted(by: strongerMemory).first
                for item in group {
                    let state: MemoryState = item.id == winner?.id ? .active : .superseded
                    memories[item.id] = withState(item, state: state)
                }
                continue
            }

            let verified = group.filter(\.userVerified)
            if verified.count >= 2 {
                for item in group {
                    memories[item.id] = withState(item, state: .contested)
                }
                continue
            }

            let ordered = group.sorted(by: strongerMemory)
            guard let winner = ordered.first else { continue }
            let winnerKey = memoryStrengthKey(winner)
            let tied = ordered.filter { memoryStrengthKey($0) == winnerKey }
            if tied.count == 1 {
                for item in group {
                    memories[item.id] = withState(
                        item,
                        state: item.id == winner.id ? .active : .superseded
                    )
                }
            } else {
                // Stable UUID ordering makes the result reproducible, but it
                // must not silently choose between equally strong values.
                for item in group {
                    memories[item.id] = withState(
                        item,
                        state: tied.contains(where: { $0.id == item.id }) ? .contested : .superseded
                    )
                }
            }
        }
    }

    private static func isSuppressedByTombstone(
        _ memory: AyaneMemoryExport,
        tombstones: [AyaneTombstoneExport]
    ) -> Bool {
        let key = normalizeKey(memory.canonicalKey)
        return tombstones.contains { tombstone in
            guard tombstone.entityType == "memory" else { return false }
            guard resolvedRoleID(tombstone.roleID) == resolvedRoleID(memory.roleID) else {
                return false
            }
            if tombstone.entityID == memory.id { return true }
            let tombstoneKey = normalizeTombstoneKey(tombstone.canonicalKey)
            if tombstoneKey.isEmpty {
                return memory.createdAt <= tombstone.deletedAt
            }
            return !key.isEmpty
                && !tombstoneKey.isEmpty
                && key == tombstoneKey
                && memory.createdAt <= tombstone.deletedAt
        }
    }

    private static func memoryStrengthKey(
        _ item: AyaneMemoryExport
    ) -> (Bool, Int, Date, Date) {
        (item.userVerified, item.sourceRank, item.observedAt, item.updatedAt)
    }

    private static func strongerMemory(
        _ lhs: AyaneMemoryExport,
        _ rhs: AyaneMemoryExport
    ) -> Bool {
        let lhsKey = memoryStrengthKey(lhs)
        let rhsKey = memoryStrengthKey(rhs)
        if lhsKey.0 != rhsKey.0 { return lhsKey.0 }
        if lhsKey.1 != rhsKey.1 { return lhsKey.1 > rhsKey.1 }
        if lhsKey.2 != rhsKey.2 { return lhsKey.2 > rhsKey.2 }
        if lhsKey.3 != rhsKey.3 { return lhsKey.3 > rhsKey.3 }
        return stableUUIDLess(lhs.id, rhs.id)
    }

    private static func normalizeKey(_ value: String) -> String {
        MemoryTombstoneRecord.normalizedCanonicalKey(value)
    }

    private static func normalizeTombstoneKey(_ value: String) -> String {
        MemoryTombstoneRecord.normalizedCanonicalKey(value)
    }

    private static func scopedCanonicalKey(_ item: AyaneMemoryExport) -> String {
        let key = normalizeKey(item.canonicalKey)
        guard !key.isEmpty else { return "" }
        return resolvedRoleID(item.roleID).uuidString.lowercased() + "\u{001F}" + key
    }

    /// SwiftData's predicate builder cannot express the Unicode-aware
    /// normalization above. Keep the compatibility lookup finite and scoped
    /// to each incoming logical key instead of scanning the whole memory
    /// table. The common legacy spellings (case, boundary whitespace/BOM and
    /// one interior BOM) are enough to discover old rows; a hard cap keeps a
    /// malformed key from turning a merge into an unbounded query fan-out.
    private static let maximumCanonicalKeyQueryVariants = 96

    private static func canonicalKeyVariants(_ value: String) -> [String] {
        let normalized = normalizeKey(value)
        guard !normalized.isEmpty else { return [] }

        var variants: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String) -> Bool {
            guard !candidate.isEmpty,
                  seen.insert(candidate).inserted else { return true }
            guard variants.count < maximumCanonicalKeyQueryVariants else {
                return false
            }
            variants.append(candidate)
            return true
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleCased = normalized.capitalized
        let uppercased = normalized.uppercased()
        let coreForms = [value, trimmed, normalized, titleCased, uppercased]

        // Preserve exact source/target spellings first. This also means a
        // source key that already contains a legacy BOM is queried directly.
        for form in coreForms where !append(form) {
            return variants
        }

        // Boundary noise is deliberately a small, explicit compatibility
        // set. Arbitrary Unicode format/control sequences cannot be represented
        // by a bounded set of equality predicates, so they are never expanded
        // into an unbounded table scan.
        let boundaryNoise = ["", " ", "\u{FEFF}", "\u{FEFF} ", " \u{FEFF}"]
        for form in [normalized, titleCased, uppercased] {
            for prefix in boundaryNoise {
                for suffix in boundaryNoise {
                    if !append(prefix + form + suffix) {
                        return variants
                    }
                }
            }
        }

        // A single interior BOM is a common artifact of concatenated JSON
        // fragments. Enumerating each scalar boundary is still bounded by the
        // explicit cap above and catches the practical legacy spellings such
        // as `user.<BOM>favorite`.
        for form in [normalized, titleCased, uppercased] {
            var index = form.startIndex
            while index <= form.endIndex {
                let candidate = String(form[..<index])
                    + "\u{FEFF}"
                    + String(form[index...])
                if !append(candidate) {
                    return variants
                }
                if index == form.endIndex { break }
                index = form.index(after: index)
            }
        }

        return variants
    }

    private static func normalizeValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedMemoryExport(
        _ item: AyaneMemoryExport
    ) -> AyaneMemoryExport {
        let normalized = AyaneMemoryExport(
            mergeID: item.id,
            kind: item.kind,
            kindRaw: item.kindRaw,
            subject: item.subject,
            predicate: item.predicate,
            value: item.value,
            canonicalKey: normalizeKey(item.canonicalKey),
            state: item.state,
            stateRaw: item.stateRaw,
            confidence: item.confidence,
            importance: item.importance,
            sensitive: item.sensitive,
            sourceRank: item.sourceRank,
            validFrom: item.validFrom,
            validTo: item.validTo,
            observedAt: item.observedAt,
            supersedesID: item.supersedesID,
            extractorID: item.extractorID,
            schemaVersion: item.schemaVersion,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            isPinned: item.isPinned,
            userVerified: item.userVerified,
            embeddingBase64: item.embeddingBase64,
            embeddingModelID: item.embeddingModelID,
            deviceID: item.deviceID,
            roleID: item.roleID
        )
        return erasedMemoryExportIfForgotten(normalized)
    }

    /// Forgotten assertions are intentionally represented as an erased
    /// projection.  This is applied to both imported values and destination
    /// snapshots so a stale copy cannot reintroduce value-bearing fields when
    /// it loses an UUID-level merge.
    private static func erasedMemoryExportIfForgotten(
        _ item: AyaneMemoryExport
    ) -> AyaneMemoryExport {
        guard item.stateRaw == MemoryState.forgotten.rawValue else { return item }
        return AyaneMemoryExport(
            mergeID: item.id,
            kind: item.kind,
            kindRaw: item.kindRaw,
            subject: item.subject,
            predicate: item.predicate,
            value: "",
            canonicalKey: item.canonicalKey,
            state: MemoryState.forgotten.rawValue,
            stateRaw: MemoryState.forgotten.rawValue,
            confidence: item.confidence,
            importance: item.importance,
            sensitive: item.sensitive,
            sourceRank: item.sourceRank,
            validFrom: item.validFrom,
            validTo: item.validTo,
            observedAt: item.observedAt,
            supersedesID: item.supersedesID,
            extractorID: item.extractorID,
            schemaVersion: item.schemaVersion,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            isPinned: false,
            userVerified: false,
            embeddingBase64: nil,
            embeddingModelID: nil,
            deviceID: item.deviceID,
            roleID: item.roleID
        )
    }

    private static func withState(
        _ item: AyaneMemoryExport,
        state: MemoryState
    ) -> AyaneMemoryExport {
        let updated = AyaneMemoryExport(
            mergeID: item.id,
            kind: item.kind,
            kindRaw: item.kindRaw,
            subject: item.subject,
            predicate: item.predicate,
            value: item.value,
            canonicalKey: normalizeKey(item.canonicalKey),
            state: state.rawValue,
            stateRaw: state.rawValue,
            confidence: item.confidence,
            importance: item.importance,
            sensitive: item.sensitive,
            sourceRank: item.sourceRank,
            validFrom: item.validFrom,
            validTo: item.validTo,
            observedAt: item.observedAt,
            supersedesID: item.supersedesID,
            extractorID: item.extractorID,
            schemaVersion: item.schemaVersion,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            isPinned: item.isPinned,
            userVerified: item.userVerified,
            embeddingBase64: item.embeddingBase64,
            embeddingModelID: item.embeddingModelID,
            deviceID: item.deviceID,
            roleID: item.roleID
        )
        return erasedMemoryExportIfForgotten(updated)
    }

    private static func sameEventIdentity(_ lhs: AyaneEventExport, _ rhs: AyaneEventExport) -> Bool {
        lhs.roleID == rhs.roleID
            && lhs.conversationID == rhs.conversationID
            && lhs.deviceID == rhs.deviceID
            && lhs.deviceSequence == rhs.deviceSequence
            && lhs.logicalTimestamp == rhs.logicalTimestamp
            && lhs.roleRaw == rhs.roleRaw
            && lhs.content == rhs.content
            && lhs.contentHash.lowercased() == rhs.contentHash.lowercased()
            && lhs.payloadKindRaw == rhs.payloadKindRaw
            && lhs.stickerID == rhs.stickerID
            && lhs.imageData == rhs.imageData
            && lhs.fileName == rhs.fileName
            && lhs.fileTypeIdentifier == rhs.fileTypeIdentifier
            && lhs.fileData == rhs.fileData
            && lhs.senderRoleID == rhs.senderRoleID
            && lhs.parentEventID == rhs.parentEventID
    }

    private static func mergeEvent(
        current: AyaneEventExport,
        incoming: AyaneEventExport
    ) -> AyaneEventExport {
        let processedAt: Date?
        switch (current.memoryProcessedAt, incoming.memoryProcessedAt) {
        case let (lhs?, rhs?): processedAt = max(lhs, rhs)
        case let (lhs?, nil): processedAt = lhs
        case let (nil, rhs?): processedAt = rhs
        case (nil, nil): processedAt = nil
        }
        let version = max(current.memoryProcessingVersion, incoming.memoryProcessingVersion)
        let deliveryState = mergedDeliveryState(current.deliveryStateRaw, incoming.deliveryStateRaw)
        return AyaneEventExport(
            mergeID: current.id,
            conversationID: current.conversationID,
            deviceID: current.deviceID,
            deviceSequence: current.deviceSequence,
            logicalTimestamp: current.logicalTimestamp,
            occurredAt: current.occurredAt,
            recordedAt: current.recordedAt,
            role: current.role,
            roleRaw: current.roleRaw,
            content: current.content,
            contentHash: current.contentHash,
            parentEventID: current.parentEventID,
            deliveryState: deliveryState,
            deliveryStateRaw: deliveryState,
            redacted: current.redacted || incoming.redacted,
            memoryProcessedAt: processedAt,
            memoryProcessingVersion: version,
            roleID: current.roleID,
            payloadKind: current.payloadKind,
            payloadKindRaw: current.payloadKindRaw,
            stickerID: current.stickerID,
            senderRoleID: current.senderRoleID,
            imageData: current.imageData,
            fileName: current.fileName,
            fileTypeIdentifier: current.fileTypeIdentifier,
            fileData: current.fileData
        )
    }

    private static func mergedDeliveryState(_ lhs: String, _ rhs: String) -> String {
        let left = EventDeliveryState(rawValue: lhs) ?? .streaming
        let right = EventDeliveryState(rawValue: rhs) ?? .streaming
        let leftRank = deliveryRank(left)
        let rightRank = deliveryRank(right)
        if leftRank != rightRank { return leftRank > rightRank ? left.rawValue : right.rawValue }
        return max(left.rawValue, right.rawValue)
    }

    private static func deliveryRank(_ state: EventDeliveryState) -> Int {
        switch state {
        case .streaming: 0
        case .cancelled, .failed: 1
        case .complete: 2
        case .undelivered: 3
        }
    }

    private static func sameEvidenceIdentity(_ lhs: AyaneEvidenceExport, _ rhs: AyaneEvidenceExport) -> Bool {
        lhs.roleID == rhs.roleID
            && lhs.memoryID == rhs.memoryID
            && lhs.eventID == rhs.eventID
            && lhs.startUTF16 == rhs.startUTF16
            && lhs.endUTF16 == rhs.endUTF16
            && lhs.relationRaw == rhs.relationRaw
            && lhs.quoteHash.lowercased() == rhs.quoteHash.lowercased()
    }

    private static func mergeEvidence(
        current: AyaneEvidenceExport,
        incoming: AyaneEvidenceExport
    ) -> AyaneEvidenceExport {
        AyaneEvidenceExport(
            mergeID: current.id,
            memoryID: current.memoryID,
            eventID: current.eventID,
            startUTF16: current.startUTF16,
            endUTF16: current.endUTF16,
            relation: current.relation,
            relationRaw: current.relationRaw,
            quoteHash: current.quoteHash,
            confidence: max(current.confidence, incoming.confidence),
            createdAt: min(current.createdAt, incoming.createdAt),
            roleID: current.roleID
        )
    }

    private static func sameTombstoneIdentity(_ lhs: AyaneTombstoneExport, _ rhs: AyaneTombstoneExport) -> Bool {
        lhs.roleID == rhs.roleID
            && lhs.entityID == rhs.entityID
            && lhs.entityType == rhs.entityType
            && normalizeTombstoneKey(lhs.canonicalKey) == normalizeTombstoneKey(rhs.canonicalKey)
            && lhs.deviceID == rhs.deviceID
            && lhs.reason == rhs.reason
    }

    private static func mergeTombstone(
        current: AyaneTombstoneExport,
        incoming: AyaneTombstoneExport
    ) -> AyaneTombstoneExport {
        AyaneTombstoneExport(
            mergeID: current.id,
            entityID: current.entityID,
            entityType: current.entityType,
            canonicalKey: normalizeTombstoneKey(current.canonicalKey),
            sourceEventIDs: Set(current.sourceEventIDs + incoming.sourceEventIDs).sorted(by: stableUUIDLess),
            deletedAt: max(current.deletedAt, incoming.deletedAt),
            deviceID: current.deviceID,
            reason: current.reason,
            roleID: current.roleID
        )
    }

    private static func fingerprint(_ item: AyaneConversationExport) -> String {
        [
            uuid(item.id), uuid(resolvedRoleID(item.roleID)), string(item.title), date(item.createdAt),
            date(item.updatedAt), bool(item.archived)
        ].joined(separator: "|")
    }

    private static func fingerprint(_ item: AyaneSummaryExport) -> String {
        [
            uuid(item.id), uuid(resolvedRoleID(item.roleID)), uuid(item.conversationID),
            string(item.scope), string(item.content),
            optionalUUID(item.firstEventID), optionalUUID(item.lastEventID), String(item.coveredEventCount),
            string(item.extractorID), date(item.createdAt), date(item.updatedAt)
        ].joined(separator: "|")
    }

    private static func fingerprint(_ item: AyaneMemoryExport) -> String {
        [
            uuid(resolvedRoleID(item.roleID)), string(item.kindRaw), string(item.subject),
            string(item.predicate), string(item.value),
            string(item.canonicalKey), string(item.stateRaw), String(item.confidence.bitPattern, radix: 16),
            String(item.importance.bitPattern, radix: 16), bool(item.sensitive), String(item.sourceRank),
            optionalDate(item.validFrom), optionalDate(item.validTo), date(item.observedAt), optionalUUID(item.supersedesID),
            string(item.extractorID), String(item.schemaVersion), date(item.createdAt), date(item.updatedAt),
            bool(item.isPinned), bool(item.userVerified), item.embeddingBase64 ?? "", item.embeddingModelID ?? "",
            string(item.deviceID), uuid(item.id)
        ].joined(separator: "|")
    }

    private static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }
    private static func optionalUUID(_ id: UUID?) -> String { id.map(uuid) ?? "-" }
    private static func date(_ value: Date) -> String { String(value.timeIntervalSince1970.bitPattern, radix: 16) }
    private static func optionalDate(_ value: Date?) -> String { value.map(date) ?? "-" }
    private static func string(_ value: String) -> String { "\(value.utf8.count):\(value)" }
    private static func bool(_ value: Bool) -> String { value ? "1" : "0" }

    private static func stableUUIDLess(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString.lowercased() < rhs.uuidString.lowercased()
    }

    private static func relationshipSafetyRank(
        stateRaw: String,
        retiredAt: Date?
    ) -> Int {
        if retiredAt != nil { return 6 }
        switch CompanionRelationshipState(rawValue: stateRaw) {
        case .blocked: return 5
        case .deleted: return 4
        case .rejected: return 3
        case .recoveryPending: return 2
        case .pending: return 1
        case .accepted: return 0
        case nil: return 7
        }
    }

    private static func preferredRelationship(
        _ lhs: CompanionRelationshipRecord,
        over rhs: CompanionRelationshipRecord
    ) -> Bool {
        let leftSafety = relationshipSafetyRank(stateRaw: lhs.stateRaw, retiredAt: lhs.retiredAt)
        let rightSafety = relationshipSafetyRank(stateRaw: rhs.stateRaw, retiredAt: rhs.retiredAt)
        if leftSafety != rightSafety { return leftSafety > rightSafety }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return stableUUIDLess(lhs.id, rhs.id)
    }

    private static func newerRelationship(
        current: AyaneRelationshipExport,
        incoming: AyaneRelationshipExport
    ) -> AyaneRelationshipExport {
        let incomingSafety = relationshipSafetyRank(
            stateRaw: incoming.stateRaw,
            retiredAt: incoming.retiredAt
        )
        let currentSafety = relationshipSafetyRank(
            stateRaw: current.stateRaw,
            retiredAt: current.retiredAt
        )
        let relationshipWinner: AyaneRelationshipExport
        if incomingSafety != currentSafety {
            relationshipWinner = incomingSafety > currentSafety ? incoming : current
        } else if incoming.revision != current.revision {
            relationshipWinner = incoming.revision > current.revision ? incoming : current
        } else if incoming.updatedAt != current.updatedAt {
            relationshipWinner = incoming.updatedAt > current.updatedAt ? incoming : current
        } else if incoming.deviceID != current.deviceID {
            relationshipWinner = incoming.deviceID > current.deviceID ? incoming : current
        } else {
            relationshipWinner = relationshipFingerprint(incoming) > relationshipFingerprint(current)
                ? incoming
                : current
        }

        // Contact membership is an independent user-managed stream. Preserve
        // its newest value even when the relationship reducer selected the
        // other physical row for state/safety reasons.
        let contactWinner = preferredRelationshipContact(incoming, over: current)
            ? incoming
            : current
        var merged = relationshipWinner
        merged.contactMembershipRaw = contactWinner.contactMembershipRaw
        merged.contactStateUpdatedAt = contactWinner.contactStateUpdatedAt
        merged.lastUserRemovalID = contactWinner.lastUserRemovalID
        return merged
    }

    private static func preferredRelationshipContact(
        _ lhs: AyaneRelationshipExport,
        over rhs: AyaneRelationshipExport
    ) -> Bool {
        if lhs.contactStateUpdatedAt != rhs.contactStateUpdatedAt {
            return lhs.contactStateUpdatedAt > rhs.contactStateUpdatedAt
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        if lhs.contactMembershipRaw != rhs.contactMembershipRaw {
            return lhs.contactMembershipRaw > rhs.contactMembershipRaw
        }
        return (lhs.lastUserRemovalID?.uuidString ?? "")
            > (rhs.lastUserRemovalID?.uuidString ?? "")
    }

    private static func relationshipFingerprint(_ item: AyaneRelationshipExport) -> String {
        [
            item.roleID.uuidString.lowercased(), item.stateRaw,
            String(item.harmStreak), String(item.hurtScore.bitPattern, radix: 16),
            String(item.harmThreshold), String(item.forgivenessScore.bitPattern, radix: 16),
            String(item.forgivenessThreshold.bitPattern, radix: 16),
            String(item.affinityScore.bitPattern, radix: 16), String(item.affinityTier),
            String(item.affinityPolicyVersion), optionalUUID(item.lastAffinityEventID),
            String(item.dignity.bitPattern, radix: 16),
            String(item.independence.bitPattern, radix: 16),
            String(item.boundarySensitivity.bitPattern, radix: 16),
            String(item.apologyAttempts), String(item.policyVersion),
            optionalUUID(item.lastProcessedEventID), optionalUUID(item.lastTransitionID),
            date(item.createdAt), date(item.updatedAt), String(item.revision),
            item.deviceID, optionalDate(item.retiredAt), optionalDate(item.resetAt),
            item.contactMembershipRaw, date(item.contactStateUpdatedAt),
            optionalUUID(item.lastUserRemovalID)
        ].joined(separator: "|")
    }

    private static func sameTransitionIdentity(
        _ lhs: AyaneRelationshipTransitionExport,
        _ rhs: AyaneRelationshipTransitionExport
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.roleID == rhs.roleID
            && lhs.from == rhs.from
            && lhs.to == rhs.to
            && lhs.reason == rhs.reason
            && lhs.sourceEventID == rhs.sourceEventID
            && lhs.scoreAfter == rhs.scoreAfter
            && lhs.policyVersion == rhs.policyVersion
            && lhs.occurredAt == rhs.occurredAt
            && lhs.deviceID == rhs.deviceID
            && lhs.revision == rhs.revision
    }

    private static func sameTransitionIdentity(
        _ lhs: CompanionRelationshipTransitionRecord,
        _ rhs: CompanionRelationshipTransitionRecord
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.roleID == rhs.roleID
            && lhs.from == rhs.from
            && lhs.to == rhs.to
            && lhs.reason == rhs.reason
            && lhs.sourceEventID == rhs.sourceEventID
            && lhs.scoreAfter == rhs.scoreAfter
            && lhs.policyVersion == rhs.policyVersion
            && lhs.occurredAt == rhs.occurredAt
            && lhs.deviceID == rhs.deviceID
            && lhs.revision == rhs.revision
    }

    private static func preferredTransition(
        _ lhs: CompanionRelationshipTransitionRecord,
        over rhs: CompanionRelationshipTransitionRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return false
    }

    private static func stableTransitionLess(
        _ lhs: AyaneRelationshipTransitionExport,
        _ rhs: AyaneRelationshipTransitionExport
    ) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        return stableUUIDLess(lhs.id, rhs.id)
    }

    private static func makeProfile(_ item: AyanePersonaExport) -> CompanionProfileRecord {
        CompanionProfileRecord(
            id: resolvedRoleID(item.roleID),
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

    private static func makeMomentPost(_ item: AyaneMomentPostExport) -> MomentPostRecord {
        MomentPostRecord(
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
    ) -> MomentInteractionRecord {
        MomentInteractionRecord(
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
            deletedAt: item.deletedAt,
            revision: item.revision,
            deviceID: item.deviceID
        )
    }

    private static func makeRelationship(
        _ item: AyaneRelationshipExport
    ) -> CompanionRelationshipRecord {
        CompanionRelationshipRecord(
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
    ) -> CompanionRelationshipTransitionRecord {
        CompanionRelationshipTransitionRecord(
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
    ) -> CompanionMomentTaskRecord {
        CompanionMomentTaskRecord(
            id: item.id,
            roleID: resolvedRoleID(item.roleID),
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
    ) -> MomentAIInteractionTaskRecord {
        MomentAIInteractionTaskRecord(
            id: item.id,
            kindRaw: item.kindRaw,
            postID: item.postID,
            targetInteractionID: item.targetInteractionID,
            parentInteractionID: item.parentInteractionID,
            rootInteractionID: item.rootInteractionID,
            roleID: resolvedRoleID(item.roleID),
            stateRaw: item.stateRaw,
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

    private static func makeConversationReadState(
        _ item: AyaneConversationReadStateExport
    ) -> ConversationReadStateRecord {
        ConversationReadStateRecord(
            id: item.id,
            roleID: item.roleID,
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
    ) -> MomentReadStateRecord {
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

    private static func makeEvent(_ item: AyaneEventExport) -> ConversationEvent {
        let record = ConversationEvent(
            id: item.id,
            conversationID: item.conversationID,
            deviceID: item.deviceID,
            deviceSequence: item.deviceSequence,
            logicalTimestamp: item.logicalTimestamp,
            occurredAt: item.occurredAt,
            role: EventRole(rawValue: item.roleRaw) ?? .user,
            content: item.content,
            contentHash: item.contentHash,
            parentEventID: item.parentEventID,
            deliveryState: EventDeliveryState(rawValue: item.deliveryStateRaw) ?? .complete,
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
        let record = MemoryAssertionRecord(
            id: item.id,
            kind: MemoryKind(rawValue: item.kindRaw) ?? .profile,
            subject: item.subject,
            predicate: item.predicate,
            value: item.value,
            canonicalKey: normalizeKey(item.canonicalKey),
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
                throw DataMergeError.invalidValue("记忆 \(item.id) 的向量数据损坏。")
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
            canonicalKey: normalizeTombstoneKey(item.canonicalKey),
            sourceEventIDs: item.sourceEventIDs,
            deviceID: item.deviceID,
            reason: item.reason,
            roleID: item.roleID
        )
        record.id = item.id
        record.canonicalKey = normalizeTombstoneKey(item.canonicalKey)
        record.canonicalKeyNormalizationVersion =
            MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        record.deletedAt = item.deletedAt
        return record
    }

    private static func apply(_ item: AyaneConversationExport, to record: ConversationRecord) {
        record.roleID = item.roleID
        record.title = item.title
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.archived = item.archived
    }

    private static func apply(_ item: AyanePersonaExport, to record: CompanionProfileRecord) {
        record.worldProfileID = item.worldProfileID
        record.name = item.name
        record.userName = item.userName
        record.prompt = item.prompt
        record.birthdayMonth = item.birthdayMonth
        record.birthdayDay = item.birthdayDay
        record.avatarImageData = item.avatarImageData
        record.chatBackgroundImageData = item.chatBackgroundImageData
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(
        _ item: AyaneUserProfileExport,
        to record: UserProfileRecord
    ) {
        record.displayName = item.displayName
        record.birthdayMonth = item.birthdayMonth
        record.birthdayDay = item.birthdayDay
        record.birthdayTimeZoneIdentifier = item.birthdayTimeZoneIdentifier
        record.avatarImageData = item.avatarImageData
        record.momentsCoverImageData = item.momentsCoverImageData
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(
        _ item: AyaneMomentPostExport,
        to record: MomentPostRecord
    ) {
        record.authorKindRaw = item.authorKindRaw
        record.authorRoleID = item.authorRoleID
        record.body = item.body
        record.imageData = item.imageData
        record.bundledImageName = item.bundledImageName
        record.sourceTaskID = item.sourceTaskID
        record.publishedAt = item.publishedAt
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.deletedAt = item.deletedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(
        _ item: AyaneMomentInteractionExport,
        to record: MomentInteractionRecord
    ) {
        record.postID = item.postID
        record.parentInteractionID = item.parentInteractionID
        record.rootInteractionID = item.rootInteractionID
        record.kindRaw = item.kindRaw
        record.actorKindRaw = item.actorKindRaw
        record.actorRoleID = item.actorRoleID
        record.body = item.body
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.deletedAt = item.deletedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(
        _ item: AyaneRelationshipExport,
        to record: CompanionRelationshipRecord
    ) {
        record.roleID = item.roleID
        record.stateRaw = item.stateRaw
        record.harmStreak = item.harmStreak
        record.hurtScore = item.hurtScore
        record.harmThreshold = item.harmThreshold
        record.forgivenessScore = item.forgivenessScore
        record.forgivenessThreshold = item.forgivenessThreshold
        record.affinityScore = item.affinityScore
        record.affinityTier = item.affinityTier
        record.affinityPolicyVersion = item.affinityPolicyVersion
        record.lastAffinityEventID = item.lastAffinityEventID
        record.dignity = item.dignity
        record.independence = item.independence
        record.boundarySensitivity = item.boundarySensitivity
        record.apologyAttempts = item.apologyAttempts
        record.policyVersion = item.policyVersion
        record.lastProcessedEventID = item.lastProcessedEventID
        record.lastTransitionID = item.lastTransitionID
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
        record.retiredAt = item.retiredAt
        record.resetAt = item.resetAt
        record.contactMembershipRaw = item.contactMembershipRaw
        record.contactStateUpdatedAt = item.contactStateUpdatedAt
        record.lastUserRemovalID = item.lastUserRemovalID
    }

    private static func apply(
        _ item: AyaneMomentTaskExport,
        to record: CompanionMomentTaskRecord
    ) {
        record.roleID = resolvedRoleID(item.roleID)
        record.instruction = item.instruction
        record.scheduledAt = item.scheduledAt
        record.seriesID = item.seriesID
        record.occurrenceKey = item.occurrenceKey
        record.recurrenceRaw = item.recurrenceRaw
        record.recurrenceInterval = item.recurrenceInterval
        record.recurrenceWeekday = item.recurrenceWeekday
        record.recurrenceDayOfMonth = item.recurrenceDayOfMonth
        record.recurrenceHour = item.recurrenceHour
        record.recurrenceMinute = item.recurrenceMinute
        record.timezoneIdentifier = item.timezoneIdentifier
        record.nextAttemptAt = item.nextAttemptAt
        record.stateRaw = item.stateRaw
        record.resultText = item.resultText
        record.publishedAt = item.publishedAt
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.attemptCount = item.attemptCount
        record.lastError = item.lastError
        record.leaseOwner = item.leaseOwner
        record.leaseExpiresAt = item.leaseExpiresAt
        record.deviceID = item.deviceID
        record.revision = item.revision
    }

    private static func apply(
        _ item: AyaneMomentAIInteractionTaskExport,
        to record: MomentAIInteractionTaskRecord
    ) {
        record.kindRaw = item.kindRaw
        record.postID = item.postID
        record.targetInteractionID = item.targetInteractionID
        record.parentInteractionID = item.parentInteractionID
        record.rootInteractionID = item.rootInteractionID
        record.roleID = resolvedRoleID(item.roleID)
        record.stateRaw = item.stateRaw
        record.attemptCount = item.attemptCount
        record.nextAttemptAt = item.nextAttemptAt
        record.lastError = item.lastError
        record.idempotencyKey = item.idempotencyKey
        record.timezoneIdentifier = item.timezoneIdentifier
        record.inputText = item.inputText
        record.generatedText = item.generatedText
        record.generatedLike = item.generatedLike
        record.resultInteractionID = item.resultInteractionID
        record.leaseOwner = item.leaseOwner
        record.leaseExpiresAt = item.leaseExpiresAt
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneEventExport, to record: ConversationEvent) {
        record.roleID = item.roleID
        record.redacted = item.redacted
        record.memoryProcessedAt = item.memoryProcessedAt
        record.memoryProcessingVersion = item.memoryProcessingVersion
        record.deliveryStateRaw = item.deliveryStateRaw
        record.payloadKindRaw = item.payloadKindRaw
        record.stickerID = item.payloadKindRaw == MessagePayloadKind.sticker.rawValue
            ? item.stickerID
            : ""
        record.imageData = item.payloadKindRaw == MessagePayloadKind.image.rawValue
            ? item.imageData
            : nil
        record.fileName = item.payloadKindRaw == MessagePayloadKind.file.rawValue
            ? item.fileName
            : ""
        record.fileTypeIdentifier = item.payloadKindRaw == MessagePayloadKind.file.rawValue
            ? item.fileTypeIdentifier
            : ""
        record.fileData = item.payloadKindRaw == MessagePayloadKind.file.rawValue
            ? item.fileData
            : nil
        record.senderRoleID = item.senderRoleID
    }

    private static func apply(
        _ item: AyaneConversationReadStateExport,
        to record: ConversationReadStateRecord
    ) {
        // Keep the destination physical UUID. The scope `(roleID,
        // conversationID)` is the marker identity; adopting a source UUID
        // here could collide with another physical duplicate.
        record.roleID = resolvedRoleID(item.roleID)
        record.conversationID = item.conversationID
        record.lastReadOccurredAt = item.lastReadOccurredAt
        record.lastReadLogicalTimestamp = item.lastReadLogicalTimestamp
        record.lastReadEventID = item.lastReadEventID
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(
        _ item: AyaneMomentReadStateExport,
        to record: MomentReadStateRecord
    ) {
        // As above, preserve the destination row UUID while replacing only
        // the display cursor metadata.
        record.postID = item.postID
        record.lastReadCreatedAt = item.lastReadCreatedAt
        record.lastReadInteractionID = item.lastReadInteractionID
        record.updatedAt = item.updatedAt
        record.revision = item.revision
        record.deviceID = item.deviceID
    }

    private static func apply(_ item: AyaneMemoryExport, to record: MemoryAssertionRecord) throws {
        record.roleID = item.roleID
        record.kindRaw = item.kindRaw
        record.subject = item.subject
        record.predicate = item.predicate
        record.value = item.value
        record.canonicalKey = normalizeKey(item.canonicalKey)
        record.stateRaw = item.stateRaw
        record.confidence = item.confidence
        record.importance = item.importance
        record.sensitive = item.sensitive
        record.sourceRank = item.sourceRank
        record.validFrom = item.validFrom
        record.validTo = item.validTo
        record.observedAt = item.observedAt
        record.supersedesID = item.supersedesID
        record.extractorID = item.extractorID
        record.schemaVersion = item.schemaVersion
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
        record.isPinned = item.isPinned
        record.userVerified = item.userVerified
        if let base64 = item.embeddingBase64 {
            guard let data = Data(base64Encoded: base64) else {
                throw DataMergeError.invalidValue("记忆 \(item.id) 的向量数据损坏。")
            }
            record.embeddingData = data
        } else {
            record.embeddingData = nil
        }
        record.embeddingModelID = item.embeddingModelID
    }

    private static func apply(_ item: AyaneEvidenceExport, to record: MemoryEvidenceRecord) {
        record.roleID = item.roleID
        record.confidence = max(record.confidence, item.confidence)
        record.createdAt = min(record.createdAt, item.createdAt)
    }

    private static func apply(_ item: AyaneSummaryExport, to record: MemorySummaryRecord) {
        record.roleID = item.roleID
        record.conversationID = item.conversationID
        record.scope = item.scope
        record.content = item.content
        record.firstEventID = item.firstEventID
        record.lastEventID = item.lastEventID
        record.coveredEventCount = item.coveredEventCount
        record.extractorID = item.extractorID
        record.createdAt = item.createdAt
        record.updatedAt = item.updatedAt
    }

    private static func apply(_ item: AyaneTombstoneExport, to record: MemoryTombstoneRecord) {
        record.roleID = item.roleID
        record.canonicalKey = normalizeTombstoneKey(item.canonicalKey)
        record.canonicalKeyNormalizationVersion =
            MemoryTombstoneRecord.currentCanonicalKeyNormalizationVersion
        record.sourceEventIDsRaw = Set(item.sourceEventIDs)
            .sorted(by: stableUUIDLess)
            .map(\.uuidString)
            .joined(separator: ",")
        record.deletedAt = max(record.deletedAt, item.deletedAt)
    }
}

// The export DTOs intentionally expose only their record-backed initializer.
// These file-private constructors let the merge planner produce a modified
// value without making the DTO surface part of the app's public API.
fileprivate extension AyaneEventExport {
    init(
        mergeID id: UUID,
        conversationID: UUID,
        deviceID: String,
        deviceSequence: Int,
        logicalTimestamp: String,
        occurredAt: Date,
        recordedAt: Date,
        role: String,
        roleRaw: String,
        content: String,
        contentHash: String,
        parentEventID: UUID?,
        deliveryState: String,
        deliveryStateRaw: String,
        redacted: Bool,
        memoryProcessedAt: Date?,
        memoryProcessingVersion: Int,
        roleID: UUID? = nil,
        payloadKind: String = MessagePayloadKind.text.rawValue,
        payloadKindRaw: String? = nil,
        stickerID: String = "",
        senderRoleID: UUID? = nil,
        imageData: Data? = nil,
        fileName: String = "",
        fileTypeIdentifier: String = "",
        fileData: Data? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.conversationID = conversationID
        self.deviceID = deviceID
        self.deviceSequence = deviceSequence
        self.logicalTimestamp = logicalTimestamp
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.role = role
        self.roleRaw = roleRaw
        self.content = content
        self.contentHash = contentHash
        self.payloadKind = payloadKind
        self.payloadKindRaw = payloadKindRaw ?? payloadKind
        self.stickerID = stickerID
        self.senderRoleID = senderRoleID
        self.imageData = imageData
        self.fileName = fileName
        self.fileTypeIdentifier = fileTypeIdentifier
        self.fileData = fileData
        self.parentEventID = parentEventID
        self.deliveryState = deliveryState
        self.deliveryStateRaw = deliveryStateRaw
        self.redacted = redacted
        self.memoryProcessedAt = memoryProcessedAt
        self.memoryProcessingVersion = memoryProcessingVersion
    }
}

fileprivate extension AyaneMemoryExport {
    init(
        mergeID id: UUID,
        kind: String,
        kindRaw: String,
        subject: String,
        predicate: String,
        value: String,
        canonicalKey: String,
        state: String,
        stateRaw: String,
        confidence: Double,
        importance: Double,
        sensitive: Bool,
        sourceRank: Int,
        validFrom: Date?,
        validTo: Date?,
        observedAt: Date,
        supersedesID: UUID?,
        extractorID: String,
        schemaVersion: Int,
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool,
        userVerified: Bool,
        embeddingBase64: String?,
        embeddingModelID: String?,
        deviceID: String,
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.kind = kind
        self.kindRaw = kindRaw
        self.subject = subject
        self.predicate = predicate
        self.value = value
        self.canonicalKey = canonicalKey
        self.state = state
        self.stateRaw = stateRaw
        self.confidence = confidence
        self.importance = importance
        self.sensitive = sensitive
        self.sourceRank = sourceRank
        self.validFrom = validFrom
        self.validTo = validTo
        self.observedAt = observedAt
        self.supersedesID = supersedesID
        self.extractorID = extractorID
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.userVerified = userVerified
        self.embeddingBase64 = embeddingBase64
        self.embeddingModelID = embeddingModelID
        self.deviceID = deviceID
    }
}

fileprivate extension AyaneTombstoneExport {
    init(
        mergeID id: UUID,
        entityID: UUID,
        entityType: String,
        canonicalKey: String,
        sourceEventIDs: [UUID],
        deletedAt: Date,
        deviceID: String,
        reason: String,
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.entityID = entityID
        self.entityType = entityType
        self.canonicalKey = canonicalKey
        self.sourceEventIDs = sourceEventIDs
        self.deletedAt = deletedAt
        self.deviceID = deviceID
        self.reason = reason
    }
}

fileprivate extension AyaneEvidenceExport {
    init(
        mergeID id: UUID,
        memoryID: UUID,
        eventID: UUID,
        startUTF16: Int,
        endUTF16: Int,
        relation: String,
        relationRaw: String,
        quoteHash: String,
        confidence: Double,
        createdAt: Date,
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.memoryID = memoryID
        self.eventID = eventID
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.relation = relation
        self.relationRaw = relationRaw
        self.quoteHash = quoteHash
        self.confidence = confidence
        self.createdAt = createdAt
    }
}
