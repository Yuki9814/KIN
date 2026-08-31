import Foundation

extension GroupTurnPlanner {
    func dominantReason(
        topic: Double,
        personality: Double,
        affinity: Double,
        talkativeness: Double
    ) -> GroupTurnActivationReason {
        let values: [(GroupTurnActivationReason, Double)] = [
            (.topicRelevance, topic),
            (.personalityFit, personality),
            (.affinity, affinity),
            (.talkativeness, talkativeness)
        ]
        return values.max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? .fallback
    }

    func directedPlan(
        members: [GroupTurnMember],
        reason: GroupTurnActivationReason,
        strategy: GroupReplyStrategy,
        context: GroupTurnPlanningContext
    ) -> GroupTurnPlan {
        makePlan(
            members: members,
            reason: reason,
            strategy: strategy,
            context: context,
            explicitlyDirected: true,
            cap: false
        )
    }

    func makePlan(
        members: [GroupTurnMember],
        reason: GroupTurnActivationReason,
        strategy: GroupReplyStrategy,
        context: GroupTurnPlanningContext,
        explicitlyDirected: Bool,
        cap: Bool = true
    ) -> GroupTurnPlan {
        let resolved = cap
            ? Array(members.prefix(context.maxAutomaticResponders))
            : members
        return GroupTurnPlan(
            strategy: strategy,
            promptAssemblyMode: context.promptAssemblyMode,
            selections: resolved.map {
                GroupTurnSelection(
                    roleID: $0.roleID,
                    displayName: $0.displayName,
                    score: 1,
                    reason: reason
                )
            },
            shouldGenerateSequentially: true,
            wasExplicitlyDirected: explicitlyDirected
        )
    }

    func makePlan(
        rankedMembers: [RankedMember],
        strategy: GroupReplyStrategy,
        context: GroupTurnPlanningContext,
        explicitlyDirected: Bool,
        forcedReason: GroupTurnActivationReason? = nil
    ) -> GroupTurnPlan {
        GroupTurnPlan(
            strategy: strategy,
            promptAssemblyMode: context.promptAssemblyMode,
            selections: rankedMembers.map {
                GroupTurnSelection(
                    roleID: $0.member.roleID,
                    displayName: $0.member.displayName,
                    score: $0.score,
                    reason: forcedReason ?? $0.reason
                )
            },
            shouldGenerateSequentially: true,
            wasExplicitlyDirected: explicitlyDirected
        )
    }

    func emptyPlan(_ context: GroupTurnPlanningContext) -> GroupTurnPlan {
        GroupTurnPlan(
            strategy: context.strategy,
            promptAssemblyMode: context.promptAssemblyMode,
            selections: [],
            shouldGenerateSequentially: true,
            wasExplicitlyDirected: false
        )
    }

    func canonicalMembers(_ members: [GroupTurnMember]) -> [GroupTurnMember] {
        var winners: [UUID: GroupTurnMember] = [:]
        for member in members {
            guard let current = winners[member.roleID] else {
                winners[member.roleID] = member
                continue
            }
            if member.order < current.order {
                winners[member.roleID] = member
            }
        }
        return winners.values.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.roleID.uuidString < rhs.roleID.uuidString
        }
    }

    func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func asksEveryone(_ message: String) -> Bool {
        let value = normalized(message)
        let markers = [
            "@所有人", "@全体成员", "@大家", "@everyone", "@all",
            "大家都", "所有人都", "你们都", "每个人"
        ]
        return markers.contains(where: value.contains)
    }

    func invitesDiscussion(_ message: String) -> Bool {
        let value = normalized(message)
        let markers = [
            "大家怎么看", "你们怎么看", "一起讨论", "分别说说", "各自说说",
            "都来回答", "轮流说", "what do you all think", "everyone answer"
        ]
        return markers.contains(where: value.contains)
            || value.filter { $0 == "？" || $0 == "?" }.count >= 2
    }

    func isDirectQuestion(_ message: String) -> Bool {
        let value = normalized(message)
        guard !value.isEmpty else { return false }
        if value.contains("？") || value.contains("?") { return true }
        let questionMarkers = [
            "吗", "呢", "为什么", "怎么", "哪", "谁", "多少", "是不是",
            "能不能", "可不可以", "what", "why", "how", "who", "where", "when"
        ]
        return questionMarkers.contains(where: value.contains)
    }
}
