import Foundation
import SwiftData

/// A count of physical duplicate-reconciliation operations for one model type.
struct StoreDuplicateEntityReconcileCount: Equatable, Sendable {
    let removed: Int
    let updated: Int

    init(removed: Int = 0, updated: Int = 0) {
        self.removed = removed
        self.updated = updated
    }
}

/// The result of one duplicate reconciliation pass.
struct StoreDuplicateReconcileSummary: Equatable, Sendable {
    let profiles: StoreDuplicateEntityReconcileCount
    let userProfiles: StoreDuplicateEntityReconcileCount
    let momentPosts: StoreDuplicateEntityReconcileCount
    let momentInteractions: StoreDuplicateEntityReconcileCount
    let relationships: StoreDuplicateEntityReconcileCount
    let transitions: StoreDuplicateEntityReconcileCount
    let momentTasks: StoreDuplicateEntityReconcileCount
    let conversations: StoreDuplicateEntityReconcileCount
    let events: StoreDuplicateEntityReconcileCount
    let conversationReadStates: StoreDuplicateEntityReconcileCount
    let momentReadStates: StoreDuplicateEntityReconcileCount
    let memories: StoreDuplicateEntityReconcileCount
    let evidence: StoreDuplicateEntityReconcileCount
    let summaries: StoreDuplicateEntityReconcileCount
    let tombstones: StoreDuplicateEntityReconcileCount
    let worldProfiles: StoreDuplicateEntityReconcileCount
    let groupConversations: StoreDuplicateEntityReconcileCount
    let groupParticipants: StoreDuplicateEntityReconcileCount
    let chatTurnPresentations: StoreDuplicateEntityReconcileCount
    let proactiveMessageTasks: StoreDuplicateEntityReconcileCount
    let friendApplications: StoreDuplicateEntityReconcileCount

    init(
        profiles: StoreDuplicateEntityReconcileCount = .init(),
        userProfiles: StoreDuplicateEntityReconcileCount = .init(),
        momentPosts: StoreDuplicateEntityReconcileCount = .init(),
        momentInteractions: StoreDuplicateEntityReconcileCount = .init(),
        relationships: StoreDuplicateEntityReconcileCount = .init(),
        transitions: StoreDuplicateEntityReconcileCount = .init(),
        momentTasks: StoreDuplicateEntityReconcileCount = .init(),
        conversations: StoreDuplicateEntityReconcileCount = .init(),
        events: StoreDuplicateEntityReconcileCount = .init(),
        conversationReadStates: StoreDuplicateEntityReconcileCount = .init(),
        momentReadStates: StoreDuplicateEntityReconcileCount = .init(),
        memories: StoreDuplicateEntityReconcileCount = .init(),
        evidence: StoreDuplicateEntityReconcileCount = .init(),
        summaries: StoreDuplicateEntityReconcileCount = .init(),
        tombstones: StoreDuplicateEntityReconcileCount = .init(),
        worldProfiles: StoreDuplicateEntityReconcileCount = .init(),
        groupConversations: StoreDuplicateEntityReconcileCount = .init(),
        groupParticipants: StoreDuplicateEntityReconcileCount = .init(),
        chatTurnPresentations: StoreDuplicateEntityReconcileCount = .init(),
        proactiveMessageTasks: StoreDuplicateEntityReconcileCount = .init(),
        friendApplications: StoreDuplicateEntityReconcileCount = .init()
    ) {
        self.profiles = profiles
        self.userProfiles = userProfiles
        self.momentPosts = momentPosts
        self.momentInteractions = momentInteractions
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
        self.worldProfiles = worldProfiles
        self.groupConversations = groupConversations
        self.groupParticipants = groupParticipants
        self.chatTurnPresentations = chatTurnPresentations
        self.proactiveMessageTasks = proactiveMessageTasks
        self.friendApplications = friendApplications
    }

    var total: Int {
        let counts = [profiles, userProfiles, momentPosts, momentInteractions, relationships, transitions, momentTasks, conversations, events, conversationReadStates, momentReadStates, memories, evidence, summaries, tombstones, worldProfiles, groupConversations, groupParticipants, chatTurnPresentations, proactiveMessageTasks, friendApplications]
        return counts.reduce(0) { partial, count in
            partial + count.removed + count.updated
        }
    }

    var totalRemoved: Int {
        let counts = [profiles, userProfiles, momentPosts, momentInteractions, relationships, transitions, momentTasks, conversations, events, conversationReadStates, momentReadStates, memories, evidence, summaries, tombstones, worldProfiles, groupConversations, groupParticipants, chatTurnPresentations, proactiveMessageTasks, friendApplications]
        return counts.reduce(0) { $0 + $1.removed }
    }

    var totalUpdated: Int {
        let counts = [profiles, userProfiles, momentPosts, momentInteractions, relationships, transitions, momentTasks, conversations, events, conversationReadStates, momentReadStates, memories, evidence, summaries, tombstones, worldProfiles, groupConversations, groupParticipants, chatTurnPresentations, proactiveMessageTasks, friendApplications]
        return counts.reduce(0) { $0 + $1.updated }
    }

    var isNoOp: Bool { total == 0 }

    var conversationsRemoved: Int { conversations.removed }
    var conversationsUpdated: Int { conversations.updated }
    var eventsRemoved: Int { events.removed }
    var eventsUpdated: Int { events.updated }
    var conversationReadStatesRemoved: Int { conversationReadStates.removed }
    var conversationReadStatesUpdated: Int { conversationReadStates.updated }
    var momentReadStatesRemoved: Int { momentReadStates.removed }
    var momentReadStatesUpdated: Int { momentReadStates.updated }
    var memoriesRemoved: Int { memories.removed }
    var memoriesUpdated: Int { memories.updated }
    var evidenceRemoved: Int { evidence.removed }
    var evidenceUpdated: Int { evidence.updated }
    var summariesRemoved: Int { summaries.removed }
    var summariesUpdated: Int { summaries.updated }
    var tombstonesRemoved: Int { tombstones.removed }
    var tombstonesUpdated: Int { tombstones.updated }
    var profilesRemoved: Int { profiles.removed }
    var profilesUpdated: Int { profiles.updated }
    var userProfilesRemoved: Int { userProfiles.removed }
    var userProfilesUpdated: Int { userProfiles.updated }
    var momentPostsRemoved: Int { momentPosts.removed }
    var momentPostsUpdated: Int { momentPosts.updated }
    var momentInteractionsRemoved: Int { momentInteractions.removed }
    var momentInteractionsUpdated: Int { momentInteractions.updated }
    var relationshipsRemoved: Int { relationships.removed }
    var relationshipsUpdated: Int { relationships.updated }
    var transitionsRemoved: Int { transitions.removed }
    var transitionsUpdated: Int { transitions.updated }
    var momentTasksRemoved: Int { momentTasks.removed }
    var momentTasksUpdated: Int { momentTasks.updated }
    var friendApplicationsRemoved: Int { friendApplications.removed }
    var friendApplicationsUpdated: Int { friendApplications.updated }
}

enum StoreDuplicateReconcileError: LocalizedError, Equatable {
    case profileConflict(UUID)
    case userProfileConflict(UUID)
    case momentPostConflict(UUID)
    case momentInteractionConflict(UUID)
    case conversationConflict(UUID)
    case eventConflict(UUID)
    case memoryConflict(UUID)
    case evidenceConflict(UUID)
    case summaryConflict(UUID)
    case tombstoneConflict(UUID)
    case relationshipConflict(UUID)
    case transitionConflict(UUID)
    case momentTaskConflict(UUID)
    case conversationReadStateConflict(UUID)
    case momentReadStateConflict(UUID)

    var errorDescription: String? {
        switch self {
        case .profileConflict(let id):
            return "Persona (\(id.uuidString)) 的重复物理对象包含无效内容。"
        case .userProfileConflict(let id):
            return "用户资料 (\(id.uuidString)) 的重复物理对象包含无效内容。"
        case .momentPostConflict(let id):
            return "朋友圈 (\(id.uuidString)) 的重复物理对象包含冲突身份或无效内容。"
        case .momentInteractionConflict(let id):
            return "朋友圈互动 (\(id.uuidString)) 的重复物理对象包含冲突身份或无效内容。"
        case .conversationConflict(let id):
            return "会话 (\(id.uuidString)) 的重复物理对象属于不同角色。"
        case .eventConflict(let id):
            return "事件 (\(id.uuidString)) 的重复物理对象包含不一致的不可变身份或原文。"
        case .memoryConflict(let id):
            return "记忆 (\(id.uuidString)) 的重复物理对象属于不同角色。"
        case .evidenceConflict(let id):
            return "证据 (\(id.uuidString)) 的重复物理对象包含不一致的引用身份。"
        case .summaryConflict(let id):
            return "摘要 (\(id.uuidString)) 的重复物理对象属于不同角色。"
        case .tombstoneConflict(let id):
            return "墓碑 (\(id.uuidString)) 的重复物理对象包含不一致的删除身份。"
        case .relationshipConflict(let id):
            return "关系 (\(id.uuidString)) 的重复物理对象包含无效或不安全的状态。"
        case .transitionConflict(let id):
            return "关系变更 (\(id.uuidString)) 的重复物理对象身份冲突，未执行收敛。"
        case .momentTaskConflict(let id):
            return "朋友圈任务 (\(id.uuidString)) 的重复物理对象包含冲突的终态或发布结果。"
        case .conversationReadStateConflict(let id):
            return "会话已读状态 (\(id.uuidString)) 的重复物理对象属于不同角色或会话。"
        case .momentReadStateConflict(let id):
            return "朋友圈已读状态 (\(id.uuidString)) 的重复物理对象属于不同帖子。"
        }
    }
}

/// Collapses SwiftData physical duplicates which share an application-level UUID.
///
/// SwiftData's backing identity is distinct from the UUID fields used by Ayane's
/// CloudKit-safe references. A delayed import can therefore leave two model
/// objects with the same `id`. This reconciler deliberately handles only those
/// groups. Objects with an independent application UUID are never deleted.
@MainActor
enum StoreDuplicateReconciler {
    private struct ConversationReadStateScope: Hashable {
        let roleID: UUID
        let conversationID: UUID
    }

    /// Duplicate checks run on app startup and after CloudKit imports. Keep the
    /// source scan paged so a large, mostly unique history does not need to be
    /// materialized as seven full SwiftData arrays merely to prove that no
    /// duplicate application UUID exists.
    private static let duplicateScanBatchSize = 256

