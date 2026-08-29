import Foundation

/// Selects which group members answer one turn. It returns only stable role
/// identifiers; names and message content remain the caller's concern.
struct GroupResponseCoordinator {
    struct Member: Equatable, Hashable, Sendable {
        let roleID: UUID
        let displayName: String
        let order: Int
        let topicRelevance: Double
        let personalityFit: Double
        let affinityScore: Double
        let recentTurnPenalty: Double

        init(
            roleID: UUID,
            displayName: String = "",
            order: Int = 0,
            topicRelevance: Double = 0.5,
            personalityFit: Double = 0.5,
            affinityScore: Double = 50,
            recentTurnPenalty: Double = 0
        ) {
            self.roleID = roleID
            self.displayName = displayName
            self.order = order
            self.topicRelevance = Self.clampUnit(topicRelevance)
            self.personalityFit = Self.clampUnit(personalityFit)
            self.affinityScore = Self.clampPercent(affinityScore)
            self.recentTurnPenalty = Self.clampUnit(recentTurnPenalty)
        }

        private static func clampUnit(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(1, max(0, value))
        }

        private static func clampPercent(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(100, max(0, value))
        }
    }

    /// The default keeps an unmentioned turn to one or two responders.
    let maximumUnmentionedResponders: Int

    init(maximumUnmentionedResponders: Int = 2) {
        self.maximumUnmentionedResponders = max(1, min(2, maximumUnmentionedResponders))
    }

    /// Returns the strict response order. Mentioned members all answer; when
    /// there is no mention, one or two members are selected by deterministic
    /// relevance, fit, affinity, and recent-turn penalty. Fewer than two
    /// distinct members is not a group and yields no response.
    func responseOrder(
        members: [Member],
        mentionedRoleIDs: Set<UUID> = []
    ) -> [UUID] {
        let ordered = stableMembers(members)
        guard ordered.count >= 2 else { return [] }

        let mentioned = ordered.filter { mentionedRoleIDs.contains($0.roleID) }
        if !mentioned.isEmpty {
            return mentioned.map(\.roleID)
        }

        let ranked = ordered.sorted { lhs, rhs in
            let lhsScore = score(for: lhs)
            let rhsScore = score(for: rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.roleID.uuidString < rhs.roleID.uuidString
        }
        guard let winner = ranked.first else { return [] }
        let winnerScore = score(for: winner)
        let threshold = max(0.45, winnerScore - 0.20)
        let selected = ranked
            .prefix(maximumUnmentionedResponders)
            .filter { score(for: $0) >= threshold }
        return selected.isEmpty ? [winner.roleID] : selected.map(\.roleID)
    }

    /// Resolves @name and @role-UUID mentions, then applies the same ordering
    /// rule. Unknown mentions are ignored and never produce an arbitrary role.
    func responseOrder(
        members: [Member],
        message: String
    ) -> [UUID] {
        responseOrder(
            members: members,
            mentionedRoleIDs: mentionedRoleIDs(in: message, members: members)
        )
    }

    /// Uses the UI's role-ID selections when available. This is important for
    /// duplicate display names: the text remains readable, while the selected
    /// IDs identify exactly which members should answer. Empty or stale
    /// selections fall back to the token-aware text parser for typed mentions.
    func responseOrder(
        members: [Member],
        message: String,
        explicitlyMentionedRoleIDs: Set<UUID> = []
    ) -> [UUID] {
        let knownRoleIDs = Set(members.map(\.roleID))
        let explicit = explicitlyMentionedRoleIDs.intersection(knownRoleIDs)
        if !explicit.isEmpty {
            return responseOrder(members: members, mentionedRoleIDs: explicit)
        }
        return responseOrder(members: members, message: message)
    }

    func mentionedRoleIDs(
        in message: String,
        members: [Member]
    ) -> Set<UUID> {
        Set(members.compactMap { member in
            let nameMention = !member.displayName.isEmpty
                && containsMentionToken("@\(member.displayName)", in: message)
            let idMention = containsMentionToken(
                "@\(member.roleID.uuidString)",
                in: message,
                options: [.caseInsensitive]
            )
            return nameMention || idMention ? member.roleID : nil
        })
    }

    /// Alias for call sites that use “responders” terminology.
    func responderRoleIDs(
        for members: [Member],
        mentionedRoleIDs: Set<UUID> = []
    ) -> [UUID] {
        responseOrder(members: members, mentionedRoleIDs: mentionedRoleIDs)
    }

    private func stableMembers(_ members: [Member]) -> [Member] {
        var seen: Set<UUID> = []
        let unique = members.filter { seen.insert($0.roleID).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.roleID.uuidString < rhs.roleID.uuidString
        }
    }

    /// Finds a complete @mention rather than a substring. This keeps a name
    /// such as "安" from matching "@安娜" and avoids treating the middle of
    /// an email-like token as a role mention.
    private func containsMentionToken(
        _ token: String,
        in message: String,
        options: String.CompareOptions = []
    ) -> Bool {
        guard !token.isEmpty, !message.isEmpty else { return false }
        var searchStart = message.startIndex
        while searchStart < message.endIndex,
              let range = message.range(
                  of: token,
                  options: options,
                  range: searchStart..<message.endIndex
              ) {
            if hasMentionBoundaries(for: range, in: message) {
                return true
            }
            guard range.lowerBound < message.endIndex else { return false }
            searchStart = message.index(after: range.lowerBound)
        }
        return false
    }

    private func hasMentionBoundaries(
        for range: Range<String.Index>,
        in message: String
    ) -> Bool {
        let hasLeadingBoundary: Bool
        if range.lowerBound == message.startIndex {
            hasLeadingBoundary = true
        } else {
            let previous = message[message.index(before: range.lowerBound)]
            hasLeadingBoundary = previous != "@" && isMentionBoundary(previous)
        }

        let hasTrailingBoundary: Bool
        if range.upperBound == message.endIndex {
            hasTrailingBoundary = true
        } else {
            let next = message[range.upperBound]
            hasTrailingBoundary = next != "@" && isMentionBoundary(next)
        }
        return hasLeadingBoundary && hasTrailingBoundary
    }

    private func isMentionBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character.isPunctuation || character.isSymbol
    }

    private func score(for member: Member) -> Double {
        // Topic relevance leads the choice, while affinity contributes as a
        // normalized 0...1 value. The penalty is the only subtractive term.
        member.topicRelevance * 0.45
            + member.personalityFit * 0.25
            + (member.affinityScore / 100) * 0.20
            - member.recentTurnPenalty * 0.10
    }
}
