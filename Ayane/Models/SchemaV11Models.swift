import Foundation
import SwiftData

// MARK: - Stable message payload

/// The wire-level kind of a conversation message.  The raw value is kept in
/// `ConversationEvent` so older stores can continue to open without decoding a
/// Swift enum column.
enum MessagePayloadKind: String, Codable, CaseIterable, Sendable {
    case text
    case sticker
    case image
    case file
}

/// A value-only message payload. Text remains the legacy `content` column;
/// stickers add a stable identifier and images add bytes without changing
/// that legacy accessible text/hash.
struct MessagePayload: Codable, Equatable, Hashable, Sendable {
    let kind: MessagePayloadKind
    /// Text is the message body for text payloads and the optional accessible
    /// description/fallback for media payloads.
    let text: String?
    let stickerID: String?
    let imageData: Data?
    let fileName: String?
    let fileTypeIdentifier: String?
    let fileData: Data?

    init(
        kind: MessagePayloadKind,
        text: String? = nil,
        stickerID: String? = nil,
        imageData: Data? = nil,
        fileName: String? = nil,
        fileTypeIdentifier: String? = nil,
        fileData: Data? = nil
    ) {
        self.kind = kind
        self.text = text
        self.stickerID = stickerID
        self.imageData = imageData
        self.fileName = fileName
        self.fileTypeIdentifier = fileTypeIdentifier
        self.fileData = fileData
    }

    static func text(_ value: String) -> MessagePayload {
        MessagePayload(kind: .text, text: value, stickerID: nil, imageData: nil)
    }

    static func sticker(_ identifier: String) -> MessagePayload {
        MessagePayload(kind: .sticker, text: nil, stickerID: identifier, imageData: nil)
    }

    static func sticker(stickerID identifier: String) -> MessagePayload {
        sticker(identifier)
    }

    /// Creates an image payload. The optional accessibility text is retained
    /// in `text` so older clients can still present a meaningful fallback.
    static func image(
        _ data: Data,
        accessibilityText: String? = nil
    ) -> MessagePayload {
        MessagePayload(kind: .image, text: accessibilityText, stickerID: nil, imageData: data)
    }

    static func image(
        data: Data,
        accessibilityText: String? = nil
    ) -> MessagePayload {
        image(data, accessibilityText: accessibilityText)
    }

    static func image(
        imageData data: Data,
        accessibilityText: String? = nil
    ) -> MessagePayload {
        image(data, accessibilityText: accessibilityText)
    }

    /// Label-compatible aliases for callers that use the payload's `text`
    /// spelling for the accessible fallback.
    static func image(_ data: Data, text: String?) -> MessagePayload {
        image(data, accessibilityText: text)
    }

    static func image(data: Data, text: String?) -> MessagePayload {
        image(data, accessibilityText: text)
    }

    static func image(imageData data: Data, text: String?) -> MessagePayload {
        image(data, accessibilityText: text)
    }

    /// Creates a file payload. File metadata is kept separate from the
    /// legacy text/image columns so a document can be restored byte-for-byte.
    static func file(
        data: Data,
        fileName: String,
        fileTypeIdentifier: String
    ) -> MessagePayload {
        MessagePayload(
            kind: .file,
            text: nil,
            stickerID: nil,
            imageData: nil,
            fileName: fileName,
            fileTypeIdentifier: fileTypeIdentifier,
            fileData: data
        )
    }

    var isText: Bool { kind == .text }
    var isSticker: Bool { kind == .sticker }
    var isImage: Bool { kind == .image }
    var isFile: Bool { kind == .file }

    /// Explicit aliases keep media presentation code from having to know that
    /// the wire-level field is named `text` for backward compatibility.
    var accessibleText: String? { text }
    var accessibilityText: String? { text }
}

// MARK: - Shared world

/// A persisted world profile that can be shared by any number of roles and
/// conversations. Arrays are encoded as JSON in a scalar string to keep the
/// SwiftData model CloudKit-compatible (no relationships or transformable
/// collections). `realityID` is retained as the default legacy world, but is
/// no longer a uniqueness constraint or a singleton identity.
@Model
final class WorldProfileRecord {
    static let realityID = UUID(uuidString: "5D3E6F4B-8C9A-4A1E-9F6B-4F5C2D7A8E11")!
    static let singletonID = realityID

