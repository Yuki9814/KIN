import CryptoKit
import Foundation

/// Selects safe, relevant slices of the original conversation for prompt
/// assembly.  The SwiftData adapter is intentionally synchronous: callers copy
/// their `ConversationEvent` values on the main actor before doing any async
/// index work, and the actual strategy operates on the sendable snapshots below.
struct RawConversationRetriever: Sendable {
    static let assistantScoreMultiplier: Double = 0.65
    static let maximumResultCount = 12

    /// A value-only copy of the fields needed by historical retrieval.  Keeping
    /// this separate from `ConversationEvent` means no SwiftData model crosses an
    /// actor boundary when the local FTS index is queried.
    struct EventSnapshot: Equatable, Hashable, Sendable {
        let id: UUID
        let conversationID: UUID
        let role: String
        let content: String
        let occurredAt: Date
        let contentHash: String
        let deliveryState: String
        let redacted: Bool

        init(
            id: UUID,
            conversationID: UUID,
            role: String,
            content: String,
            occurredAt: Date = Date(),
            contentHash: String = "",
            deliveryState: String = EventDeliveryState.complete.rawValue,
            redacted: Bool = false
        ) {
            self.id = id
            self.conversationID = conversationID
            self.role = role
            self.content = content
            self.occurredAt = occurredAt
            self.contentHash = contentHash
            self.deliveryState = deliveryState
            self.redacted = redacted
        }

        /// This initializer is a main-actor-side adapter in practice.  It only
        /// copies scalar values; the snapshot itself is safe to send thereafter.
        @MainActor init(_ event: ConversationEvent) {
            self.init(
                id: event.id,
                conversationID: event.conversationID,
                role: event.roleRaw,
                content: event.content,
                occurredAt: event.occurredAt,
                contentHash: event.contentHash,
                deliveryState: event.deliveryStateRaw,
                redacted: event.redacted
            )
        }

        var eventRole: EventRole? {
            EventRole(rawValue: role)
        }

        var eventDeliveryState: EventDeliveryState? {
            EventDeliveryState(rawValue: deliveryState)
        }
    }

    typealias ConversationEventSnapshot = EventSnapshot
    typealias Snapshot = EventSnapshot

    /// Returns bounded historical excerpts from SwiftData events corresponding
    /// to lexical FTS candidates.  This overload is intended to be called while
    /// the caller is on the main actor; it immediately copies the model values
    /// and delegates to the sendable snapshot strategy.
    @MainActor static func retrieve<RecentIDs: Collection, SuppressedIDs: Collection, ForgottenIDs: Collection>(
        candidates: [LocalConversationSearchIndex.SearchCandidate],
        events: [ConversationEvent],
        currentEvent: ConversationEvent,
        recentEventIDs: RecentIDs = [],
        suppressedSourceEventIDs: SuppressedIDs = [],
        forgottenSourceEventIDs: ForgottenIDs = [],
        currentConversationID: UUID? = nil,
        limit: Int = maximumResultCount
    ) -> [HistoricalPromptExcerpt]
    where RecentIDs.Element == UUID, SuppressedIDs.Element == UUID, ForgottenIDs.Element == UUID {
        retrieve(
            candidates: candidates,
            events: events.map { EventSnapshot($0) },
            currentEvent: EventSnapshot(currentEvent),
            recentEventIDs: recentEventIDs,
            suppressedSourceEventIDs: suppressedSourceEventIDs,
            forgottenSourceEventIDs: forgottenSourceEventIDs,
            currentConversationID: currentConversationID,
            limit: limit
        )
    }

