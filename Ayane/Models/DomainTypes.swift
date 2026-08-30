import Foundation

/// The application-level scope used by every role-owned record.
///
/// Older stores did not persist a role identifier.  Resolving a missing value
/// to the original companion UUID keeps those rows readable while allowing
/// newly-created records to belong to any logical profile.
enum RoleScope: Sendable {
    /// Stable identity of the pre-multi-role companion.
    static let legacyRoleID = UUID(uuidString: "8D5DFB45-198D-4B74-B1F1-4C9C7A8248A1")!

    /// Returns the supplied role or the legacy companion for a migrated row.
    static func resolve(_ roleID: UUID?) -> UUID {
        roleID ?? legacyRoleID
    }
}

enum EventRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case system
    case manual
}

enum EventDeliveryState: String, Codable, Sendable {
    case complete
    case streaming
    case cancelled
    case failed
    /// The event was intentionally not delivered because the relationship
    /// does not currently permit a chat.  Keeping this separate from
    /// `failed` lets the UI explain a relationship decision without treating
    /// it as a transport error.
    case undelivered
}

/// The small, auditable lifecycle used by a companion relationship.
///
/// Relationship records deliberately persist `rawValue` rather than a
/// SwiftData relationship.  This enum is therefore safe to use at UI and
/// domain boundaries while old stores can continue to decode unknown values
/// conservatively.
enum CompanionRelationshipState: String, Codable, CaseIterable, Sendable {
    case pending
    case accepted
    case rejected
    case deleted
    case recoveryPending
    case blocked

    var title: String {
        switch self {
        case .pending: "待处理"
        case .accepted: "已接受"
        case .rejected: "已拒绝"
        case .deleted: "已删除"
        case .recoveryPending: "恢复申请中"
        case .blocked: "已拉黑"
        }
    }

    /// Contact lifecycle is display and user-management metadata. It never
    /// blocks ordinary chat; a physically retired role is handled separately.
    var canChat: Bool {
        true
    }
}

/// User-managed contact visibility is intentionally orthogonal to the
/// companion relationship lifecycle.  Archiving a contact must not rewrite a
/// pending/accepted/deleted relationship or its audit trail.
enum ContactMembershipState: String, Codable, CaseIterable, Sendable {
    case active
    case archivedByUser = "archived_by_user"

    var isActive: Bool {
        self == .active
    }

    var title: String {
        switch self {
        case .active: "已加入通讯录"
        case .archivedByUser: "已归档"
        }
    }
}

/// The direction from the local user's point of view.  Aliases retain the
/// terminology used by earlier prototypes without introducing extra wire
/// values.
enum FriendApplicationDirection: String, Codable, CaseIterable, Sendable {
    case incoming
    case outgoing

    static let received = Self.incoming
    static let sent = Self.outgoing
    static let fromUser = Self.outgoing
    static let toUser = Self.incoming
}

/// Why a friend application exists.  New-friend and recovery applications
/// share one durable model but remain distinguishable for UI and reducers.
enum FriendApplicationPurpose: String, Codable, CaseIterable, Sendable {
    case newFriend = "new_friend"
    case recovery
    case reset

    static let addFriend = Self.newFriend
    static let friendRequest = Self.newFriend
    static let reconnect = Self.recovery
    static let restore = Self.recovery
}

/// Durable status of a friend application.  Unknown values are rejected at
/// the import boundary instead of being treated as an actionable request.
enum FriendApplicationStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case pending
    case accepted
    case rejected
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .accepted, .rejected, .cancelled: true
        case .scheduled, .pending: false
        }
    }
}

/// The persisted lifecycle of one local text-only Moments task.
///
/// The raw value is the sync boundary.  Unknown values are mapped back to the
/// terminal `cancelled` state by the stored model so an older/newer device
/// cannot accidentally publish a task in a state this build cannot operate.
enum MomentTaskState: String, Codable, CaseIterable, Sendable {
    case scheduled
    case running
    case published
    case cancelled

