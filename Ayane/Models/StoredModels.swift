import Foundation
import SwiftData

/// The persisted, cross-device source of truth for the companion's persona.
///
/// This model intentionally contains only scalar fields with defaults.  In
/// particular, it has no relationship or uniqueness constraint: CloudKit can
/// temporarily materialize more than one physical object for the same
/// application-level UUID, and `CompanionProfileService` resolves that case
/// deterministically before exposing a profile to the rest of the app.
@Model
final class CompanionProfileRecord {
    /// Compatibility alias for the pre-multi-role singleton identity.
    static let singletonID = RoleScope.legacyRoleID
    static let legacyRoleID = RoleScope.legacyRoleID

    var id: UUID = CompanionProfileRecord.singletonID
    /// The world this role belongs to. Legacy rows default to the stable
    /// reality world while allowing new roles to be reused across worlds.
    var worldProfileID: UUID = WorldProfileRecord.realityID
    var name: String = "绫音"
    var userName: String = "你"
    var prompt: String = ""
    /// Optional birthday components are kept separate so legacy profiles can
    /// migrate without inventing a year or locale-specific date.
    var birthdayMonth: Int? = nil
    var birthdayDay: Int? = nil
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    @Attribute(.externalStorage) var chatBackgroundImageData: Data? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    /// A profile's persisted model ID is its logical role ID.
    var roleID: UUID { id }

    init(
        id: UUID = CompanionProfileRecord.singletonID,
        worldProfileID: UUID = WorldProfileRecord.realityID,
        name: String = "绫音",
        userName: String = "你",
        prompt: String = "",
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        avatarImageData: Data? = nil,
        chatBackgroundImageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.worldProfileID = worldProfileID
        self.name = name
        self.userName = userName
        self.prompt = prompt
        self.birthdayMonth = birthdayMonth
        self.birthdayDay = birthdayDay
        self.avatarImageData = avatarImageData
        self.chatBackgroundImageData = chatBackgroundImageData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }
}

/// A local text-only scheduled Moments task.
///
/// Every persisted value is scalar and has a default.  There are deliberately
/// no SwiftData relationships or uniqueness constraints: CloudKit may briefly
/// materialize duplicate physical rows while devices converge, and the task
/// lifecycle itself provides the idempotent publish boundary.
@Model
final class CompanionMomentTaskRecord {
    var id: UUID = UUID()
    var roleID: UUID = RoleScope.legacyRoleID
    var instruction: String = ""
    var scheduledAt: Date = Date()
    /// A recurring task is represented as a flat scalar row so it remains
    /// CloudKit-compatible. Legacy rows default to one-shot scheduling.
    var seriesID: UUID? = nil
    var occurrenceKey: String = ""
    var recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue
    var recurrenceInterval: Int = 1
    var recurrenceWeekday: Int? = nil
    var recurrenceDayOfMonth: Int? = nil
    var recurrenceHour: Int = 0
    var recurrenceMinute: Int = 0
    var timezoneIdentifier: String = TimeZone.current.identifier
    var nextAttemptAt: Date? = nil
    var stateRaw: String = MomentTaskState.scheduled.rawValue
    var resultText: String = ""
    var publishedAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var attemptCount: Int = 0
    var lastError: String = ""
    var leaseOwner: String = ""
    var leaseExpiresAt: Date? = nil
    var deviceID: String = ""
    var revision: Int = 0

    init(
        id: UUID = UUID(),
        roleID: UUID? = RoleScope.legacyRoleID,
        instruction: String = "",
        scheduledAt: Date = Date(),
        seriesID: UUID? = nil,
        occurrenceKey: String = "",
        recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        nextAttemptAt: Date? = nil,
        state: MomentTaskState = .scheduled,
        resultText: String = "",
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String = "",
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        deviceID: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.instruction = instruction
        self.scheduledAt = scheduledAt
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
        self.stateRaw = state.rawValue
        self.resultText = resultText
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = max(0, attemptCount)
        self.lastError = lastError
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.deviceID = deviceID
        self.revision = max(0, revision)
    }

    /// Compatibility initializer for import/merge code that already stores a
    /// raw lifecycle value.
    init(
        id: UUID = UUID(),
        roleID: UUID? = RoleScope.legacyRoleID,
        instruction: String = "",
        scheduledAt: Date = Date(),
        seriesID: UUID? = nil,
        occurrenceKey: String = "",
        recurrenceRaw: String = MomentTaskRecurrenceFrequency.once.rawValue,
        recurrenceInterval: Int = 1,
        recurrenceWeekday: Int? = nil,
        recurrenceDayOfMonth: Int? = nil,
        recurrenceHour: Int = 0,
        recurrenceMinute: Int = 0,
        timezoneIdentifier: String = TimeZone.current.identifier,
        nextAttemptAt: Date? = nil,
        stateRaw: String,
        resultText: String = "",
        publishedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attemptCount: Int = 0,
        lastError: String = "",
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        deviceID: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.instruction = instruction
        self.scheduledAt = scheduledAt
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
        self.stateRaw = stateRaw
        self.resultText = resultText
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = max(0, attemptCount)
        self.lastError = lastError
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.deviceID = deviceID
        self.revision = max(0, revision)
    }