    private struct ProfilePlan {
        let winner: CompanionProfileRecord
        let duplicates: [CompanionProfileRecord]
    }

    private struct UserProfilePlan {
        let winner: UserProfileRecord
        let duplicates: [UserProfileRecord]
    }

    private struct MomentPostPlan {
        let winner: MomentPostRecord
        let duplicates: [MomentPostRecord]
    }

    private struct MomentInteractionPlan {
        let winner: MomentInteractionRecord
        let duplicates: [MomentInteractionRecord]
        /// The newest tombstone found in the duplicate group. This is kept as
        /// plan data rather than mutating `winner` during preflight, because
        /// `makePlan` is also used by read-only source canonicalization.
        let deletedAt: Date?
    }

    private struct RelationshipPlan {
        let winner: CompanionRelationshipRecord
        let duplicates: [CompanionRelationshipRecord]
        let manualAffinityScore: Double?
        let manualAffinityUpdatedAt: Date?
        let changes: Bool
    }

    private struct TransitionPlan {
        let winner: CompanionRelationshipTransitionRecord
        let duplicates: [CompanionRelationshipTransitionRecord]
    }

    private struct MomentTaskPlan {
        let winner: CompanionMomentTaskRecord
        let duplicates: [CompanionMomentTaskRecord]
    }

    private struct ConversationPlan {
        let winner: ConversationRecord
        let duplicates: [ConversationRecord]
        let createdAt: Date
        let updatedAt: Date
        let title: String
        let archived: Bool
        let changes: Bool
    }

    private struct EventPlan {
        let winner: ConversationEvent
        let duplicates: [ConversationEvent]
        let occurredAt: Date
        let recordedAt: Date
        let redacted: Bool
        let memoryProcessedAt: Date?
        let memoryProcessingVersion: Int
        let deliveryStateRaw: String
        let changes: Bool
    }

    private struct ConversationReadStatePlan {
        let winner: ConversationReadStateRecord
        let duplicates: [ConversationReadStateRecord]
    }

    private struct MomentReadStatePlan {
        let winner: MomentReadStateRecord
        let duplicates: [MomentReadStateRecord]
    }

    private struct MemoryPlan {
        let winner: MemoryAssertionRecord
        let duplicates: [MemoryAssertionRecord]
        let createdAt: Date
        let updatedAt: Date
        let value: String
        let confidence: Double
        let importance: Double
        let sensitive: Bool
        let isPinned: Bool
        let userVerified: Bool
        let stateRaw: String
        let embeddingData: Data?
        let embeddingModelID: String?
        let changes: Bool
    }

    private struct EvidencePlan {
        let winner: MemoryEvidenceRecord
        let duplicates: [MemoryEvidenceRecord]
        let confidence: Double
        let createdAt: Date
        let changes: Bool
    }

    private struct SummaryPlan {
        let winner: MemorySummaryRecord
        let duplicates: [MemorySummaryRecord]
    }

    private struct TombstonePlan {
        let winner: MemoryTombstoneRecord
        let duplicates: [MemoryTombstoneRecord]
        let sourceEventIDs: [UUID]
        let deletedAt: Date
        let changes: Bool
    }

    private struct Plan {
        let profiles: [ProfilePlan]
        let userProfiles: [UserProfilePlan]
        let momentPosts: [MomentPostPlan]
        let momentInteractions: [MomentInteractionPlan]
        let relationships: [RelationshipPlan]
        let transitions: [TransitionPlan]
        let momentTasks: [MomentTaskPlan]
        let conversations: [ConversationPlan]
        let events: [EventPlan]
        let conversationReadStates: [ConversationReadStatePlan]
        let momentReadStates: [MomentReadStatePlan]
        let memories: [MemoryPlan]
        let evidence: [EvidencePlan]
        let summaries: [SummaryPlan]
        let tombstones: [TombstonePlan]
    }

    /// Performs a read-only preflight followed by one save if changes exist.
    ///
    /// All conflict checks happen in `makePlan` before any model is modified. If
    /// SwiftData rejects the single save, `rollback()` restores the context to
    /// its pre-apply state.
    static func preflight(
        context: ModelContext,
        scanBatchSize: Int = 256
    ) throws -> StoreDuplicateReconcileSummary {
        let oldSummary = try summary(for: makePlan(context: context, scanBatchSize: scanBatchSize))
        return adding(oldSummary, schemaV11: SchemaV11DataSupport.duplicateSummary(context: context))
    }

    @discardableResult
    static func reconcile(
        context: ModelContext,
        scanBatchSize: Int = 256
    ) throws -> StoreDuplicateReconcileSummary {
        do {
            let summary = try stage(context: context, scanBatchSize: scanBatchSize)
            if !summary.isNoOp {
                try context.save()
            }
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Applies a fully preflighted duplicate-collapse plan to the context
    /// without saving it. Migration uses this form only for the destination so
    /// canonicalization and the subsequent merge share one atomic `save()`.
    @discardableResult
    static func stage(
        context: ModelContext,
        scanBatchSize: Int = 256
    ) throws -> StoreDuplicateReconcileSummary {
        let plan = try makePlan(context: context, scanBatchSize: scanBatchSize)
        let oldSummary = isEmpty(plan)
            ? StoreDuplicateReconcileSummary()
            : apply(plan, context: context)
        let schemaV11Summary = try SchemaV11DataSupport.reconcileDuplicates(
            context: context,
            save: false
        )
        return adding(oldSummary, schemaV11: schemaV11Summary)
    }

    private static func adding(
        _ summary: StoreDuplicateReconcileSummary,
        schemaV11: SchemaV11DataSupport.DuplicateSummary
    ) -> StoreDuplicateReconcileSummary {
        StoreDuplicateReconcileSummary(
            profiles: summary.profiles,
            userProfiles: summary.userProfiles,
            momentPosts: summary.momentPosts,
            momentInteractions: summary.momentInteractions,
            relationships: summary.relationships,
            transitions: summary.transitions,
            momentTasks: summary.momentTasks,
            conversations: summary.conversations,
            events: summary.events,
            conversationReadStates: summary.conversationReadStates,
            momentReadStates: summary.momentReadStates,
            memories: summary.memories,
            evidence: summary.evidence,
            summaries: summary.summaries,
            tombstones: summary.tombstones,
            worldProfiles: .init(removed: schemaV11.worldProfiles),
            groupConversations: .init(removed: schemaV11.groupConversations),
            groupParticipants: .init(removed: schemaV11.groupParticipants),
            chatTurnPresentations: .init(removed: schemaV11.chatTurnPresentations),
            proactiveMessageTasks: .init(removed: schemaV11.proactiveMessageTasks),
            friendApplications: .init(removed: schemaV11.friendApplications)
        )
    }

    /// Produces a canonical source snapshot without ever saving source changes.
    ///
    /// The duplicate plan is projected directly into immutable export values.
    /// No source object is mutated or deleted, which avoids SwiftData's unsafe
    /// fetch-after-pending-delete path and makes this operation strictly
    /// read-only.
    static func makeCanonicalPayload(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> AyaneDataExport {
        let plan = try makePlan(
            context: context,
            scanBatchSize: duplicateScanBatchSize
        )
        guard !isEmpty(plan) else {
            return try DataExportService.makePayload(
                context: context,
                defaults: defaults,
                now: now
            )
        }

        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        let userProfiles = try context.fetch(FetchDescriptor<UserProfileRecord>())
        let momentPosts = try context.fetch(FetchDescriptor<MomentPostRecord>())
        let momentInteractions = try context.fetch(FetchDescriptor<MomentInteractionRecord>())
        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
        let transitions = try context.fetch(FetchDescriptor<CompanionRelationshipTransitionRecord>())
        let momentTasks = try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>())
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        let conversationReadStates = try context.fetch(
            FetchDescriptor<ConversationReadStateRecord>()
        )
        let momentReadStates = try context.fetch(
            FetchDescriptor<MomentReadStateRecord>()
        )
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>())
        let summaries = try context.fetch(FetchDescriptor<MemorySummaryRecord>())
        let tombstones = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>())
        let worldProfiles = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        let groupConversations = try context.fetch(FetchDescriptor<GroupConversationRecord>())
        let groupParticipants = try context.fetch(FetchDescriptor<GroupParticipantRecord>())
        let chatTurnPresentations = try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
        let proactiveMessageTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let friendApplications = try context.fetch(FetchDescriptor<FriendApplicationRecord>())

        let plannedProfileIDs = Set(plan.profiles.map { $0.winner.id })
        let plannedMomentPostIDs = Set(plan.momentPosts.map { $0.winner.id })
        let plannedMomentInteractionIDs = Set(plan.momentInteractions.map { $0.winner.id })
        let plannedRelationshipRoles = Set(plan.relationships.map { $0.winner.roleID })
        let plannedTransitionIDs = Set(plan.transitions.map { $0.winner.id })
        let plannedMomentTaskIDs = Set(plan.momentTasks.map { $0.winner.id })
        let plannedConversationIDs = Set(plan.conversations.map { $0.winner.id })
        let plannedEventIDs = Set(plan.events.map { $0.winner.id })
        let plannedConversationReadStateScopes = Set(
            plan.conversationReadStates.map {
                ConversationReadStateScope(
                    roleID: $0.winner.resolvedRoleID,
                    conversationID: $0.winner.conversationID
                )
            }
        )
        let plannedMomentReadStatePostIDs = Set(
            plan.momentReadStates.map { $0.winner.postID }
        )
        let plannedMemoryIDs = Set(plan.memories.map { $0.winner.id })
        let plannedEvidenceIDs = Set(plan.evidence.map { $0.winner.id })
        let plannedSummaryIDs = Set(plan.summaries.map { $0.winner.id })
        let plannedTombstoneIDs = Set(plan.tombstones.map { $0.winner.id })

        let profileExports = profiles
            .filter { !plannedProfileIDs.contains($0.id) }
            .map(AyanePersonaExport.init)
            + plan.profiles.map { AyanePersonaExport($0.winner) }
        let userProfileExport: AyaneUserProfileExport? = {
            if let winner = plan.userProfiles.first?.winner {
                return AyaneUserProfileExport(winner)
            }
            return userProfiles
                .first(where: { $0.id == UserProfileRecord.singletonID })
                .map(AyaneUserProfileExport.init)
        }()
        let momentPostExports = momentPosts
            .filter { !plannedMomentPostIDs.contains($0.id) }
            .map(AyaneMomentPostExport.init)
            + plan.momentPosts.map { AyaneMomentPostExport($0.winner) }
        let momentInteractionExports = momentInteractions
            .filter { !plannedMomentInteractionIDs.contains($0.id) }
            .map(AyaneMomentInteractionExport.init)
            + plan.momentInteractions.map { item in
                var export = AyaneMomentInteractionExport(item.winner)
                if let deletedAt = item.deletedAt {
                    export.deletedAt = deletedAt
                }
                return export
            }
        let relationshipExports = relationships
            .filter { !plannedRelationshipRoles.contains($0.roleID) }
            .map(AyaneRelationshipExport.init)
            + plan.relationships.map { item in
                var export = AyaneRelationshipExport(item.winner)
                export.manualAffinityScore = item.manualAffinityScore
                export.manualAffinityUpdatedAt = item.manualAffinityUpdatedAt
                return export
            }
        let transitionExports = transitions
            .filter { !plannedTransitionIDs.contains($0.id) }
            .map(AyaneRelationshipTransitionExport.init)
            + plan.transitions.map { AyaneRelationshipTransitionExport($0.winner) }
        let momentTaskExports = momentTasks
            .filter { !plannedMomentTaskIDs.contains($0.id) }
            .map(AyaneMomentTaskExport.init)
            + plan.momentTasks.map { AyaneMomentTaskExport($0.winner) }
        let conversationExports = conversations
            .filter { !plannedConversationIDs.contains($0.id) }
            .map(AyaneConversationExport.init)
            + plan.conversations.map {
                AyaneConversationExport(
                    $0.winner,
                    title: $0.title,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    archived: $0.archived
                )
            }
        let eventExports = events
            .filter { !plannedEventIDs.contains($0.id) }
            .map(AyaneEventExport.init)
            + plan.events.map {
                AyaneEventExport(
                    $0.winner,
                    occurredAt: $0.occurredAt,
                    recordedAt: $0.recordedAt,
                    deliveryStateRaw: $0.deliveryStateRaw,
                    redacted: $0.redacted,
                    memoryProcessedAt: $0.memoryProcessedAt,
                memoryProcessingVersion: $0.memoryProcessingVersion
                )
            }
        let conversationReadStateExports = conversationReadStates
            .filter {
                !plannedConversationReadStateScopes.contains(
                    ConversationReadStateScope(
                        roleID: $0.resolvedRoleID,
                        conversationID: $0.conversationID
                    )
                )
            }
            .map(AyaneConversationReadStateExport.init)
            + plan.conversationReadStates.map {
                AyaneConversationReadStateExport($0.winner)
            }
        let momentReadStateExports = momentReadStates
            .filter { !plannedMomentReadStatePostIDs.contains($0.postID) }
            .map(AyaneMomentReadStateExport.init)
            + plan.momentReadStates.map {
                AyaneMomentReadStateExport($0.winner)
            }
        let memoryExports = memories
            .filter { !plannedMemoryIDs.contains($0.id) }
            .map(AyaneMemoryExport.init)
            + plan.memories.map {
                AyaneMemoryExport(
                    projecting: $0.winner,
                    value: $0.value,
                    stateRaw: $0.stateRaw,
                    confidence: $0.confidence,
                    importance: $0.importance,
                    sensitive: $0.sensitive,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    isPinned: $0.isPinned,
                    userVerified: $0.userVerified,
                    embeddingData: $0.embeddingData,
                    embeddingModelID: $0.embeddingModelID
                )
            }
        let evidenceExports = evidence
            .filter { !plannedEvidenceIDs.contains($0.id) }
            .map(AyaneEvidenceExport.init)
            + plan.evidence.map {
                AyaneEvidenceExport(
                    $0.winner,
                    confidence: $0.confidence,
                    createdAt: $0.createdAt
                )
            }
        let summaryExports = summaries
            .filter { !plannedSummaryIDs.contains($0.id) }
            .map(AyaneSummaryExport.init)
            + plan.summaries.map { AyaneSummaryExport($0.winner) }
        let tombstoneExports = tombstones
            .filter { !plannedTombstoneIDs.contains($0.id) }
            .map(AyaneTombstoneExport.init)
            + plan.tombstones.map {
                AyaneTombstoneExport(
                    $0.winner,
                    sourceEventIDs: $0.sourceEventIDs,
                    deletedAt: $0.deletedAt
                )
            }

        return DataExportService.makePayload(
            profiles: profileExports,
            conversations: conversationExports,
            events: eventExports,
            memories: memoryExports,
            evidence: evidenceExports,
            summaries: summaryExports,
            tombstones: tombstoneExports,
            relationships: relationshipExports,
            friendApplications: friendApplications.map(AyaneFriendApplicationExport.init),
            transitions: transitionExports,
            momentTasks: momentTaskExports,
            userProfile: userProfileExport,
            momentPosts: momentPostExports,
            momentInteractions: momentInteractionExports,
            conversationReadStates: conversationReadStateExports,
            momentReadStates: momentReadStateExports,
            worldProfile: worldProfiles.first(where: {
                $0.id == WorldProfileRecord.realityID
            }).map(AyaneWorldProfileExport.init)
                ?? worldProfiles.first.map(AyaneWorldProfileExport.init)
                ?? .realityDefault,
            worldProfiles: worldProfiles.map(AyaneWorldProfileExport.init),
            groupConversations: groupConversations.map(AyaneGroupConversationExport.init),
            groupParticipants: groupParticipants.map(AyaneGroupParticipantExport.init),
            chatTurnPresentations: chatTurnPresentations.map(AyaneChatTurnPresentationExport.init),
            proactiveMessageTasks: proactiveMessageTasks.map(AyaneProactiveMessageTaskExport.init),
            defaults: defaults,
            now: now
        )
    }