    var title: String {
        switch self {
        case .scheduled: "待发布"
        case .running: "生成中"
        case .published: "已发布"
        case .cancelled: "已取消"
        }
    }

    var isTerminal: Bool {
        self == .published || self == .cancelled
    }
}

enum MomentAuthorKind: String, Codable, CaseIterable, Sendable {
    case user
    case companion
}

enum MomentInteractionKind: String, Codable, CaseIterable, Sendable {
    case like
    case comment
}

/// Model-generated Moments operations. Keeping these separate from
/// `MomentInteractionKind` makes an in-flight generation auditable even when
/// the model decides not to publish a like or a comment.
enum MomentAIInteractionTaskKind: String, Codable, CaseIterable, Sendable {
    case reactionLike
    case reactionComment
    case replyLike
    case replyComment
}

/// Durable lifecycle for one model-generated Moments operation.
///
/// Retryable failures are represented by `pending` plus a future
/// `nextAttemptAt`; `failed` is reserved for the terminal retry-limit state.
enum MomentAIInteractionTaskState: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }

    var isRetryable: Bool {
        self == .pending || self == .running
    }
}

/// Retry policy shared by AppModel and import/merge validation. The bounded
/// exponential delay avoids a tight loop when a provider is unavailable while
/// still making a recovered task catch up without user intervention.
enum MomentAIInteractionTaskPolicy {
    static let maximumAttempts = 5
    static let initialBackoff: TimeInterval = 30
    static let maximumBackoff: TimeInterval = 60 * 60

    static func retryDelay(afterAttemptCount attemptCount: Int) -> TimeInterval {
        let boundedAttempt = max(1, attemptCount)
        var delay = initialBackoff
        if boundedAttempt > 1 {
            for _ in 1..<boundedAttempt {
                delay = min(maximumBackoff, delay * 2)
                if delay >= maximumBackoff { break }
            }
        }
        return min(maximumBackoff, delay)
    }

    static func nextAttemptAt(now: Date, attemptCount: Int) -> Date {
        now.addingTimeInterval(retryDelay(afterAttemptCount: attemptCount))
    }

    static func canAttempt(_ attemptCount: Int) -> Bool {
        attemptCount < maximumAttempts
    }
}

// Compatibility spellings keep the persistence boundary discoverable to
// callers that use the shorter domain terminology.
typealias MomentInteractionTaskKind = MomentAIInteractionTaskKind
typealias MomentInteractionTaskState = MomentAIInteractionTaskState

enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case profile
    case preference
    case boundary
    case relationship
    case episode
    case timeline
    case commitment
    case reflection

    var title: String {
        switch self {
        case .profile: "资料"
        case .preference: "偏好"
        case .boundary: "边界"
        case .relationship: "关系"
        case .episode: "经历"
        case .timeline: "时间线"
        case .commitment: "承诺"
        case .reflection: "感受"
        }
    }
}

enum MemoryState: String, Codable, CaseIterable, Sendable {
    case candidate
    case active
    case superseded
    case contested
    case forgotten

    var title: String {
        switch self {
        case .candidate: "待确认"
        case .active: "有效"
        case .superseded: "已更新"
        case .contested: "有冲突"
        case .forgotten: "已忘记"
        }
    }
}

enum EvidenceRelation: String, Codable, Sendable {
    case supports
    case contradicts
    case updates
}

enum ExtractionOperation: String, Codable, Sendable {
    case upsert
    case retract
}

struct ProviderConfiguration: Equatable, Sendable {
    var baseURL: String
    var model: String
    var embeddingModel: String
    var temperature: Double
    var streamsResponses: Bool