    /// Unknown values fail closed to the terminal state.  A newer device may
    /// have written a terminal lifecycle that this build does not know yet;
    /// retrying it would risk publishing the same task twice.
    var state: MomentTaskState {
        get { MomentTaskState(rawValue: stateRaw) ?? .cancelled }
        set { stateRaw = newValue.rawValue }
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

/// The local user's account-level identity. It is intentionally separate from
/// `CompanionProfileRecord`: a companion's `userName` only describes how that
/// role addresses the user and is not the user's social profile.
@Model
final class UserProfileRecord {
    static let singletonID = UUID(uuidString: "A63B5A53-6A4C-4E89-8E5E-D1B4920F2C15")!

    var id: UUID = UserProfileRecord.singletonID
    var displayName: String = BuiltInCompanionCatalog.userDisplayName
    var birthdayMonth: Int? = nil
    var birthdayDay: Int? = nil
    var birthdayTimeZoneIdentifier: String = TimeZone.current.identifier
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    @Attribute(.externalStorage) var momentsCoverImageData: Data? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UserProfileRecord.singletonID,
        displayName: String = BuiltInCompanionCatalog.userDisplayName,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthdayTimeZoneIdentifier: String = TimeZone.current.identifier,
        avatarImageData: Data? = nil,
        momentsCoverImageData: Data? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }
}

/// One durable post in the friend-scoped Moments feed.
@Model
final class MomentPostRecord {
    var id: UUID = UUID()
    var authorKindRaw: String = MomentAuthorKind.user.rawValue
    var authorRoleID: UUID? = nil
    var body: String = ""
    @Attribute(.externalStorage) var imageData: Data? = nil
    /// Bundled CGs use an asset name so backups remain small and old posts can
    /// continue referring to the shipped immutable artwork.
    var bundledImageName: String = ""
    var sourceTaskID: UUID? = nil
    var publishedAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date? = nil
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        authorKind: MomentAuthorKind = .user,
        authorRoleID: UUID? = nil,
        body: String = "",
        imageData: Data? = nil,
        bundledImageName: String = "",
        sourceTaskID: UUID? = nil,
        publishedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.authorKindRaw = authorKind.rawValue
        self.authorRoleID = authorRoleID.map(RoleScope.resolve)
        self.body = body
        self.imageData = imageData
        self.bundledImageName = bundledImageName
        self.sourceTaskID = sourceTaskID
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var authorKind: MomentAuthorKind {
        MomentAuthorKind(rawValue: authorKindRaw) ?? .user
    }
}

/// Likes and comments share one append-only value model. A like is removed
/// when toggled off; comments retain a tombstone when the author removes one.
/// The optional deletion timestamp is intentionally part of the row instead
/// of a physical delete so imports, CloudKit and duplicate reconciliation can
/// carry the removal decision across devices.
@Model
final class MomentInteractionRecord {
    var id: UUID = UUID()
    var postID: UUID = UUID()
    /// Optional reply-tree links. Legacy interactions intentionally keep both
    /// values nil; `rootInteractionID` lets a client jump to the first
    /// interaction without introducing a SwiftData relationship.
    var parentInteractionID: UUID? = nil
    var rootInteractionID: UUID? = nil
    var kindRaw: String = MomentInteractionKind.comment.rawValue
    var actorKindRaw: String = MomentAuthorKind.user.rawValue
    var actorRoleID: UUID? = nil
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Nil means the interaction is live. Adding this optional column is a
    /// SwiftData lightweight migration for stores written before comment
    /// deletion existed.
    var deletedAt: Date? = nil
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        postID: UUID,
        kind: MomentInteractionKind,
        actorKind: MomentAuthorKind,
        actorRoleID: UUID? = nil,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.postID = postID
        self.parentInteractionID = parentInteractionID
        self.rootInteractionID = rootInteractionID
        self.kindRaw = kind.rawValue
        self.actorKindRaw = actorKind.rawValue
        self.actorRoleID = actorRoleID.map(RoleScope.resolve)
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var kind: MomentInteractionKind {
        MomentInteractionKind(rawValue: kindRaw) ?? .comment
    }

    var actorKind: MomentAuthorKind {
        MomentAuthorKind(rawValue: actorKindRaw) ?? .user
    }

    var isDeleted: Bool { deletedAt != nil }