    private static func makePlan(
        context: ModelContext,
        scanBatchSize: Int
    ) throws -> Plan {
        try validateReadStatePhysicalIdentities(context: context)

        let profilePlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<CompanionProfileRecord>(
                    sortBy: [SortDescriptor(\CompanionProfileRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \CompanionProfileRecord.id,
            batchSize: scanBatchSize,
            validate: validateProfile
        )
            .map { try profilePlan($0.value) }

        let userProfilePlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<UserProfileRecord>(
                    sortBy: [SortDescriptor(\UserProfileRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \UserProfileRecord.id,
            batchSize: scanBatchSize,
            validate: validateUserProfile
        )
            .map { try userProfilePlan($0.value) }

        let momentPostPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MomentPostRecord>(
                    sortBy: [SortDescriptor(\MomentPostRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MomentPostRecord.id,
            batchSize: scanBatchSize,
            validate: validateMomentPost
        )
            .map { try momentPostPlan($0.value) }

        let momentInteractionPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MomentInteractionRecord>(
                    sortBy: [SortDescriptor(\MomentInteractionRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MomentInteractionRecord.id,
            batchSize: scanBatchSize,
            validate: validateMomentInteraction
        )
            .map { try momentInteractionPlan($0.value) }

        let relationshipPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<CompanionRelationshipRecord>(
                    sortBy: [
                        SortDescriptor(\CompanionRelationshipRecord.roleID, order: .forward),
                        SortDescriptor(\CompanionRelationshipRecord.id, order: .forward)
                    ]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \CompanionRelationshipRecord.roleID,
            batchSize: scanBatchSize
        )
            .map { try relationshipPlan($0.value) }

        let transitionPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<CompanionRelationshipTransitionRecord>(
                    sortBy: [SortDescriptor(\CompanionRelationshipTransitionRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \CompanionRelationshipTransitionRecord.id,
            batchSize: scanBatchSize
        )
            .map { try transitionPlan($0.value) }

        let momentTaskPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<CompanionMomentTaskRecord>(
                    sortBy: [SortDescriptor(\CompanionMomentTaskRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \CompanionMomentTaskRecord.id,
            batchSize: scanBatchSize,
            validate: validateMomentTask
        )
            .map { try momentTaskPlan($0.value) }

        let conversationPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<ConversationRecord>(
                    sortBy: [SortDescriptor(\ConversationRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \ConversationRecord.id,
            batchSize: scanBatchSize
        )
            .map { try conversationPlan($0) }

        let eventPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<ConversationEvent>(
                    sortBy: [SortDescriptor(\ConversationEvent.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \ConversationEvent.id,
            batchSize: scanBatchSize,
            validate: validateEventPayload
        )
            .map { try eventPlan($0.value) }

        let conversationReadStatePlans = try duplicateGroupsByKey(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<ConversationReadStateRecord>(
                    sortBy: [
                        SortDescriptor(\ConversationReadStateRecord.roleID, order: .forward),
                        SortDescriptor(\ConversationReadStateRecord.conversationID, order: .forward),
                        SortDescriptor(\ConversationReadStateRecord.id, order: .forward)
                    ]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            key: {
                ConversationReadStateScope(
                    roleID: $0.resolvedRoleID,
                    conversationID: $0.conversationID
                )
            },
            batchSize: scanBatchSize,
            validate: validateConversationReadState
        )
            .map { try conversationReadStatePlan($0.value) }

        let momentReadStatePlans = try duplicateGroupsByKey(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MomentReadStateRecord>(
                    sortBy: [
                        SortDescriptor(\MomentReadStateRecord.postID, order: .forward),
                        SortDescriptor(\MomentReadStateRecord.id, order: .forward)
                    ]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            key: \.postID,
            batchSize: scanBatchSize,
            validate: validateMomentReadState
        )
            .map { try momentReadStatePlan($0.value) }

        let memoryPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MemoryAssertionRecord>(
                    sortBy: [SortDescriptor(\MemoryAssertionRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MemoryAssertionRecord.id,
            batchSize: scanBatchSize
        )
            .map { try memoryPlan($0) }

        let evidencePlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MemoryEvidenceRecord>(
                    sortBy: [SortDescriptor(\MemoryEvidenceRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MemoryEvidenceRecord.id,
            batchSize: scanBatchSize
        )
            .map { try evidencePlan($0.value) }

        let summaryPlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MemorySummaryRecord>(
                    sortBy: [SortDescriptor(\MemorySummaryRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MemorySummaryRecord.id,
            batchSize: scanBatchSize
        )
            .map { try summaryPlan($0) }

        let tombstonePlans = try duplicateGroups(
            fetchPage: { offset, limit in
                var descriptor = FetchDescriptor<MemoryTombstoneRecord>(
                    sortBy: [SortDescriptor(\MemoryTombstoneRecord.id, order: .forward)]
                )
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = limit
                return try context.fetch(descriptor)
            },
            id: \MemoryTombstoneRecord.id,
            batchSize: scanBatchSize
        )
            .map { try tombstonePlan($0.value) }

        return Plan(
            profiles: profilePlans,
            userProfiles: userProfilePlans,
            momentPosts: momentPostPlans,
            momentInteractions: momentInteractionPlans,
            relationships: relationshipPlans,
            transitions: transitionPlans,
            momentTasks: momentTaskPlans,
            conversations: conversationPlans,
            events: eventPlans,
            conversationReadStates: conversationReadStatePlans,
            momentReadStates: momentReadStatePlans,
            memories: memoryPlans,
            evidence: evidencePlans,
            summaries: summaryPlans,
            tombstones: tombstonePlans
        )
    }

    private static func validateReadStatePhysicalIdentities(
        context: ModelContext
    ) throws {
        var conversationScopes: [UUID: ConversationReadStateScope] = [:]
        for state in try context.fetch(FetchDescriptor<ConversationReadStateRecord>()) {
            let scope = ConversationReadStateScope(
                roleID: state.resolvedRoleID,
                conversationID: state.conversationID
            )
            if let existing = conversationScopes[state.id], existing != scope {
                throw StoreDuplicateReconcileError.conversationReadStateConflict(state.id)
            }
            conversationScopes[state.id] = scope
        }

        var momentPosts: [UUID: UUID] = [:]
        for state in try context.fetch(FetchDescriptor<MomentReadStateRecord>()) {
            if let existing = momentPosts[state.id], existing != state.postID {
                throw StoreDuplicateReconcileError.momentReadStateConflict(state.id)
            }
            momentPosts[state.id] = state.postID
        }
    }

    /// Returns only physical duplicate groups while releasing each page of
    /// unique rows before fetching the next page. Sorting by the application
    /// UUID keeps every duplicate group contiguous; `pendingGroup` bridges a
    /// group that straddles two page boundaries.
    private static func duplicateGroups<Element>(
        fetchPage: (_ offset: Int, _ limit: Int) throws -> [Element],
        id: KeyPath<Element, UUID>,
        batchSize: Int,
        validate: (Element) throws -> Void = { _ in }
    ) throws -> [(key: UUID, value: [Element])] {
        let boundedBatchSize = max(1, batchSize)
        var offset = 0
        var pendingID: UUID?
        var pendingGroup: [Element] = []
        var duplicates: [(key: UUID, value: [Element])] = []

        while true {
            let page = try fetchPage(offset, boundedBatchSize)
            guard !page.isEmpty else { break }
            offset += page.count

            for record in page {
                try validate(record)
                let recordID = record[keyPath: id]
                if pendingID == recordID {
                    pendingGroup.append(record)
                    continue
                }

                if let pendingID, pendingGroup.count > 1 {
                    duplicates.append((pendingID, pendingGroup))
                }
                pendingID = recordID
                pendingGroup = [record]
            }

            if page.count < boundedBatchSize { break }
        }

        if let pendingID, pendingGroup.count > 1 {
            duplicates.append((pendingID, pendingGroup))
        }
        return duplicates
    }

    /// Variant used for models whose logical identity is a compound scope
    /// rather than their physical UUID. Pages are sorted by the same key in
    /// the caller, and this bridge keeps a scope that straddles two pages.
    private static func duplicateGroupsByKey<Element, Key: Hashable>(
        fetchPage: (_ offset: Int, _ limit: Int) throws -> [Element],
        key: (Element) -> Key,
        batchSize: Int,
        validate: (Element) throws -> Void = { _ in }
    ) throws -> [(key: Key, value: [Element])] {
        let boundedBatchSize = max(1, batchSize)
        var offset = 0
        var pendingKey: Key?
        var pendingGroup: [Element] = []
        var duplicates: [(key: Key, value: [Element])] = []

        while true {
            let page = try fetchPage(offset, boundedBatchSize)
            guard !page.isEmpty else { break }
            offset += page.count

            for record in page {
                try validate(record)
                let recordKey = key(record)
                if pendingKey == recordKey {
                    pendingGroup.append(record)
                    continue
                }

                if let pendingKey, pendingGroup.count > 1 {
                    duplicates.append((pendingKey, pendingGroup))
                }
                pendingKey = recordKey
                pendingGroup = [record]
            }

            if page.count < boundedBatchSize { break }
        }

        if let pendingKey, pendingGroup.count > 1 {
            duplicates.append((pendingKey, pendingGroup))
        }
        return duplicates
    }

    private static func apply(
        _ plan: Plan,
        context: ModelContext
    ) -> StoreDuplicateReconcileSummary {
        var profileCount = StoreDuplicateEntityReconcileCount()
        for item in plan.profiles {
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            profileCount = add(
                profileCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var userProfileCount = StoreDuplicateEntityReconcileCount()
        for item in plan.userProfiles {
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            userProfileCount = add(
                userProfileCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var momentPostCount = StoreDuplicateEntityReconcileCount()
        for item in plan.momentPosts {
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            momentPostCount = add(
                momentPostCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var momentInteractionCount = StoreDuplicateEntityReconcileCount()
        for item in plan.momentInteractions {
            let changed = item.deletedAt != item.winner.deletedAt
            if let deletedAt = item.deletedAt {
                item.winner.deletedAt = deletedAt
            }
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            momentInteractionCount = add(
                momentInteractionCount,
                removed: item.duplicates.count,
                updated: changed ? 1 : 0
            )
        }

        var relationshipCount = StoreDuplicateEntityReconcileCount()
        for item in plan.relationships {
            item.winner.manualAffinityScore = item.manualAffinityScore
            item.winner.manualAffinityUpdatedAt = item.manualAffinityUpdatedAt
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            relationshipCount = add(
                relationshipCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        var transitionCount = StoreDuplicateEntityReconcileCount()
        for item in plan.transitions {
            // Transition fields are immutable. Exact identity was checked in
            // makePlan before any delete is staged; only byte-identical
            // duplicate rows are removed here.
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            transitionCount = add(
                transitionCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var momentTaskCount = StoreDuplicateEntityReconcileCount()
        for item in plan.momentTasks {
            // Terminal-state ordering and published-result conflicts were
            // validated before staging. Keep the selected winner untouched so
            // an active lease remains available to the scheduler.
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            momentTaskCount = add(
                momentTaskCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var conversationCount = StoreDuplicateEntityReconcileCount()
        for item in plan.conversations {
            item.winner.createdAt = item.createdAt
            item.winner.updatedAt = item.updatedAt
            item.winner.title = item.title
            item.winner.archived = item.archived
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            conversationCount = add(
                conversationCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        var eventCount = StoreDuplicateEntityReconcileCount()
        for item in plan.events {
            // occurredAt is an immutable event timestamp, but it is selected
            // from the deterministic physical winner. JSON round-trips may
            // quantize this value, so it is intentionally not a conflict key.
            item.winner.occurredAt = item.occurredAt
            item.winner.recordedAt = item.recordedAt
            item.winner.redacted = item.redacted
            item.winner.memoryProcessedAt = item.memoryProcessedAt
            item.winner.memoryProcessingVersion = item.memoryProcessingVersion
            item.winner.deliveryStateRaw = item.deliveryStateRaw
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            eventCount = add(
                eventCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        var conversationReadStateCount = StoreDuplicateEntityReconcileCount()
        for item in plan.conversationReadStates {
            // The winner is selected by cursor-first ordering during
            // preflight. Its row already carries the maximum safe progress;
            // only the lower-progress physical copies are removed.
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            conversationReadStateCount = add(
                conversationReadStateCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var momentReadStateCount = StoreDuplicateEntityReconcileCount()
        for item in plan.momentReadStates {
            // As with chat markers, never copy a lower cursor over the
            // selected winner and never touch the post/interaction models.
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            momentReadStateCount = add(
                momentReadStateCount,
                removed: item.duplicates.count,
                updated: 0
            )
        }

        var memoryCount = StoreDuplicateEntityReconcileCount()
        for item in plan.memories {
            item.winner.createdAt = item.createdAt
            item.winner.updatedAt = item.updatedAt
            item.winner.value = item.value
            item.winner.confidence = item.confidence
            item.winner.importance = item.importance
            item.winner.sensitive = item.sensitive
            item.winner.isPinned = item.isPinned
            item.winner.userVerified = item.userVerified
            item.winner.stateRaw = item.stateRaw
            item.winner.embeddingData = item.embeddingData
            item.winner.embeddingModelID = item.embeddingModelID
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            memoryCount = add(
                memoryCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        var evidenceCount = StoreDuplicateEntityReconcileCount()
        for item in plan.evidence {
            item.winner.confidence = item.confidence
            item.winner.createdAt = item.createdAt
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            evidenceCount = add(
                evidenceCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        var summaryCount = StoreDuplicateEntityReconcileCount()
        for item in plan.summaries {
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            summaryCount = add(summaryCount, removed: item.duplicates.count, updated: 0)
        }

        var tombstoneCount = StoreDuplicateEntityReconcileCount()
        for item in plan.tombstones {
            item.winner.sourceEventIDsRaw = encodeUUIDs(item.sourceEventIDs)
            item.winner.deletedAt = item.deletedAt
            for duplicate in item.duplicates {
                context.delete(duplicate)
            }
            tombstoneCount = add(
                tombstoneCount,
                removed: item.duplicates.count,
                updated: item.changes ? 1 : 0
            )
        }

        return StoreDuplicateReconcileSummary(
            profiles: profileCount,
            userProfiles: userProfileCount,
            momentPosts: momentPostCount,
            momentInteractions: momentInteractionCount,
            relationships: relationshipCount,
            transitions: transitionCount,
            momentTasks: momentTaskCount,
            conversations: conversationCount,
            events: eventCount,
            conversationReadStates: conversationReadStateCount,
            momentReadStates: momentReadStateCount,
            memories: memoryCount,
            evidence: evidenceCount,
            summaries: summaryCount,
            tombstones: tombstoneCount
        )
    }

    private static func summary(for plan: Plan) -> StoreDuplicateReconcileSummary {
        StoreDuplicateReconcileSummary(
            profiles: StoreDuplicateEntityReconcileCount(
                removed: plan.profiles.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            userProfiles: StoreDuplicateEntityReconcileCount(
                removed: plan.userProfiles.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            momentPosts: StoreDuplicateEntityReconcileCount(
                removed: plan.momentPosts.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            momentInteractions: StoreDuplicateEntityReconcileCount(
                removed: plan.momentInteractions.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.momentInteractions.reduce(0) {
                    $0 + ($1.deletedAt != $1.winner.deletedAt ? 1 : 0)
                }
            ),
            relationships: StoreDuplicateEntityReconcileCount(
                removed: plan.relationships.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            transitions: StoreDuplicateEntityReconcileCount(
                removed: plan.transitions.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            momentTasks: StoreDuplicateEntityReconcileCount(
                removed: plan.momentTasks.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            conversations: StoreDuplicateEntityReconcileCount(
                removed: plan.conversations.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.conversations.reduce(0) { $0 + ($1.changes ? 1 : 0) }
            ),
            events: StoreDuplicateEntityReconcileCount(
                removed: plan.events.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.events.reduce(0) { $0 + ($1.changes ? 1 : 0) }
            ),
            conversationReadStates: StoreDuplicateEntityReconcileCount(
                removed: plan.conversationReadStates.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            momentReadStates: StoreDuplicateEntityReconcileCount(
                removed: plan.momentReadStates.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            memories: StoreDuplicateEntityReconcileCount(
                removed: plan.memories.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.memories.reduce(0) { $0 + ($1.changes ? 1 : 0) }
            ),
            evidence: StoreDuplicateEntityReconcileCount(
                removed: plan.evidence.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.evidence.reduce(0) { $0 + ($1.changes ? 1 : 0) }
            ),
            summaries: StoreDuplicateEntityReconcileCount(
                removed: plan.summaries.reduce(0) { $0 + $1.duplicates.count },
                updated: 0
            ),
            tombstones: StoreDuplicateEntityReconcileCount(
                removed: plan.tombstones.reduce(0) { $0 + $1.duplicates.count },
                updated: plan.tombstones.reduce(0) { $0 + ($1.changes ? 1 : 0) }
            )
        )
    }

    private static func validateProfile(_ profile: CompanionProfileRecord) throws {
        guard profile.createdAt.timeIntervalSince1970.isFinite,
              profile.updatedAt.timeIntervalSince1970.isFinite,
              profile.createdAt <= profile.updatedAt,
              profile.revision >= 0,
              validBirthday(month: profile.birthdayMonth, day: profile.birthdayDay) else {
            throw StoreDuplicateReconcileError.profileConflict(profile.id)
        }
        do {
            _ = try CompanionProfileService.validatedConfiguration(
                PersonaConfiguration(
                    name: profile.name,
                    userName: profile.userName,
                    prompt: profile.prompt
                )
            )
        } catch {
            throw StoreDuplicateReconcileError.profileConflict(profile.id)
        }
    }

    private static func profilePlan(_ records: [CompanionProfileRecord]) throws -> ProfilePlan {
        guard let first = records.first else {
            preconditionFailure("Profile duplicate group cannot be empty")
        }
        guard records.allSatisfy({ $0.id == first.id }) else {
            throw StoreDuplicateReconcileError.profileConflict(first.id)
        }
        for profile in records {
            try validateProfile(profile)
        }

        let winner = records.max(by: profileOrdering) ?? first
        return ProfilePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func validateUserProfile(_ profile: UserProfileRecord) throws {
        guard profile.id == UserProfileRecord.singletonID,
              !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.displayName.count <= 40,
              profile.createdAt.timeIntervalSince1970.isFinite,
              profile.updatedAt.timeIntervalSince1970.isFinite,
              profile.updatedAt >= profile.createdAt,
              profile.revision >= 0,
              profile.deviceID.count <= 256,
              validBirthday(month: profile.birthdayMonth, day: profile.birthdayDay),
              !profile.birthdayTimeZoneIdentifier.isEmpty,
              profile.birthdayTimeZoneIdentifier.count <= 128,
              TimeZone(identifier: profile.birthdayTimeZoneIdentifier) != nil else {
            throw StoreDuplicateReconcileError.userProfileConflict(profile.id)
        }
    }

    private static func userProfilePlan(
        _ records: [UserProfileRecord]
    ) throws -> UserProfilePlan {
        guard let first = records.first else {
            preconditionFailure("User profile duplicate group cannot be empty")
        }
        guard records.allSatisfy({ $0.id == first.id }) else {
            throw StoreDuplicateReconcileError.userProfileConflict(first.id)
        }
        for profile in records {
            try validateUserProfile(profile)
        }
        let winner = records.max(by: userProfileOrdering) ?? first
        return UserProfilePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func userProfileOrdering(
        _ lhs: UserProfileRecord,
        _ rhs: UserProfileRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return userProfileStableKey(lhs) < userProfileStableKey(rhs)
    }

    private static func validateMomentPost(_ post: MomentPostRecord) throws {
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
            throw StoreDuplicateReconcileError.momentPostConflict(post.id)
        }
    }

    private static func momentPostPlan(
        _ records: [MomentPostRecord]
    ) throws -> MomentPostPlan {
        guard let first = records.first else {
            preconditionFailure("Moment post duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ sameMomentPostIdentity(first, $0) }) else {
            throw StoreDuplicateReconcileError.momentPostConflict(first.id)
        }
        for post in records {
            try validateMomentPost(post)
        }
        let winner = records.max(by: momentPostOrdering) ?? first
        return MomentPostPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func sameMomentPostIdentity(
        _ lhs: MomentPostRecord,
        _ rhs: MomentPostRecord
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.authorKindRaw == rhs.authorKindRaw
            && lhs.authorRoleID == rhs.authorRoleID
    }

    private static func momentPostOrdering(
        _ lhs: MomentPostRecord,
        _ rhs: MomentPostRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return momentPostStableKey(lhs) < momentPostStableKey(rhs)
    }

    private static func validateMomentInteraction(
        _ interaction: MomentInteractionRecord
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
            throw StoreDuplicateReconcileError.momentInteractionConflict(interaction.id)
        }
    }

    private static func momentInteractionPlan(
        _ records: [MomentInteractionRecord]
    ) throws -> MomentInteractionPlan {
        guard let first = records.first else {
            preconditionFailure("Moment interaction duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ sameMomentInteractionIdentity(first, $0) }) else {
            throw StoreDuplicateReconcileError.momentInteractionConflict(first.id)
        }
        for interaction in records {
            try validateMomentInteraction(interaction)
        }
        let winner = records.max(by: momentInteractionOrdering) ?? first
        // Keep the normal revision/date/device winner, but retain any known
        // deletion marker on that physical row. This makes deduplication
        // monotonic even when an older live duplicate has a larger version.
        let newestDeletion = records.compactMap(\.deletedAt).max()
        return MomentInteractionPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            deletedAt: newestDeletion
        )
    }

    private static func sameMomentInteractionIdentity(
        _ lhs: MomentInteractionRecord,
        _ rhs: MomentInteractionRecord
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.postID == rhs.postID
            && lhs.kindRaw == rhs.kindRaw
            && lhs.actorKindRaw == rhs.actorKindRaw
            && lhs.actorRoleID == rhs.actorRoleID
    }

    private static func momentInteractionOrdering(
        _ lhs: MomentInteractionRecord,
        _ rhs: MomentInteractionRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return momentInteractionStableKey(lhs) < momentInteractionStableKey(rhs)
    }

    private static func relationshipPlan(
        _ records: [CompanionRelationshipRecord]
    ) throws -> RelationshipPlan {
        guard let first = records.first else {
            preconditionFailure("Relationship duplicate group cannot be empty")
        }
        guard records.allSatisfy({ $0.roleID == first.roleID }) else {
            throw StoreDuplicateReconcileError.relationshipConflict(first.id)
        }
        for record in records {
            try validateRelationship(record)
        }
        let winner = records.reduce(first) { current, candidate in
            preferredRelationship(candidate, over: current) ? candidate : current
        }
        let manualWinner = records.reduce(winner) { current, candidate in
            preferredManualAffinity(candidate, over: current) ? candidate : current
        }
        let manualAffinityUpdatedAt = effectiveManualAffinityUpdatedAt(manualWinner)
        return RelationshipPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            manualAffinityScore: manualWinner.manualAffinityScore,
            manualAffinityUpdatedAt: manualAffinityUpdatedAt,
            changes: winner.manualAffinityScore != manualWinner.manualAffinityScore
                || winner.manualAffinityUpdatedAt != manualAffinityUpdatedAt
        )
    }

    private static func validateRelationship(
        _ record: CompanionRelationshipRecord
    ) throws {
        guard CompanionRelationshipState(rawValue: record.stateRaw) != nil,
              record.harmStreak >= 0,
              record.hurtScore.isFinite,
              record.hurtScore >= 0,
              record.harmThreshold > 0,
              record.forgivenessScore.isFinite,
              record.forgivenessScore >= 0,
              record.forgivenessThreshold.isFinite,
              record.forgivenessThreshold > 0,
              record.affinityScore.isFinite,
              (0...100).contains(record.affinityScore),
              (0...3).contains(record.affinityTier),
              record.affinityPolicyVersion > 0,
              (record.manualAffinityScore.map {
                  $0.isFinite && (0...100).contains($0)
              } ?? true),
              record.manualAffinityUpdatedAt?.timeIntervalSince1970.isFinite ?? true,
              record.dignity.isFinite,
              (0...1).contains(record.dignity),
              record.independence.isFinite,
              (0...1).contains(record.independence),
              record.boundarySensitivity.isFinite,
              (0...1).contains(record.boundarySensitivity),
              record.apologyAttempts >= 0,
              record.policyVersion > 0,
              record.createdAt.timeIntervalSince1970.isFinite,
              record.updatedAt.timeIntervalSince1970.isFinite,
              record.updatedAt >= record.createdAt,
              record.retiredAt?.timeIntervalSince1970.isFinite ?? true,
              record.resetAt?.timeIntervalSince1970.isFinite ?? true,
              record.revision >= 0 else {
            throw StoreDuplicateReconcileError.relationshipConflict(record.id)
        }
    }

    private static func relationshipSafetyRank(
        _ record: CompanionRelationshipRecord
    ) -> Int {
        if record.retiredAt != nil { return 6 }
        switch CompanionRelationshipState(rawValue: record.stateRaw) {
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
        let leftSafety = relationshipSafetyRank(lhs)
        let rightSafety = relationshipSafetyRank(rhs)
        if leftSafety != rightSafety { return leftSafety > rightSafety }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return uuidKey(lhs.id) < uuidKey(rhs.id)
    }

    private static func preferredManualAffinity(
        _ lhs: CompanionRelationshipRecord,
        over rhs: CompanionRelationshipRecord
    ) -> Bool {
        switch (
            effectiveManualAffinityUpdatedAt(lhs),
            effectiveManualAffinityUpdatedAt(rhs)
        ) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        default:
            break
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        let leftScore = lhs.manualAffinityScore.map {
            String($0.bitPattern, radix: 16)
        } ?? "nil"
        let rightScore = rhs.manualAffinityScore.map {
            String($0.bitPattern, radix: 16)
        } ?? "nil"
        if leftScore != rightScore { return leftScore > rightScore }
        return uuidKey(lhs.id) < uuidKey(rhs.id)
    }

    private static func effectiveManualAffinityUpdatedAt(
        _ record: CompanionRelationshipRecord
    ) -> Date? {
        record.manualAffinityUpdatedAt
            ?? (record.manualAffinityScore == nil ? nil : record.updatedAt)
    }

    private static func transitionPlan(
        _ records: [CompanionRelationshipTransitionRecord]
    ) throws -> TransitionPlan {
        guard let first = records.first else {
            preconditionFailure("Transition duplicate group cannot be empty")
        }
        for record in records {
            guard CompanionRelationshipState(rawValue: record.from) != nil,
                  CompanionRelationshipState(rawValue: record.to) != nil,
                  !record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.scoreAfter.isFinite,
                  record.scoreAfter >= 0,
                  record.policyVersion > 0,
                  record.occurredAt.timeIntervalSince1970.isFinite,
                  record.revision >= 0 else {
                throw StoreDuplicateReconcileError.transitionConflict(first.id)
            }
            guard sameTransitionIdentity(first, record) else {
                throw StoreDuplicateReconcileError.transitionConflict(first.id)
            }
        }
        return TransitionPlan(
            winner: first,
            duplicates: records.filter { $0 !== first }
        )
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

    private static func validateMomentTask(
        _ task: CompanionMomentTaskRecord
    ) throws {
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
            throw StoreDuplicateReconcileError.momentTaskConflict(task.id)
        }
        guard MomentTaskRecurrenceFrequency(rawValue: task.recurrenceRaw) != nil,
              task.recurrenceInterval >= 1,
              (0...23).contains(task.recurrenceHour),
              (0...59).contains(task.recurrenceMinute),
              !task.timezoneIdentifier.isEmpty,
              task.timezoneIdentifier.count <= AyaneMomentTaskValidationLimits.timezoneIdentifier,
              TimeZone(identifier: task.timezoneIdentifier) != nil,
              task.occurrenceKey.count <= AyaneMomentTaskValidationLimits.occurrenceKey,
              task.recurrenceWeekday.map({ (1...7).contains($0) }) ?? true,
              task.recurrenceDayOfMonth.map({ (1...31).contains($0) }) ?? true else {
            throw StoreDuplicateReconcileError.momentTaskConflict(task.id)
        }
        switch MomentTaskRecurrenceFrequency(rawValue: task.recurrenceRaw) {
        case .weekly where task.recurrenceWeekday == nil:
            throw StoreDuplicateReconcileError.momentTaskConflict(task.id)
        case .monthly where task.recurrenceDayOfMonth == nil:
            throw StoreDuplicateReconcileError.momentTaskConflict(task.id)
        default:
            break
        }
        if task.stateRaw == MomentTaskState.published.rawValue,
           (task.resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || task.publishedAt == nil) {
            throw StoreDuplicateReconcileError.momentTaskConflict(task.id)
        }
    }

    private static func momentTaskPlan(
        _ records: [CompanionMomentTaskRecord]
    ) throws -> MomentTaskPlan {
        guard let first = records.first else {
            preconditionFailure("Moment task duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ task in
            task.id == first.id
                && task.resolvedRoleID == first.resolvedRoleID
                && (task.stateRaw != MomentTaskState.published.rawValue
                    || first.stateRaw != MomentTaskState.published.rawValue
                    || task.resultText == first.resultText)
        }) else {
            throw StoreDuplicateReconcileError.momentTaskConflict(first.id)
        }
        for task in records {
            try validateMomentTask(task)
        }
        let winner = records.reduce(first) { current, candidate in
            momentTaskPreferred(candidate, over: current) ? candidate : current
        }
        return MomentTaskPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func momentTaskPreferred(
        _ lhs: CompanionMomentTaskRecord,
        over rhs: CompanionMomentTaskRecord
    ) -> Bool {
        let leftRank = momentTaskStateRank(lhs.stateRaw)
        let rightRank = momentTaskStateRank(rhs.stateRaw)
        if leftRank != rightRank { return leftRank > rightRank }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return momentTaskStableKey(lhs) > momentTaskStableKey(rhs)
    }

    private static func momentTaskStateRank(_ rawValue: String) -> Int {
        switch rawValue {
        // Both states are non-terminal. Let revision/timestamp decide between
        // them so a newer scheduled retry can supersede stale running data.
        case MomentTaskState.scheduled.rawValue,
             MomentTaskState.running.rawValue: return 0
        case MomentTaskState.cancelled.rawValue: return 1
        case MomentTaskState.published.rawValue: return 2
        default: return -1
        }
    }

    private static func momentTaskStableKey(_ task: CompanionMomentTaskRecord) -> String {
        [
            uuidKey(task.id), uuidKey(task.resolvedRoleID), task.instruction,
            dateKey(task.scheduledAt), task.seriesID.map(uuidKey) ?? "-",
            task.occurrenceKey, task.recurrenceRaw, String(task.recurrenceInterval),
            task.recurrenceWeekday.map(String.init) ?? "-",
            task.recurrenceDayOfMonth.map(String.init) ?? "-",
            String(task.recurrenceHour), String(task.recurrenceMinute),
            task.timezoneIdentifier, dateKey(task.nextAttemptAt),
            task.stateRaw, task.resultText,
            dateKey(task.publishedAt), dateKey(task.createdAt), dateKey(task.updatedAt),
            String(task.attemptCount), task.lastError, task.leaseOwner,
            dateKey(task.leaseExpiresAt), task.deviceID, String(task.revision)
        ].joined(separator: "\u{1f}")
    }

    /// Profile duplicate copies use the same logical ordering as incremental
    /// merge: revision, update timestamp, device, then canonical content. The
    /// final fingerprint makes copies from equal clocks converge identically
    /// without depending on SwiftData fetch order.
    private static func profileOrdering(
        _ lhs: CompanionProfileRecord,
        _ rhs: CompanionProfileRecord
    ) -> Bool {
        if CompanionProfileService.isPreferred(lhs, over: rhs) { return false }
        if CompanionProfileService.isPreferred(rhs, over: lhs) { return true }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return profileStableKey(lhs) < profileStableKey(rhs)
    }

    private static func conversationPlan(
        _ grouped: (key: UUID, value: [ConversationRecord])
    ) throws -> ConversationPlan {
        let records = grouped.value
        guard let first = records.first,
              records.dropFirst().allSatisfy({
                  $0.resolvedRoleID == first.resolvedRoleID
              }) else {
            throw StoreDuplicateReconcileError.conversationConflict(grouped.key)
        }
        let winner = records.max(by: conversationOrdering) ?? records[0]
        let createdAt = records.map(\.createdAt).min() ?? winner.createdAt
        let updatedAt = records.map(\.updatedAt).max() ?? winner.updatedAt
        let title = winner.title
        let archived = records.contains(where: \.archived)
        let changes = winner.createdAt != createdAt
            || winner.updatedAt != updatedAt
            || winner.title != title
            || winner.archived != archived
        return ConversationPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: title,
            archived: archived,
            changes: changes
        )
    }

    private static func eventPlan(_ records: [ConversationEvent]) throws -> EventPlan {
        guard let first = records.first else {
            preconditionFailure("Event duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ event in
            event.resolvedRoleID == first.resolvedRoleID
                && event.conversationID == first.conversationID
                && event.deviceID == first.deviceID
                && event.deviceSequence == first.deviceSequence
                && event.logicalTimestamp == first.logicalTimestamp
                && event.roleRaw == first.roleRaw
                && event.content == first.content
                && event.contentHash.lowercased() == first.contentHash.lowercased()
                && event.payloadKindRaw == first.payloadKindRaw
                && event.stickerID == first.stickerID
                && event.imageData == first.imageData
                && event.fileName == first.fileName
                && event.fileTypeIdentifier == first.fileTypeIdentifier
                && event.fileData == first.fileData
                && event.senderRoleID.map(RoleScope.resolve)
                    == first.senderRoleID.map(RoleScope.resolve)
                && event.parentEventID == first.parentEventID
        }) else {
            throw StoreDuplicateReconcileError.eventConflict(first.id)
        }

        for event in records {
            try validateEventPayload(event)
        }

        let redacted = records.contains(where: \.redacted)
        let memoryProcessingVersion = records.map(\.memoryProcessingVersion).max() ?? first.memoryProcessingVersion
        let memoryProcessedAt = records.compactMap(\.memoryProcessedAt).max()
        let deliveryStateRaw = records
            .sorted(by: deliveryStateOrdering)
            .last?
            .deliveryStateRaw ?? first.deliveryStateRaw
        let winner = records.min(by: eventPhysicalOrdering) ?? first
        // occurredAt and recordedAt are not identity fields. Preserve both
        // timestamps from the deterministic physical winner so a restore that
        // quantized subsecond dates cannot create a new, arbitrary hybrid.
        let occurredAt = winner.occurredAt
        let recordedAt = winner.recordedAt
        let changes = winner.redacted != redacted
            || winner.memoryProcessingVersion != memoryProcessingVersion
            || winner.memoryProcessedAt != memoryProcessedAt
            || winner.deliveryStateRaw != deliveryStateRaw

        return EventPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            occurredAt: occurredAt,
            recordedAt: recordedAt,
            redacted: redacted,
            memoryProcessedAt: memoryProcessedAt,
            memoryProcessingVersion: memoryProcessingVersion,
            deliveryStateRaw: deliveryStateRaw,
            changes: changes
        )
    }

    private static func validateConversationReadState(
        _ state: ConversationReadStateRecord
    ) throws {
        guard state.updatedAt.timeIntervalSince1970.isFinite,
              state.revision >= 0,
              state.deviceID.count <= 256 else {
            throw StoreDuplicateReconcileError.conversationReadStateConflict(state.id)
        }
        if let occurredAt = state.lastReadOccurredAt {
            guard occurredAt.timeIntervalSince1970.isFinite else {
                throw StoreDuplicateReconcileError.conversationReadStateConflict(state.id)
            }
        }
        if state.lastReadEventID != nil,
           state.lastReadLogicalTimestamp.isEmpty {
            throw StoreDuplicateReconcileError.conversationReadStateConflict(state.id)
        }
    }

    private static func validateMomentReadState(
        _ state: MomentReadStateRecord
    ) throws {
        guard state.updatedAt.timeIntervalSince1970.isFinite,
              state.revision >= 0,
              state.deviceID.count <= 256 else {
            throw StoreDuplicateReconcileError.momentReadStateConflict(state.id)
        }
        if let createdAt = state.lastReadCreatedAt {
            guard createdAt.timeIntervalSince1970.isFinite else {
                throw StoreDuplicateReconcileError.momentReadStateConflict(state.id)
            }
        }
    }

    private static func conversationReadStatePlan(
        _ records: [ConversationReadStateRecord]
    ) throws -> ConversationReadStatePlan {
        guard let first = records.first else {
            preconditionFailure("Conversation read-state duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({
            $0.resolvedRoleID == first.resolvedRoleID
                && $0.conversationID == first.conversationID
        }) else {
            throw StoreDuplicateReconcileError.conversationReadStateConflict(first.id)
        }
        for state in records {
            try validateConversationReadState(state)
        }
        let winner = records.reduce(first) { current, candidate in
            ReadStateService.isNewer(candidate, than: current) ? candidate : current
        }
        return ConversationReadStatePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func momentReadStatePlan(
        _ records: [MomentReadStateRecord]
    ) throws -> MomentReadStatePlan {
        guard let first = records.first else {
            preconditionFailure("Moment read-state duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ $0.postID == first.postID }) else {
            throw StoreDuplicateReconcileError.momentReadStateConflict(first.id)
        }
        for state in records {
            try validateMomentReadState(state)
        }
        let winner = records.reduce(first) { current, candidate in
            ReadStateService.isNewer(candidate, than: current) ? candidate : current
        }
        return MomentReadStatePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func memoryPlan(
        _ grouped: (key: UUID, value: [MemoryAssertionRecord])
    ) throws -> MemoryPlan {
        let records = grouped.value
        guard let first = records.first,
              records.dropFirst().allSatisfy({
                  $0.resolvedRoleID == first.resolvedRoleID
              }) else {
            throw StoreDuplicateReconcileError.memoryConflict(grouped.key)
        }
        // A forgotten copy is a durable privacy decision, not an ordinary
        // stale version. CloudKit can briefly materialize an active copy beside
        // the forgotten copy; selecting the active row here would delete the
        // only copy carrying the deletion state and permanently resurrect the
        // memory on the next read. Once any physical copy is forgotten, retain
        // a deterministic forgotten winner and scrub content-bearing fields.
        let hasForgottenCopy = records.contains { $0.state == .forgotten }
        let winnerPool = hasForgottenCopy
            ? records.filter { $0.state == .forgotten }
            : records
        let winner = winnerPool.max(by: memoryOrdering) ?? records[0]
        let createdAt = records.map(\.createdAt).min() ?? winner.createdAt
        let updatedAt = records.map(\.updatedAt).max() ?? winner.updatedAt
        let value = hasForgottenCopy ? "" : winner.value
        let confidence = records.map(\.confidence).max() ?? winner.confidence
        let importance = records.map(\.importance).max() ?? winner.importance
        let sensitive = records.contains(where: \.sensitive)
        let isPinned = hasForgottenCopy ? false : records.contains(where: \.isPinned)
        let userVerified = hasForgottenCopy ? false : records.contains(where: \.userVerified)
        // Do not synthesize a user tombstone here. The forgotten state itself
        // is the durable deletion decision; the existing tombstone/evidence
        // pipeline remains responsible for source-event suppression. Scrubbing
        // the retained row is the minimum safe projection when no tombstone is
        // present yet.
        let stateRaw = hasForgottenCopy
            ? MemoryState.forgotten.rawValue
            : winner.stateRaw
        let embedding: Data?
        let embeddingModelID: String?
        if hasForgottenCopy {
            embedding = nil
            embeddingModelID = nil
        } else if let winnerEmbedding = winner.embeddingData {
            embedding = winnerEmbedding
            embeddingModelID = winner.embeddingModelID
        } else if let fallback = records
            .sorted(by: { memoryStableKey($0) < memoryStableKey($1) })
            .first(where: { $0.embeddingData != nil }) {
            // Keep a vector and its model identifier as a pair. A model ID
            // from one physical copy must not be attached to another copy's
            // vector.
            embedding = fallback.embeddingData
            embeddingModelID = fallback.embeddingModelID
        } else {
            embedding = nil
            embeddingModelID = winner.embeddingModelID
        }
        let changes = winner.createdAt != createdAt
            || winner.updatedAt != updatedAt
            || winner.value != value
            || winner.confidence != confidence
            || winner.importance != importance
            || winner.sensitive != sensitive
            || winner.isPinned != isPinned
            || winner.userVerified != userVerified
            || winner.stateRaw != stateRaw
            || winner.embeddingData != embedding
            || winner.embeddingModelID != embeddingModelID

        return MemoryPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            createdAt: createdAt,
            updatedAt: updatedAt,
            value: value,
            confidence: confidence,
            importance: importance,
            sensitive: sensitive,
            isPinned: isPinned,
            userVerified: userVerified,
            stateRaw: stateRaw,
            embeddingData: embedding,
            embeddingModelID: embeddingModelID,
            changes: changes
        )
    }

    private static func evidencePlan(_ records: [MemoryEvidenceRecord]) throws -> EvidencePlan {
        guard let first = records.first else {
            preconditionFailure("Evidence duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ evidence in
            evidence.resolvedRoleID == first.resolvedRoleID
                && evidence.memoryID == first.memoryID
                && evidence.eventID == first.eventID
                && evidence.startUTF16 == first.startUTF16
                && evidence.endUTF16 == first.endUTF16
                && evidence.relationRaw == first.relationRaw
                && evidence.quoteHash.lowercased() == first.quoteHash.lowercased()
        }) else {
            throw StoreDuplicateReconcileError.evidenceConflict(first.id)
        }

        let winner = records.min(by: evidencePhysicalOrdering) ?? first
        let confidence = records.map(\.confidence).max() ?? first.confidence
        let createdAt = records.map(\.createdAt).min() ?? first.createdAt
        return EvidencePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            confidence: confidence,
            createdAt: createdAt,
            changes: winner.confidence != confidence || winner.createdAt != createdAt
        )
    }

    private static func summaryPlan(
        _ grouped: (key: UUID, value: [MemorySummaryRecord])
    ) throws -> SummaryPlan {
        let records = grouped.value
        guard let first = records.first,
              records.dropFirst().allSatisfy({
                  $0.resolvedRoleID == first.resolvedRoleID
              }) else {
            throw StoreDuplicateReconcileError.summaryConflict(grouped.key)
        }
        let winner = records.max(by: summaryOrdering) ?? records[0]
        return SummaryPlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner }
        )
    }

    private static func tombstonePlan(_ records: [MemoryTombstoneRecord]) throws -> TombstonePlan {
        guard let first = records.first else {
            preconditionFailure("Tombstone duplicate group cannot be empty")
        }
        guard records.dropFirst().allSatisfy({ tombstone in
            tombstone.resolvedRoleID == first.resolvedRoleID
                && tombstone.entityID == first.entityID
                && tombstone.entityType == first.entityType
                && tombstone.canonicalKey == first.canonicalKey
                && tombstone.deviceID == first.deviceID
                && tombstone.reason == first.reason
        }) else {
            throw StoreDuplicateReconcileError.tombstoneConflict(first.id)
        }

        let sourceEventIDs = Set(records.flatMap(\.sourceEventIDs)).sorted { uuidKey($0) < uuidKey($1) }
        let deletedAt = records.map(\.deletedAt).max() ?? first.deletedAt
        let winner = records.min(by: tombstonePhysicalOrdering) ?? first
        return TombstonePlan(
            winner: winner,
            duplicates: records.filter { $0 !== winner },
            sourceEventIDs: sourceEventIDs,
            deletedAt: deletedAt,
            changes: winner.sourceEventIDs != sourceEventIDs || winner.deletedAt != deletedAt
        )
    }

    private static func conversationOrdering(
        _ lhs: ConversationRecord,
        _ rhs: ConversationRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.archived == false && rhs.archived == true
    }

    private static func eventPhysicalOrdering(
        _ lhs: ConversationEvent,
        _ rhs: ConversationEvent
    ) -> Bool {
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
        return eventStableKey(lhs) < eventStableKey(rhs)
    }

    private static func deliveryStateOrdering(
        _ lhs: ConversationEvent,
        _ rhs: ConversationEvent
    ) -> Bool {
        let lhsRank = deliveryRank(lhs.deliveryStateRaw)
        let rhsRank = deliveryRank(rhs.deliveryStateRaw)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
        return eventStableKey(lhs) < eventStableKey(rhs)
    }

    private static func memoryOrdering(
        _ lhs: MemoryAssertionRecord,
        _ rhs: MemoryAssertionRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        if lhs.userVerified != rhs.userVerified { return !lhs.userVerified && rhs.userVerified }
        if lhs.sourceRank != rhs.sourceRank { return lhs.sourceRank < rhs.sourceRank }
        return memoryStableKey(lhs) < memoryStableKey(rhs)
    }

    private static func evidencePhysicalOrdering(
        _ lhs: MemoryEvidenceRecord,
        _ rhs: MemoryEvidenceRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return evidenceStableKey(lhs) < evidenceStableKey(rhs)
    }

    private static func summaryOrdering(
        _ lhs: MemorySummaryRecord,
        _ rhs: MemorySummaryRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return summaryStableKey(lhs) < summaryStableKey(rhs)
    }

    private static func tombstonePhysicalOrdering(
        _ lhs: MemoryTombstoneRecord,
        _ rhs: MemoryTombstoneRecord
    ) -> Bool {
        if lhs.deletedAt != rhs.deletedAt { return lhs.deletedAt < rhs.deletedAt }
        return tombstoneStableKey(lhs) < tombstoneStableKey(rhs)
    }

    private static func deliveryRank(_ raw: String) -> Int {
        switch EventDeliveryState(rawValue: raw) {
        case .undelivered: return 5
        case .complete: return 4
        case .failed: return 3
        case .cancelled: return 2
        case .streaming: return 1
        case nil: return 0
        }
    }

    private static func eventStableKey(_ event: ConversationEvent) -> String {
        [
            uuidKey(event.id),
            uuidKey(event.conversationID),
            event.deviceID,
            String(event.deviceSequence),
            event.logicalTimestamp,
            dateKey(event.occurredAt),
            event.roleRaw,
            event.content,
            event.contentHash,
            event.payloadKindRaw,
            event.stickerID,
            SchemaV11DataSupport.imageDataHash(event.imageData),
            event.fileName,
            event.fileTypeIdentifier,
            SchemaV11DataSupport.fileDataHash(event.fileData),
            event.senderRoleID.map(uuidKey) ?? "-",
            event.parentEventID.map(uuidKey) ?? "-",
            event.deliveryStateRaw,
            event.redacted ? "1" : "0",
            dateKey(event.memoryProcessedAt),
            String(event.memoryProcessingVersion)
        ].joined(separator: "\u{1f}")
    }

    private static func validateEventPayload(_ event: ConversationEvent) throws {
        guard MessagePayloadKind(rawValue: event.payloadKindRaw) != nil,
              event.stickerID.count <= SchemaV11DataSupport.maxTextLength,
              (event.imageData?.count ?? 0) <= SchemaV11DataSupport.maxImageDataBytes,
              event.fileName.count <= SchemaV11DataSupport.maxFileNameLength,
              event.fileTypeIdentifier.count <= SchemaV11DataSupport.maxFileTypeIdentifierLength,
              (event.fileData?.count ?? 0) <= SchemaV11DataSupport.maxFileDataBytes else {
            throw StoreDuplicateReconcileError.eventConflict(event.id)
        }
        if event.payloadKindRaw == MessagePayloadKind.image.rawValue {
            guard let imageData = event.imageData, !imageData.isEmpty else {
                throw StoreDuplicateReconcileError.eventConflict(event.id)
            }
        } else if event.imageData != nil {
            throw StoreDuplicateReconcileError.eventConflict(event.id)
        }
        if event.payloadKindRaw == MessagePayloadKind.file.rawValue {
            guard !event.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !event.fileTypeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let fileData = event.fileData,
                  !fileData.isEmpty else {
                throw StoreDuplicateReconcileError.eventConflict(event.id)
            }
        } else if !event.fileName.isEmpty || !event.fileTypeIdentifier.isEmpty || event.fileData != nil {
            throw StoreDuplicateReconcileError.eventConflict(event.id)
        }
        if event.payloadKindRaw == MessagePayloadKind.sticker.rawValue,
           event.stickerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw StoreDuplicateReconcileError.eventConflict(event.id)
        }
    }

    private static func userProfileStableKey(_ profile: UserProfileRecord) -> String {
        [
            uuidKey(profile.id), profile.displayName,
            String(profile.birthdayMonth ?? 0), String(profile.birthdayDay ?? 0),
            profile.birthdayTimeZoneIdentifier,
            profile.avatarImageData?.base64EncodedString() ?? "-",
            profile.momentsCoverImageData?.base64EncodedString() ?? "-",
            dateKey(profile.createdAt), dateKey(profile.updatedAt),
            String(profile.revision), profile.deviceID
        ].joined(separator: "\u{1f}")
    }

    private static func profileStableKey(_ profile: CompanionProfileRecord) -> String {
        [
            uuidKey(profile.id), uuidKey(profile.worldProfileID), profile.name,
            profile.userName, profile.prompt,
            String(profile.birthdayMonth ?? 0), String(profile.birthdayDay ?? 0),
            profile.avatarImageData?.base64EncodedString() ?? "-",
            profile.chatBackgroundImageData?.base64EncodedString() ?? "-",
            dateKey(profile.createdAt), dateKey(profile.updatedAt),
            String(profile.revision), profile.deviceID
        ].joined(separator: "\u{1f}")
    }

    private static func validBirthday(month: Int?, day: Int?) -> Bool {
        guard (month == nil) == (day == nil) else { return false }
        guard let month, let day else { return true }
        guard (1...12).contains(month), (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let date = calendar.date(
            from: DateComponents(year: 2000, month: month, day: day)
        ) else { return false }
        return calendar.component(.month, from: date) == month
            && calendar.component(.day, from: date) == day
    }

    private static func momentPostStableKey(_ post: MomentPostRecord) -> String {
        [
            uuidKey(post.id), post.authorKindRaw,
            post.authorRoleID.map(uuidKey) ?? "-", post.body,
            post.imageData?.base64EncodedString() ?? "-", post.bundledImageName,
            post.sourceTaskID.map(uuidKey) ?? "-", dateKey(post.publishedAt),
            dateKey(post.createdAt), dateKey(post.updatedAt), dateKey(post.deletedAt),
            String(post.revision), post.deviceID
        ].joined(separator: "\u{1f}")
    }

    private static func momentInteractionStableKey(
        _ interaction: MomentInteractionRecord
    ) -> String {
        [
            uuidKey(interaction.id), uuidKey(interaction.postID), interaction.kindRaw,
            interaction.actorKindRaw, interaction.actorRoleID.map(uuidKey) ?? "-",
            interaction.body, dateKey(interaction.createdAt), dateKey(interaction.updatedAt),
            dateKey(interaction.deletedAt),
            String(interaction.revision), interaction.deviceID
        ].joined(separator: "\u{1f}")
    }

    private static func memoryStableKey(_ memory: MemoryAssertionRecord) -> String {
        [
            uuidKey(memory.id),
            memory.kindRaw,
            memory.subject,
            memory.predicate,
            memory.value,
            memory.canonicalKey,
            memory.stateRaw,
            String(memory.confidence.bitPattern, radix: 16),
            String(memory.importance.bitPattern, radix: 16),
            memory.sensitive ? "1" : "0",
            String(memory.sourceRank),
            dateKey(memory.validFrom),
            dateKey(memory.validTo),
            dateKey(memory.observedAt),
            memory.supersedesID.map(uuidKey) ?? "-",
            memory.extractorID,
            String(memory.schemaVersion),
            dateKey(memory.createdAt),
            dateKey(memory.updatedAt),
            memory.isPinned ? "1" : "0",
            memory.userVerified ? "1" : "0",
            memory.embeddingData?.base64EncodedString() ?? "-",
            memory.embeddingModelID ?? "-",
            memory.deviceID
        ].joined(separator: "\u{1f}")
    }

    private static func evidenceStableKey(_ evidence: MemoryEvidenceRecord) -> String {
        [
            uuidKey(evidence.id),
            uuidKey(evidence.memoryID),
            uuidKey(evidence.eventID),
            String(evidence.startUTF16),
            String(evidence.endUTF16),
            evidence.relationRaw,
            evidence.quoteHash,
            String(evidence.confidence.bitPattern, radix: 16),
            dateKey(evidence.createdAt)
        ].joined(separator: "\u{1f}")
    }

    private static func summaryStableKey(_ summary: MemorySummaryRecord) -> String {
        [
            uuidKey(summary.id),
            uuidKey(summary.conversationID),
            summary.scope,
            summary.content,
            summary.firstEventID.map(uuidKey) ?? "-",
            summary.lastEventID.map(uuidKey) ?? "-",
            String(summary.coveredEventCount),
            summary.extractorID,
            dateKey(summary.createdAt),
            dateKey(summary.updatedAt)
        ].joined(separator: "\u{1f}")
    }

    private static func tombstoneStableKey(_ tombstone: MemoryTombstoneRecord) -> String {
        [
            uuidKey(tombstone.id),
            uuidKey(tombstone.entityID),
            tombstone.entityType,
            tombstone.canonicalKey,
            tombstone.sourceEventIDs.map(uuidKey).sorted().joined(separator: ","),
            dateKey(tombstone.deletedAt),
            tombstone.deviceID,
            tombstone.reason
        ].joined(separator: "\u{1f}")
    }

    private static func dateKey(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(date.timeIntervalSince1970.bitPattern, radix: 16)
    }

    private static func uuidKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func encodeUUIDs(_ ids: [UUID]) -> String {
        ids.map(uuidKey).sorted().joined(separator: ",")
    }

    private static func add(
        _ current: StoreDuplicateEntityReconcileCount,
        removed: Int,
        updated: Int
    ) -> StoreDuplicateEntityReconcileCount {
        StoreDuplicateEntityReconcileCount(
            removed: current.removed + removed,
            updated: current.updated + updated
        )
    }

    private static func isEmpty(_ plan: Plan) -> Bool {
        plan.profiles.isEmpty
            && plan.userProfiles.isEmpty
            && plan.momentPosts.isEmpty
            && plan.momentInteractions.isEmpty
            && plan.relationships.isEmpty
            && plan.transitions.isEmpty
            && plan.momentTasks.isEmpty
            && plan.conversations.isEmpty
            && plan.events.isEmpty
            && plan.conversationReadStates.isEmpty
            && plan.momentReadStates.isEmpty
            && plan.memories.isEmpty
            && plan.evidence.isEmpty
            && plan.summaries.isEmpty
            && plan.tombstones.isEmpty
    }
}

private extension AyaneMemoryExport {
    /// Projects the planned value without mutating the source SwiftData row.
    /// This matters for a mixed active/forgotten duplicate group: the retained
    /// forgotten winner is scrubbed only when the plan is applied, while a
    /// read-only canonical export must still avoid copying the old value.
    init(
        projecting record: MemoryAssertionRecord,
        value: String,
        stateRaw: String,
        confidence: Double,
        importance: Double,
        sensitive: Bool,
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool,
        userVerified: Bool,
        embeddingData: Data?,
        embeddingModelID: String?
    ) {
        id = record.id
        kind = record.kind.rawValue
        kindRaw = record.kindRaw
        subject = record.subject
        predicate = record.predicate
        self.value = value
        canonicalKey = record.canonicalKey
        state = stateRaw
        self.stateRaw = stateRaw
        self.confidence = confidence
        self.importance = importance
        self.sensitive = sensitive
        sourceRank = record.sourceRank
        validFrom = record.validFrom
        validTo = record.validTo
        observedAt = record.observedAt
        supersedesID = record.supersedesID
        extractorID = record.extractorID
        schemaVersion = record.schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.userVerified = userVerified
        embeddingBase64 = embeddingData?.base64EncodedString()
        self.embeddingModelID = embeddingModelID
        deviceID = record.deviceID
    }
}
