import Foundation

enum GroupReplyStrategy: String, Codable, CaseIterable, Sendable {
    case manual
    case natural
    case listOrder = "list_order"
    case pooled
}

enum GroupPromptAssemblyMode: String, Codable, CaseIterable, Sendable {
    /// Only the active speaker receives their full card. Other members are
    /// represented by compact names/shared facts, preventing identity merging.
    case swapActiveCharacter = "swap_active_character"
    /// Every card is joined. Kept as an explicit compatibility option because
    /// it costs more context and can merge personalities on weaker models.
    case joinCharacterCards = "join_character_cards"
}

enum GroupTurnActivationReason: String, Codable, CaseIterable, Sendable {
    case manual
    case explicitMention = "explicit_mention"
    case mentionAll = "mention_all"
    case listOrder = "list_order"
    case pooled
    case topicRelevance = "topic_relevance"
    case personalityFit = "personality_fit"
    case affinity
    case talkativeness
    case fallback
}

struct GroupTurnMember: Identifiable, Equatable, Sendable {
    var id: UUID { roleID }
    let roleID: UUID
    let displayName: String
    let order: Int
    let topicRelevance: Double
    let personalityFit: Double
    let affinityScore: Double
    let talkativeness: Double
    let recentTurnPenalty: Double
    let isMuted: Bool
    let hasSpokenSinceUserMessage: Bool

    init(
        roleID: UUID,
        displayName: String,
        order: Int,
        topicRelevance: Double = 0,
        personalityFit: Double = 0,
        affinityScore: Double = 0,
        talkativeness: Double = 0.5,
        recentTurnPenalty: Double = 0,
        isMuted: Bool = false,
        hasSpokenSinceUserMessage: Bool = false
    ) {
        self.roleID = roleID
        self.displayName = displayName
        self.order = order
        self.topicRelevance = Self.unit(topicRelevance)
        self.personalityFit = Self.unit(personalityFit)
        self.affinityScore = Self.unit(affinityScore / 100)
        self.talkativeness = Self.unit(talkativeness)
        self.recentTurnPenalty = Self.unit(recentTurnPenalty)
        self.isMuted = isMuted
        self.hasSpokenSinceUserMessage = hasSpokenSinceUserMessage
    }

    init(
        coordinatorMember: GroupResponseCoordinator.Member,
        talkativeness: Double = 0.5,
        isMuted: Bool = false,
        hasSpokenSinceUserMessage: Bool = false
    ) {
        self.init(
            roleID: coordinatorMember.roleID,
            displayName: coordinatorMember.displayName,
            order: coordinatorMember.order,
            topicRelevance: coordinatorMember.topicRelevance,
            personalityFit: coordinatorMember.personalityFit,
            affinityScore: coordinatorMember.affinityScore,
            talkativeness: talkativeness,
            recentTurnPenalty: coordinatorMember.recentTurnPenalty,
            isMuted: isMuted,
            hasSpokenSinceUserMessage: hasSpokenSinceUserMessage
        )
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return value.sign == .minus ? 0 : 1 }
        return min(1, max(0, value))
    }
}

struct GroupTurnPlanningContext: Equatable, Sendable {
    var strategy: GroupReplyStrategy
    var promptAssemblyMode: GroupPromptAssemblyMode
    var manuallySelectedRoleID: UUID?
    var explicitlyMentionedRoleIDs: Set<UUID>
    var lastSpeakerRoleID: UUID?
    var allowSelfResponses: Bool
    var forceManualSpeaker: Bool
    var maxAutomaticResponders: Int

    init(
        strategy: GroupReplyStrategy = .natural,
        promptAssemblyMode: GroupPromptAssemblyMode = .swapActiveCharacter,
        manuallySelectedRoleID: UUID? = nil,
        explicitlyMentionedRoleIDs: Set<UUID> = [],
        lastSpeakerRoleID: UUID? = nil,
        allowSelfResponses: Bool = false,
        forceManualSpeaker: Bool = false,
        maxAutomaticResponders: Int = 2
    ) {
        self.strategy = strategy
        self.promptAssemblyMode = promptAssemblyMode
        self.manuallySelectedRoleID = manuallySelectedRoleID
        self.explicitlyMentionedRoleIDs = explicitlyMentionedRoleIDs
        self.lastSpeakerRoleID = lastSpeakerRoleID
        self.allowSelfResponses = allowSelfResponses
        self.forceManualSpeaker = forceManualSpeaker
        self.maxAutomaticResponders = max(1, min(4, maxAutomaticResponders))
    }
}

struct GroupTurnSelection: Identifiable, Equatable, Sendable {
    var id: UUID { roleID }
    let roleID: UUID
    let displayName: String
    let score: Double
    let reason: GroupTurnActivationReason
}

struct GroupTurnPlan: Equatable, Sendable {
    let strategy: GroupReplyStrategy
    let promptAssemblyMode: GroupPromptAssemblyMode
    let selections: [GroupTurnSelection]
    /// Group replies are generated one at a time so every later speaker sees
    /// the earlier speaker's completed message and cannot answer stale context.
    let shouldGenerateSequentially: Bool
    let wasExplicitlyDirected: Bool

    var responseOrder: [UUID] { selections.map(\.roleID) }
    var isEmpty: Bool { selections.isEmpty }
}

/// Plans a complete group turn instead of only ranking member IDs. It supports
/// explicit/manual control, deterministic natural flow, pooled fairness and a
/// safe prompt-assembly mode while keeping generation itself outside the pure
/// domain service.
