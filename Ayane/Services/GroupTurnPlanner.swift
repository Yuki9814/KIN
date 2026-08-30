import Foundation

struct GroupTurnPlanner {
    private let mentionCoordinator: GroupResponseCoordinator

    init(mentionCoordinator: GroupResponseCoordinator = GroupResponseCoordinator()) {
        self.mentionCoordinator = mentionCoordinator
    }

    func plan(
        members: [GroupTurnMember],
        message: String,
        context: GroupTurnPlanningContext = GroupTurnPlanningContext()
    ) -> GroupTurnPlan {
        let canonical = canonicalMembers(members)
        guard !canonical.isEmpty else {
            return emptyPlan(context)
        }

        if context.strategy == .manual {
            return manualPlan(members: canonical, context: context)
        }

        let available = canonical.filter { !$0.isMuted }
        guard !available.isEmpty else { return emptyPlan(context) }

        let parsedMentions = mentionCoordinator.mentionedRoleIDs(
            in: message,
            members: available.map {
                GroupResponseCoordinator.Member(
                    roleID: $0.roleID,
                    displayName: $0.displayName,
                    order: $0.order,
                    topicRelevance: $0.topicRelevance,
                    personalityFit: $0.personalityFit,
                    affinityScore: $0.affinityScore * 100,
                    recentTurnPenalty: $0.recentTurnPenalty
                )
            }
        )
        let mentionedIDs = context.explicitlyMentionedRoleIDs.union(parsedMentions)
        let mentionAll = asksEveryone(message)

        if mentionAll {
            return directedPlan(
                members: available,
                reason: .mentionAll,
                strategy: context.strategy,
                context: context
            )
        }
        if !mentionedIDs.isEmpty {
            let directed = available.filter { mentionedIDs.contains($0.roleID) }
            return directedPlan(
                members: directed,
                reason: .explicitMention,
                strategy: context.strategy,
                context: context
            )
        }

        switch context.strategy {
        case .manual:
            return manualPlan(members: canonical, context: context)
        case .listOrder:
            let selected = Array(available.prefix(context.maxAutomaticResponders))
            return makePlan(
                members: selected,
                reason: .listOrder,
                strategy: .listOrder,
                context: context,
                explicitlyDirected: false
            )
        case .pooled:
            let pool = available.filter { !$0.hasSpokenSinceUserMessage }
            let candidates = pool.isEmpty ? available : pool
            guard let winner = ranked(candidates, context: context).first else {
                return emptyPlan(context)
            }
            return makePlan(
                rankedMembers: [winner],
                strategy: .pooled,
                context: context,
                explicitlyDirected: false,
                forcedReason: .pooled
            )
        case .natural:
            return naturalPlan(
                members: available,
                message: message,
                context: context
            )
        }
    }

    private func manualPlan(
        members: [GroupTurnMember],
        context: GroupTurnPlanningContext
    ) -> GroupTurnPlan {
        guard let roleID = context.manuallySelectedRoleID,
              let member = members.first(where: { $0.roleID == roleID }),
              context.forceManualSpeaker || !member.isMuted else {
            return emptyPlan(context)
        }
        return makePlan(
            members: [member],
            reason: .manual,
            strategy: .manual,
            context: context,
            explicitlyDirected: true
        )
    }

    private func naturalPlan(
        members: [GroupTurnMember],
        message: String,
        context: GroupTurnPlanningContext
    ) -> GroupTurnPlan {
        var rankedMembers = ranked(members, context: context)
        guard let winner = rankedMembers.first else { return emptyPlan(context) }

        let threshold = max(0.34, winner.score - 0.16)
        rankedMembers = rankedMembers.filter { $0.score >= threshold }
        let desiredCount: Int
        if asksEveryone(message) || invitesDiscussion(message) {
            desiredCount = min(2, context.maxAutomaticResponders)
        } else if isDirectQuestion(message) || normalized(message).count <= 20 {
            desiredCount = 1
        } else if rankedMembers.count >= 2,
                  winner.score >= 0.52,
                  winner.score - rankedMembers[1].score <= 0.08 {
            desiredCount = min(2, context.maxAutomaticResponders)
        } else {
            desiredCount = 1
        }

        let selected = Array(rankedMembers.prefix(max(1, desiredCount)))
        return makePlan(
            rankedMembers: selected,
            strategy: .natural,
            context: context,
            explicitlyDirected: false
        )
    }

    struct RankedMember {
        let member: GroupTurnMember
        let score: Double
        let reason: GroupTurnActivationReason
    }

    private func ranked(
        _ members: [GroupTurnMember],
        context: GroupTurnPlanningContext
    ) -> [RankedMember] {
        members.map { member in
            let topic = member.topicRelevance * 0.36
            let personality = member.personalityFit * 0.22
            let affinity = member.affinityScore * 0.16
            let talkativeness = member.talkativeness * 0.18
            let recentPenalty = member.recentTurnPenalty * 0.08
            let consecutivePenalty = context.allowSelfResponses
                || context.lastSpeakerRoleID != member.roleID ? 0 : 0.18
            let pooledPenalty = member.hasSpokenSinceUserMessage ? 0.06 : 0
            let score = topic + personality + affinity + talkativeness
                - recentPenalty - consecutivePenalty - pooledPenalty
            let reason = dominantReason(
                topic: topic,
                personality: personality,
                affinity: affinity,
                talkativeness: talkativeness
            )
            return RankedMember(member: member, score: score, reason: reason)
        }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.member.order != rhs.member.order {
                return lhs.member.order < rhs.member.order
            }
            return lhs.member.roleID.uuidString < rhs.member.roleID.uuidString
        }
    }
}
