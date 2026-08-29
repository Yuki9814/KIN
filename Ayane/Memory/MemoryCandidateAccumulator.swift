import Foundation

/// Keeps the strongest candidates from an arbitrarily large sequence of
/// memory snapshots without retaining the complete source library.
///
/// Each batch and the already-retained candidates are ranked with the same
/// hybrid scorer and near-duplicate/diversity policy used at the final prompt
/// boundary. The deliberately generous reservoir is still bounded; the final
/// `MemoryEngine.search` call owns the exact prompt token budget.
struct MemoryCandidateAccumulator: Sendable {
    private let query: String
    private let limit: Int
    private let now: Date
    private let queryEmbedding: [Float]?
    private let individualTokenBudget: Int?
    private var retained: [MemorySnapshot] = []

    init(
        query: String,
        limit: Int,
        now: Date,
        queryEmbedding: [Float]?,
        individualTokenBudget: Int? = nil
    ) {
        self.query = query
        self.limit = max(0, limit)
        self.now = now
        self.queryEmbedding = queryEmbedding
        self.individualTokenBudget = individualTokenBudget.map { max(0, $0) }
    }

    var snapshots: [MemorySnapshot] { retained }
    var count: Int { retained.count }

    mutating func consume(_ batch: [MemorySnapshot]) {
        guard limit > 0, !batch.isEmpty else { return }

        // CloudKit can temporarily materialize more than one physical row for
        // an application UUID. Resolve the value snapshots deterministically
        // before ranking, preferring the newest version of that UUID.
        var newestByID: [String: MemorySnapshot] = [:]
        newestByID.reserveCapacity(retained.count + batch.count)
        for snapshot in retained + batch {
            if let individualTokenBudget,
               MemoryTokenizer.tokenCount(of: snapshot.text) > individualTokenBudget {
                continue
            }
            guard let existing = newestByID[snapshot.id] else {
                newestByID[snapshot.id] = snapshot
                continue
            }
            if isNewer(snapshot, than: existing) {
                newestByID[snapshot.id] = snapshot
            }
        }

        // Stable input identity prevents Dictionary iteration order from
        // becoming an otherwise invisible ranking tie-break.
        let ordered = newestByID.values.sorted { $0.id < $1.id }
        retained = MemoryEngine.shared.search(
            query,
            in: ordered,
            options: MemorySearchOptions(
                maxResults: limit,
                tokenBudget: nil,
                now: now,
                queryEmbedding: queryEmbedding,
                includeExpired: false,
                minimumScore: 0,
                duplicateJaccardThreshold: 0.86,
                diversityStrength: 0.18,
                recencyHalfLifeDays: 180
            )
        ).map(\.memory)
    }

    private func isNewer(_ lhs: MemorySnapshot, than rhs: MemorySnapshot) -> Bool {
        if lhs.lastModifiedAt != rhs.lastModifiedAt {
            return lhs.lastModifiedAt > rhs.lastModifiedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.text > rhs.text
    }
}
