import Foundation

extension LorebookEngine {
    static func candidateRanksBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.reason.rank != rhs.reason.rank { return lhs.reason.rank > rhs.reason.rank }
        let lhsMatches = lhs.primaryMatches.count + lhs.secondaryMatches.count
        let rhsMatches = rhs.primaryMatches.count + rhs.secondaryMatches.count
        if lhsMatches != rhsMatches { return lhsMatches > rhsMatches }
        if lhs.entry.priority != rhs.entry.priority { return lhs.entry.priority > rhs.entry.priority }
        if lhs.entry.insertionOrder != rhs.entry.insertionOrder {
            return lhs.entry.insertionOrder > rhs.entry.insertionOrder
        }
        if lhs.entry.groupWeight != rhs.entry.groupWeight {
            return lhs.entry.groupWeight > rhs.entry.groupWeight
        }
        return lhs.entry.id.uuidString < rhs.entry.id.uuidString
    }

    static func resolveInclusionGroups(
        _ candidates: [Candidate],
        seed: String
    ) -> (accepted: [Candidate], skipped: [UUID]) {
        var claimedGroups = Set<String>()
        var accepted: [Candidate] = []
        var skipped: [UUID] = []

        // Ranking already makes the winner deterministic. The seed is folded
        // into a stable tie-break only for otherwise equivalent weighted rows.
        let ordered = candidates.sorted { lhs, rhs in
            if candidateRanksBefore(lhs, rhs) { return true }
            if candidateRanksBefore(rhs, lhs) { return false }
            let left = stableHash(seed + lhs.entry.id.uuidString)
            let right = stableHash(seed + rhs.entry.id.uuidString)
            return left < right
        }
        for candidate in ordered {
            let groups = Set(candidate.entry.inclusionGroups.map {
                $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            })
            if !groups.isDisjoint(with: claimedGroups) {
                skipped.append(candidate.entry.id)
                continue
            }
            accepted.append(candidate)
            claimedGroups.formUnion(groups)
        }
        return (accepted, skipped)
    }

    static func selectionRendersBefore(
        _ lhs: LorebookActivationSelection,
        _ rhs: LorebookActivationSelection
    ) -> Bool {
        let leftPosition = lhs.entry.insertionPosition.stableOrder
        let rightPosition = rhs.entry.insertionPosition.stableOrder
        if leftPosition != rightPosition { return leftPosition < rightPosition }
        if lhs.entry.insertionOrder != rhs.entry.insertionOrder {
            return lhs.entry.insertionOrder < rhs.entry.insertionOrder
        }
        if lhs.entry.priority != rhs.entry.priority {
            return lhs.entry.priority < rhs.entry.priority
        }
        return lhs.entry.id.uuidString < rhs.entry.id.uuidString
    }
}