    var isComplete: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct PersonaConfiguration: Equatable, Sendable {
    var name: String
    var userName: String
    var prompt: String
    var birthdayMonth: Int?
    var birthdayDay: Int?
    var avatarImageData: Data?
    var chatBackgroundImageData: Data?

    init(
        name: String,
        userName: String,
        prompt: String,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        avatarImageData: Data? = nil,
        chatBackgroundImageData: Data? = nil
    ) {
        self.name = name
        self.userName = userName
        self.prompt = prompt
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.avatarImageData = avatarImageData
        self.chatBackgroundImageData = chatBackgroundImageData
    }
}

/// A value-only companion snapshot for root lists and role switching.
/// SwiftData model objects stay inside `AppModel` so views never hold stale
/// cross-context references after CloudKit refreshes or duplicate folding.
struct CompanionProfileSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let userName: String
    let prompt: String
    let avatarImageData: Data?
    let birthdayMonth: Int?
    let birthdayDay: Int?
    let isPersisted: Bool
    /// Existing callers and stores pre-dating relationship lifecycle support
    /// keep their chat-ready behavior by defaulting to an accepted relation.
    let relationshipState: CompanionRelationshipState
    /// User-managed contact visibility, independent from `relationshipState`.
    let contactMembership: ContactMembershipState

    init(
        id: UUID,
        name: String,
        userName: String,
        prompt: String,
        avatarImageData: Data? = nil,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        isPersisted: Bool,
        relationshipState: CompanionRelationshipState = .accepted,
        contactMembership: ContactMembershipState = .active
    ) {
        self.id = id
        self.name = name
        self.userName = userName
        self.prompt = prompt
        self.avatarImageData = avatarImageData
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.isPersisted = isPersisted
        self.relationshipState = relationshipState
        self.contactMembership = contactMembership
    }
}

struct GroupConversationSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let conversationID: UUID
    let name: String
    let avatarImageData: Data?
    let participantRoleIDs: [UUID]
    let participantNames: [String]
    let updatedAt: Date
}

/// A value-only group member projection for contact/group pickers.
struct GroupParticipantSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let roleID: UUID?
    let kind: GroupParticipantKind
    let displayName: String
    let avatarImageData: Data?

    init(
        id: UUID,
        roleID: UUID? = nil,
        kind: GroupParticipantKind = .external,
        displayName: String = "",
        avatarImageData: Data? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.kind = kind
        self.displayName = displayName
        self.avatarImageData = avatarImageData
    }
}

// SchemaV11Models predates the value-only summary and intentionally keeps its
// enum conformances minimal. Add Hashable at this boundary so summaries can be
// used safely as SwiftUI list identities and dictionary keys.
extension GroupParticipantKind: Hashable {}

/// A value-only friend-application projection suitable for list and review
/// screens. All fields mirror the CloudKit-safe persisted record.
struct FriendApplicationSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let roleID: UUID
    let direction: FriendApplicationDirection
    let purpose: FriendApplicationPurpose
    let status: FriendApplicationStatus
    let message: String
    let scheduledAt: Date
    let createdAt: Date
    let resolvedAt: Date?
    let idempotencyKey: String
    let revision: Int
    let deviceID: String

    init(
        id: UUID,
        roleID: UUID,
        direction: FriendApplicationDirection,
        purpose: FriendApplicationPurpose,
        status: FriendApplicationStatus,
        message: String = "",
        scheduledAt: Date = Date(),
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        idempotencyKey: String = "",
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = roleID
        self.direction = direction
        self.purpose = purpose
        self.status = status
        self.message = message
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.idempotencyKey = idempotencyKey
        self.revision = revision
        self.deviceID = deviceID
    }
}

struct UsedMemorySummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let text: String
    let score: Float
    let confidence: Float
    let isPinned: Bool
}

