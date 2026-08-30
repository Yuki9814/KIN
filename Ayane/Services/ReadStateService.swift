import Foundation
import SwiftData

/// A stable ordering key for conversation events. `occurredAt` alone is not
/// sufficient because two devices can write at the same instant, so the
/// logical timestamp and event UUID complete the cursor.
struct ConversationReadCursor: Equatable, Comparable, Sendable {
    let occurredAt: Date
    let logicalTimestamp: String
    let eventID: UUID

    static func < (lhs: ConversationReadCursor, rhs: ConversationReadCursor) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.logicalTimestamp != rhs.logicalTimestamp {
            return lhs.logicalTimestamp < rhs.logicalTimestamp
        }
        return lhs.eventID.uuidString.lowercased() < rhs.eventID.uuidString.lowercased()
    }
}

/// A stable ordering key for Moments reactions.
struct MomentReadCursor: Equatable, Comparable, Sendable {
    let createdAt: Date
    let interactionID: UUID

    /// A post publication is a virtual event. It must sort before every real
    /// interaction at the same timestamp without being persisted as an
    /// interaction ID (read-state import validates IDs against real rows).
    static let zeroInteractionID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static func < (lhs: MomentReadCursor, rhs: MomentReadCursor) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.interactionID.uuidString.lowercased() < rhs.interactionID.uuidString.lowercased()
    }
}

/// Owns the durable read cursors for the iOS chat and Moments surfaces.
///
/// This service deliberately stores display state in separate models. It
/// never mutates event/post bodies, hashes, delivery state, or memory metadata.
@MainActor
final class ReadStateService {
    let context: ModelContext
    let deviceID: String

    init(context: ModelContext, deviceID: String = "") {
        self.context = context
        self.deviceID = deviceID
    }

    // MARK: - Conversation cursors

    func unreadConversationCount(
        conversationID: UUID,
        roleID: UUID? = nil
    ) throws -> Int {
        let resolvedRoleID = RoleScope.resolve(roleID)
        let marker = try canonicalConversationMarker(
            conversationID: conversationID,
            roleID: resolvedRoleID
        )
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
        let presentations = try canonicalPresentationsByReplyEventID()
        return events.filter { event in
            event.conversationID == conversationID
                && event.resolvedRoleID == resolvedRoleID
                && isUnreadConversationEvent(event, after: marker)
        }.reduce(into: 0) { total, event in
            total += visibleBubbleCount(
                for: event,
                presentation: presentations[event.id]
            )
        }
    }

    /// With a conversation ID this is an exact query. Without one, a role ID
    /// scopes the aggregate to that role's unarchived conversations; with
    /// neither ID it returns the total for all unarchived conversations.
    func unreadConversationCount(
        conversationID: UUID? = nil,
        roleID: UUID? = nil
    ) throws -> Int {
        if let conversationID {
            return try unreadConversationCount(
                conversationID: conversationID,
                roleID: roleID
            )
        }

        let resolvedRoleID = roleID.map(RoleScope.resolve)
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
            .filter { !$0.archived }
            .filter { conversation in
                resolvedRoleID == nil || conversation.resolvedRoleID == resolvedRoleID
            }
        var seen = Set<UUID>()
        return try conversations.reduce(into: 0) { total, conversation in
            guard seen.insert(conversation.id).inserted else { return }
            total += try unreadConversationCount(
                conversationID: conversation.id,
                roleID: conversation.resolvedRoleID
            )
        }
    }

    func unreadConversationCounts(
        roleID: UUID? = nil
    ) throws -> [UUID: Int] {
        let resolvedRoleID = roleID.map(RoleScope.resolve)
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
            .filter { !$0.archived }
            .filter { conversation in
                resolvedRoleID == nil || conversation.resolvedRoleID == resolvedRoleID
            }
        var result: [UUID: Int] = [:]
        for conversation in conversations {
            // Physical duplicates share one application-level conversation ID.
            // The count is deterministic and is only exposed once to the UI.
            if result[conversation.id] == nil {
                result[conversation.id] = try unreadConversationCount(
                    conversationID: conversation.id,
                    roleID: conversation.resolvedRoleID
                )
            }
        }
        return result
    }