    /// The pure strategy used by the model adapter and by tests.  All inputs are
    /// value types, so this overload can safely be used from any actor.
    static func retrieve<RecentIDs: Collection, SuppressedIDs: Collection, ForgottenIDs: Collection>(
        candidates: [LocalConversationSearchIndex.SearchCandidate],
        events: [EventSnapshot],
        currentEvent: EventSnapshot,
        recentEventIDs: RecentIDs = [],
        suppressedSourceEventIDs: SuppressedIDs = [],
        forgottenSourceEventIDs: ForgottenIDs = [],
        currentConversationID: UUID? = nil,
        limit: Int = maximumResultCount
    ) -> [HistoricalPromptExcerpt]
    where RecentIDs.Element == UUID, SuppressedIDs.Element == UUID, ForgottenIDs.Element == UUID {
        let boundedLimit = min(max(0, limit), maximumResultCount)
        guard boundedLimit > 0 else { return [] }

        let recentIDs = Set(recentEventIDs)
        let excludedSourceIDs = Set(suppressedSourceEventIDs).union(forgottenSourceEventIDs)
        let conversationID = currentConversationID ?? currentEvent.conversationID
        let currentContent = currentEvent.content
        let currentHash = normalizedHash(currentEvent.contentHash)

        // A candidate ID should have one score.  If the index happens to return
        // duplicate rows, retain the strongest finite score deterministically.
        var scoresByID: [UUID: Double] = [:]
        scoresByID.reserveCapacity(candidates.count)
        for candidate in candidates where candidate.score.isFinite {
            if let previous = scoresByID[candidate.eventID] {
                scoresByID[candidate.eventID] = max(previous, candidate.score)
            } else {
                scoresByID[candidate.eventID] = candidate.score
            }
        }

        var ranked: [RankedEvent] = []
        ranked.reserveCapacity(min(events.count, scoresByID.count))

        for event in events {
            guard let score = scoresByID[event.id],
                  event.id != currentEvent.id,
                  event.conversationID == conversationID,
                  !recentIDs.contains(event.id),
                  !excludedSourceIDs.contains(event.id),
                  isIndexable(snapshot: event),
                  event.occurredAt <= currentEvent.occurredAt else {
                continue
            }

            let eventHash = normalizedHash(event.contentHash)
            if !currentHash.isEmpty, !eventHash.isEmpty, currentHash == eventHash {
                continue
            }
            if !currentContent.isEmpty, event.content == currentContent {
                continue
            }

            let adjustedScore = event.role == EventRole.assistant.rawValue
                ? score * assistantScoreMultiplier
                : score
            guard adjustedScore.isFinite else { continue }
            ranked.append(RankedEvent(event: event, score: adjustedScore))
        }

        // Sorting before hash de-duplication makes the representative stable and
        // keeps the highest effective score for repeated source content.
        ranked.sort(by: rankedOrdering)

        var result: [HistoricalPromptExcerpt] = []
        result.reserveCapacity(boundedLimit)
        var seenContentKeys = Set<String>()
        seenContentKeys.reserveCapacity(ranked.count)

        for rankedEvent in ranked {
            let contentKey = deduplicationKey(for: rankedEvent.event)
            guard seenContentKeys.insert(contentKey).inserted else { continue }
            guard let role = rankedEvent.event.eventRole else { continue }
            result.append(
                HistoricalPromptExcerpt(
                    eventID: rankedEvent.event.id,
                    role: role,
                    content: rankedEvent.event.content,
                    occurredAt: rankedEvent.event.occurredAt,
                    score: Float(rankedEvent.score),
                    redacted: false
                )
            )
            if result.count == boundedLimit { break }
        }
        return result
    }

    /// Natural aliases for callers that describe this operation as filtering or
    /// selecting rather than retrieval.
    @MainActor static func filter<RecentIDs: Collection, SuppressedIDs: Collection, ForgottenIDs: Collection>(
        candidates: [LocalConversationSearchIndex.SearchCandidate],
        events: [ConversationEvent],
        currentEvent: ConversationEvent,
        recentEventIDs: RecentIDs = [],
        suppressedSourceEventIDs: SuppressedIDs = [],
        forgottenSourceEventIDs: ForgottenIDs = [],
        currentConversationID: UUID? = nil,
        limit: Int = maximumResultCount
    ) -> [HistoricalPromptExcerpt]
    where RecentIDs.Element == UUID, SuppressedIDs.Element == UUID, ForgottenIDs.Element == UUID {
        retrieve(
            candidates: candidates,
            events: events,
            currentEvent: currentEvent,
            recentEventIDs: recentEventIDs,
            suppressedSourceEventIDs: suppressedSourceEventIDs,
            forgottenSourceEventIDs: forgottenSourceEventIDs,
            currentConversationID: currentConversationID,
            limit: limit
        )
    }