/// A value-only task summary for lists and role switching.
///
/// `roleID` is always resolved before this value leaves the persistence
/// boundary, so UI code cannot accidentally mix a nil legacy row with a
/// different role.  It deliberately contains no SwiftData model reference.
struct CompanionMomentTaskSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let roleID: UUID
    let instruction: String
    let scheduledAt: Date
    let state: MomentTaskState
    let resultText: String
    let publishedAt: Date?
    let lastError: String
    let attemptCount: Int
    let seriesID: UUID?
    let occurrenceKey: String
    let recurrenceRaw: String
    let recurrenceInterval: Int
    let recurrenceWeekday: Int?
    let recurrenceDayOfMonth: Int?
    let recurrenceHour: Int
    let recurrenceMinute: Int
    let timezoneIdentifier: String
    let nextAttemptAt: Date?

    var resolvedRoleID: UUID { roleID }

    var recurrenceRule: MomentTaskRecurrenceRule {
        MomentTaskRecurrenceRule(
            recurrenceRaw: recurrenceRaw,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            timezoneIdentifier: timezoneIdentifier,
            scheduledAt: scheduledAt,
            seriesID: seriesID
        )
    }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        instruction: String = "",
        scheduledAt: Date = Date(),
        state: MomentTaskState = .scheduled,
        resultText: String = "",
        publishedAt: Date? = nil,
        lastError: String = "",
        attemptCount: Int = 0,
        seriesID: UUID? = nil,
        occurrenceKey: String = "",
        recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        nextAttemptAt: Date? = nil
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.instruction = instruction
        self.scheduledAt = scheduledAt
        self.state = state
        self.resultText = resultText
        self.publishedAt = publishedAt
        self.lastError = lastError
        self.attemptCount = max(0, attemptCount)
        self.seriesID = seriesID
        self.occurrenceKey = occurrenceKey
        self.recurrenceRaw = recurrenceRaw
        self.recurrenceInterval = max(1, recurrenceInterval)
        self.recurrenceWeekday = recurrenceWeekday
        self.recurrenceDayOfMonth = recurrenceDayOfMonth
        self.recurrenceHour = recurrenceHour
        self.recurrenceMinute = recurrenceMinute
        self.timezoneIdentifier = timezoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : timezoneIdentifier
        self.nextAttemptAt = nextAttemptAt
    }

    /// Spells the role scope explicitly for call sites that already have a
    /// resolved identity.
    init(
        id: UUID = UUID(),
        resolvedRoleID: UUID,
        instruction: String = "",
        scheduledAt: Date = Date(),
        state: MomentTaskState = .scheduled,
        resultText: String = "",
        publishedAt: Date? = nil,
        lastError: String = "",
        attemptCount: Int = 0,
        seriesID: UUID? = nil,
        occurrenceKey: String = "",
        recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        nextAttemptAt: Date? = nil
    ) {
        self.init(
            id: id,
            roleID: resolvedRoleID,
            instruction: instruction,
            scheduledAt: scheduledAt,
            state: state,
            resultText: resultText,
            publishedAt: publishedAt,
            lastError: lastError,
            attemptCount: attemptCount,
            seriesID: seriesID,
            occurrenceKey: occurrenceKey,
            recurrenceRaw: recurrenceRaw,
            recurrenceInterval: recurrenceInterval,
            recurrenceWeekday: recurrenceWeekday,
            recurrenceDayOfMonth: recurrenceDayOfMonth,
            recurrenceHour: recurrenceHour,
            recurrenceMinute: recurrenceMinute,
            timezoneIdentifier: timezoneIdentifier,
            nextAttemptAt: nextAttemptAt
        )
    }
}