    /// Advances a conversation marker through the newest currently persisted
    /// event. Events arriving after this snapshot remain unread until a later
    /// explicit mark/read pass.
    func markConversationRead(
        conversationID: UUID,
        roleID: UUID? = nil,
        now: Date = Date()
    ) throws {
        let resolvedRoleID = RoleScope.resolve(roleID)
        let events = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.conversationID == conversationID
                    && $0.resolvedRoleID == resolvedRoleID
            }
        // A streaming logical reply is not fully read yet: more visible
        // bubbles can still arrive under the same event cursor. Advance only
        // once the reply has completed while this conversation is on screen.
        let newest = events
            .filter(isReadableConversationEvent)
            .map(ConversationReadCursor.init(event:))
            .max()
        // Do not move a read cursor to `now` while the only reply is still
        // streaming. That reply keeps the same event timestamp when it later
        // completes, so advancing here would incorrectly consume every
        // not-yet-visible bubble.
        guard let newest else { return }
        let marker = try writableConversationMarker(
            conversationID: conversationID,
            roleID: resolvedRoleID,
            now: now
        )
        let current = conversationCursor(from: marker)
        let candidate = newest
        guard current == nil || current! < candidate else { return }
        marker.lastReadOccurredAt = candidate.occurredAt
        marker.lastReadLogicalTimestamp = candidate.logicalTimestamp
        marker.lastReadEventID = newest.eventID
        marker.updatedAt = now
        marker.revision = max(0, marker.revision) + 1
        marker.deviceID = deviceID
        try context.save()
    }

    // MARK: - Moments cursors

    func unreadMomentCount(postID: UUID) throws -> Int {
        let marker = try canonicalMomentMarker(postID: postID)
        let posts = try context.fetch(FetchDescriptor<MomentPostRecord>())
        guard let post = posts.first(where: { $0.id == postID }),
              try isVisibleMomentPost(post) else {
            return 0
        }
        let interactions = try companionReactions(for: postID)
        let unreadInteractions = interactions.filter { interaction in
            isUnreadMomentInteraction(interaction, after: marker)
        }.count
        guard post.authorKind == .companion else { return unreadInteractions }

        let publication = MomentReadCursor(
            createdAt: post.publishedAt,
            interactionID: MomentReadCursor.zeroInteractionID
        )
        return unreadInteractions + (isUnreadMomentCursor(publication, after: marker) ? 1 : 0)
    }

    func unreadMomentCounts(postIDs: [UUID]? = nil) throws -> [UUID: Int] {
        let posts = try context.fetch(FetchDescriptor<MomentPostRecord>())
            .filter { $0.deletedAt == nil }
        let allowed = postIDs.map(Set.init)
        var result: [UUID: Int] = [:]
        for post in posts where allowed?.contains(post.id) ?? true {
            result[post.id] = try unreadMomentCount(postID: post.id)
        }
        return result
    }

    /// Marks all supplied/currently visible posts through the current snapshot.
    /// A companion publication and its interactions share one per-post cursor;
    /// user posts only have the interaction portion of that cursor.
    func markMomentsRead(
        postIDs: [UUID]? = nil,
        now: Date = Date()
    ) throws {
        let posts = try context.fetch(FetchDescriptor<MomentPostRecord>())
            .filter { $0.deletedAt == nil }
        let allowed = postIDs.map(Set.init)
        var changed = false
        for post in posts where allowed?.contains(post.id) ?? true {
            guard try isVisibleMomentPost(post) else { continue }
            let interactions = try companionReactions(for: post.id)
            let candidate = latestMomentReadCursor(
                for: post,
                interactions: interactions,
                now: now
            )
            let marker = try writableMomentMarker(postID: post.id, now: now)
            let current = momentCursor(from: marker)
            guard current == nil || current! < candidate else { continue }
            marker.lastReadCreatedAt = candidate.createdAt
            marker.lastReadInteractionID = candidate.interactionID == MomentReadCursor.zeroInteractionID
                ? nil
                : candidate.interactionID
            marker.updatedAt = now
            marker.revision = max(0, marker.revision) + 1
            marker.deviceID = deviceID
            changed = true
        }
        if changed || !posts.isEmpty { try context.save() }
    }

    func unreadMomentsCount(postIDs: [UUID]? = nil) throws -> Int {
        try unreadMomentCounts(postIDs: postIDs).values.reduce(0, +)
    }

    // MARK: - First-run compatibility

    /// Creates a read baseline only for scopes with no marker. This is used
    /// once when upgrading an old store, which had no unread concept. Existing
    /// history therefore does not suddenly produce badges, while later writes
    /// remain eligible for unread counting.
    func establishInitialReadBaseline(now: Date = Date()) throws {
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let uniqueConversations = Dictionary(
            conversations.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for conversation in uniqueConversations.values
            where try canonicalConversationMarker(
                conversationID: conversation.id,
                roleID: conversation.resolvedRoleID
            ) == nil {
            let marker = try writableConversationMarker(
                conversationID: conversation.id,
                roleID: conversation.resolvedRoleID,
                now: now
            )
            let events = try context.fetch(FetchDescriptor<ConversationEvent>())
                .filter {
                    $0.conversationID == conversation.id
                        && $0.resolvedRoleID == conversation.resolvedRoleID
                }
            if let newest = events.compactMap({ ConversationReadCursor(event: $0) }).max() {
                marker.lastReadOccurredAt = newest.occurredAt
                marker.lastReadLogicalTimestamp = newest.logicalTimestamp
                marker.lastReadEventID = newest.eventID
            } else {
                marker.lastReadOccurredAt = now
                marker.lastReadLogicalTimestamp = ""
                marker.lastReadEventID = nil
            }
            marker.updatedAt = now
            marker.revision = max(0, marker.revision) + 1
            marker.deviceID = deviceID
        }

        let posts = try context.fetch(FetchDescriptor<MomentPostRecord>())
            .filter { $0.deletedAt == nil }
        let uniquePosts = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for post in uniquePosts.values where try canonicalMomentMarker(postID: post.id) == nil {
            let marker = try writableMomentMarker(postID: post.id, now: now)
            let candidate = latestMomentReadCursor(
                for: post,
                interactions: try companionReactions(for: post.id),
                now: now
            )
            marker.lastReadCreatedAt = candidate.createdAt
            marker.lastReadInteractionID = candidate.interactionID == MomentReadCursor.zeroInteractionID
                ? nil
                : candidate.interactionID
            marker.updatedAt = now
            marker.revision = max(0, marker.revision) + 1
            marker.deviceID = deviceID
        }
        try context.save()
    }

    // MARK: - Cursor helpers shared by import/merge

    static func conversationCursor(from marker: ConversationReadStateRecord) -> ConversationReadCursor? {
        guard let occurredAt = marker.lastReadOccurredAt else { return nil }
        return ConversationReadCursor(
            occurredAt: occurredAt,
            logicalTimestamp: marker.lastReadLogicalTimestamp,
            eventID: marker.lastReadEventID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        )
    }

    static func momentCursor(from marker: MomentReadStateRecord) -> MomentReadCursor? {
        guard let createdAt = marker.lastReadCreatedAt else { return nil }
        return MomentReadCursor(
            createdAt: createdAt,
            interactionID: marker.lastReadInteractionID ?? MomentReadCursor.zeroInteractionID
        )
    }

    static func isNewer(
        _ lhs: ConversationReadStateRecord,
        than rhs: ConversationReadStateRecord
    ) -> Bool {
        switch (conversationCursor(from: lhs), conversationCursor(from: rhs)) {
        case let (left?, right?):
            if left != right { return left > right }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased()
    }

    static func isNewer(
        _ lhs: MomentReadStateRecord,
        than rhs: MomentReadStateRecord
    ) -> Bool {
        switch (momentCursor(from: lhs), momentCursor(from: rhs)) {
        case let (left?, right?):
            if left != right { return left > right }
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): break
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased()
    }

    // MARK: - Private storage helpers

    private func canonicalConversationMarker(
        conversationID: UUID,
        roleID: UUID
    ) throws -> ConversationReadStateRecord? {
        let candidates = try context.fetch(FetchDescriptor<ConversationReadStateRecord>())
            .filter {
                $0.conversationID == conversationID
                    && $0.resolvedRoleID == roleID
            }
        return candidates.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return Self.isNewer(candidate, than: current) ? candidate : current
        }
    }

    private func writableConversationMarker(
        conversationID: UUID,
        roleID: UUID,
        now: Date
    ) throws -> ConversationReadStateRecord {
        if let marker = try canonicalConversationMarker(
            conversationID: conversationID,
            roleID: roleID
        ) {
            return marker
        }
        let marker = ConversationReadStateRecord(
            roleID: roleID,
            conversationID: conversationID,
            updatedAt: now,
            deviceID: deviceID
        )
        context.insert(marker)
        return marker
    }

    private func canonicalMomentMarker(postID: UUID) throws -> MomentReadStateRecord? {
        let candidates = try context.fetch(FetchDescriptor<MomentReadStateRecord>())
            .filter { $0.postID == postID }
        return candidates.reduce(nil) { current, candidate in
            guard let current else { return candidate }
            return Self.isNewer(candidate, than: current) ? candidate : current
        }
    }

    private func writableMomentMarker(
        postID: UUID,
        now: Date
    ) throws -> MomentReadStateRecord {
        if let marker = try canonicalMomentMarker(postID: postID) { return marker }
        let marker = MomentReadStateRecord(
            postID: postID,
            updatedAt: now,
            deviceID: deviceID
        )
        context.insert(marker)
        return marker
    }

    private func conversationCursor(from marker: ConversationReadStateRecord?) -> ConversationReadCursor? {
        guard let marker else { return nil }
        return Self.conversationCursor(from: marker)
    }

    private func momentCursor(from marker: MomentReadStateRecord?) -> MomentReadCursor? {
        guard let marker else { return nil }
        return Self.momentCursor(from: marker)
    }

    private func isUnreadConversationEvent(
        _ event: ConversationEvent,
        after marker: ConversationReadStateRecord?
    ) -> Bool {
        guard isReadableConversationEvent(event) else { return false }
        guard let markerCursor = conversationCursor(from: marker) else { return true }
        return ConversationReadCursor(event: event) > markerCursor
    }

    private func isReadableConversationEvent(_ event: ConversationEvent) -> Bool {
        event.role == .assistant
            && event.deliveryState == .complete
            && !event.redacted
    }

    /// One durable assistant event can be presented as several sequential
    /// WeChat-style bubbles. Unread badges represent what the user sees, while
    /// memory, sync, and idempotency continue to treat it as one logical reply.
    private func visibleBubbleCount(
        for event: ConversationEvent,
        presentation: ChatTurnPresentationRecord?
    ) -> Int {
        guard let presentation else { return 1 }
        let plannedCount = presentation.segments.count
        let visibleCount = presentation.state == .completed
            ? plannedCount
            : min(max(0, presentation.displayedSegmentCount), plannedCount)
        return max(1, visibleCount)
    }

    private func canonicalPresentationsByReplyEventID() throws
        -> [UUID: ChatTurnPresentationRecord] {
        let rows = try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
        var result: [UUID: ChatTurnPresentationRecord] = [:]
        for candidate in rows {
            guard let replyEventID = candidate.logicalReplyEventID else { continue }
            guard let current = result[replyEventID] else {
                result[replyEventID] = candidate
                continue
            }
            let shouldReplace: Bool
            if candidate.revision != current.revision {
                shouldReplace = candidate.revision > current.revision
            } else if candidate.updatedAt != current.updatedAt {
                shouldReplace = candidate.updatedAt > current.updatedAt
            } else {
                shouldReplace = candidate.id.uuidString.lowercased()
                    > current.id.uuidString.lowercased()
            }
            if shouldReplace { result[replyEventID] = candidate }
        }
        return result
    }

    private func isUnreadMomentInteraction(
        _ interaction: MomentInteractionRecord,
        after marker: MomentReadStateRecord?
    ) -> Bool {
        guard interaction.deletedAt == nil else { return false }
        return isUnreadMomentCursor(
            MomentReadCursor(interaction: interaction),
            after: marker
        )
    }

    private func isUnreadMomentCursor(
        _ cursor: MomentReadCursor,
        after marker: MomentReadStateRecord?
    ) -> Bool {
        guard let markerCursor = momentCursor(from: marker) else { return true }
        return cursor > markerCursor
    }

    private func latestMomentReadCursor(
        for post: MomentPostRecord,
        interactions: [MomentInteractionRecord],
        now: Date
    ) -> MomentReadCursor {
        let newestInteraction = interactions
            .compactMap { MomentReadCursor(interaction: $0) }
            .max()
        guard post.authorKind == .companion else {
            return newestInteraction ?? MomentReadCursor(
                createdAt: now,
                interactionID: MomentReadCursor.zeroInteractionID
            )
        }

        let publication = MomentReadCursor(
            createdAt: post.publishedAt,
            interactionID: MomentReadCursor.zeroInteractionID
        )
        return max(publication, newestInteraction ?? publication)
    }

    private func isVisibleMomentPost(_ post: MomentPostRecord) throws -> Bool {
        guard post.deletedAt == nil else { return false }
        guard post.authorKind == .companion else { return true }
        guard let authorRoleID = post.authorRoleID else { return false }

        let roleID = RoleScope.resolve(authorRoleID)
        guard let relationship = try canonicalCompanionRelationships()[roleID] else {
            // Legacy stores may have no relationship row for the original
            // companion; retain that compatibility while rejecting malformed
            // role-authored posts from unknown roles.
            return roleID == RoleScope.legacyRoleID
        }
        return relationship.state == .accepted
            && relationship.retiredAt == nil
            && relationship.contactMembership == .active
    }

    private func canonicalCompanionRelationships() throws
        -> [UUID: CompanionRelationshipRecord] {
        let groupedRelationships = Dictionary(
            grouping: try context.fetch(FetchDescriptor<CompanionRelationshipRecord>()),
            by: { RoleScope.resolve($0.roleID) }
        )
        return Dictionary(uniqueKeysWithValues: groupedRelationships.compactMap {
            roleID, copies -> (UUID, CompanionRelationshipRecord)? in
            guard let record = copies.max(by: {
                if $0.revision != $1.revision { return $0.revision < $1.revision }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
                return $0.deviceID < $1.deviceID
            }) else { return nil }
            return (roleID, record)
        })
    }

    private func companionReactions(for postID: UUID) throws -> [MomentInteractionRecord] {
        let relationships = try canonicalCompanionRelationships()
        return try context.fetch(FetchDescriptor<MomentInteractionRecord>()).filter {
            guard let actorRoleID = $0.actorRoleID else { return false }
            let roleID = RoleScope.resolve(actorRoleID)
            let actorIsAvailable: Bool
            if let relationship = relationships[roleID] {
                actorIsAvailable = relationship.state == .accepted
                    && relationship.retiredAt == nil
                    && relationship.contactMembership == .active
            } else {
                actorIsAvailable = roleID == RoleScope.legacyRoleID
            }
            return $0.postID == postID
                && $0.actorKind == .companion
                && actorIsAvailable
                && $0.deletedAt == nil
                && ($0.kind == .like || $0.kind == .comment)
        }
    }
}

private extension ConversationReadCursor {
    init(event: ConversationEvent) {
        self.init(
            occurredAt: event.occurredAt,
            logicalTimestamp: event.logicalTimestamp,
            eventID: event.id
        )
    }
}

private extension MomentReadCursor {
    init(interaction: MomentInteractionRecord) {
        self.init(createdAt: interaction.createdAt, interactionID: interaction.id)
    }
}