    /// Applies the local soft-delete mutation while preserving the row's
    /// identity. Repeating the operation is idempotent for an already deleted
    /// row and therefore does not create a newer competing version.
    func softDelete(at timestamp: Date = Date(), deviceID sourceDeviceID: String) {
        guard deletedAt == nil else { return }
        deletedAt = timestamp
        updatedAt = timestamp
        revision = max(0, revision) + 1
        deviceID = sourceDeviceID
    }
}

/// A durable model-generation operation for a user-authored Moments post.
///
/// This intentionally has no SwiftData relationships. CloudKit can materialize
/// duplicate physical rows while devices converge, and all foreign keys are
/// validated by the import/merge boundary. `idempotencyKey` is the logical
/// operation identity; `resultInteractionID` and the deterministic IDs derived
/// from it make a crash between interaction insertion and task completion safe.
@Model
final class MomentAIInteractionTaskRecord {
    var id: UUID = UUID()
    var kindRaw: String = MomentAIInteractionTaskKind.reactionComment.rawValue
    var postID: UUID = UUID()
    var targetInteractionID: UUID? = nil
    var parentInteractionID: UUID? = nil
    var rootInteractionID: UUID? = nil
    var roleID: UUID = RoleScope.legacyRoleID
    var stateRaw: String = MomentAIInteractionTaskState.pending.rawValue
    var attemptCount: Int = 0
    var nextAttemptAt: Date = Date()
    var lastError: String = ""
    var idempotencyKey: String = ""
    var timezoneIdentifier: String = TimeZone.current.identifier
    /// Input is retained so a reply can be resumed even if the visible feed is
    /// refreshed while the provider request is in flight.
    var inputText: String = ""
    var generatedText: String = ""
    var generatedLike: Bool? = nil
    var resultInteractionID: UUID? = nil
    var leaseOwner: String = ""
    var leaseExpiresAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        kind: MomentAIInteractionTaskKind = .reactionComment,
        postID: UUID,
        targetInteractionID: UUID? = nil,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        roleID: UUID? = RoleScope.legacyRoleID,
        state: MomentAIInteractionTaskState = .pending,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastError: String = "",
        idempotencyKey: String = "",
        timezoneIdentifier: String = TimeZone.current.identifier,
        inputText: String = "",
        generatedText: String = "",
        generatedLike: Bool? = nil,
        resultInteractionID: UUID? = nil,
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.postID = postID
        self.targetInteractionID = targetInteractionID
        self.parentInteractionID = parentInteractionID
        self.rootInteractionID = rootInteractionID
        self.roleID = RoleScope.resolve(roleID)
        self.stateRaw = state.rawValue
        self.attemptCount = max(0, attemptCount)
        self.nextAttemptAt = nextAttemptAt ?? createdAt
        self.lastError = lastError
        self.idempotencyKey = idempotencyKey.isEmpty
            ? Self.defaultIdempotencyKey(
                kind: kind,
                postID: postID,
                targetInteractionID: targetInteractionID,
                parentInteractionID: parentInteractionID,
                roleID: self.roleID
            )
            : idempotencyKey
        self.timezoneIdentifier = timezoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : timezoneIdentifier
        self.inputText = inputText
        self.generatedText = generatedText
        self.generatedLike = generatedLike
        self.resultInteractionID = resultInteractionID
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    /// Compatibility initializer for import/merge callers that work with raw
    /// persisted values instead of enum conveniences.
    init(
        id: UUID = UUID(),
        kindRaw: String,
        postID: UUID,
        targetInteractionID: UUID? = nil,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        roleID: UUID? = RoleScope.legacyRoleID,
        stateRaw: String,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastError: String = "",
        idempotencyKey: String = "",
        timezoneIdentifier: String = TimeZone.current.identifier,
        inputText: String = "",
        generatedText: String = "",
        generatedLike: Bool? = nil,
        resultInteractionID: UUID? = nil,
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.postID = postID
        self.targetInteractionID = targetInteractionID
        self.parentInteractionID = parentInteractionID
        self.rootInteractionID = rootInteractionID
        self.roleID = RoleScope.resolve(roleID)
        self.stateRaw = stateRaw
        self.attemptCount = max(0, attemptCount)
        self.nextAttemptAt = nextAttemptAt ?? createdAt
        self.lastError = lastError
        self.idempotencyKey = idempotencyKey.isEmpty
            ? Self.defaultIdempotencyKey(
                kindRaw: kindRaw,
                postID: postID,
                targetInteractionID: targetInteractionID,
                parentInteractionID: parentInteractionID,
                roleID: self.roleID
            )
            : idempotencyKey
        self.timezoneIdentifier = timezoneIdentifier.isEmpty
            ? TimeZone.current.identifier
            : timezoneIdentifier
        self.inputText = inputText
        self.generatedText = generatedText
        self.generatedLike = generatedLike
        self.resultInteractionID = resultInteractionID
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var kind: MomentAIInteractionTaskKind {
        get { MomentAIInteractionTaskKind(rawValue: kindRaw) ?? .reactionComment }
        set { kindRaw = newValue.rawValue }
    }

    var taskKind: MomentAIInteractionTaskKind {
        get { kind }
        set { kind = newValue }
    }

    var state: MomentAIInteractionTaskState {
        get { MomentAIInteractionTaskState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    var status: MomentAIInteractionTaskState {
        get { state }
        set { state = newValue }
    }

    var momentID: UUID {
        get { postID }
        set { postID = newValue }
    }

    var targetCommentID: UUID? {
        get { targetInteractionID }
        set { targetInteractionID = newValue }
    }

    var parentCommentID: UUID? {
        get { parentInteractionID }
        set { parentInteractionID = newValue }
    }

    var nextRetryAt: Date {
        get { nextAttemptAt }
        set { nextAttemptAt = newValue }
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }

    var isTerminal: Bool { state.isTerminal }

    private static func defaultIdempotencyKey(
        kind: MomentAIInteractionTaskKind,
        postID: UUID,
        targetInteractionID: UUID?,
        parentInteractionID: UUID?,
        roleID: UUID
    ) -> String {
        defaultIdempotencyKey(
            kindRaw: kind.rawValue,
            postID: postID,
            targetInteractionID: targetInteractionID,
            parentInteractionID: parentInteractionID,
            roleID: roleID
        )
    }

    private static func defaultIdempotencyKey(
        kindRaw: String,
        postID: UUID,
        targetInteractionID: UUID?,
        parentInteractionID: UUID?,
        roleID: UUID
    ) -> String {
        [
            "moment-ai",
            kindRaw,
            postID.uuidString.lowercased(),
            targetInteractionID?.uuidString.lowercased() ?? "-",
            parentInteractionID?.uuidString.lowercased() ?? "-",
            roleID.uuidString.lowercased()
        ].joined(separator: ":")
    }
}

// Full terminology aliases make migration and tests resilient to the naming
// used by earlier prototypes without creating another SwiftData entity.
typealias CompanionMomentInteractionTaskRecord = MomentAIInteractionTaskRecord
typealias MomentInteractionTaskRecord = MomentAIInteractionTaskRecord

/// The durable read cursor for one role-owned conversation.
///
/// Read state is intentionally kept out of `ConversationEvent`: events are an
/// append-only source of truth whose body and content hash are also used by
/// memory extraction and import validation. A cursor is enough to derive the
/// unread count while preserving every historical event.
@Model
final class ConversationReadStateRecord {
    /// The logical identity is `(roleID, conversationID)`. In normal stores the
    /// conversation UUID is globally unique, so using it as the marker ID also
    /// makes independent devices converge on one CloudKit row. Duplicate
    /// physical rows are still reduced by `StoreDuplicateReconciler`.
    var id: UUID = UUID()
    var roleID: UUID = RoleScope.legacyRoleID
    var conversationID: UUID = UUID()
    var lastReadOccurredAt: Date? = nil
    var lastReadLogicalTimestamp: String = ""
    var lastReadEventID: UUID? = nil
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID? = nil,
        roleID: UUID? = RoleScope.legacyRoleID,
        conversationID: UUID,
        lastReadOccurredAt: Date? = nil,
        lastReadLogicalTimestamp: String = "",
        lastReadEventID: UUID? = nil,
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id ?? conversationID
        self.roleID = RoleScope.resolve(roleID)
        self.conversationID = conversationID
        self.lastReadOccurredAt = lastReadOccurredAt
        self.lastReadLogicalTimestamp = lastReadLogicalTimestamp
        self.lastReadEventID = lastReadEventID
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

/// The durable read cursor for one Moments post.
///
/// Only companion reactions on a user-authored post are currently unread
/// candidates. The post ID is the logical scope, so reactions on another post
/// cannot affect this marker.
@Model
final class MomentReadStateRecord {
    /// Using the post UUID as the logical marker ID lets devices converge on
    /// one row without requiring a SwiftData uniqueness constraint.
    var id: UUID = UUID()
    var postID: UUID = UUID()
    var lastReadCreatedAt: Date? = nil
    var lastReadInteractionID: UUID? = nil
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID? = nil,
        postID: UUID,
        lastReadCreatedAt: Date? = nil,
        lastReadInteractionID: UUID? = nil,
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id ?? postID
        self.postID = postID
        self.lastReadCreatedAt = lastReadCreatedAt
        self.lastReadInteractionID = lastReadInteractionID
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }
}

/// The persisted lifecycle state for one logical role.
///
/// This model intentionally has no `@Attribute(.unique)` declaration and no
/// SwiftData relationship.  CloudKit can materialize duplicate physical rows
/// while records from two devices converge; `AppModel` owns the deterministic
/// one-row-per-role reconciliation.  Every persisted field is a scalar with a
/// default so the model remains CloudKit-compatible and old stores can be
/// opened before a migration has filled newer values.
@Model
final class CompanionRelationshipRecord {
    static let currentPolicyVersion = 1

    var id: UUID = UUID()
    var roleID: UUID = RoleScope.legacyRoleID
    var stateRaw: String = CompanionRelationshipState.accepted.rawValue
    var harmStreak: Int = 0
    var hurtScore: Double = 0
    var harmThreshold: Int = 3
    var forgivenessScore: Double = 0
    var forgivenessThreshold: Double = 2
    var affinityScore: Double = 0
    var affinityTier: Int = 0
    var affinityPolicyVersion: Int = 1
    var lastAffinityEventID: UUID?
    /// When present, this user-selected score is authoritative for prompt and
    /// behavior policy. The automatic score remains intact underneath so the
    /// user can return to automatic progression without losing history.
    var manualAffinityScore: Double?
    var dignity: Double = 0.5
    var independence: Double = 0.5
    var boundarySensitivity: Double = 0.5
    var apologyAttempts: Int = 0
    var policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion
    var lastProcessedEventID: UUID?
    var lastTransitionID: UUID?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""
    var retiredAt: Date?
    var resetAt: Date?
    /// User-managed contact visibility is independent from relationship state.
    var contactMembershipRaw: String = ContactMembershipState.active.rawValue
    var contactStateUpdatedAt: Date = Date()
    /// Identifies the user action which most recently removed the role from
    /// contacts. It is optional so pre-v12 rows migrate without fabricated IDs.
    var lastUserRemovalID: UUID?

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        state: CompanionRelationshipState = .accepted,
        harmStreak: Int = 0,
        hurtScore: Double = 0,
        harmThreshold: Int = 3,
        forgivenessScore: Double = 0,
        forgivenessThreshold: Double = 2,
        affinityScore: Double = 0,
        affinityTier: Int = 0,
        affinityPolicyVersion: Int = 1,
        lastAffinityEventID: UUID? = nil,
        manualAffinityScore: Double? = nil,
        dignity: Double = 0.5,
        independence: Double = 0.5,
        boundarySensitivity: Double = 0.5,
        apologyAttempts: Int = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        lastProcessedEventID: UUID? = nil,
        lastTransitionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = "",
        retiredAt: Date? = nil,
        resetAt: Date? = nil,
        contactMembership: ContactMembershipState = .active,
        contactStateUpdatedAt: Date? = nil,
        lastUserRemovalID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.stateRaw = state.rawValue
        self.harmStreak = harmStreak
        self.hurtScore = hurtScore
        self.harmThreshold = harmThreshold
        self.forgivenessScore = forgivenessScore
        self.forgivenessThreshold = forgivenessThreshold
        self.affinityScore = min(100, max(0, affinityScore.isFinite ? affinityScore : 0))
        self.affinityTier = min(3, max(0, affinityTier))
        self.affinityPolicyVersion = max(1, affinityPolicyVersion)
        self.lastAffinityEventID = lastAffinityEventID
        self.manualAffinityScore = manualAffinityScore.flatMap {
            $0.isFinite ? min(100, max(0, $0)) : nil
        }
        self.dignity = dignity
        self.independence = independence
        self.boundarySensitivity = boundarySensitivity
        self.apologyAttempts = apologyAttempts
        self.policyVersion = policyVersion
        self.lastProcessedEventID = lastProcessedEventID
        self.lastTransitionID = lastTransitionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
        self.retiredAt = retiredAt
        self.resetAt = resetAt
        self.contactMembershipRaw = contactMembership.rawValue
        self.contactStateUpdatedAt = contactStateUpdatedAt ?? updatedAt
        self.lastUserRemovalID = lastUserRemovalID
    }

    /// Compatibility initializer for callers that already hold the persisted
    /// raw state rather than a decoded enum.
    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        stateRaw: String,
        harmStreak: Int = 0,
        hurtScore: Double = 0,
        harmThreshold: Int = 3,
        forgivenessScore: Double = 0,
        forgivenessThreshold: Double = 2,
        affinityScore: Double = 0,
        affinityTier: Int = 0,
        affinityPolicyVersion: Int = 1,
        lastAffinityEventID: UUID? = nil,
        manualAffinityScore: Double? = nil,
        dignity: Double = 0.5,
        independence: Double = 0.5,
        boundarySensitivity: Double = 0.5,
        apologyAttempts: Int = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        lastProcessedEventID: UUID? = nil,
        lastTransitionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = "",
        retiredAt: Date? = nil,
        resetAt: Date? = nil,
        contactMembershipRaw: String = ContactMembershipState.active.rawValue,
        contactStateUpdatedAt: Date? = nil,
        lastUserRemovalID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.stateRaw = stateRaw
        self.harmStreak = harmStreak
        self.hurtScore = hurtScore
        self.harmThreshold = harmThreshold
        self.forgivenessScore = forgivenessScore
        self.forgivenessThreshold = forgivenessThreshold
        self.affinityScore = min(100, max(0, affinityScore.isFinite ? affinityScore : 0))
        self.affinityTier = min(3, max(0, affinityTier))
        self.affinityPolicyVersion = max(1, affinityPolicyVersion)
        self.lastAffinityEventID = lastAffinityEventID
        self.manualAffinityScore = manualAffinityScore.flatMap {
            $0.isFinite ? min(100, max(0, $0)) : nil
        }
        self.dignity = dignity
        self.independence = independence
        self.boundarySensitivity = boundarySensitivity
        self.apologyAttempts = apologyAttempts
        self.policyVersion = policyVersion
        self.lastProcessedEventID = lastProcessedEventID
        self.lastTransitionID = lastTransitionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
        self.retiredAt = retiredAt
        self.resetAt = resetAt
        self.contactMembershipRaw = contactMembershipRaw
        self.contactStateUpdatedAt = contactStateUpdatedAt ?? updatedAt
        self.lastUserRemovalID = lastUserRemovalID
    }

    var state: CompanionRelationshipState {
        get { CompanionRelationshipState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var contactMembership: ContactMembershipState {
        get { ContactMembershipState(rawValue: contactMembershipRaw) ?? .active }
        set { contactMembershipRaw = newValue.rawValue }
    }
}

/// A CloudKit-compatible, scalar-only friend application. Applications are
/// separate from the relationship state so scheduling, review and audit can
/// converge without rewriting the relationship reducer's history.
@Model
final class FriendApplicationRecord {
    var id: UUID = UUID()
    var roleID: UUID = RoleScope.legacyRoleID
    var directionRaw: String = FriendApplicationDirection.outgoing.rawValue
    var purposeRaw: String = FriendApplicationPurpose.newFriend.rawValue
    var statusRaw: String = FriendApplicationStatus.pending.rawValue
    var message: String = ""
    var scheduledAt: Date = Date()
    var createdAt: Date = Date()
    var resolvedAt: Date?
    var idempotencyKey: String = ""
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        direction: FriendApplicationDirection = .outgoing,
        purpose: FriendApplicationPurpose = .newFriend,
        status: FriendApplicationStatus = .pending,
        message: String = "",
        scheduledAt: Date = Date(),
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        idempotencyKey: String = "",
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.directionRaw = direction.rawValue
        self.purposeRaw = purpose.rawValue
        self.statusRaw = status.rawValue
        self.message = message
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.idempotencyKey = idempotencyKey
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    /// Raw-value initializer used by import/merge and CloudKit snapshots.
    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        directionRaw: String = FriendApplicationDirection.outgoing.rawValue,
        purposeRaw: String = FriendApplicationPurpose.newFriend.rawValue,
        statusRaw: String = FriendApplicationStatus.pending.rawValue,
        message: String = "",
        scheduledAt: Date = Date(),
        createdAt: Date = Date(),
        resolvedAt: Date? = nil,
        idempotencyKey: String = "",
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = RoleScope.resolve(roleID)
        self.directionRaw = directionRaw
        self.purposeRaw = purposeRaw
        self.statusRaw = statusRaw
        self.message = message
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.idempotencyKey = idempotencyKey
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var direction: FriendApplicationDirection {
        get { FriendApplicationDirection(rawValue: directionRaw) ?? .outgoing }
        set { directionRaw = newValue.rawValue }
    }

    var purpose: FriendApplicationPurpose {
        get { FriendApplicationPurpose(rawValue: purposeRaw) ?? .newFriend }
        set { purposeRaw = newValue.rawValue }
    }

    var status: FriendApplicationStatus {
        get { FriendApplicationStatus(rawValue: statusRaw) ?? .cancelled }
        set { statusRaw = newValue.rawValue }
    }
}

/// An append-only audit row for a relationship state transition.
///
/// SwiftData model properties must be mutable storage, so immutability is
/// expressed with `private(set)`: callers can read and export an audit row but
/// cannot rewrite its identity, edge, score, or provenance after insertion.
/// There are deliberately no relationships or uniqueness constraints here.
@Model
final class CompanionRelationshipTransitionRecord {
    private(set) var id: UUID = UUID()
    private(set) var roleID: UUID = RoleScope.legacyRoleID
    private(set) var from: String = CompanionRelationshipState.pending.rawValue
    private(set) var to: String = CompanionRelationshipState.pending.rawValue
    private(set) var reason: String = ""
    private(set) var sourceEventID: UUID?
    private(set) var scoreAfter: Double = 0
    private(set) var policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion
    private(set) var occurredAt: Date = Date()
    private(set) var deviceID: String = ""
    private(set) var revision: Int = 0

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        from: CompanionRelationshipState,
        to: CompanionRelationshipState,
        reason: String,
        sourceEventID: UUID? = nil,
        scoreAfter: Double = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        occurredAt: Date = Date(),
        deviceID: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.roleID = roleID
        self.from = from.rawValue
        self.to = to.rawValue
        self.reason = reason
        self.sourceEventID = sourceEventID
        self.scoreAfter = scoreAfter
        self.policyVersion = policyVersion
        self.occurredAt = occurredAt
        self.deviceID = deviceID
        self.revision = revision
    }

    /// Compatibility initializer for import/merge paths that already hold raw
    /// state values.
    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        from: String,
        to: String,
        reason: String,
        sourceEventID: UUID? = nil,
        scoreAfter: Double = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        occurredAt: Date = Date(),
        deviceID: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.roleID = roleID
        self.from = from
        self.to = to
        self.reason = reason
        self.sourceEventID = sourceEventID
        self.scoreAfter = scoreAfter
        self.policyVersion = policyVersion
        self.occurredAt = occurredAt
        self.deviceID = deviceID
        self.revision = revision
    }

    var fromState: CompanionRelationshipState {
        CompanionRelationshipState(rawValue: from) ?? .pending
    }

    var toState: CompanionRelationshipState {
        CompanionRelationshipState(rawValue: to) ?? .pending
    }
}

@Model
final class ConversationRecord {
    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var title: String = "绫音"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archived: Bool = false