    @MainActor static func select<RecentIDs: Collection, SuppressedIDs: Collection, ForgottenIDs: Collection>(
        candidates: [LocalConversationSearchIndex.SearchCandidate],
        events: [ConversationEvent],
        currentEvent: ConversationEvent,
        recentEventIDs: RecentIDs = [],
        suppressedSourceEventIDs: SuppressedIDs = [],
        forgottenSourceEventIDs: ForgottenIDs = [],
        currentConversationID: UUID? = nil,
        limit: Int = maximumResultCount
    ) -> [HistoricalPromptExcerpt]
    where RecentIDs.Element == UUID, SuppressedIDs.Element == UUID, ForgottenIDs.Element == UUID {
        retrieve(
            candidates: candidates,
            events: events,
            currentEvent: currentEvent,
            recentEventIDs: recentEventIDs,
            suppressedSourceEventIDs: suppressedSourceEventIDs,
            forgottenSourceEventIDs: forgottenSourceEventIDs,
            currentConversationID: currentConversationID,
            limit: limit
        )
    }

    /// An event is eligible for the derived FTS cache only while its original
    /// user/assistant content is complete, visible, and non-empty.
    @MainActor static func isIndexable(event: ConversationEvent) -> Bool {
        isIndexable(snapshot: EventSnapshot(event))
    }

    @MainActor static func isIndexable(_ event: ConversationEvent) -> Bool {
        isIndexable(event: event)
    }

    static func isIndexable(snapshot: EventSnapshot) -> Bool {
        guard snapshot.role == EventRole.user.rawValue || snapshot.role == EventRole.assistant.rawValue,
              snapshot.deliveryState == EventDeliveryState.complete.rawValue,
              !snapshot.redacted else {
            return false
        }
        return !snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Builds a deterministic fingerprint for the source snapshot.  Event order
    /// is deliberately removed from the fingerprint so CloudKit fetch order or
    /// a different SwiftData sort cannot cause needless index rebuilds.  State,
    /// redaction, role, body/hash, and time changes remain visible.
    @MainActor static func manifest(events: [ConversationEvent]) -> String {
        manifest(snapshots: events.map { EventSnapshot($0) })
    }

    @MainActor static func manifest(_ events: [ConversationEvent]) -> String {
        manifest(events: events)
    }

    static func manifest(snapshots: [EventSnapshot]) -> String {
        let records = snapshots.map(manifestRecord)
        let sortedRecords = records.sorted { lhs, rhs in
            let left = lhs.map(lengthPrefixed).joined()
            let right = rhs.map(lengthPrefixed).joined()
            return left < right
        }
        let canonical = sortedRecords
            .map { record in
                record.map(lengthPrefixed).joined()
            }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private struct RankedEvent {
        let event: EventSnapshot
        let score: Double
    }

    private static func rankedOrdering(_ lhs: RankedEvent, _ rhs: RankedEvent) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.event.occurredAt != rhs.event.occurredAt {
            return lhs.event.occurredAt > rhs.event.occurredAt
        }
        return uuidKey(lhs.event.id) < uuidKey(rhs.event.id)
    }

    private static func normalizedHash(_ hash: String) -> String {
        hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func deduplicationKey(for event: EventSnapshot) -> String {
        let hash = normalizedHash(event.contentHash)
        guard !hash.isEmpty else {
            // Missing hashes should not make every blank-hash event collide.  A
            // body fallback still gives equivalent source text one representative.
            return "content:\(event.content)"
        }
        return "hash:\(hash)"
    }

    private static func uuidKey(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }

    private static func manifestRecord(_ event: EventSnapshot) -> [String] {
        [
            uuidKey(event.id),
            uuidKey(event.conversationID),
            event.role,
            event.deliveryState,
            event.redacted ? "1" : "0",
            event.contentHash,
            event.content,
            String(event.occurredAt.timeIntervalSince1970.bitPattern, radix: 16)
        ]
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}