    var id: UUID = WorldProfileRecord.realityID
    /// Human-facing world label. The stored value is deliberately scalar with
    /// a default so existing CloudKit rows can be upgraded in place.
    var displayName: String = "现实世界"
    var worldKindRaw: String = "reality"
    var timezoneIdentifier: String = TimeZone.current.identifier
    var locationContext: String = ""
    var commonFactsRaw: String = "[]"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = WorldProfileRecord.realityID,
        displayName: String = "现实世界",
        worldKind: String = "reality",
        timezoneIdentifier: String = TimeZone.current.identifier,
        locationContext: String = "",
        commonFacts: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.worldKindRaw = worldKind
        self.timezoneIdentifier = timezoneIdentifier
        self.locationContext = locationContext
        self.commonFactsRaw = Self.encodeFacts(commonFacts)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    /// Compatibility initializer for callers that already hold the scalar
    /// representation used by SwiftData/CloudKit.
    init(
        id: UUID = WorldProfileRecord.realityID,
        displayName: String = "现实世界",
        worldKindRaw: String,
        timezoneIdentifier: String = TimeZone.current.identifier,
        locationContext: String = "",
        commonFactsRaw: String = "[]",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.worldKindRaw = worldKindRaw
        self.timezoneIdentifier = timezoneIdentifier
        self.locationContext = locationContext
        self.commonFactsRaw = commonFactsRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var worldKind: String {
        get { worldKindRaw }
        set { worldKindRaw = newValue }
    }

    /// Compatibility spelling used by some callers and older design notes.
    /// `displayName` remains the sole persisted column.
    var title: String {
        get { displayName }
        set { displayName = newValue }
    }

    var timezone: String {
        get { timezoneIdentifier }
        set { timezoneIdentifier = newValue }
    }

    var timeZoneIdentifier: String {
        get { timezoneIdentifier }
        set { timezoneIdentifier = newValue }
    }

    var location: String {
        get { locationContext }
        set { locationContext = newValue }
    }

    var commonFacts: [String] {
        get { Self.decodeFacts(commonFactsRaw) }
        set { commonFactsRaw = Self.encodeFacts(newValue) }
    }

    var facts: [String] {
        get { commonFacts }
        set { commonFacts = newValue }
    }

    static var realityDefault: WorldProfileRecord {
        WorldProfileRecord(
            id: realityID,
            displayName: "现实世界",
            worldKind: "reality",
            timezoneIdentifier: TimeZone.current.identifier,
            locationContext: "",
            commonFacts: [],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            revision: 0,
            deviceID: ""
        )
    }

    private static func encodeFacts(_ facts: [String]) -> String {
        guard let data = try? JSONEncoder().encode(facts) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeFacts(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let facts = try? JSONDecoder().decode([String].self, from: data) else {
            return raw.isEmpty ? [] : [raw]
        }
        return facts
    }
}

enum GroupConversationLifecycle: String, Codable, CaseIterable, Sendable {
    case active
    case archived
    case deleted
    case creating
}

enum GroupParticipantKind: String, Codable, CaseIterable, Sendable {
    case user
    case companion
    case external
}

/// Group metadata for a normal `ConversationRecord`.  `conversationID` is the
/// logical key; `id` remains an independent scalar because SwiftData has no
/// uniqueness constraint in a CloudKit-backed model.
@Model
final class GroupConversationRecord {
    var id: UUID = UUID()
    var conversationID: UUID = UUID()
    var groupName: String = "群聊"
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    var lifecycleRaw: String = GroupConversationLifecycle.active.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupName: String = "群聊",
        avatarImageData: Data? = nil,
        lifecycle: GroupConversationLifecycle = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupName = groupName
        self.avatarImageData = avatarImageData
        self.lifecycleRaw = lifecycle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupName: String = "群聊",
        avatarImageData: Data? = nil,
        lifecycleRaw: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupName = groupName
        self.avatarImageData = avatarImageData
        self.lifecycleRaw = lifecycleRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var name: String {
        get { groupName }
        set { groupName = newValue }
    }

    var avatarData: Data? {
        get { avatarImageData }
        set { avatarImageData = newValue }
    }

    var lifecycle: GroupConversationLifecycle {
        get { GroupConversationLifecycle(rawValue: lifecycleRaw) ?? .active }
        set { lifecycleRaw = newValue.rawValue }
    }

    var stateRaw: String {
        get { lifecycleRaw }
        set { lifecycleRaw = newValue }
    }
}

/// One member of a group.  The `(conversationID, participantRoleID)` scope is
/// deliberately retained by merge/reconciliation so the same role can appear
/// in multiple groups without being collapsed into one membership.
@Model
final class GroupParticipantRecord {
    var id: UUID = UUID()
    var conversationID: UUID = UUID()
    var groupConversationID: UUID = UUID()
    var participantRoleID: UUID? = nil
    var participantKindRaw: String = GroupParticipantKind.companion.rawValue
    var displayName: String = ""
    @Attribute(.externalStorage) var avatarImageData: Data? = nil
    var joinedAt: Date = Date()
    var leftAt: Date? = nil
    var lifecycleRaw: String = GroupConversationLifecycle.active.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupConversationID: UUID? = nil,
        participantRoleID: UUID? = nil,
        participantKind: GroupParticipantKind = .companion,
        displayName: String = "",
        avatarImageData: Data? = nil,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        lifecycle: GroupConversationLifecycle = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupConversationID = groupConversationID ?? conversationID
        self.participantRoleID = participantRoleID
        self.participantKindRaw = participantKind.rawValue
        self.displayName = displayName
        self.avatarImageData = avatarImageData
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lifecycleRaw = lifecycle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupConversationID: UUID? = nil,
        participantRoleID: UUID? = nil,
        participantKindRaw: String,
        displayName: String = "",
        avatarImageData: Data? = nil,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        lifecycleRaw: String = GroupConversationLifecycle.active.rawValue,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupConversationID = groupConversationID ?? conversationID
        self.participantRoleID = participantRoleID
        self.participantKindRaw = participantKindRaw
        self.displayName = displayName
        self.avatarImageData = avatarImageData
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lifecycleRaw = lifecycleRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var roleID: UUID? {
        get { participantRoleID }
        set { participantRoleID = newValue }
    }

    var participantKind: GroupParticipantKind {
        get { GroupParticipantKind(rawValue: participantKindRaw) ?? .external }
        set { participantKindRaw = newValue.rawValue }
    }

    var lifecycle: GroupConversationLifecycle {
        get { GroupConversationLifecycle(rawValue: lifecycleRaw) ?? .active }
        set { lifecycleRaw = newValue.rawValue }
    }
}

// MARK: - Reply presentation and proactive tasks

enum ChatTurnPresentationState: String, Codable, CaseIterable, Sendable {
    case generating
    case waiting
    case perItem
    case delivering
    case streaming
    case completed
    case cancelled
    case failed

    var isTerminal: Bool {
        self == .completed || self == .cancelled || self == .failed
    }
}

/// Durable UI presentation state for one logical assistant reply.  Segments
/// are stored as a JSON scalar; the reply event itself remains immutable.
@Model
final class ChatTurnPresentationRecord {
    var id: UUID = UUID()
    var conversationID: UUID = UUID()
    var roleID: UUID? = nil
    var logicalReplyEventID: UUID? = nil
    var segmentsRaw: String = "[]"
    var displayProgress: Double = 0
    var displayedSegmentCount: Int = 0
    var stateRaw: String = ChatTurnPresentationState.generating.rawValue
    var plannedAt: Date? = nil
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var cancelledAt: Date? = nil
    var failureMessage: String = ""
    var idempotencyKey: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        roleID: UUID? = nil,
        logicalReplyEventID: UUID? = nil,
        segments: [String] = [],
        displayProgress: Double = 0,
        displayedSegmentCount: Int = 0,
        state: ChatTurnPresentationState = .generating,
        plannedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        failureMessage: String = "",
        idempotencyKey: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleID = roleID
        self.logicalReplyEventID = logicalReplyEventID
        self.segmentsRaw = Self.encodeSegments(segments)
        self.displayProgress = min(1, max(0, displayProgress.isFinite ? displayProgress : 0))
        self.displayedSegmentCount = max(0, displayedSegmentCount)
        self.stateRaw = state.rawValue
        self.plannedAt = plannedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.failureMessage = failureMessage
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        roleID: UUID? = nil,
        logicalReplyEventID: UUID? = nil,
        segmentsRaw: String,
        displayProgress: Double = 0,
        displayedSegmentCount: Int = 0,
        stateRaw: String,
        plannedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        failureMessage: String = "",
        idempotencyKey: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleID = roleID
        self.logicalReplyEventID = logicalReplyEventID
        self.segmentsRaw = segmentsRaw
        self.displayProgress = min(1, max(0, displayProgress.isFinite ? displayProgress : 0))
        self.displayedSegmentCount = max(0, displayedSegmentCount)
        self.stateRaw = stateRaw
        self.plannedAt = plannedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.failureMessage = failureMessage
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var replyEventID: UUID? {
        get { logicalReplyEventID }
        set { logicalReplyEventID = newValue }
    }

    var scheduledAt: Date? {
        get { plannedAt }
        set { plannedAt = newValue }
    }

    var segments: [String] {
        get { Self.decodeSegments(segmentsRaw) }
        set { segmentsRaw = Self.encodeSegments(newValue) }
    }

    var state: ChatTurnPresentationState {
        get { ChatTurnPresentationState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    private static func encodeSegments(_ segments: [String]) -> String {
        guard let data = try? JSONEncoder().encode(segments) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeSegments(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let segments = try? JSONDecoder().decode([String].self, from: data) else {
            return raw.isEmpty ? [] : [raw]
        }
        return segments
    }
}

enum ProactiveMessageTaskState: String, Codable, CaseIterable, Sendable {
    case scheduled
    case waiting
    case running
    case deferred
    case completed
    case cancelled
    case failed

    var isTerminal: Bool {
        self == .completed || self == .cancelled || self == .failed
    }
}

/// A scheduler task independent from chat-turn presentation. Lease and
/// idempotency columns make retries safe across devices and process restarts.
@Model
final class ProactiveMessageTaskRecord {
    var id: UUID = UUID()
    var roleID: UUID? = nil
    var conversationID: UUID = UUID()
    var scheduledAt: Date = Date()
    var followUpCount: Int = 0
    var stateRaw: String = ProactiveMessageTaskState.scheduled.rawValue
    var silentDeferredUntil: Date? = nil
    var leaseOwner: String = ""
    var leaseExpiresAt: Date? = nil
    var idempotencyKey: String = ""
    var lastError: String = ""
    /// Generated content is persisted before scheduling a local notification,
    /// so a restart never needs to generate the same proactive reply again.
    var generatedText: String = ""
    /// The user turn which caused this task. A later user event can cancel or
    /// supersede the task without inspecting transient scheduler state.
    var lastUserEventID: UUID? = nil
    var scheduledFromUserAt: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var revision: Int = 0
    var deviceID: String = ""

    init(
        id: UUID = UUID(),
        roleID: UUID? = nil,
        conversationID: UUID,
        scheduledAt: Date = Date(),
        followUpCount: Int = 0,
        state: ProactiveMessageTaskState = .scheduled,
        silentDeferredUntil: Date? = nil,
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        idempotencyKey: String = "",
        lastError: String = "",
        generatedText: String = "",
        lastUserEventID: UUID? = nil,
        scheduledFromUserAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = roleID.map(RoleScope.resolve)
        self.conversationID = conversationID
        self.scheduledAt = scheduledAt
        self.followUpCount = max(0, followUpCount)
        self.stateRaw = state.rawValue
        self.silentDeferredUntil = silentDeferredUntil
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.idempotencyKey = idempotencyKey
        self.lastError = lastError
        self.generatedText = generatedText
        self.lastUserEventID = lastUserEventID
        self.scheduledFromUserAt = scheduledFromUserAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        roleID: UUID? = nil,
        conversationID: UUID,
        scheduledAt: Date = Date(),
        followUpCount: Int = 0,
        stateRaw: String,
        silentDeferredUntil: Date? = nil,
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        idempotencyKey: String = "",
        lastError: String = "",
        generatedText: String = "",
        lastUserEventID: UUID? = nil,
        scheduledFromUserAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = roleID.map(RoleScope.resolve)
        self.conversationID = conversationID
        self.scheduledAt = scheduledAt
        self.followUpCount = max(0, followUpCount)
        self.stateRaw = stateRaw
        self.silentDeferredUntil = silentDeferredUntil
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.idempotencyKey = idempotencyKey
        self.lastError = lastError
        self.generatedText = generatedText
        self.lastUserEventID = lastUserEventID
        self.scheduledFromUserAt = scheduledFromUserAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = max(0, revision)
        self.deviceID = deviceID
    }

    var state: ProactiveMessageTaskState {
        get { ProactiveMessageTaskState(rawValue: stateRaw) ?? .failed }
        set { stateRaw = newValue.rawValue }
    }

    var silentDeferUntil: Date? {
        get { silentDeferredUntil }
        set { silentDeferredUntil = newValue }
    }

    var resolvedRoleID: UUID { RoleScope.resolve(roleID) }
}

// MARK: - Codable projections

struct AyaneWorldProfileExport: Codable, Equatable, Sendable {
    static let realityID = WorldProfileRecord.realityID
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var displayName: String
    var worldKind: String
    var timezoneIdentifier: String
    var locationContext: String
    var commonFacts: [String]
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case legacyTitle = "title"
        case worldKind = "world_kind"
        case timezoneIdentifier = "timezone_identifier"
        case locationContext = "location_context"
        case commonFacts = "common_facts"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = Self.realityID,
        displayName: String = "现实世界",
        worldKind: String = "reality",
        timezoneIdentifier: String = TimeZone.current.identifier,
        locationContext: String = "",
        commonFacts: [String] = [],
        createdAt: Date = Self.legacyEpoch,
        updatedAt: Date = Self.legacyEpoch,
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.worldKind = worldKind
        self.timezoneIdentifier = timezoneIdentifier
        self.locationContext = locationContext
        self.commonFacts = commonFacts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: WorldProfileRecord) {
        self.init(
            id: record.id,
            displayName: record.displayName,
            worldKind: record.worldKindRaw,
            timezoneIdentifier: record.timezoneIdentifier,
            locationContext: record.locationContext,
            commonFacts: record.commonFacts,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    static var realityDefault: AyaneWorldProfileExport {
        AyaneWorldProfileExport()
    }

    /// Compatibility spelling for clients that call a world's display label a
    /// title. Only `displayName` is serialized.
    var title: String {
        get { displayName }
        set { displayName = newValue }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.realityID
        if let explicitDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName) {
            displayName = explicitDisplayName
        } else {
            displayName = try container.decodeIfPresent(String.self, forKey: .legacyTitle)
                ?? "现实世界"
        }
        worldKind = try container.decodeIfPresent(String.self, forKey: .worldKind) ?? "reality"
        timezoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
            ?? TimeZone.current.identifier
        locationContext = try container.decodeIfPresent(String.self, forKey: .locationContext) ?? ""
        commonFacts = try container.decodeIfPresent([String].self, forKey: .commonFacts) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(worldKind, forKey: .worldKind)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(locationContext, forKey: .locationContext)
        try container.encode(commonFacts, forKey: .commonFacts)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }

}

struct AyaneGroupConversationExport: Codable, Equatable, Sendable {
    var id: UUID
    var conversationID: UUID
    var groupName: String
    var avatarImageData: Data?
    var lifecycleRaw: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    var lifecycle: GroupConversationLifecycle {
        GroupConversationLifecycle(rawValue: lifecycleRaw) ?? .active
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case groupName = "group_name"
        case avatarImageData = "avatar_image_data"
        case lifecycle = "lifecycle"
        case lifecycleRaw = "lifecycle_raw"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupName: String = "群聊",
        avatarImageData: Data? = nil,
        lifecycle: GroupConversationLifecycle = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupName = groupName
        self.avatarImageData = avatarImageData
        self.lifecycleRaw = lifecycle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: GroupConversationRecord) {
        self.init(
            id: record.id,
            conversationID: record.conversationID,
            groupName: record.groupName,
            avatarImageData: record.avatarImageData,
            lifecycle: record.lifecycle,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? "群聊"
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        lifecycleRaw = try container.decodeIfPresent(String.self, forKey: .lifecycleRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .lifecycle))
            ?? GroupConversationLifecycle.active.rawValue
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(groupName, forKey: .groupName)
        try container.encodeIfPresent(avatarImageData, forKey: .avatarImageData)
        try container.encode(lifecycleRaw, forKey: .lifecycle)
        try container.encode(lifecycleRaw, forKey: .lifecycleRaw)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }

}

struct AyaneGroupParticipantExport: Codable, Equatable, Sendable {
    var id: UUID
    var conversationID: UUID
    var groupConversationID: UUID
    var participantRoleID: UUID?
    var participantKindRaw: String
    var displayName: String
    var avatarImageData: Data?
    var joinedAt: Date
    var leftAt: Date?
    var lifecycleRaw: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    var roleID: UUID? {
        get { participantRoleID }
        set { participantRoleID = newValue }
    }

    var participantKind: GroupParticipantKind {
        GroupParticipantKind(rawValue: participantKindRaw) ?? .external
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case groupConversationID = "group_conversation_id"
        case participantRoleID = "participant_role_id"
        case roleID = "role_id"
        case participantKind = "participant_kind"
        case participantKindRaw = "participant_kind_raw"
        case displayName = "display_name"
        case avatarImageData = "avatar_image_data"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
        case lifecycle = "lifecycle"
        case lifecycleRaw = "lifecycle_raw"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        groupConversationID: UUID? = nil,
        participantRoleID: UUID? = nil,
        participantKind: GroupParticipantKind = .companion,
        displayName: String = "",
        avatarImageData: Data? = nil,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        lifecycle: GroupConversationLifecycle = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.groupConversationID = groupConversationID ?? conversationID
        self.participantRoleID = participantRoleID
        self.participantKindRaw = participantKind.rawValue
        self.displayName = displayName
        self.avatarImageData = avatarImageData
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lifecycleRaw = lifecycle.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: GroupParticipantRecord) {
        self.init(
            id: record.id,
            conversationID: record.conversationID,
            groupConversationID: record.groupConversationID,
            participantRoleID: record.participantRoleID,
            participantKind: record.participantKind,
            displayName: record.displayName,
            avatarImageData: record.avatarImageData,
            joinedAt: record.joinedAt,
            leftAt: record.leftAt,
            lifecycle: record.lifecycle,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        groupConversationID = try container.decodeIfPresent(UUID.self, forKey: .groupConversationID)
            ?? conversationID
        participantRoleID = try container.decodeIfPresent(UUID.self, forKey: .participantRoleID)
            ?? (try container.decodeIfPresent(UUID.self, forKey: .roleID))
        participantKindRaw = try container.decodeIfPresent(String.self, forKey: .participantKindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .participantKind))
            ?? GroupParticipantKind.external.rawValue
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        joinedAt = try container.decodeIfPresent(Date.self, forKey: .joinedAt)
            ?? Date(timeIntervalSince1970: 0)
        leftAt = try container.decodeIfPresent(Date.self, forKey: .leftAt)
        lifecycleRaw = try container.decodeIfPresent(String.self, forKey: .lifecycleRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .lifecycle))
            ?? GroupConversationLifecycle.active.rawValue
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? joinedAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(groupConversationID, forKey: .groupConversationID)
        try container.encodeIfPresent(participantRoleID, forKey: .participantRoleID)
        try container.encodeIfPresent(participantRoleID, forKey: .roleID)
        try container.encode(participantKindRaw, forKey: .participantKind)
        try container.encode(participantKindRaw, forKey: .participantKindRaw)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarImageData, forKey: .avatarImageData)
        try container.encode(joinedAt, forKey: .joinedAt)
        try container.encodeIfPresent(leftAt, forKey: .leftAt)
        try container.encode(lifecycleRaw, forKey: .lifecycle)
        try container.encode(lifecycleRaw, forKey: .lifecycleRaw)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }

}

struct AyaneChatTurnPresentationExport: Codable, Equatable, Sendable {
    var id: UUID
    var conversationID: UUID
    var roleID: UUID?
    var logicalReplyEventID: UUID?
    var segments: [String]
    var displayProgress: Double
    var displayedSegmentCount: Int
    var stateRaw: String
    var plannedAt: Date?
    var startedAt: Date?
    var completedAt: Date?
    var cancelledAt: Date?
    var failureMessage: String
    var idempotencyKey: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    var state: ChatTurnPresentationState {
        ChatTurnPresentationState(rawValue: stateRaw) ?? .failed
    }

    var replyEventID: UUID? {
        get { logicalReplyEventID }
        set { logicalReplyEventID = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case roleID = "role_id"
        case logicalReplyEventID = "logical_reply_event_id"
        case replyEventID = "reply_event_id"
        case segments
        case displayProgress = "display_progress"
        case displayedSegmentCount = "displayed_segment_count"
        case state
        case stateRaw = "state_raw"
        case plannedAt = "planned_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case cancelledAt = "cancelled_at"
        case failureMessage = "failure_message"
        case idempotencyKey = "idempotency_key"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        conversationID: UUID,
        roleID: UUID? = nil,
        logicalReplyEventID: UUID? = nil,
        segments: [String] = [],
        displayProgress: Double = 0,
        displayedSegmentCount: Int = 0,
        state: ChatTurnPresentationState = .generating,
        plannedAt: Date? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        cancelledAt: Date? = nil,
        failureMessage: String = "",
        idempotencyKey: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.conversationID = conversationID
        self.roleID = roleID.map(RoleScope.resolve)
        self.logicalReplyEventID = logicalReplyEventID
        self.segments = segments
        self.displayProgress = displayProgress
        self.displayedSegmentCount = displayedSegmentCount
        self.stateRaw = state.rawValue
        self.plannedAt = plannedAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.cancelledAt = cancelledAt
        self.failureMessage = failureMessage
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: ChatTurnPresentationRecord) {
        self.init(
            id: record.id,
            conversationID: record.conversationID,
            roleID: record.roleID,
            logicalReplyEventID: record.logicalReplyEventID,
            segments: record.segments,
            displayProgress: record.displayProgress,
            displayedSegmentCount: record.displayedSegmentCount,
            state: record.state,
            plannedAt: record.plannedAt,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            cancelledAt: record.cancelledAt,
            failureMessage: record.failureMessage,
            idempotencyKey: record.idempotencyKey,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        logicalReplyEventID = try container.decodeIfPresent(UUID.self, forKey: .logicalReplyEventID)
            ?? (try container.decodeIfPresent(UUID.self, forKey: .replyEventID))
        segments = try container.decodeIfPresent([String].self, forKey: .segments) ?? []
        displayProgress = try container.decodeIfPresent(Double.self, forKey: .displayProgress) ?? 0
        displayedSegmentCount = try container.decodeIfPresent(Int.self, forKey: .displayedSegmentCount) ?? 0
        stateRaw = try container.decodeIfPresent(String.self, forKey: .stateRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .state))
            ?? ChatTurnPresentationState.generating.rawValue
        plannedAt = try container.decodeIfPresent(Date.self, forKey: .plannedAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage) ?? ""
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encodeIfPresent(logicalReplyEventID, forKey: .logicalReplyEventID)
        try container.encodeIfPresent(logicalReplyEventID, forKey: .replyEventID)
        try container.encode(segments, forKey: .segments)
        try container.encode(displayProgress, forKey: .displayProgress)
        try container.encode(displayedSegmentCount, forKey: .displayedSegmentCount)
        try container.encode(stateRaw, forKey: .state)
        try container.encode(stateRaw, forKey: .stateRaw)
        try container.encodeIfPresent(plannedAt, forKey: .plannedAt)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(cancelledAt, forKey: .cancelledAt)
        try container.encode(failureMessage, forKey: .failureMessage)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

struct AyaneProactiveMessageTaskExport: Codable, Equatable, Sendable {
    var id: UUID
    var roleID: UUID?
    var conversationID: UUID
    var scheduledAt: Date
    var followUpCount: Int
    var stateRaw: String
    var silentDeferredUntil: Date?
    var leaseOwner: String
    var leaseExpiresAt: Date?
    var idempotencyKey: String
    var lastError: String
    var generatedText: String
    var lastUserEventID: UUID?
    var scheduledFromUserAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    var state: ProactiveMessageTaskState {
        ProactiveMessageTaskState(rawValue: stateRaw) ?? .failed
    }

    var silentDeferUntil: Date? {
        get { silentDeferredUntil }
        set { silentDeferredUntil = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case conversationID = "conversation_id"
        case scheduledAt = "scheduled_at"
        case followUpCount = "follow_up_count"
        case state
        case stateRaw = "state_raw"
        case silentDeferredUntil = "silent_deferred_until"
        case silentDeferUntil = "silent_defer_until"
        case leaseOwner = "lease_owner"
        case leaseExpiresAt = "lease_expires_at"
        case idempotencyKey = "idempotency_key"
        case lastError = "last_error"
        case generatedText = "generated_text"
        case lastUserEventID = "last_user_event_id"
        case scheduledFromUserAt = "scheduled_from_user_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        roleID: UUID? = nil,
        conversationID: UUID,
        scheduledAt: Date = Date(),
        followUpCount: Int = 0,
        state: ProactiveMessageTaskState = .scheduled,
        silentDeferredUntil: Date? = nil,
        leaseOwner: String = "",
        leaseExpiresAt: Date? = nil,
        idempotencyKey: String = "",
        lastError: String = "",
        generatedText: String = "",
        lastUserEventID: UUID? = nil,
        scheduledFromUserAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.id = id
        self.roleID = roleID.map(RoleScope.resolve)
        self.conversationID = conversationID
        self.scheduledAt = scheduledAt
        self.followUpCount = followUpCount
        self.stateRaw = state.rawValue
        self.silentDeferredUntil = silentDeferredUntil
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.idempotencyKey = idempotencyKey
        self.lastError = lastError
        self.generatedText = generatedText
        self.lastUserEventID = lastUserEventID
        self.scheduledFromUserAt = scheduledFromUserAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: ProactiveMessageTaskRecord) {
        self.init(
            id: record.id,
            roleID: record.roleID,
            conversationID: record.conversationID,
            scheduledAt: record.scheduledAt,
            followUpCount: record.followUpCount,
            state: record.state,
            silentDeferredUntil: record.silentDeferredUntil,
            leaseOwner: record.leaseOwner,
            leaseExpiresAt: record.leaseExpiresAt,
            idempotencyKey: record.idempotencyKey,
            lastError: record.lastError,
            generatedText: record.generatedText,
            lastUserEventID: record.lastUserEventID,
            scheduledFromUserAt: record.scheduledFromUserAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt)
            ?? Date(timeIntervalSince1970: 0)
        followUpCount = try container.decodeIfPresent(Int.self, forKey: .followUpCount) ?? 0
        stateRaw = try container.decodeIfPresent(String.self, forKey: .stateRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .state))
            ?? ProactiveMessageTaskState.scheduled.rawValue
        silentDeferredUntil = try container.decodeIfPresent(Date.self, forKey: .silentDeferredUntil)
            ?? (try container.decodeIfPresent(Date.self, forKey: .silentDeferUntil))
        leaseOwner = try container.decodeIfPresent(String.self, forKey: .leaseOwner) ?? ""
        leaseExpiresAt = try container.decodeIfPresent(Date.self, forKey: .leaseExpiresAt)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? ""
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
        generatedText = try container.decodeIfPresent(String.self, forKey: .generatedText) ?? ""
        lastUserEventID = try container.decodeIfPresent(UUID.self, forKey: .lastUserEventID)
        scheduledFromUserAt = try container.decodeIfPresent(Date.self, forKey: .scheduledFromUserAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? Date(timeIntervalSince1970: 0)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(followUpCount, forKey: .followUpCount)
        try container.encode(stateRaw, forKey: .state)
        try container.encode(stateRaw, forKey: .stateRaw)
        try container.encodeIfPresent(silentDeferredUntil, forKey: .silentDeferredUntil)
        try container.encodeIfPresent(silentDeferredUntil, forKey: .silentDeferUntil)
        try container.encode(leaseOwner, forKey: .leaseOwner)
        try container.encodeIfPresent(leaseExpiresAt, forKey: .leaseExpiresAt)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(lastError, forKey: .lastError)
        try container.encode(generatedText, forKey: .generatedText)
        try container.encodeIfPresent(lastUserEventID, forKey: .lastUserEventID)
        try container.encodeIfPresent(scheduledFromUserAt, forKey: .scheduledFromUserAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}