    init(
        id: UUID = UUID(),
        title: String = "绫音",
        createdAt: Date = Date(),
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

@Model
final class ConversationEvent {
    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var conversationID: UUID = UUID()
    var deviceID: String = ""
    var deviceSequence: Int = 0
    var logicalTimestamp: String = ""
    var occurredAt: Date = Date()
    var recordedAt: Date = Date()
    var roleRaw: String = EventRole.user.rawValue
    var content: String = ""
    var contentHash: String = ""
    /// v11/v15 payload columns are additive. Text events keep the original
    /// `content` and `contentHash`; sticker, image, and file events carry
    /// their structured value alongside the legacy columns.
    var payloadKindRaw: String = MessagePayloadKind.text.rawValue
    var stickerID: String = ""
    /// Original image bytes are kept out of the ordinary SQLite row when the
    /// store supports external storage. The legacy `content` column remains
    /// the accessible text/fallback for image messages.
    @Attribute(.externalStorage) var imageData: Data? = nil
    /// File bytes use their own external-storage column. Image and text
    /// payloads must leave this column empty so switching payload kinds cannot
    /// leak unrelated bytes into an export or merge.
    @Attribute(.externalStorage) var fileData: Data? = nil
    var fileName: String = ""
    var fileTypeIdentifier: String = ""
    /// In a group conversation this identifies the independent sender role;
    /// ordinary one-to-one events leave it nil for legacy compatibility.
    var senderRoleID: UUID? = nil
    var parentEventID: UUID?
    var deliveryStateRaw: String = EventDeliveryState.complete.rawValue
    var redacted: Bool = false
    /// Derived-processing metadata. The original role/content/hash remain unchanged.
    var memoryProcessedAt: Date?
    var memoryProcessingVersion: Int = 0

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        deviceID: String,
        deviceSequence: Int,
        logicalTimestamp: String,
        occurredAt: Date = Date(),
        role: EventRole,
        content: String,
        contentHash: String,
        parentEventID: UUID? = nil,
        deliveryState: EventDeliveryState = .complete,
        roleID: UUID? = nil,
        payload: MessagePayload? = nil,
        payloadKind: MessagePayloadKind = .text,
        stickerID: String? = nil,
        senderRoleID: UUID? = nil,
        imageData: Data? = nil,
        fileName: String = "",
        fileTypeIdentifier: String = "",
        fileData: Data? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.conversationID = conversationID
        self.deviceID = deviceID
        self.deviceSequence = deviceSequence
        self.logicalTimestamp = logicalTimestamp
        self.occurredAt = occurredAt
        self.recordedAt = Date()
        self.roleRaw = role.rawValue
        self.content = content
        self.contentHash = contentHash
        let resolvedPayloadKind = payload?.kind ?? payloadKind
        self.payloadKindRaw = resolvedPayloadKind.rawValue
        self.stickerID = resolvedPayloadKind == .sticker
            ? (payload?.stickerID ?? stickerID ?? "")
            : ""
        self.imageData = resolvedPayloadKind == .image
            ? (payload?.imageData ?? imageData)
            : nil
        self.fileName = resolvedPayloadKind == .file
            ? (payload?.fileName ?? fileName)
            : ""
        self.fileTypeIdentifier = resolvedPayloadKind == .file
            ? (payload?.fileTypeIdentifier ?? fileTypeIdentifier)
            : ""
        self.fileData = resolvedPayloadKind == .file
            ? (payload?.fileData ?? fileData)
            : nil
        self.senderRoleID = senderRoleID
        self.parentEventID = parentEventID
        self.deliveryStateRaw = deliveryState.rawValue
    }

    var role: EventRole {
        EventRole(rawValue: roleRaw) ?? .user
    }

    var deliveryState: EventDeliveryState {
        EventDeliveryState(rawValue: deliveryStateRaw) ?? .complete
    }

    var payloadKind: MessagePayloadKind {
        get { MessagePayloadKind(rawValue: payloadKindRaw) ?? .text }
        set {
            payloadKindRaw = newValue.rawValue
            if newValue != .sticker { stickerID = "" }
            if newValue != .image { imageData = nil }
            if newValue != .file {
                fileName = ""
                fileTypeIdentifier = ""
                fileData = nil
            }
        }
    }

    var payload: MessagePayload {
        get {
            switch payloadKind {
            case .sticker:
                return .sticker(stickerID)
            case .text:
                return .text(content)
            case .image:
                return MessagePayload(
                    kind: .image,
                    text: content,
                    imageData: imageData
                )
            case .file:
                return MessagePayload(
                    kind: .file,
                    fileName: fileName,
                    fileTypeIdentifier: fileTypeIdentifier,
                    fileData: fileData
                )
            }
        }
        set {
            payloadKindRaw = newValue.kind.rawValue
            stickerID = newValue.kind == .sticker ? (newValue.stickerID ?? "") : ""
            imageData = newValue.kind == .image ? newValue.imageData : nil
            fileName = newValue.kind == .file ? (newValue.fileName ?? "") : ""
            fileTypeIdentifier = newValue.kind == .file ? (newValue.fileTypeIdentifier ?? "") : ""
            fileData = newValue.kind == .file ? newValue.fileData : nil
            if (newValue.kind == .text || newValue.kind == .image), let text = newValue.text {
                content = text
                contentHash = ContentHasher.sha256(text)
            }
        }
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

@Model
final class MemoryAssertionRecord {
    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var kindRaw: String = MemoryKind.profile.rawValue
    var subject: String = "user"
    var predicate: String = ""
    var value: String = ""
    var canonicalKey: String = ""
    var stateRaw: String = MemoryState.candidate.rawValue
    var confidence: Double = 0.5
    var importance: Double = 0.5
    var sensitive: Bool = false
    var sourceRank: Int = 0
    var validFrom: Date?
    var validTo: Date?
    var observedAt: Date = Date()
    var supersedesID: UUID?
    var extractorID: String = ""
    var schemaVersion: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isPinned: Bool = false
    var userVerified: Bool = false
    var embeddingData: Data?
    var embeddingModelID: String?
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        kind: MemoryKind,
        subject: String,
        predicate: String,
        value: String,
        canonicalKey: String,
        state: MemoryState,
        confidence: Double,
        importance: Double,
        sensitive: Bool,
        sourceRank: Int,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        observedAt: Date = Date(),
        supersedesID: UUID? = nil,
        extractorID: String,
        deviceID: String,
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.kindRaw = kind.rawValue
        self.subject = subject
        self.predicate = predicate
        self.value = value
        self.canonicalKey = canonicalKey
        self.stateRaw = state.rawValue
        self.confidence = confidence
        self.importance = importance
        self.sensitive = sensitive
        self.sourceRank = sourceRank
        self.validFrom = validFrom
        self.validTo = validTo
        self.observedAt = observedAt
        self.supersedesID = supersedesID
        self.extractorID = extractorID
        self.deviceID = deviceID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: MemoryKind {
        MemoryKind(rawValue: kindRaw) ?? .profile
    }

    var state: MemoryState {
        MemoryState(rawValue: stateRaw) ?? .candidate
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

@Model
final class MemoryEvidenceRecord {
    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var memoryID: UUID = UUID()
    var eventID: UUID = UUID()
    var startUTF16: Int = 0
    var endUTF16: Int = 0
    var relationRaw: String = EvidenceRelation.supports.rawValue
    var quoteHash: String = ""
    var confidence: Double = 0.5
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        memoryID: UUID,
        eventID: UUID,
        startUTF16: Int,
        endUTF16: Int,
        relation: EvidenceRelation,
        quoteHash: String,
        confidence: Double,
        roleID: UUID? = nil
    ) {
        self.id = id
        self.roleID = roleID
        self.memoryID = memoryID
        self.eventID = eventID
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
        self.relationRaw = relation.rawValue
        self.quoteHash = quoteHash
        self.confidence = confidence
        self.createdAt = Date()
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

@Model
final class MemorySummaryRecord {
    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var conversationID: UUID = UUID()
    var scope: String = "session"
    var content: String = ""
    var firstEventID: UUID?
    var lastEventID: UUID?
    var coveredEventCount: Int = 0
    var extractorID: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        conversationID: UUID,
        scope: String,
        content: String,
        firstEventID: UUID?,
        lastEventID: UUID?,
        coveredEventCount: Int,
        extractorID: String,
        roleID: UUID? = nil
    ) {
        self.conversationID = conversationID
        self.roleID = roleID
        self.scope = scope
        self.content = content
        self.firstEventID = firstEventID
        self.lastEventID = lastEventID
        self.coveredEventCount = coveredEventCount
        self.extractorID = extractorID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

@Model
final class MemoryTombstoneRecord {
    /// Version 2 trims Unicode whitespace as well as BOM/format/control
    /// scalars at canonical-key boundaries. Bumping this value is important:
    /// rows written by version 1 already looked normalized, but could still
    /// carry invisible boundary characters and must be re-migrated.
    static let currentCanonicalKeyNormalizationVersion = 2

    var id: UUID = UUID()
    /// Optional for migration; nil rows belong to the legacy companion.
    var roleID: UUID? = nil
    var entityID: UUID = UUID()
    var entityType: String = "memory"
    var canonicalKey: String = ""
    /// Rows created by older builds did not prove that canonicalKey had been
    /// trimmed and case-normalized. Zero is deliberately the migration value:
    /// new rows set the current version in init, while a newly synced legacy
    /// row remains discoverable and must be normalized before memory reads.
    var canonicalKeyNormalizationVersion: Int = 0
    var sourceEventIDsRaw: String = ""
    var deletedAt: Date = Date()
    var deviceID: String = ""
    var reason: String = "user_requested"

    init(
        entityID: UUID,
        entityType: String,
        canonicalKey: String = "",
        sourceEventIDs: [UUID] = [],
        deviceID: String,
        reason: String = "user_requested",
        roleID: UUID? = nil
    ) {
        self.roleID = roleID
        self.entityID = entityID
        self.entityType = entityType
        self.canonicalKey = Self.normalizedCanonicalKey(canonicalKey)
        self.canonicalKeyNormalizationVersion = Self.currentCanonicalKeyNormalizationVersion
        self.sourceEventIDsRaw = Self.encodeSourceEventIDs(sourceEventIDs)
        self.deletedAt = Date()
        self.deviceID = deviceID
        self.reason = reason
    }

    var sourceEventIDs: [UUID] {
        sourceEventIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }

    static func normalizedCanonicalKey(_ value: String) -> String {
        let scalars = value.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex

        // `CharacterSet.whitespacesAndNewlines` does not include zero-width
        // spaces, BOM, or every Unicode control/format scalar. Canonical keys
        // are identifiers, so those invisible boundary scalars are always
        // accidental transport padding rather than meaningful content.
        func isBoundaryNoise(_ scalar: Unicode.Scalar) -> Bool {
            scalar.value == 0xFEFF
                || scalar.properties.generalCategory == .format
                || scalar.properties.generalCategory == .control
                || scalar.properties.isWhitespace
        }

        while start < end, isBoundaryNoise(scalars[start]) {
            start = scalars.index(after: start)
        }
        while start < end {
            let previous = scalars.index(before: end)
            guard isBoundaryNoise(scalars[previous]) else { break }
            end = previous
        }

        // A BOM or format/control scalar may also appear after the first
        // scalar when a payload was concatenated incorrectly. Remove those
        // invisible identifier characters globally while preserving the
        // existing behavior for ordinary interior whitespace/visible text.
        return String(scalars[start..<end])
            .unicodeScalars
            .filter {
                $0.value != 0xFEFF
                    && $0.properties.generalCategory != .format
                    && $0.properties.generalCategory != .control
            }
            .map(String.init)
            .joined()
            .lowercased()
    }

    private static func encodeSourceEventIDs(_ ids: [UUID]) -> String {
        Set(ids).map(\.uuidString).sorted().joined(separator: ",")
    }
}