struct UserProfileSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let birthdayMonth: Int?
    let birthdayDay: Int?
    let birthdayTimeZoneIdentifier: String
    let avatarImageData: Data?
    let momentsCoverImageData: Data?

    init(
        id: UUID,
        displayName: String,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthdayTimeZoneIdentifier: String = TimeZone.current.identifier,
        avatarImageData: Data? = nil,
        momentsCoverImageData: Data? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.birthdayTimeZoneIdentifier = birthdayTimeZoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : birthdayTimeZoneIdentifier
        self.avatarImageData = avatarImageData
        self.momentsCoverImageData = momentsCoverImageData
    }

    static let fallback = UserProfileSummary(
        id: UserProfileRecord.singletonID,
        displayName: BuiltInCompanionCatalog.userDisplayName,
        birthdayMonth: nil,
        birthdayDay: nil,
        birthdayTimeZoneIdentifier: TimeZone.current.identifier,
        avatarImageData: nil,
        momentsCoverImageData: nil
    )
}

struct MomentInteractionSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let postID: UUID
    let parentInteractionID: UUID?
    let rootInteractionID: UUID?
    let kind: MomentInteractionKind
    let actorKind: MomentAuthorKind
    let actorRoleID: UUID?
    let actorName: String
    let body: String
    let createdAt: Date
    /// Mirrors the persisted interaction tombstone so feed consumers can
    /// filter at the domain boundary instead of hiding a deleted row only in
    /// a view.
    let deletedAt: Date?

    init(
        id: UUID,
        postID: UUID,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        kind: MomentInteractionKind,
        actorKind: MomentAuthorKind,
        actorRoleID: UUID?,
        actorName: String,
        body: String,
        createdAt: Date,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.postID = postID
        self.parentInteractionID = parentInteractionID
        self.rootInteractionID = rootInteractionID
        self.kind = kind
        self.actorKind = actorKind
        self.actorRoleID = actorRoleID
        self.actorName = actorName
        self.body = body
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }
}

struct MomentPostSummary: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let authorKind: MomentAuthorKind
    let authorRoleID: UUID?
    let authorName: String
    let authorAvatarImageData: Data?
    let body: String
    let imageData: Data?
    let bundledImageName: String
    let publishedAt: Date
    let interactions: [MomentInteractionSummary]

    var isUserAuthored: Bool { authorKind == .user }

    var likes: [MomentInteractionSummary] {
        interactions.filter { $0.deletedAt == nil && $0.kind == .like }
    }

    var comments: [MomentInteractionSummary] {
        interactions.filter { $0.deletedAt == nil && $0.kind == .comment }
    }

    var userDidLike: Bool {
        likes.contains { $0.actorKind == .user }
    }
}

struct APIChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

struct ExtractedMemoryCandidate: Codable, Equatable, Sendable {
    var operation: ExtractionOperation
    var kind: MemoryKind
    var subject: String
    var predicate: String
    var value: String
    var canonicalKey: String
    var confidence: Double
    var importance: Double
    var explicit: Bool
    var sensitive: Bool
    var sourceEventID: UUID
    var sourceQuote: String
    var startUTF16: Int?
    var endUTF16: Int?
    var validFrom: Date?
    var validTo: Date?

    enum CodingKeys: String, CodingKey {
        case operation
        case kind
        case subject
        case predicate
        case value
        case canonicalKey = "canonical_key"
        case confidence
        case importance
        case explicit
        case sensitive
        case sourceEventID = "source_event_id"
        case sourceQuote = "source_quote"
        case startUTF16 = "start_utf16"
        case endUTF16 = "end_utf16"
        case validFrom = "valid_from"
        case validTo = "valid_to"
    }
}

struct MemoryExtractionEnvelope: Codable, Sendable {
    var memories: [ExtractedMemoryCandidate]
}

struct ConnectionTestResult: Equatable, Sendable {
    let latency: TimeInterval
    let reply: String
}

enum AppSection: String, CaseIterable, Identifiable {
    case chats
    case contacts
    case discover
    case me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: "微信"
        case .contacts: "通讯录"
        case .discover: "发现"
        case .me: "我"
        }
    }

    var systemImage: String {
        switch self {
        case .chats: "message.fill"
        case .contacts: "person.2.fill"
        case .discover: "safari.fill"
        case .me: "person.fill"
        }
    }
}
