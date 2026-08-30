import CryptoKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A complete, human-readable snapshot of the data Ayane stores locally.
///
/// API keys deliberately do not have a representation in this type: they are
/// kept in Keychain and are never copied into an export.
struct AyaneDataExport: Codable, Equatable, Sendable {
    /// v17 adds the optional deleted_at tombstone for Moments interactions
    /// while retaining v16 profile birthdays and recurring task metadata.
    /// The singular `worldProfile` projection remains on the wire for older
    /// readers.
    static let currentSchemaVersion = 17
    static let readStateSchemaVersion = 10
    static let legacySchemaVersion = 4

    let schemaVersion: Int
    let exportedAt: Date
    var conversations: [AyaneConversationExport]
    var events: [AyaneEventExport]
    var memories: [AyaneMemoryExport]
    var evidence: [AyaneEvidenceExport]
    var summaries: [AyaneSummaryExport]
    var tombstones: [AyaneTombstoneExport]
    /// All logical profiles in the snapshot. A v6 writer always emits this
    /// collection, while v4/v5 readers synthesize it from `persona`.
    var profiles: [AyanePersonaExport]
    /// A compatibility projection retained for v4/v5 consumers. Writers use
    /// the legacy-role profile when present, otherwise the deterministic first
    /// profile, so older readers still receive one useful persona.
    var persona: AyanePersonaExport
    /// Relationship state is exported separately from profiles so a profile
    /// can remain backward-compatible with v4-v6 readers.
    var relationships: [AyaneRelationshipExport]
    /// Durable friend applications are independent from relationship state.
    var friendApplications: [AyaneFriendApplicationExport]
    /// Transition rows are append-only audit records and are never rewritten
    /// during import/merge when their identity conflicts.
    var transitions: [AyaneRelationshipTransitionExport]
    /// Scheduled/published 朋友圈 tasks.  This is intentionally a flat
    /// collection so old readers can ignore the key and old writers can be
    /// imported with an empty task set.
    var momentTasks: [AyaneMomentTaskExport]
    /// The local user's account-level profile. This is a singleton in storage;
    /// it is optional in the wire format for v4-v8 compatibility.
    var userProfile: AyaneUserProfileExport?
    /// Durable Moments posts and interactions. Older backups simply omit both
    /// arrays and are normalized to empty collections on import.
    var momentPosts: [AyaneMomentPostExport]
    var momentInteractions: [AyaneMomentInteractionExport]
    /// Read cursors are display metadata, separate from immutable events/posts.
    var conversationReadStates: [AyaneConversationReadStateExport]
    var momentReadStates: [AyaneMomentReadStateExport]
    /// Durable AI-generated likes/comments/replies. Older backups omit this
    /// key and are normalized to an empty collection.
    var momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport]
    /// Compatibility projection of the default world. New writers emit this
    /// alongside `worldProfiles`; old readers can continue consuming one
    /// world without knowing the collection exists.
    var worldProfile: AyaneWorldProfileExport
    /// All logical worlds in the snapshot. v4-v16 backups synthesize this from
    /// the singular compatibility projection during decoding.
    var worldProfiles: [AyaneWorldProfileExport]
    var groupConversations: [AyaneGroupConversationExport]
    var groupParticipants: [AyaneGroupParticipantExport]
    var chatTurnPresentations: [AyaneChatTurnPresentationExport]
    var proactiveMessageTasks: [AyaneProactiveMessageTaskExport]
    let settings: AyaneSettingsExport

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case conversations
        case events
        case memories
        case evidence
        case summaries
        case tombstones
        case profiles
        case persona
        case relationships
        case friendApplications = "friend_applications"
        case transitions
        case momentTasks = "moment_tasks"
        case userProfile = "user_profile"
        case momentPosts = "moment_posts"
        case momentInteractions = "moment_interactions"
        case conversationReadStates = "conversation_read_states"
        case momentReadStates = "moment_read_states"
        case momentAIInteractionTasks = "moment_ai_interaction_tasks"
        case worldProfile = "world_profile"
        case worldProfiles = "world_profiles"
        case groupConversations = "group_conversations"
        case groupParticipants = "group_participants"
        case chatTurnPresentations = "chat_turn_presentations"
        case proactiveMessageTasks = "proactive_message_tasks"
        case settings
    }

    init(
        schemaVersion: Int = AyaneDataExport.currentSchemaVersion,
        exportedAt: Date = Date(),
        conversations: [AyaneConversationExport],
        events: [AyaneEventExport],
        memories: [AyaneMemoryExport],
        evidence: [AyaneEvidenceExport],
        summaries: [AyaneSummaryExport],
        tombstones: [AyaneTombstoneExport],
        persona: AyanePersonaExport,
        settings: AyaneSettingsExport,
        profiles: [AyanePersonaExport]? = nil,
        relationships: [AyaneRelationshipExport] = [],
        friendApplications: [AyaneFriendApplicationExport] = [],
        transitions: [AyaneRelationshipTransitionExport] = [],
        momentTasks: [AyaneMomentTaskExport] = [],
        userProfile: AyaneUserProfileExport? = nil,
        momentPosts: [AyaneMomentPostExport] = [],
        momentInteractions: [AyaneMomentInteractionExport] = [],
        conversationReadStates: [AyaneConversationReadStateExport] = [],
        momentReadStates: [AyaneMomentReadStateExport] = [],
        momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport] = [],
        momentInteractionTasks: [AyaneMomentAIInteractionTaskExport]? = nil,
        worldProfile: AyaneWorldProfileExport = .realityDefault,
        worldProfiles: [AyaneWorldProfileExport]? = nil,
        groupConversations: [AyaneGroupConversationExport] = [],
        groupParticipants: [AyaneGroupParticipantExport] = [],
        chatTurnPresentations: [AyaneChatTurnPresentationExport] = [],
        proactiveMessageTasks: [AyaneProactiveMessageTaskExport] = []
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.conversations = conversations
        self.events = events
        self.memories = memories
        self.evidence = evidence
        self.summaries = summaries
        self.tombstones = tombstones
        self.profiles = profiles ?? [persona]
        self.persona = persona
        self.relationships = relationships
        self.friendApplications = friendApplications
        self.transitions = transitions
        self.momentTasks = momentTasks
        self.userProfile = userProfile
        self.momentPosts = momentPosts
        self.momentInteractions = momentInteractions
        self.conversationReadStates = conversationReadStates
        self.momentReadStates = momentReadStates
        self.momentAIInteractionTasks = momentInteractionTasks ?? momentAIInteractionTasks
        let resolvedWorlds: [AyaneWorldProfileExport]
        if let worldProfiles, !worldProfiles.isEmpty {
            resolvedWorlds = worldProfiles
        } else {
            resolvedWorlds = [worldProfile]
        }
        let canonicalWorlds = SchemaV11DataSupport.canonicalWorldProfiles(resolvedWorlds)
        self.worldProfiles = canonicalWorlds.isEmpty ? [.realityDefault] : canonicalWorlds
        self.worldProfile = Self.compatibilityWorld(from: self.worldProfiles)
        self.groupConversations = groupConversations
        self.groupParticipants = groupParticipants
        self.chatTurnPresentations = chatTurnPresentations
        self.proactiveMessageTasks = proactiveMessageTasks
        self.settings = settings
    }

    /// v6 convenience initializer for callers that have only a profile list.
    /// The compatibility persona is selected deterministically by the same
    /// rule used by `DataExportService`.
    init(
        schemaVersion: Int = AyaneDataExport.currentSchemaVersion,
        exportedAt: Date = Date(),
        conversations: [AyaneConversationExport],
        events: [AyaneEventExport],
        memories: [AyaneMemoryExport],
        evidence: [AyaneEvidenceExport],
        summaries: [AyaneSummaryExport],
        tombstones: [AyaneTombstoneExport],
        profiles: [AyanePersonaExport],
        settings: AyaneSettingsExport,
        relationships: [AyaneRelationshipExport] = [],
        friendApplications: [AyaneFriendApplicationExport] = [],
        transitions: [AyaneRelationshipTransitionExport] = [],
        momentTasks: [AyaneMomentTaskExport] = [],
        userProfile: AyaneUserProfileExport? = nil,
        momentPosts: [AyaneMomentPostExport] = [],
        momentInteractions: [AyaneMomentInteractionExport] = [],
        conversationReadStates: [AyaneConversationReadStateExport] = [],
        momentReadStates: [AyaneMomentReadStateExport] = [],
        momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport] = [],
        momentInteractionTasks: [AyaneMomentAIInteractionTaskExport]? = nil,
        worldProfile: AyaneWorldProfileExport = .realityDefault,
        worldProfiles: [AyaneWorldProfileExport]? = nil,
        groupConversations: [AyaneGroupConversationExport] = [],
        groupParticipants: [AyaneGroupParticipantExport] = [],
        chatTurnPresentations: [AyaneChatTurnPresentationExport] = [],
        proactiveMessageTasks: [AyaneProactiveMessageTaskExport] = []
    ) {
        let compatibilityPersona = profiles.first {
            $0.roleID == RoleScope.legacyRoleID
        } ?? profiles.first ?? AyanePersonaExport(
            name: "绫音",
            userName: "你",
            prompt: SettingsStore.defaultPersonaPrompt,
            roleID: RoleScope.legacyRoleID
        )
        self.init(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            conversations: conversations,
            events: events,
            memories: memories,
            evidence: evidence,
            summaries: summaries,
            tombstones: tombstones,
            persona: compatibilityPersona,
            settings: settings,
            profiles: profiles,
            relationships: relationships,
            friendApplications: friendApplications,
            transitions: transitions,
            momentTasks: momentTasks,
            userProfile: userProfile,
            momentPosts: momentPosts,
            momentInteractions: momentInteractions,
            conversationReadStates: conversationReadStates,
            momentReadStates: momentReadStates,
            momentAIInteractionTasks: momentInteractionTasks ?? momentAIInteractionTasks,
            worldProfile: worldProfile,
            worldProfiles: worldProfiles,
            groupConversations: groupConversations,
            groupParticipants: groupParticipants,
            chatTurnPresentations: chatTurnPresentations,
            proactiveMessageTasks: proactiveMessageTasks
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        conversations = try container.decode([AyaneConversationExport].self, forKey: .conversations)
        events = try container.decode([AyaneEventExport].self, forKey: .events)
        memories = try container.decode([AyaneMemoryExport].self, forKey: .memories)
        evidence = try container.decode([AyaneEvidenceExport].self, forKey: .evidence)
        summaries = try container.decode([AyaneSummaryExport].self, forKey: .summaries)
        tombstones = try container.decode([AyaneTombstoneExport].self, forKey: .tombstones)
        let decodedPersona = try container.decodeIfPresent(
            AyanePersonaExport.self,
            forKey: .persona
        )
        let decodedProfiles = try container.decodeIfPresent(
            [AyanePersonaExport].self,
            forKey: .profiles
        )
        guard let compatibilityPersona = decodedPersona ?? decodedProfiles?.first else {
            throw DecodingError.keyNotFound(
                CodingKeys.persona,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "backup must contain persona or profiles"
                )
            )
        }
        profiles = decodedProfiles ?? [compatibilityPersona]
        persona = decodedPersona ?? profiles.first ?? compatibilityPersona
        // v4/v5/v6 payloads predate these keys. Treat omission as an empty
        // collection; `DataImportService` performs the accepted-relation
        // compatibility synthesis before validating/restoring them.
        relationships = try container.decodeIfPresent(
            [AyaneRelationshipExport].self,
            forKey: .relationships
        ) ?? []
        friendApplications = try container.decodeIfPresent(
            [AyaneFriendApplicationExport].self,
            forKey: .friendApplications
        ) ?? []
        transitions = try container.decodeIfPresent(
            [AyaneRelationshipTransitionExport].self,
            forKey: .transitions
        ) ?? []
        // v4-v15 payloads predate or omit the current task metadata. Missing
        // data is deliberately an empty collection rather than a decoding
        // failure.
        momentTasks = try container.decodeIfPresent(
            [AyaneMomentTaskExport].self,
            forKey: .momentTasks
        ) ?? []
        userProfile = try container.decodeIfPresent(
            AyaneUserProfileExport.self,
            forKey: .userProfile
        )
        momentPosts = try container.decodeIfPresent(
            [AyaneMomentPostExport].self,
            forKey: .momentPosts
        ) ?? []
        momentInteractions = try container.decodeIfPresent(
            [AyaneMomentInteractionExport].self,
            forKey: .momentInteractions
        ) ?? []
        // v4-v9 payloads predate read cursors. Missing keys intentionally mean
        // no imported cursor; AppModel establishes an initial read baseline
        // after a legacy restore so old history does not become unread.
        conversationReadStates = try container.decodeIfPresent(
            [AyaneConversationReadStateExport].self,
            forKey: .conversationReadStates
        ) ?? []
        momentReadStates = try container.decodeIfPresent(
            [AyaneMomentReadStateExport].self,
            forKey: .momentReadStates
        ) ?? []
        momentAIInteractionTasks = try container.decodeIfPresent(
            [AyaneMomentAIInteractionTaskExport].self,
            forKey: .momentAIInteractionTasks
        ) ?? []
        let decodedWorldProfile = try container.decodeIfPresent(
            AyaneWorldProfileExport.self,
            forKey: .worldProfile
        )
        let decodedWorldProfiles = try container.decodeIfPresent(
            [AyaneWorldProfileExport].self,
            forKey: .worldProfiles
        )
        let resolvedWorlds: [AyaneWorldProfileExport]
        if let decodedWorldProfiles, !decodedWorldProfiles.isEmpty {
            resolvedWorlds = decodedWorldProfiles
        } else {
            resolvedWorlds = [decodedWorldProfile ?? .realityDefault]
        }
        let canonicalWorlds = SchemaV11DataSupport.canonicalWorldProfiles(resolvedWorlds)
        worldProfiles = canonicalWorlds.isEmpty ? [.realityDefault] : canonicalWorlds
        worldProfile = Self.compatibilityWorld(from: worldProfiles)
        groupConversations = try container.decodeIfPresent(
            [AyaneGroupConversationExport].self,
            forKey: .groupConversations
        ) ?? []
        groupParticipants = try container.decodeIfPresent(
            [AyaneGroupParticipantExport].self,
            forKey: .groupParticipants
        ) ?? []
        chatTurnPresentations = try container.decodeIfPresent(
            [AyaneChatTurnPresentationExport].self,
            forKey: .chatTurnPresentations
        ) ?? []
        proactiveMessageTasks = try container.decodeIfPresent(
            [AyaneProactiveMessageTaskExport].self,
            forKey: .proactiveMessageTasks
        ) ?? []
        settings = try container.decode(AyaneSettingsExport.self, forKey: .settings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(conversations, forKey: .conversations)
        try container.encode(events, forKey: .events)
        try container.encode(memories, forKey: .memories)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(summaries, forKey: .summaries)
        try container.encode(tombstones, forKey: .tombstones)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(persona, forKey: .persona)
        try container.encode(relationships, forKey: .relationships)
        try container.encode(friendApplications, forKey: .friendApplications)
        try container.encode(transitions, forKey: .transitions)
        try container.encode(momentTasks, forKey: .momentTasks)
        try container.encodeIfPresent(userProfile, forKey: .userProfile)
        try container.encode(momentPosts, forKey: .momentPosts)
        try container.encode(momentInteractions, forKey: .momentInteractions)
        try container.encode(conversationReadStates, forKey: .conversationReadStates)
        try container.encode(momentReadStates, forKey: .momentReadStates)
        try container.encode(momentAIInteractionTasks, forKey: .momentAIInteractionTasks)
        try container.encode(worldProfile, forKey: .worldProfile)
        try container.encode(worldProfiles, forKey: .worldProfiles)
        try container.encode(groupConversations, forKey: .groupConversations)
        try container.encode(groupParticipants, forKey: .groupParticipants)
        try container.encode(chatTurnPresentations, forKey: .chatTurnPresentations)
        try container.encode(proactiveMessageTasks, forKey: .proactiveMessageTasks)
        try container.encode(settings, forKey: .settings)
    }

    /// Compatibility projection for callers that use the shorter collection
    /// name. The wire format keeps one canonical key to avoid duplicate data.
    var momentInteractionTasks: [AyaneMomentAIInteractionTaskExport] {
        get { momentAIInteractionTasks }
        set { momentAIInteractionTasks = newValue }
    }

    private static func compatibilityWorld(
        from worlds: [AyaneWorldProfileExport]
    ) -> AyaneWorldProfileExport {
        worlds.first(where: { $0.id == WorldProfileRecord.realityID })
            ?? worlds.first
            ?? .realityDefault
    }
}

struct AyaneConversationExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archived
    }

    init(_ record: ConversationRecord) {
        self.init(
            record,
            title: record.title,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            archived: record.archived,
            roleID: record.resolvedRoleID
        )
    }

    init(
        _ record: ConversationRecord,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        archived: Bool,
        roleID: UUID? = nil
    ) {
        id = record.id
        self.roleID = roleID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }
}

struct AyaneEventExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let conversationID: UUID
    let deviceID: String
    let deviceSequence: Int
    let logicalTimestamp: String
    let occurredAt: Date
    let recordedAt: Date
    let role: String
    let roleRaw: String
    let content: String
    let contentHash: String
    /// v11-v15 message payload metadata. Text continues to use the legacy
    /// `content`/`content_hash` columns; sticker, image, and file messages add
    /// their structured payload values alongside those legacy columns.
    var payloadKind: String = MessagePayloadKind.text.rawValue
    var payloadKindRaw: String = MessagePayloadKind.text.rawValue
    var stickerID: String = ""
    var imageData: Data? = nil
    var fileName: String = ""
    var fileTypeIdentifier: String = ""
    var fileData: Data? = nil
    var senderRoleID: UUID? = nil
    let parentEventID: UUID?
    let deliveryState: String
    let deliveryStateRaw: String
    let redacted: Bool
    let memoryProcessedAt: Date?
    let memoryProcessingVersion: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case conversationID = "conversation_id"
        case deviceID = "device_id"
        case deviceSequence = "device_sequence"
        case logicalTimestamp = "logical_timestamp"
        case occurredAt = "occurred_at"
        case recordedAt = "recorded_at"
        case role
        case roleRaw = "role_raw"
        case content
        case contentHash = "content_hash"
        case payloadKind = "payload_kind"
        case payloadKindRaw = "payload_kind_raw"
        case stickerID = "sticker_id"
        case imageData = "image_data"
        case fileName = "file_name"
        case fileTypeIdentifier = "file_type_identifier"
        case fileData = "file_data"
        case senderRoleID = "sender_role_id"
        case parentEventID = "parent_event_id"
        case deliveryState = "delivery_state"
        case deliveryStateRaw = "delivery_state_raw"
        case redacted
        case memoryProcessedAt = "memory_processed_at"
        case memoryProcessingVersion = "memory_processing_version"
    }

    init(_ record: ConversationEvent) {
        self.init(
            record,
            occurredAt: record.occurredAt,
            recordedAt: record.recordedAt,
            deliveryStateRaw: record.deliveryStateRaw,
            redacted: record.redacted,
            memoryProcessedAt: record.memoryProcessedAt,
            memoryProcessingVersion: record.memoryProcessingVersion,
            roleID: record.resolvedRoleID,
            payloadKind: record.payloadKindRaw,
            payloadKindRaw: record.payloadKindRaw,
            stickerID: record.stickerID,
            senderRoleID: record.senderRoleID,
            imageData: record.imageData,
            fileName: record.fileName,
            fileTypeIdentifier: record.fileTypeIdentifier,
            fileData: record.fileData
        )
    }

    init(
        _ record: ConversationEvent,
        occurredAt: Date,
        recordedAt: Date,
        deliveryStateRaw: String,
        redacted: Bool,
        memoryProcessedAt: Date?,
        memoryProcessingVersion: Int,
        roleID: UUID? = nil,
        payloadKind: String = MessagePayloadKind.text.rawValue,
        payloadKindRaw: String? = nil,
        stickerID: String = "",
        senderRoleID: UUID? = nil,
        imageData: Data? = nil,
        fileName: String = "",
        fileTypeIdentifier: String = "",
        fileData: Data? = nil
    ) {
        id = record.id
        self.roleID = roleID
        conversationID = record.conversationID
        deviceID = record.deviceID
        deviceSequence = record.deviceSequence
        logicalTimestamp = record.logicalTimestamp
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        role = record.role.rawValue
        roleRaw = record.roleRaw
        content = record.content
        contentHash = record.contentHash
        self.payloadKind = payloadKind
        self.payloadKindRaw = payloadKindRaw ?? payloadKind
        self.stickerID = stickerID
        self.imageData = imageData
        self.fileName = fileName
        self.fileTypeIdentifier = fileTypeIdentifier
        self.fileData = fileData
        self.senderRoleID = senderRoleID
        parentEventID = record.parentEventID
        deliveryState = deliveryStateRaw
        self.deliveryStateRaw = deliveryStateRaw
        self.redacted = redacted
        self.memoryProcessedAt = memoryProcessedAt
        self.memoryProcessingVersion = memoryProcessingVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        conversationID = try container.decode(UUID.self, forKey: .conversationID)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        deviceSequence = try container.decodeIfPresent(Int.self, forKey: .deviceSequence) ?? 0
        logicalTimestamp = try container.decodeIfPresent(String.self, forKey: .logicalTimestamp) ?? ""
        occurredAt = try container.decodeIfPresent(Date.self, forKey: .occurredAt) ?? Self.legacyEpoch
        recordedAt = try container.decodeIfPresent(Date.self, forKey: .recordedAt) ?? occurredAt
        roleRaw = try container.decodeIfPresent(String.self, forKey: .roleRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .role))
            ?? EventRole.user.rawValue
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? roleRaw
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash) ?? ""
        payloadKindRaw = try container.decodeIfPresent(String.self, forKey: .payloadKindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .payloadKind))
            ?? MessagePayloadKind.text.rawValue
        payloadKind = try container.decodeIfPresent(String.self, forKey: .payloadKind) ?? payloadKindRaw
        stickerID = try container.decodeIfPresent(String.self, forKey: .stickerID) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileTypeIdentifier = try container.decodeIfPresent(String.self, forKey: .fileTypeIdentifier) ?? ""
        fileData = try container.decodeIfPresent(Data.self, forKey: .fileData)
        senderRoleID = try container.decodeIfPresent(UUID.self, forKey: .senderRoleID)
        parentEventID = try container.decodeIfPresent(UUID.self, forKey: .parentEventID)
        deliveryStateRaw = try container.decodeIfPresent(String.self, forKey: .deliveryStateRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .deliveryState))
            ?? EventDeliveryState.complete.rawValue
        deliveryState = try container.decodeIfPresent(String.self, forKey: .deliveryState)
            ?? deliveryStateRaw
        redacted = try container.decodeIfPresent(Bool.self, forKey: .redacted) ?? false
        memoryProcessedAt = try container.decodeIfPresent(Date.self, forKey: .memoryProcessedAt)
        memoryProcessingVersion = try container.decodeIfPresent(Int.self, forKey: .memoryProcessingVersion) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(deviceSequence, forKey: .deviceSequence)
        try container.encode(logicalTimestamp, forKey: .logicalTimestamp)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(recordedAt, forKey: .recordedAt)
        try container.encode(role, forKey: .role)
        try container.encode(roleRaw, forKey: .roleRaw)
        try container.encode(content, forKey: .content)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(payloadKind, forKey: .payloadKind)
        try container.encode(payloadKindRaw, forKey: .payloadKindRaw)
        try container.encode(stickerID, forKey: .stickerID)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(fileTypeIdentifier, forKey: .fileTypeIdentifier)
        try container.encodeIfPresent(fileData, forKey: .fileData)
        try container.encodeIfPresent(senderRoleID, forKey: .senderRoleID)
        try container.encodeIfPresent(parentEventID, forKey: .parentEventID)
        try container.encode(deliveryState, forKey: .deliveryState)
        try container.encode(deliveryStateRaw, forKey: .deliveryStateRaw)
        try container.encode(redacted, forKey: .redacted)
        try container.encodeIfPresent(memoryProcessedAt, forKey: .memoryProcessedAt)
        try container.encode(memoryProcessingVersion, forKey: .memoryProcessingVersion)
    }

    private static let legacyEpoch = Date(timeIntervalSince1970: 0)
}

struct AyaneConversationReadStateExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let conversationID: UUID
    let lastReadOccurredAt: Date?
    let lastReadLogicalTimestamp: String
    let lastReadEventID: UUID?
    let updatedAt: Date
    let revision: Int
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case conversationID = "conversation_id"
        case lastReadOccurredAt = "last_read_occurred_at"
        case lastReadLogicalTimestamp = "last_read_logical_timestamp"
        case lastReadEventID = "last_read_event_id"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(_ record: ConversationReadStateRecord) {
        id = record.id
        roleID = record.resolvedRoleID
        conversationID = record.conversationID
        lastReadOccurredAt = record.lastReadOccurredAt
        lastReadLogicalTimestamp = record.lastReadLogicalTimestamp
        lastReadEventID = record.lastReadEventID
        updatedAt = record.updatedAt
        revision = record.revision
        deviceID = record.deviceID
    }

    init(
        id: UUID,
        roleID: UUID? = nil,
        conversationID: UUID,
        lastReadOccurredAt: Date?,
        lastReadLogicalTimestamp: String,
        lastReadEventID: UUID?,
        updatedAt: Date,
        revision: Int,
        deviceID: String
    ) {
        self.id = id
        self.roleID = roleID
        self.conversationID = conversationID
        self.lastReadOccurredAt = lastReadOccurredAt
        self.lastReadLogicalTimestamp = lastReadLogicalTimestamp
        self.lastReadEventID = lastReadEventID
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }
}

struct AyaneMomentReadStateExport: Codable, Equatable, Sendable {
    let id: UUID
    let postID: UUID
    let lastReadCreatedAt: Date?
    let lastReadInteractionID: UUID?
    let updatedAt: Date
    let revision: Int
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case lastReadCreatedAt = "last_read_created_at"
        case lastReadInteractionID = "last_read_interaction_id"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(_ record: MomentReadStateRecord) {
        id = record.id
        postID = record.postID
        lastReadCreatedAt = record.lastReadCreatedAt
        lastReadInteractionID = record.lastReadInteractionID
        updatedAt = record.updatedAt
        revision = record.revision
        deviceID = record.deviceID
    }

    init(
        id: UUID,
        postID: UUID,
        lastReadCreatedAt: Date?,
        lastReadInteractionID: UUID?,
        updatedAt: Date,
        revision: Int,
        deviceID: String
    ) {
        self.id = id
        self.postID = postID
        self.lastReadCreatedAt = lastReadCreatedAt
        self.lastReadInteractionID = lastReadInteractionID
        self.updatedAt = updatedAt
        self.revision = revision
        self.deviceID = deviceID
    }
}

struct AyaneMemoryExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let kind: String
    let kindRaw: String
    let subject: String
    let predicate: String
    let value: String
    let canonicalKey: String
    let state: String
    let stateRaw: String
    let confidence: Double
    let importance: Double
    let sensitive: Bool
    let sourceRank: Int
    let validFrom: Date?
    let validTo: Date?
    let observedAt: Date
    let supersedesID: UUID?
    let extractorID: String
    let schemaVersion: Int
    let createdAt: Date
    let updatedAt: Date
    let isPinned: Bool
    let userVerified: Bool
    let embeddingBase64: String?
    let embeddingModelID: String?
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case kind
        case kindRaw = "kind_raw"
        case subject
        case predicate
        case value
        case canonicalKey = "canonical_key"
        case state
        case stateRaw = "state_raw"
        case confidence
        case importance
        case sensitive
        case sourceRank = "source_rank"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case observedAt = "observed_at"
        case supersedesID = "supersedes_id"
        case extractorID = "extractor_id"
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPinned = "is_pinned"
        case userVerified = "user_verified"
        case embeddingBase64 = "embedding_base64"
        case embeddingModelID = "embedding_model_id"
        case deviceID = "device_id"
    }

    init(_ record: MemoryAssertionRecord) {
        self.init(
            record,
            stateRaw: record.stateRaw,
            confidence: record.confidence,
            importance: record.importance,
            sensitive: record.sensitive,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isPinned: record.isPinned,
            userVerified: record.userVerified,
            embeddingData: record.embeddingData,
            embeddingModelID: record.embeddingModelID,
            roleID: record.resolvedRoleID
        )
    }

    init(
        _ record: MemoryAssertionRecord,
        stateRaw: String,
        confidence: Double,
        importance: Double,
        sensitive: Bool,
        createdAt: Date,
        updatedAt: Date,
        isPinned: Bool,
        userVerified: Bool,
        embeddingData: Data?,
        embeddingModelID: String?,
        roleID: UUID? = nil
    ) {
        id = record.id
        self.roleID = roleID
        kind = record.kind.rawValue
        kindRaw = record.kindRaw
        subject = record.subject
        predicate = record.predicate
        value = record.value
        canonicalKey = record.canonicalKey
        state = stateRaw
        self.stateRaw = stateRaw
        self.confidence = confidence
        self.importance = importance
        self.sensitive = sensitive
        sourceRank = record.sourceRank
        validFrom = record.validFrom
        validTo = record.validTo
        observedAt = record.observedAt
        supersedesID = record.supersedesID
        extractorID = record.extractorID
        schemaVersion = record.schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.userVerified = userVerified
        embeddingBase64 = embeddingData?.base64EncodedString()
        self.embeddingModelID = embeddingModelID
        deviceID = record.deviceID
    }
}

struct AyaneEvidenceExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let memoryID: UUID
    let eventID: UUID
    let startUTF16: Int
    let endUTF16: Int
    let relation: String
    let relationRaw: String
    let quoteHash: String
    let confidence: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case memoryID = "memory_id"
        case eventID = "event_id"
        case startUTF16 = "start_utf16"
        case endUTF16 = "end_utf16"
        case relation
        case relationRaw = "relation_raw"
        case quoteHash = "quote_hash"
        case confidence
        case createdAt = "created_at"
    }

    init(_ record: MemoryEvidenceRecord) {
        self.init(
            record,
            confidence: record.confidence,
            createdAt: record.createdAt,
            roleID: record.resolvedRoleID
        )
    }

    init(
        _ record: MemoryEvidenceRecord,
        confidence: Double,
        createdAt: Date,
        roleID: UUID? = nil
    ) {
        id = record.id
        self.roleID = roleID
        memoryID = record.memoryID
        eventID = record.eventID
        startUTF16 = record.startUTF16
        endUTF16 = record.endUTF16
        relation = record.relationRaw
        relationRaw = record.relationRaw
        quoteHash = record.quoteHash
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

struct AyaneSummaryExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let conversationID: UUID
    let scope: String
    let content: String
    let firstEventID: UUID?
    let lastEventID: UUID?
    let coveredEventCount: Int
    let extractorID: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case conversationID = "conversation_id"
        case scope
        case content
        case firstEventID = "first_event_id"
        case lastEventID = "last_event_id"
        case coveredEventCount = "covered_event_count"
        case extractorID = "extractor_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(_ record: MemorySummaryRecord) {
        id = record.id
        roleID = record.resolvedRoleID
        conversationID = record.conversationID
        scope = record.scope
        content = record.content
        firstEventID = record.firstEventID
        lastEventID = record.lastEventID
        coveredEventCount = record.coveredEventCount
        extractorID = record.extractorID
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }
}

struct AyaneTombstoneExport: Codable, Equatable, Sendable {
    let id: UUID
    var roleID: UUID? = nil
    let entityID: UUID
    let entityType: String
    let canonicalKey: String
    let sourceEventIDs: [UUID]
    let deletedAt: Date
    let deviceID: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case entityID = "entity_id"
        case entityType = "entity_type"
        case canonicalKey = "canonical_key"
        case sourceEventIDs = "source_event_ids"
        case deletedAt = "deleted_at"
        case deviceID = "device_id"
        case reason
    }

    init(_ record: MemoryTombstoneRecord) {
        self.init(
            record,
            sourceEventIDs: record.sourceEventIDs,
            deletedAt: record.deletedAt,
            roleID: record.resolvedRoleID
        )
    }

    init(
        _ record: MemoryTombstoneRecord,
        sourceEventIDs: [UUID],
        deletedAt: Date,
        roleID: UUID? = nil
    ) {
        id = record.id
        self.roleID = roleID
        entityID = record.entityID
        entityType = record.entityType
        canonicalKey = record.canonicalKey
        self.sourceEventIDs = sourceEventIDs
        self.deletedAt = deletedAt
        deviceID = record.deviceID
        reason = record.reason
    }
}

struct AyanePersonaExport: Codable, Equatable, Sendable {
    static let singletonID = UUID(uuidString: "8D5DFB45-198D-4B74-B1F1-4C9C7A8248A1")!
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    let id: UUID
    var roleID: UUID? = nil
    var worldProfileID: UUID = WorldProfileRecord.realityID
    let name: String
    let userName: String
    let prompt: String
    let birthdayMonth: Int?
    let birthdayDay: Int?
    let avatarImageData: Data?
    let chatBackgroundImageData: Data?
    let createdAt: Date
    let updatedAt: Date
    let revision: Int
    let deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case worldProfileID = "world_profile_id"
        case name
        case userName = "user_name"
        case prompt
        case birthdayMonth = "birthday_month"
        case birthdayDay = "birthday_day"
        case avatarImageData = "avatar_image_data"
        case chatBackgroundImageData = "chat_background_image_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        name: String,
        userName: String,
        prompt: String,
        id: UUID = AyanePersonaExport.singletonID,
        createdAt: Date = AyanePersonaExport.legacyEpoch,
        updatedAt: Date = AyanePersonaExport.legacyEpoch,
        revision: Int = 0,
        deviceID: String = "",
        roleID: UUID? = nil,
        worldProfileID: UUID = WorldProfileRecord.realityID,
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        avatarImageData: Data? = nil,
        chatBackgroundImageData: Data? = nil
    ) {
        self.id = id
        self.roleID = roleID
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

    init(
        _ configuration: PersonaConfiguration,
        id: UUID = AyanePersonaExport.singletonID,
        createdAt: Date = AyanePersonaExport.legacyEpoch,
        updatedAt: Date = AyanePersonaExport.legacyEpoch,
        revision: Int = 0,
        deviceID: String = "",
        roleID: UUID? = nil,
        worldProfileID: UUID = WorldProfileRecord.realityID
    ) {
        self.init(
            name: configuration.name,
            userName: configuration.userName,
            prompt: configuration.prompt,
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: revision,
            deviceID: deviceID,
            roleID: roleID,
            worldProfileID: worldProfileID,
            birthdayMonth: configuration.birthdayMonth,
            birthdayDay: configuration.birthdayDay,
            avatarImageData: configuration.avatarImageData,
            chatBackgroundImageData: configuration.chatBackgroundImageData
        )
    }

    init(_ profile: CompanionProfileRecord) {
        self.init(
            name: profile.name,
            userName: profile.userName,
            prompt: profile.prompt,
            id: profile.id,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt,
            revision: profile.revision,
            deviceID: profile.deviceID,
            roleID: profile.roleID,
            worldProfileID: profile.worldProfileID,
            birthdayMonth: profile.birthdayMonth,
            birthdayDay: profile.birthdayDay,
            avatarImageData: profile.avatarImageData,
            chatBackgroundImageData: profile.chatBackgroundImageData
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.singletonID
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        worldProfileID = try container.decodeIfPresent(UUID.self, forKey: .worldProfileID)
            ?? WorldProfileRecord.realityID
        name = try container.decode(String.self, forKey: .name)
        userName = try container.decode(String.self, forKey: .userName)
        prompt = try container.decode(String.self, forKey: .prompt)
        birthdayMonth = try container.decodeIfPresent(Int.self, forKey: .birthdayMonth)
        birthdayDay = try container.decodeIfPresent(Int.self, forKey: .birthdayDay)
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        chatBackgroundImageData = try container.decodeIfPresent(Data.self, forKey: .chatBackgroundImageData)
        // Schema v4 did not carry profile identity or revision metadata. Keep
        // its normalization deterministic so the same legacy JSON always
        // produces the same canonical profile.
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Self.legacyEpoch
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encode(worldProfileID, forKey: .worldProfileID)
        try container.encode(name, forKey: .name)
        try container.encode(userName, forKey: .userName)
        try container.encode(prompt, forKey: .prompt)
        try container.encodeIfPresent(birthdayMonth, forKey: .birthdayMonth)
        try container.encodeIfPresent(birthdayDay, forKey: .birthdayDay)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

/// Codable projection of the local user's singleton profile. This is kept
/// separate from the companion persona because it is the author identity for
/// user-created Moments and owns the Moments cover artwork.
struct AyaneUserProfileExport: Codable, Equatable, Sendable {
    static let singletonID = UserProfileRecord.singletonID
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var displayName: String
    var birthdayMonth: Int?
    var birthdayDay: Int?
    var birthdayTimeZoneIdentifier: String
    var avatarImageData: Data?
    var momentsCoverImageData: Data?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case birthdayMonth = "birthday_month"
        case birthdayDay = "birthday_day"
        case birthdayTimeZoneIdentifier = "birthday_timezone_identifier"
        case avatarImageData = "avatar_image_data"
        case momentsCoverImageData = "moments_cover_image_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = AyaneUserProfileExport.singletonID,
        displayName: String = "我",
        birthdayMonth: Int? = nil,
        birthdayDay: Int? = nil,
        birthdayTimeZoneIdentifier: String = TimeZone.current.identifier,
        avatarImageData: Data? = nil,
        momentsCoverImageData: Data? = nil,
        createdAt: Date = AyaneUserProfileExport.legacyEpoch,
        updatedAt: Date = AyaneUserProfileExport.legacyEpoch,
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
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: UserProfileRecord) {
        self.init(
            id: record.id,
            displayName: record.displayName,
            birthdayMonth: record.birthdayMonth,
            birthdayDay: record.birthdayDay,
            birthdayTimeZoneIdentifier: record.birthdayTimeZoneIdentifier,
            avatarImageData: record.avatarImageData,
            momentsCoverImageData: record.momentsCoverImageData,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? Self.singletonID
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? "我"
        birthdayMonth = try container.decodeIfPresent(Int.self, forKey: .birthdayMonth)
        birthdayDay = try container.decodeIfPresent(Int.self, forKey: .birthdayDay)
        birthdayTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .birthdayTimeZoneIdentifier
        ) ?? TimeZone.current.identifier
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        momentsCoverImageData = try container.decodeIfPresent(
            Data.self,
            forKey: .momentsCoverImageData
        )
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Self.legacyEpoch
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(birthdayMonth, forKey: .birthdayMonth)
        try container.encodeIfPresent(birthdayDay, forKey: .birthdayDay)
        try container.encode(birthdayTimeZoneIdentifier, forKey: .birthdayTimeZoneIdentifier)
        try container.encodeIfPresent(avatarImageData, forKey: .avatarImageData)
        try container.encodeIfPresent(momentsCoverImageData, forKey: .momentsCoverImageData)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

/// Codable projection of one durable Moments post. The enum conveniences are
/// backed by raw strings so unknown future values remain visible to validation
/// instead of silently turning into a different post type.
struct AyaneMomentPostExport: Codable, Equatable, Sendable {
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var authorKindRaw: String
    var authorRoleID: UUID?
    var body: String
    var imageData: Data?
    var bundledImageName: String
    var sourceTaskID: UUID?
    var publishedAt: Date
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var revision: Int
    var deviceID: String

    var authorKind: MomentAuthorKind {
        MomentAuthorKind(rawValue: authorKindRaw) ?? .user
    }

    enum CodingKeys: String, CodingKey {
        case id
        case authorKind = "author_kind"
        case authorKindRaw = "author_kind_raw"
        case authorRoleID = "author_role_id"
        case body
        case imageData = "image_data"
        case bundledImageName = "bundled_image_name"
        case sourceTaskID = "source_task_id"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case revision
        case deviceID = "device_id"
    }

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
        self.revision = revision
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        authorKindRaw: String,
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
        self.authorKindRaw = authorKindRaw
        self.authorRoleID = authorRoleID.map(RoleScope.resolve)
        self.body = body
        self.imageData = imageData
        self.bundledImageName = bundledImageName
        self.sourceTaskID = sourceTaskID
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: MomentPostRecord) {
        self.init(
            id: record.id,
            authorKindRaw: record.authorKindRaw,
            authorRoleID: record.authorRoleID,
            body: record.body,
            imageData: record.imageData,
            bundledImageName: record.bundledImageName,
            sourceTaskID: record.sourceTaskID,
            publishedAt: record.publishedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorKindRaw = try container.decodeIfPresent(String.self, forKey: .authorKindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .authorKind))
            ?? MomentAuthorKind.user.rawValue
        authorRoleID = try container.decodeIfPresent(UUID.self, forKey: .authorRoleID)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        bundledImageName = try container.decodeIfPresent(String.self, forKey: .bundledImageName) ?? ""
        sourceTaskID = try container.decodeIfPresent(UUID.self, forKey: .sourceTaskID)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt) ?? Self.legacyEpoch
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(authorKindRaw, forKey: .authorKind)
        try container.encode(authorKindRaw, forKey: .authorKindRaw)
        try container.encodeIfPresent(authorRoleID, forKey: .authorRoleID)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(bundledImageName, forKey: .bundledImageName)
        try container.encodeIfPresent(sourceTaskID, forKey: .sourceTaskID)
        try container.encode(publishedAt, forKey: .publishedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

/// Codable projection of one durable Moments like/comment. Post, kind and
/// actor identity are immutable merge keys; body and revision metadata remain
/// independently mergeable. `deletedAt` is an optional sticky tombstone so
/// pre-v17 payloads remain readable without allowing a stale live copy to
/// resurrect a removed comment.
struct AyaneMomentInteractionExport: Codable, Equatable, Sendable {
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var postID: UUID
    var parentInteractionID: UUID?
    var rootInteractionID: UUID?
    var kindRaw: String
    var actorKindRaw: String
    var actorRoleID: UUID?
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var revision: Int
    var deviceID: String

    var kind: MomentInteractionKind {
        MomentInteractionKind(rawValue: kindRaw) ?? .comment
    }

    var actorKind: MomentAuthorKind {
        MomentAuthorKind(rawValue: actorKindRaw) ?? .user
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case parentInteractionID = "parent_interaction_id"
        case rootInteractionID = "root_interaction_id"
        case kind
        case kindRaw = "kind_raw"
        case actorKind = "actor_kind"
        case actorKindRaw = "actor_kind_raw"
        case actorRoleID = "actor_role_id"
        case body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        postID: UUID,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        kind: MomentInteractionKind,
        actorKind: MomentAuthorKind,
        actorRoleID: UUID? = nil,
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
        self.revision = revision
        self.deviceID = deviceID
    }

    init(
        id: UUID = UUID(),
        postID: UUID,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        kindRaw: String,
        actorKindRaw: String,
        actorRoleID: UUID? = nil,
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
        self.kindRaw = kindRaw
        self.actorKindRaw = actorKindRaw
        self.actorRoleID = actorRoleID.map(RoleScope.resolve)
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.revision = revision
        self.deviceID = deviceID
    }

    init(_ record: MomentInteractionRecord) {
        self.init(
            id: record.id,
            postID: record.postID,
            parentInteractionID: record.parentInteractionID,
            rootInteractionID: record.rootInteractionID,
            kindRaw: record.kindRaw,
            actorKindRaw: record.actorKindRaw,
            actorRoleID: record.actorRoleID,
            body: record.body,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        postID = try container.decode(UUID.self, forKey: .postID)
        parentInteractionID = try container.decodeIfPresent(UUID.self, forKey: .parentInteractionID)
        rootInteractionID = try container.decodeIfPresent(UUID.self, forKey: .rootInteractionID)
        kindRaw = try container.decodeIfPresent(String.self, forKey: .kindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .kind))
            ?? MomentInteractionKind.comment.rawValue
        actorKindRaw = try container.decodeIfPresent(String.self, forKey: .actorKindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .actorKind))
            ?? MomentAuthorKind.user.rawValue
        actorRoleID = try container.decodeIfPresent(UUID.self, forKey: .actorRoleID)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        // Pre-tombstone exports omitted this key; omission is the live state.
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(postID, forKey: .postID)
        try container.encodeIfPresent(parentInteractionID, forKey: .parentInteractionID)
        try container.encodeIfPresent(rootInteractionID, forKey: .rootInteractionID)
        try container.encode(kindRaw, forKey: .kind)
        try container.encode(kindRaw, forKey: .kindRaw)
        try container.encode(actorKindRaw, forKey: .actorKind)
        try container.encode(actorKindRaw, forKey: .actorKindRaw)
        try container.encodeIfPresent(actorRoleID, forKey: .actorRoleID)
        try container.encode(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

/// Codable, keychain-free projection of one relationship state record.
struct AyaneRelationshipExport: Codable, Equatable, Sendable {
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var roleID: UUID
    var stateRaw: String
    var harmStreak: Int
    var hurtScore: Double
    var harmThreshold: Int
    var forgivenessScore: Double
    var forgivenessThreshold: Double
    var affinityScore: Double
    var affinityTier: Int
    var affinityPolicyVersion: Int
    var lastAffinityEventID: UUID?
    var dignity: Double
    var independence: Double
    var boundarySensitivity: Double
    var apologyAttempts: Int
    var policyVersion: Int
    var lastProcessedEventID: UUID?
    var lastTransitionID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String
    var retiredAt: Date?
    var resetAt: Date?
    /// v12 contact metadata is orthogonal to the relationship lifecycle. Old
    /// snapshots omit these keys and decode to the active membership default.
    var contactMembershipRaw: String
    var contactStateUpdatedAt: Date
    var lastUserRemovalID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case stateRaw = "state_raw"
        case harmStreak = "harm_streak"
        case hurtScore = "hurt_score"
        case harmThreshold = "harm_threshold"
        case forgivenessScore = "forgiveness_score"
        case forgivenessThreshold = "forgiveness_threshold"
        case affinityScore = "affinity_score"
        case affinityTier = "affinity_tier"
        case affinityPolicyVersion = "affinity_policy_version"
        case lastAffinityEventID = "last_affinity_event_id"
        case dignity
        case independence
        case boundarySensitivity = "boundary_sensitivity"
        case apologyAttempts = "apology_attempts"
        case policyVersion = "policy_version"
        case lastProcessedEventID = "last_processed_event_id"
        case lastTransitionID = "last_transition_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
        case retiredAt = "retired_at"
        case resetAt = "reset_at"
        case contactMembershipRaw = "contact_membership_raw"
        case contactStateUpdatedAt = "contact_state_updated_at"
        case lastUserRemovalID = "last_user_removal_id"
    }

    init(_ record: CompanionRelationshipRecord) {
        self.init(
            id: record.id,
            roleID: record.roleID,
            stateRaw: record.stateRaw,
            harmStreak: record.harmStreak,
            hurtScore: record.hurtScore,
            harmThreshold: record.harmThreshold,
            forgivenessScore: record.forgivenessScore,
            forgivenessThreshold: record.forgivenessThreshold,
            affinityScore: record.affinityScore,
            affinityTier: record.affinityTier,
            affinityPolicyVersion: record.affinityPolicyVersion,
            lastAffinityEventID: record.lastAffinityEventID,
            dignity: record.dignity,
            independence: record.independence,
            boundarySensitivity: record.boundarySensitivity,
            apologyAttempts: record.apologyAttempts,
            policyVersion: record.policyVersion,
            lastProcessedEventID: record.lastProcessedEventID,
            lastTransitionID: record.lastTransitionID,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID,
            retiredAt: record.retiredAt,
            resetAt: record.resetAt,
            contactMembershipRaw: record.contactMembershipRaw,
            contactStateUpdatedAt: record.contactStateUpdatedAt,
            lastUserRemovalID: record.lastUserRemovalID
        )
    }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        stateRaw: String = CompanionRelationshipState.accepted.rawValue,
        harmStreak: Int = 0,
        hurtScore: Double = 0,
        harmThreshold: Int = 3,
        forgivenessScore: Double = 0,
        forgivenessThreshold: Double = 2,
        affinityScore: Double = 0,
        affinityTier: Int = 0,
        affinityPolicyVersion: Int = 1,
        lastAffinityEventID: UUID? = nil,
        dignity: Double = 0.5,
        independence: Double = 0.5,
        boundarySensitivity: Double = 0.5,
        apologyAttempts: Int = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        lastProcessedEventID: UUID? = nil,
        lastTransitionID: UUID? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        updatedAt: Date = Date(timeIntervalSince1970: 0),
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
        self.affinityScore = affinityScore
        self.affinityTier = affinityTier
        self.affinityPolicyVersion = affinityPolicyVersion
        self.lastAffinityEventID = lastAffinityEventID
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
            ?? RoleScope.legacyRoleID
        stateRaw = try container.decodeIfPresent(String.self, forKey: .stateRaw)
            ?? CompanionRelationshipState.accepted.rawValue
        harmStreak = try container.decodeIfPresent(Int.self, forKey: .harmStreak) ?? 0
        hurtScore = try container.decodeIfPresent(Double.self, forKey: .hurtScore) ?? 0
        harmThreshold = try container.decodeIfPresent(Int.self, forKey: .harmThreshold) ?? 3
        forgivenessScore = try container.decodeIfPresent(Double.self, forKey: .forgivenessScore) ?? 0
        forgivenessThreshold = try container.decodeIfPresent(
            Double.self,
            forKey: .forgivenessThreshold
        ) ?? 2
        // These four fields were added in v9. Missing keys in v8 and older
        // snapshots intentionally mean the neutral affinity state.
        affinityScore = try container.decodeIfPresent(Double.self, forKey: .affinityScore) ?? 0
        affinityTier = try container.decodeIfPresent(Int.self, forKey: .affinityTier) ?? 0
        affinityPolicyVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .affinityPolicyVersion
        ) ?? 1
        lastAffinityEventID = try container.decodeIfPresent(UUID.self, forKey: .lastAffinityEventID)
        dignity = try container.decodeIfPresent(Double.self, forKey: .dignity) ?? 0.5
        independence = try container.decodeIfPresent(Double.self, forKey: .independence) ?? 0.5
        boundarySensitivity = try container.decodeIfPresent(
            Double.self,
            forKey: .boundarySensitivity
        ) ?? 0.5
        apologyAttempts = try container.decodeIfPresent(Int.self, forKey: .apologyAttempts) ?? 0
        policyVersion = try container.decodeIfPresent(Int.self, forKey: .policyVersion)
            ?? CompanionRelationshipRecord.currentPolicyVersion
        lastProcessedEventID = try container.decodeIfPresent(UUID.self, forKey: .lastProcessedEventID)
        lastTransitionID = try container.decodeIfPresent(UUID.self, forKey: .lastTransitionID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        retiredAt = try container.decodeIfPresent(Date.self, forKey: .retiredAt)
        resetAt = try container.decodeIfPresent(Date.self, forKey: .resetAt)
        contactMembershipRaw = try container.decodeIfPresent(
            String.self,
            forKey: .contactMembershipRaw
        ) ?? ContactMembershipState.active.rawValue
        contactStateUpdatedAt = try container.decodeIfPresent(
            Date.self,
            forKey: .contactStateUpdatedAt
        ) ?? updatedAt
        lastUserRemovalID = try container.decodeIfPresent(UUID.self, forKey: .lastUserRemovalID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roleID, forKey: .roleID)
        try container.encode(stateRaw, forKey: .stateRaw)
        try container.encode(harmStreak, forKey: .harmStreak)
        try container.encode(hurtScore, forKey: .hurtScore)
        try container.encode(harmThreshold, forKey: .harmThreshold)
        try container.encode(forgivenessScore, forKey: .forgivenessScore)
        try container.encode(forgivenessThreshold, forKey: .forgivenessThreshold)
        try container.encode(affinityScore, forKey: .affinityScore)
        try container.encode(affinityTier, forKey: .affinityTier)
        try container.encode(affinityPolicyVersion, forKey: .affinityPolicyVersion)
        try container.encodeIfPresent(lastAffinityEventID, forKey: .lastAffinityEventID)
        try container.encode(dignity, forKey: .dignity)
        try container.encode(independence, forKey: .independence)
        try container.encode(boundarySensitivity, forKey: .boundarySensitivity)
        try container.encode(apologyAttempts, forKey: .apologyAttempts)
        try container.encode(policyVersion, forKey: .policyVersion)
        try container.encodeIfPresent(lastProcessedEventID, forKey: .lastProcessedEventID)
        try container.encodeIfPresent(lastTransitionID, forKey: .lastTransitionID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encodeIfPresent(retiredAt, forKey: .retiredAt)
        try container.encodeIfPresent(resetAt, forKey: .resetAt)
        try container.encode(contactMembershipRaw, forKey: .contactMembershipRaw)
        try container.encode(contactStateUpdatedAt, forKey: .contactStateUpdatedAt)
        try container.encodeIfPresent(lastUserRemovalID, forKey: .lastUserRemovalID)
    }
}

/// Codable, keychain-free projection of one durable friend application.
/// Scalar raw values are emitted alongside their human-readable compatibility
/// keys so CloudKit and older JSON tooling can consume the same snapshot.
struct AyaneFriendApplicationExport: Codable, Equatable, Sendable {
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var roleID: UUID
    var directionRaw: String
    var purposeRaw: String
    var statusRaw: String
    var message: String
    var scheduledAt: Date
    var createdAt: Date
    var resolvedAt: Date?
    var idempotencyKey: String
    var revision: Int
    var deviceID: String

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

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case direction
        case directionRaw = "direction_raw"
        case purpose
        case purposeRaw = "purpose_raw"
        case status
        case statusRaw = "status_raw"
        case message
        case scheduledAt = "scheduled_at"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
        case idempotencyKey = "idempotency_key"
        case revision
        case deviceID = "device_id"
    }

    init(_ record: FriendApplicationRecord) {
        self.init(
            id: record.id,
            roleID: record.roleID,
            directionRaw: record.directionRaw,
            purposeRaw: record.purposeRaw,
            statusRaw: record.statusRaw,
            message: record.message,
            scheduledAt: record.scheduledAt,
            createdAt: record.createdAt,
            resolvedAt: record.resolvedAt,
            idempotencyKey: record.idempotencyKey,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        direction: FriendApplicationDirection = .outgoing,
        purpose: FriendApplicationPurpose = .newFriend,
        status: FriendApplicationStatus = .pending,
        message: String = "",
        scheduledAt: Date = Date(timeIntervalSince1970: 0),
        createdAt: Date = Date(timeIntervalSince1970: 0),
        resolvedAt: Date? = nil,
        idempotencyKey: String = "",
        revision: Int = 0,
        deviceID: String = ""
    ) {
        self.init(
            id: id,
            roleID: roleID,
            directionRaw: direction.rawValue,
            purposeRaw: purpose.rawValue,
            statusRaw: status.rawValue,
            message: message,
            scheduledAt: scheduledAt,
            createdAt: createdAt,
            resolvedAt: resolvedAt,
            idempotencyKey: idempotencyKey,
            revision: revision,
            deviceID: deviceID
        )
    }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        directionRaw: String,
        purposeRaw: String,
        statusRaw: String,
        message: String = "",
        scheduledAt: Date = Date(timeIntervalSince1970: 0),
        createdAt: Date = Date(timeIntervalSince1970: 0),
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
            ?? RoleScope.legacyRoleID
        directionRaw = try container.decodeIfPresent(String.self, forKey: .directionRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .direction))
            ?? FriendApplicationDirection.outgoing.rawValue
        purposeRaw = try container.decodeIfPresent(String.self, forKey: .purposeRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .purpose))
            ?? FriendApplicationPurpose.newFriend.rawValue
        statusRaw = try container.decodeIfPresent(String.self, forKey: .statusRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .status))
            ?? FriendApplicationStatus.pending.rawValue
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? createdAt
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? ""
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roleID, forKey: .roleID)
        try container.encode(directionRaw, forKey: .direction)
        try container.encode(directionRaw, forKey: .directionRaw)
        try container.encode(purposeRaw, forKey: .purpose)
        try container.encode(purposeRaw, forKey: .purposeRaw)
        try container.encode(statusRaw, forKey: .status)
        try container.encode(statusRaw, forKey: .statusRaw)
        try container.encode(message, forKey: .message)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
    }
}

typealias AyaneFriendRequestExport = AyaneFriendApplicationExport

/// Codable projection of an append-only relationship transition.
struct AyaneRelationshipTransitionExport: Codable, Equatable, Sendable {
    var id: UUID
    var roleID: UUID
    var from: String
    var to: String
    var reason: String
    var sourceEventID: UUID?
    var scoreAfter: Double
    var policyVersion: Int
    var occurredAt: Date
    var deviceID: String
    var revision: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case from
        case to
        case reason
        case sourceEventID = "source_event_id"
        case scoreAfter = "score_after"
        case policyVersion = "policy_version"
        case occurredAt = "occurred_at"
        case deviceID = "device_id"
        case revision
    }

    init(_ record: CompanionRelationshipTransitionRecord) {
        self.init(
            id: record.id,
            roleID: record.roleID,
            from: record.from,
            to: record.to,
            reason: record.reason,
            sourceEventID: record.sourceEventID,
            scoreAfter: record.scoreAfter,
            policyVersion: record.policyVersion,
            occurredAt: record.occurredAt,
            deviceID: record.deviceID,
            revision: record.revision
        )
    }

    init(
        id: UUID = UUID(),
        roleID: UUID = RoleScope.legacyRoleID,
        from: String = CompanionRelationshipState.pending.rawValue,
        to: String = CompanionRelationshipState.pending.rawValue,
        reason: String = "",
        sourceEventID: UUID? = nil,
        scoreAfter: Double = 0,
        policyVersion: Int = CompanionRelationshipRecord.currentPolicyVersion,
        occurredAt: Date = Date(timeIntervalSince1970: 0),
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
}

/// Conservative limits used when accepting task records from an external
/// backup. They keep the task payload in the same order of magnitude as the
/// existing profile prompt limit while bounding lease metadata separately.
enum AyaneMomentTaskValidationLimits {
    static let instruction = 8_000
    static let resultText = 32_000
    static let lastError = 4_000
    static let leaseOwner = 256
    static let deviceID = 256
    static let occurrenceKey = 512
    static let timezoneIdentifier = 128
}

/// Codable projection of one persisted朋友圈 generation task.
///
/// The task model intentionally remains a scalar record.  Keeping the export
/// projection equally flat makes it safe for v4-v15 readers to ignore the new
/// collection and lets merge/reconcile apply their terminal-state guards
/// without touching conversation, image, or group-chat data.
struct AyaneMomentTaskExport: Codable, Equatable, Sendable {
    var id: UUID
    var roleID: UUID?
    var instruction: String
    var scheduledAt: Date
    var seriesID: UUID?
    var occurrenceKey: String
    var recurrenceRaw: String
    var recurrenceInterval: Int
    var recurrenceWeekday: Int?
    var recurrenceDayOfMonth: Int?
    var recurrenceHour: Int
    var recurrenceMinute: Int
    var timezoneIdentifier: String
    var nextAttemptAt: Date?
    var stateRaw: String
    var resultText: String
    var publishedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var attemptCount: Int
    var lastError: String
    var leaseOwner: String
    var leaseExpiresAt: Date?
    var deviceID: String
    var revision: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roleID = "role_id"
        case instruction
        case scheduledAt = "scheduled_at"
        case seriesID = "series_id"
        case occurrenceKey = "occurrence_key"
        case recurrenceRaw = "recurrence_raw"
        case recurrenceInterval = "recurrence_interval"
        case recurrenceWeekday = "recurrence_weekday"
        case recurrenceDayOfMonth = "recurrence_day_of_month"
        case recurrenceHour = "recurrence_hour"
        case recurrenceMinute = "recurrence_minute"
        case timezoneIdentifier = "timezone_identifier"
        case nextAttemptAt = "next_attempt_at"
        case stateRaw = "state_raw"
        case resultText = "result_text"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case attemptCount = "attempt_count"
        case lastError = "last_error"
        case leaseOwner = "lease_owner"
        case leaseExpiresAt = "lease_expires_at"
        case deviceID = "device_id"
        case revision
    }

    init(
        id: UUID = UUID(),
        roleID: UUID? = nil,
        instruction: String,
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
        stateRaw: String = "scheduled",
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
        self.roleID = roleID
        self.instruction = instruction
        self.scheduledAt = scheduledAt
        self.seriesID = seriesID
        self.occurrenceKey = occurrenceKey
        self.recurrenceRaw = recurrenceRaw
        self.recurrenceInterval = recurrenceInterval
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
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.leaseOwner = leaseOwner
        self.leaseExpiresAt = leaseExpiresAt
        self.deviceID = deviceID
        self.revision = revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        instruction = try container.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        scheduledAt = try container.decodeIfPresent(Date.self, forKey: .scheduledAt) ?? Date()
        seriesID = try container.decodeIfPresent(UUID.self, forKey: .seriesID)
        occurrenceKey = try container.decodeIfPresent(String.self, forKey: .occurrenceKey) ?? ""
        recurrenceRaw = try container.decodeIfPresent(String.self, forKey: .recurrenceRaw)
            ?? MomentTaskRecurrenceFrequency.once.rawValue
        recurrenceInterval = try container.decodeIfPresent(Int.self, forKey: .recurrenceInterval) ?? 1
        recurrenceWeekday = try container.decodeIfPresent(Int.self, forKey: .recurrenceWeekday)
        recurrenceDayOfMonth = try container.decodeIfPresent(Int.self, forKey: .recurrenceDayOfMonth)
        recurrenceHour = try container.decodeIfPresent(Int.self, forKey: .recurrenceHour) ?? 0
        recurrenceMinute = try container.decodeIfPresent(Int.self, forKey: .recurrenceMinute) ?? 0
        timezoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .timezoneIdentifier
        ) ?? TimeZone.current.identifier
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
        stateRaw = try container.decodeIfPresent(String.self, forKey: .stateRaw) ?? MomentTaskState.scheduled.rawValue
        resultText = try container.decodeIfPresent(String.self, forKey: .resultText) ?? ""
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? scheduledAt
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
        leaseOwner = try container.decodeIfPresent(String.self, forKey: .leaseOwner) ?? ""
        leaseExpiresAt = try container.decodeIfPresent(Date.self, forKey: .leaseExpiresAt)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encode(instruction, forKey: .instruction)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encodeIfPresent(seriesID, forKey: .seriesID)
        try container.encode(occurrenceKey, forKey: .occurrenceKey)
        try container.encode(recurrenceRaw, forKey: .recurrenceRaw)
        try container.encode(recurrenceInterval, forKey: .recurrenceInterval)
        try container.encodeIfPresent(recurrenceWeekday, forKey: .recurrenceWeekday)
        try container.encodeIfPresent(recurrenceDayOfMonth, forKey: .recurrenceDayOfMonth)
        try container.encode(recurrenceHour, forKey: .recurrenceHour)
        try container.encode(recurrenceMinute, forKey: .recurrenceMinute)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encodeIfPresent(nextAttemptAt, forKey: .nextAttemptAt)
        try container.encode(stateRaw, forKey: .stateRaw)
        try container.encode(resultText, forKey: .resultText)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encode(lastError, forKey: .lastError)
        try container.encode(leaseOwner, forKey: .leaseOwner)
        try container.encodeIfPresent(leaseExpiresAt, forKey: .leaseExpiresAt)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(revision, forKey: .revision)
    }

    init(_ record: CompanionMomentTaskRecord) {
        self.init(
            id: record.id,
            roleID: record.roleID,
            instruction: record.instruction,
            scheduledAt: record.scheduledAt,
            seriesID: record.seriesID,
            occurrenceKey: record.occurrenceKey,
            recurrenceRaw: record.recurrenceRaw,
            recurrenceInterval: record.recurrenceInterval,
            recurrenceWeekday: record.recurrenceWeekday,
            recurrenceDayOfMonth: record.recurrenceDayOfMonth,
            recurrenceHour: record.recurrenceHour,
            recurrenceMinute: record.recurrenceMinute,
            timezoneIdentifier: record.timezoneIdentifier,
            nextAttemptAt: record.nextAttemptAt,
            stateRaw: record.stateRaw,
            resultText: record.resultText,
            publishedAt: record.publishedAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            attemptCount: record.attemptCount,
            lastError: record.lastError,
            leaseOwner: record.leaseOwner,
            leaseExpiresAt: record.leaseExpiresAt,
            deviceID: record.deviceID,
            revision: record.revision
        )
    }
}

/// Conservative limits for model-generated Moments task metadata accepted from
/// a backup. These limits are deliberately independent from the scheduled-post
/// task limits because generated replies have a separate input/output path.
enum AyaneMomentAIInteractionTaskValidationLimits {
    static let inputText = 4_000
    static let generatedText = 4_000
    static let lastError = 4_000
    static let idempotencyKey = 512
    static let timezoneIdentifier = 128
    static let leaseOwner = 256
    static let deviceID = 256
}

/// Codable projection of one durable AI-generated Moments operation.
struct AyaneMomentAIInteractionTaskExport: Codable, Equatable, Sendable {
    static let legacyEpoch = Date(timeIntervalSince1970: 0)

    var id: UUID
    var kindRaw: String
    var postID: UUID
    var targetInteractionID: UUID?
    var parentInteractionID: UUID?
    var rootInteractionID: UUID?
    var roleID: UUID?
    var stateRaw: String
    var attemptCount: Int
    var nextAttemptAt: Date
    var lastError: String
    var idempotencyKey: String
    var timezoneIdentifier: String
    var inputText: String
    var generatedText: String
    var generatedLike: Bool?
    var resultInteractionID: UUID?
    var leaseOwner: String
    var leaseExpiresAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var deviceID: String

    var kind: MomentAIInteractionTaskKind {
        MomentAIInteractionTaskKind(rawValue: kindRaw) ?? .reactionComment
    }

    var taskKind: MomentAIInteractionTaskKind { kind }

    var state: MomentAIInteractionTaskState {
        MomentAIInteractionTaskState(rawValue: stateRaw) ?? .failed
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

    enum CodingKeys: String, CodingKey {
        case id
        case kind = "kind"
        case kindRaw = "kind_raw"
        case taskKind = "task_kind"
        case postID = "post_id"
        case momentID = "moment_id"
        case targetInteractionID = "target_interaction_id"
        case targetCommentID = "target_comment_id"
        case parentInteractionID = "parent_interaction_id"
        case parentCommentID = "parent_comment_id"
        case rootInteractionID = "root_interaction_id"
        case roleID = "role_id"
        case state = "state"
        case stateRaw = "state_raw"
        case attemptCount = "attempt_count"
        case nextAttemptAt = "next_attempt_at"
        case nextRetryAt = "next_retry_at"
        case lastError = "last_error"
        case idempotencyKey = "idempotency_key"
        case timezoneIdentifier = "timezone_identifier"
        case timezone = "timezone"
        case inputText = "input_text"
        case generatedText = "generated_text"
        case generatedLike = "generated_like"
        case resultInteractionID = "result_interaction_id"
        case leaseOwner = "lease_owner"
        case leaseExpiresAt = "lease_expires_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case revision
        case deviceID = "device_id"
    }

    init(
        id: UUID = UUID(),
        kind: MomentAIInteractionTaskKind = .reactionComment,
        postID: UUID,
        targetInteractionID: UUID? = nil,
        parentInteractionID: UUID? = nil,
        rootInteractionID: UUID? = nil,
        roleID: UUID? = nil,
        state: MomentAIInteractionTaskState = .pending,
        attemptCount: Int = 0,
        nextAttemptAt: Date = Date(),
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
        self.roleID = roleID.map(RoleScope.resolve)
        self.stateRaw = state.rawValue
        self.attemptCount = max(0, attemptCount)
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
        self.idempotencyKey = idempotencyKey.isEmpty
            ? Self.defaultIdempotencyKey(
                kindRaw: kind.rawValue,
                postID: postID,
                targetInteractionID: targetInteractionID,
                parentInteractionID: parentInteractionID,
                roleID: RoleScope.resolve(roleID)
            )
            : idempotencyKey
        self.timezoneIdentifier = timezoneIdentifier
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

    init(_ record: MomentAIInteractionTaskRecord) {
        self.init(
            id: record.id,
            kind: record.kind,
            postID: record.postID,
            targetInteractionID: record.targetInteractionID,
            parentInteractionID: record.parentInteractionID,
            rootInteractionID: record.rootInteractionID,
            roleID: record.roleID,
            state: record.state,
            attemptCount: record.attemptCount,
            nextAttemptAt: record.nextAttemptAt,
            lastError: record.lastError,
            idempotencyKey: record.idempotencyKey,
            timezoneIdentifier: record.timezoneIdentifier,
            inputText: record.inputText,
            generatedText: record.generatedText,
            generatedLike: record.generatedLike,
            resultInteractionID: record.resultInteractionID,
            leaseOwner: record.leaseOwner,
            leaseExpiresAt: record.leaseExpiresAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            revision: record.revision,
            deviceID: record.deviceID
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kindRaw = try container.decodeIfPresent(String.self, forKey: .kindRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .taskKind))
            ?? (try container.decodeIfPresent(String.self, forKey: .kind))
            ?? MomentAIInteractionTaskKind.reactionComment.rawValue
        postID = try container.decodeIfPresent(UUID.self, forKey: .postID)
            ?? (try container.decodeIfPresent(UUID.self, forKey: .momentID))
            ?? UUID()
        targetInteractionID = try container.decodeIfPresent(UUID.self, forKey: .targetInteractionID)
            ?? (try container.decodeIfPresent(UUID.self, forKey: .targetCommentID))
        parentInteractionID = try container.decodeIfPresent(UUID.self, forKey: .parentInteractionID)
            ?? (try container.decodeIfPresent(UUID.self, forKey: .parentCommentID))
        rootInteractionID = try container.decodeIfPresent(UUID.self, forKey: .rootInteractionID)
        roleID = try container.decodeIfPresent(UUID.self, forKey: .roleID)
        stateRaw = try container.decodeIfPresent(String.self, forKey: .stateRaw)
            ?? (try container.decodeIfPresent(String.self, forKey: .state))
            ?? MomentAIInteractionTaskState.pending.rawValue
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
            ?? (try container.decodeIfPresent(Date.self, forKey: .nextRetryAt))
            ?? Self.legacyEpoch
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError) ?? ""
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey) ?? ""
        timezoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier)
            ?? (try container.decodeIfPresent(String.self, forKey: .timezone))
            ?? TimeZone.current.identifier
        inputText = try container.decodeIfPresent(String.self, forKey: .inputText) ?? ""
        generatedText = try container.decodeIfPresent(String.self, forKey: .generatedText) ?? ""
        generatedLike = try container.decodeIfPresent(Bool.self, forKey: .generatedLike)
        resultInteractionID = try container.decodeIfPresent(UUID.self, forKey: .resultInteractionID)
        leaseOwner = try container.decodeIfPresent(String.self, forKey: .leaseOwner) ?? ""
        leaseExpiresAt = try container.decodeIfPresent(Date.self, forKey: .leaseExpiresAt)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyEpoch
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kindRaw, forKey: .kind)
        try container.encode(kindRaw, forKey: .kindRaw)
        try container.encode(kindRaw, forKey: .taskKind)
        try container.encode(postID, forKey: .postID)
        try container.encode(postID, forKey: .momentID)
        try container.encodeIfPresent(targetInteractionID, forKey: .targetInteractionID)
        try container.encodeIfPresent(targetInteractionID, forKey: .targetCommentID)
        try container.encodeIfPresent(parentInteractionID, forKey: .parentInteractionID)
        try container.encodeIfPresent(parentInteractionID, forKey: .parentCommentID)
        try container.encodeIfPresent(rootInteractionID, forKey: .rootInteractionID)
        try container.encodeIfPresent(roleID, forKey: .roleID)
        try container.encode(stateRaw, forKey: .state)
        try container.encode(stateRaw, forKey: .stateRaw)
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encode(nextAttemptAt, forKey: .nextAttemptAt)
        try container.encode(nextAttemptAt, forKey: .nextRetryAt)
        try container.encode(lastError, forKey: .lastError)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(timezoneIdentifier, forKey: .timezone)
        try container.encode(inputText, forKey: .inputText)
        try container.encode(generatedText, forKey: .generatedText)
        try container.encodeIfPresent(generatedLike, forKey: .generatedLike)
        try container.encodeIfPresent(resultInteractionID, forKey: .resultInteractionID)
        try container.encode(leaseOwner, forKey: .leaseOwner)
        try container.encodeIfPresent(leaseExpiresAt, forKey: .leaseExpiresAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
        try container.encode(deviceID, forKey: .deviceID)
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

typealias AyaneMomentInteractionTaskExport = AyaneMomentAIInteractionTaskExport

// Explicit aliases make the DTO names discoverable to import/export callers
// that prefer the persisted model's full terminology.
typealias AyaneCompanionRelationshipExport = AyaneRelationshipExport
typealias AyaneCompanionRelationshipTransitionExport = AyaneRelationshipTransitionExport

struct AyaneProviderSettingsExport: Codable, Equatable, Sendable {
    let providerID: String?
    let baseURL: String
    let model: String
    let embeddingModel: String
    let temperature: Double
    let streamsResponses: Bool

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case baseURL = "base_url"
        case model
        case embeddingModel = "embedding_model"
        case temperature
        case streamsResponses = "streams_responses"
    }

    init(
        providerID: String? = nil,
        baseURL: String,
        model: String,
        embeddingModel: String,
        temperature: Double,
        streamsResponses: Bool
    ) {
        self.providerID = providerID
        self.baseURL = baseURL
        self.model = model
        self.embeddingModel = embeddingModel
        self.temperature = temperature
        self.streamsResponses = streamsResponses
    }
}

struct AyaneMemorySettingsExport: Codable, Equatable, Sendable {
    let autoExtractMemory: Bool
    let tokenBudget: Int
    let recentMessageLimit: Int
    let rawHistoryRecallEnabled: Bool
    let rawHistoryTokenBudget: Int

    enum CodingKeys: String, CodingKey {
        case autoExtractMemory = "auto_extract_memory"
        case tokenBudget = "token_budget"
        case recentMessageLimit = "recent_message_limit"
        case rawHistoryRecallEnabled = "raw_history_recall_enabled"
        case rawHistoryTokenBudget = "raw_history_token_budget"
    }
}

struct AyanePersistenceSettingsExport: Codable, Equatable, Sendable {
    let cloudSyncEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case cloudSyncEnabled = "cloud_sync_enabled"
    }
}

struct AyaneSettingsExport: Codable, Equatable, Sendable {
    let provider: AyaneProviderSettingsExport
    let memory: AyaneMemorySettingsExport
    let persistence: AyanePersistenceSettingsExport
    /// v11 global presentation/scheduler preferences. Per-role proactive
    /// overrides intentionally stay in UserDefaults and are not part of a
    /// portable account-wide backup.
    let humanizedReplyDelayEnabled: Bool
    let proactiveMessagesEnabled: Bool
    let proactiveQuietStartHour: Int
    let proactiveQuietEndHour: Int
    /// Whether a newly selected role should be deterministically matched to a
    /// world from its name/prompt. Older backups did not carry this setting.
    let worldviewAutoMatchEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case provider
        case memory
        case persistence
        case humanizedReplyDelayEnabled = "humanized_reply_delay_enabled"
        case proactiveMessagesEnabled = "proactive_messages_enabled"
        case proactiveQuietStartHour = "proactive_quiet_start_hour"
        case proactiveQuietEndHour = "proactive_quiet_end_hour"
        case worldviewAutoMatchEnabled = "worldview_auto_match_enabled"
    }

    init(
        provider: AyaneProviderSettingsExport,
        memory: AyaneMemorySettingsExport,
        persistence: AyanePersistenceSettingsExport,
        humanizedReplyDelayEnabled: Bool = true,
        proactiveMessagesEnabled: Bool = true,
        proactiveQuietStartHour: Int = 23,
        proactiveQuietEndHour: Int = 8,
        worldviewAutoMatchEnabled: Bool = true
    ) {
        self.provider = provider
        self.memory = memory
        self.persistence = persistence
        self.humanizedReplyDelayEnabled = humanizedReplyDelayEnabled
        self.proactiveMessagesEnabled = proactiveMessagesEnabled
        self.proactiveQuietStartHour = min(23, max(0, proactiveQuietStartHour))
        self.proactiveQuietEndHour = min(23, max(0, proactiveQuietEndHour))
        self.worldviewAutoMatchEnabled = worldviewAutoMatchEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AyaneProviderSettingsExport.self, forKey: .provider)
        memory = try container.decode(AyaneMemorySettingsExport.self, forKey: .memory)
        persistence = try container.decode(AyanePersistenceSettingsExport.self, forKey: .persistence)
        humanizedReplyDelayEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .humanizedReplyDelayEnabled
        ) ?? true
        proactiveMessagesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .proactiveMessagesEnabled
        ) ?? true
        proactiveQuietStartHour = min(23, max(0, try container.decodeIfPresent(
            Int.self,
            forKey: .proactiveQuietStartHour
        ) ?? 23))
        proactiveQuietEndHour = min(23, max(0, try container.decodeIfPresent(
            Int.self,
            forKey: .proactiveQuietEndHour
        ) ?? 8))
        worldviewAutoMatchEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .worldviewAutoMatchEnabled
        ) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(memory, forKey: .memory)
        try container.encode(persistence, forKey: .persistence)
        try container.encode(humanizedReplyDelayEnabled, forKey: .humanizedReplyDelayEnabled)
        try container.encode(proactiveMessagesEnabled, forKey: .proactiveMessagesEnabled)
        try container.encode(proactiveQuietStartHour, forKey: .proactiveQuietStartHour)
        try container.encode(proactiveQuietEndHour, forKey: .proactiveQuietEndHour)
        try container.encode(worldviewAutoMatchEnabled, forKey: .worldviewAutoMatchEnabled)
    }

    var proactiveEnabled: Bool { proactiveMessagesEnabled }
    var quietStartHour: Int { proactiveQuietStartHour }
    var quietEndHour: Int { proactiveQuietEndHour }
}

enum DataExportError: LocalizedError, Equatable {
    case invalidDocument

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            "导出文件内容无效，无法读取。"
        }
    }
}

/// Builds a deterministic, pretty-printed JSON snapshot from a ModelContext.
struct DataExportService {
    let context: ModelContext
    let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    func makePayload(now: Date = Date()) throws -> AyaneDataExport {
        try Self.makePayload(context: context, defaults: defaults, now: now)
    }

    func export(now: Date = Date()) throws -> Data {
        try Self.export(context: context, defaults: defaults, now: now)
    }

    func makeDocument(now: Date = Date()) throws -> AyaneDataExportDocument {
        try Self.makeDocument(context: context, defaults: defaults, now: now)
    }

    static func makePayload(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> AyaneDataExport {
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let events = try context.fetch(FetchDescriptor<ConversationEvent>(
            sortBy: [
                SortDescriptor(\.occurredAt, order: .forward),
                SortDescriptor(\.logicalTimestamp, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let evidence = try context.fetch(FetchDescriptor<MemoryEvidenceRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let summaries = try context.fetch(FetchDescriptor<MemorySummaryRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let tombstones = try context.fetch(FetchDescriptor<MemoryTombstoneRecord>(
            sortBy: [
                SortDescriptor(\.deletedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))

        let profileRecords = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        var profiles = canonicalProfiles(from: profileRecords).map(AyanePersonaExport.init)

        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>(
            sortBy: [
                SortDescriptor(\.roleID, order: .forward),
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneRelationshipExport.init)

        let friendApplications = try context.fetch(FetchDescriptor<FriendApplicationRecord>(
            sortBy: [
                SortDescriptor(\.roleID, order: .forward),
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneFriendApplicationExport.init)

        let transitions = try context.fetch(FetchDescriptor<CompanionRelationshipTransitionRecord>(
            sortBy: [
                SortDescriptor(\.occurredAt, order: .forward),
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneRelationshipTransitionExport.init)

        let momentTasks = try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>(
            sortBy: [
                SortDescriptor(\.scheduledAt, order: .forward),
                SortDescriptor(\.updatedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneMomentTaskExport.init)

        let userProfileRecords = try context.fetch(FetchDescriptor<UserProfileRecord>(
            sortBy: [
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.updatedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        ))
        let userProfile = canonicalUserProfile(from: userProfileRecords).map(AyaneUserProfileExport.init)

        let momentPosts = try context.fetch(FetchDescriptor<MomentPostRecord>(
            sortBy: [
                SortDescriptor(\.publishedAt, order: .forward),
                SortDescriptor(\.updatedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneMomentPostExport.init)

        let momentInteractions = try context.fetch(FetchDescriptor<MomentInteractionRecord>(
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward),
                SortDescriptor(\.updatedAt, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneMomentInteractionExport.init)

        let conversationReadStates = try context.fetch(FetchDescriptor<ConversationReadStateRecord>(
            sortBy: [
                SortDescriptor(\.roleID, order: .forward),
                SortDescriptor(\.conversationID, order: .forward),
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneConversationReadStateExport.init)

        let momentReadStates = try context.fetch(FetchDescriptor<MomentReadStateRecord>(
            sortBy: [
                SortDescriptor(\.postID, order: .forward),
                SortDescriptor(\.revision, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneMomentReadStateExport.init)

        let momentAIInteractionTasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>(
            sortBy: [
                SortDescriptor(\.nextAttemptAt, order: .forward),
                SortDescriptor(\.updatedAt, order: .forward),
                SortDescriptor(\.idempotencyKey, order: .forward),
                SortDescriptor(\.id, order: .forward)
            ]
        )).map(AyaneMomentAIInteractionTaskExport.init)

        let worldProfileRecords = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        let worldProfiles = SchemaV11DataSupport.canonicalWorldProfiles(
            worldProfileRecords.map(AyaneWorldProfileExport.init)
        )
        let worldProfile = worldProfiles.first(where: {
            $0.id == WorldProfileRecord.realityID
        }) ?? worldProfiles.first ?? .realityDefault
        let groupConversations = SchemaV11DataSupport.canonicalGroupConversations(
            (try context.fetch(FetchDescriptor<GroupConversationRecord>())).map(AyaneGroupConversationExport.init)
        )
        let groupParticipants = SchemaV11DataSupport.canonicalGroupParticipants(
            (try context.fetch(FetchDescriptor<GroupParticipantRecord>())).map(AyaneGroupParticipantExport.init)
        )
        let chatTurnPresentations = SchemaV11DataSupport.canonicalChatTurnPresentations(
            (try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())).map(AyaneChatTurnPresentationExport.init)
        )
        let proactiveMessageTasks = SchemaV11DataSupport.canonicalProactiveMessageTasks(
            (try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())).map(AyaneProactiveMessageTaskExport.init)
        )

        // A fresh installation can legitimately use the built-in legacy
        // persona without materializing a profile row. If any exported record
        // still belongs to that role, include its fallback profile so the
        // backup remains referentially complete after other roles are added.
        let referencesLegacyRole = conversations.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || events.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || memories.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || evidence.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || summaries.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || tombstones.contains { $0.resolvedRoleID == RoleScope.legacyRoleID }
            || relationships.contains { $0.roleID == RoleScope.legacyRoleID }
            || friendApplications.contains { $0.roleID == RoleScope.legacyRoleID }
            || transitions.contains { $0.roleID == RoleScope.legacyRoleID }
            || momentTasks.contains { $0.roleID == RoleScope.legacyRoleID }
            || momentAIInteractionTasks.contains { $0.roleID == RoleScope.legacyRoleID }
            || momentPosts.contains { $0.authorRoleID == RoleScope.legacyRoleID }
            || momentInteractions.contains { $0.actorRoleID == RoleScope.legacyRoleID }
        if referencesLegacyRole,
           !profiles.contains(where: { $0.roleID == RoleScope.legacyRoleID }) {
            profiles.append(legacyPersona(from: defaults))
        }

        return makePayload(
            conversations: conversations.map(AyaneConversationExport.init),
            events: events.map(AyaneEventExport.init),
            memories: memories.map(AyaneMemoryExport.init),
            evidence: evidence.map(AyaneEvidenceExport.init),
            summaries: summaries.map(AyaneSummaryExport.init),
            tombstones: tombstones.map(AyaneTombstoneExport.init),
            relationships: relationships,
            friendApplications: friendApplications,
            transitions: transitions,
            momentTasks: momentTasks,
            momentAIInteractionTasks: momentAIInteractionTasks,
            userProfile: userProfile,
            momentPosts: momentPosts,
            momentInteractions: momentInteractions,
            conversationReadStates: conversationReadStates,
            momentReadStates: momentReadStates,
            worldProfile: worldProfile,
            worldProfiles: worldProfiles,
            groupConversations: groupConversations,
            groupParticipants: groupParticipants,
            chatTurnPresentations: chatTurnPresentations,
            proactiveMessageTasks: proactiveMessageTasks,
            profile: nil,
            fallbackPersona: nil,
            profiles: profiles,
            defaults: defaults,
            now: now
        )
    }

    /// Builds a payload from an already-held record snapshot without fetching
    /// the context again.
    static func makePayload(
        conversations: [ConversationRecord],
        events: [ConversationEvent],
        memories: [MemoryAssertionRecord],
        evidence: [MemoryEvidenceRecord],
        summaries: [MemorySummaryRecord],
        tombstones: [MemoryTombstoneRecord],
        relationships: [CompanionRelationshipRecord] = [],
        friendApplications: [FriendApplicationRecord] = [],
        transitions: [CompanionRelationshipTransitionRecord] = [],
        momentTasks: [CompanionMomentTaskRecord] = [],
        momentAIInteractionTasks: [MomentAIInteractionTaskRecord] = [],
        momentInteractionTasks: [MomentAIInteractionTaskRecord]? = nil,
        userProfile: UserProfileRecord? = nil,
        momentPosts: [MomentPostRecord] = [],
        momentInteractions: [MomentInteractionRecord] = [],
        conversationReadStates: [ConversationReadStateRecord] = [],
        momentReadStates: [MomentReadStateRecord] = [],
        worldProfile: WorldProfileRecord? = nil,
        worldProfiles: [WorldProfileRecord] = [],
        groupConversations: [GroupConversationRecord] = [],
        groupParticipants: [GroupParticipantRecord] = [],
        chatTurnPresentations: [ChatTurnPresentationRecord] = [],
        proactiveMessageTasks: [ProactiveMessageTaskRecord] = [],
        profile: CompanionProfileRecord? = nil,
        fallbackPersona: AyanePersonaExport? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> AyaneDataExport {
        makePayload(
            conversations: conversations.map(AyaneConversationExport.init),
            events: events.map(AyaneEventExport.init),
            memories: memories.map(AyaneMemoryExport.init),
            evidence: evidence.map(AyaneEvidenceExport.init),
            summaries: summaries.map(AyaneSummaryExport.init),
            tombstones: tombstones.map(AyaneTombstoneExport.init),
            relationships: relationships.map(AyaneRelationshipExport.init),
            friendApplications: friendApplications.map(AyaneFriendApplicationExport.init),
            transitions: transitions.map(AyaneRelationshipTransitionExport.init),
            momentTasks: momentTasks.map(AyaneMomentTaskExport.init),
            momentAIInteractionTasks: (momentInteractionTasks ?? momentAIInteractionTasks)
                .map(AyaneMomentAIInteractionTaskExport.init),
            userProfile: userProfile.map(AyaneUserProfileExport.init),
            momentPosts: momentPosts.map(AyaneMomentPostExport.init),
            momentInteractions: momentInteractions.map(AyaneMomentInteractionExport.init),
            conversationReadStates: conversationReadStates.map(AyaneConversationReadStateExport.init),
            momentReadStates: momentReadStates.map(AyaneMomentReadStateExport.init),
            worldProfile: worldProfile.map(AyaneWorldProfileExport.init) ?? .realityDefault,
            worldProfiles: worldProfiles.isEmpty
                ? nil
                : worldProfiles.map(AyaneWorldProfileExport.init),
            groupConversations: groupConversations.map(AyaneGroupConversationExport.init),
            groupParticipants: groupParticipants.map(AyaneGroupParticipantExport.init),
            chatTurnPresentations: chatTurnPresentations.map(AyaneChatTurnPresentationExport.init),
            proactiveMessageTasks: proactiveMessageTasks.map(AyaneProactiveMessageTaskExport.init),
            profile: profile.map(AyanePersonaExport.init),
            fallbackPersona: fallbackPersona,
            defaults: defaults,
            now: now
        )
    }

    /// Builds a deterministic payload from immutable export values. This is
    /// the duplicate-safe path used by read-only source canonicalization.
    static func makePayload(
        conversations: [AyaneConversationExport],
        events: [AyaneEventExport],
        memories: [AyaneMemoryExport],
        evidence: [AyaneEvidenceExport],
        summaries: [AyaneSummaryExport],
        tombstones: [AyaneTombstoneExport],
        relationships: [AyaneRelationshipExport] = [],
        friendApplications: [AyaneFriendApplicationExport] = [],
        transitions: [AyaneRelationshipTransitionExport] = [],
        momentTasks: [AyaneMomentTaskExport] = [],
        momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport] = [],
        momentInteractionTasks: [AyaneMomentAIInteractionTaskExport]? = nil,
        userProfile: AyaneUserProfileExport? = nil,
        momentPosts: [AyaneMomentPostExport] = [],
        momentInteractions: [AyaneMomentInteractionExport] = [],
        conversationReadStates: [AyaneConversationReadStateExport] = [],
        momentReadStates: [AyaneMomentReadStateExport] = [],
        worldProfile: AyaneWorldProfileExport = .realityDefault,
        worldProfiles: [AyaneWorldProfileExport]? = nil,
        groupConversations: [AyaneGroupConversationExport] = [],
        groupParticipants: [AyaneGroupParticipantExport] = [],
        chatTurnPresentations: [AyaneChatTurnPresentationExport] = [],
        proactiveMessageTasks: [AyaneProactiveMessageTaskExport] = [],
        profile: AyanePersonaExport? = nil,
        fallbackPersona: AyanePersonaExport? = nil,
        profiles: [AyanePersonaExport]? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> AyaneDataExport {
        // A few read-only reconciliation projections predate v6 and can
        // still carry nil role IDs. Resolve those values from their owning
        // records here so every v6 writer emits a complete role scope even
        // when the caller supplied immutable DTOs directly.
        let conversationRoles = Dictionary(
            conversations.map { ($0.id, $0.roleID ?? RoleScope.legacyRoleID) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedConversations = conversations.map { item in
            var copy = item
            copy.roleID = item.roleID ?? RoleScope.legacyRoleID
            return copy
        }
        let normalizedEvents = events.map { item in
            var copy = item
            copy.roleID = item.roleID
                ?? conversationRoles[item.conversationID]
                ?? RoleScope.legacyRoleID
            return copy
        }
        let eventRoles = Dictionary(
            normalizedEvents.map { ($0.id, $0.roleID ?? RoleScope.legacyRoleID) },
            uniquingKeysWith: { first, _ in first }
        )
        let memoryRolesFromEvidence: [UUID: UUID] = Dictionary<UUID, UUID>(
            evidence.compactMap { item in
                guard let roleID = item.roleID else { return nil }
                return (item.memoryID, roleID)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedMemories = memories.map { item in
            var copy = item
            copy.roleID = item.roleID
                ?? memoryRolesFromEvidence[item.id]
                ?? RoleScope.legacyRoleID
            return copy
        }
        let memoryRoles: [UUID: UUID] = Dictionary<UUID, UUID>(
            normalizedMemories.map { ($0.id, $0.roleID ?? RoleScope.legacyRoleID) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedEvidence = evidence.map { item in
            var copy = item
            copy.roleID = item.roleID
                ?? eventRoles[item.eventID]
                ?? memoryRoles[item.memoryID]
                ?? RoleScope.legacyRoleID
            return copy
        }
        let normalizedSummaries = summaries.map { item in
            var copy = item
            copy.roleID = item.roleID
                ?? conversationRoles[item.conversationID]
                ?? RoleScope.legacyRoleID
            return copy
        }
        let normalizedTombstones = tombstones.map { item in
            var copy = item
            copy.roleID = item.roleID
                ?? item.sourceEventIDs.lazy.compactMap({ eventRoles[$0] }).first
                ?? memoryRoles[item.entityID]
                ?? conversationRoles[item.entityID]
                ?? eventRoles[item.entityID]
                ?? RoleScope.legacyRoleID
            return copy
        }
        var normalizedUserProfile = userProfile
        if let userProfile {
            normalizedUserProfile?.id = userProfile.id
        }
        let normalizedMomentPosts = momentPosts.map { item in
            var copy = item
            copy.authorRoleID = item.authorRoleID.map(RoleScope.resolve)
            return copy
        }
        let normalizedMomentInteractions = momentInteractions.map { item in
            var copy = item
            copy.actorRoleID = item.actorRoleID.map(RoleScope.resolve)
            return copy
        }
        let normalizedMomentAIInteractionTasks = (momentInteractionTasks ?? momentAIInteractionTasks).map { item in
            var copy = item
            copy.roleID = item.roleID.map(RoleScope.resolve)
            return copy
        }
        let normalizedConversationReadStates = conversationReadStates.map { item in
            var copy = item
            copy.roleID = item.roleID.map(RoleScope.resolve)
            return copy
        }
        let normalizedFriendApplications = friendApplications.map { item in
            var copy = item
            copy.roleID = RoleScope.resolve(item.roleID)
            return copy
        }
        let suppliedWorlds: [AyaneWorldProfileExport]
        if let worldProfiles, !worldProfiles.isEmpty {
            suppliedWorlds = worldProfiles
        } else {
            suppliedWorlds = [worldProfile]
        }
        let normalizedWorldProfiles = SchemaV11DataSupport.canonicalWorldProfiles(suppliedWorlds)
        let normalizedWorldProfile = normalizedWorldProfiles.first(where: {
            $0.id == WorldProfileRecord.realityID
        }) ?? normalizedWorldProfiles.first ?? .realityDefault
        let normalizedGroupConversations = SchemaV11DataSupport.canonicalGroupConversations(groupConversations)
        let normalizedGroupParticipants = SchemaV11DataSupport.canonicalGroupParticipants(groupParticipants)
        let normalizedChatTurnPresentations = SchemaV11DataSupport.canonicalChatTurnPresentations(chatTurnPresentations)
        let normalizedProactiveMessageTasks = SchemaV11DataSupport.canonicalProactiveMessageTasks(proactiveMessageTasks)

        let conversationExports = normalizedConversations
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
        let eventExports = normalizedEvents
            .sorted {
                ($0.occurredAt, $0.logicalTimestamp, $0.id.uuidString)
                    < ($1.occurredAt, $1.logicalTimestamp, $1.id.uuidString)
            }
        let memoryExports = normalizedMemories
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
        let evidenceExports = normalizedEvidence
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
        let summaryExports = normalizedSummaries
            .sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
        let tombstoneExports = normalizedTombstones
            .sorted {
                ($0.deletedAt, $0.id.uuidString) < ($1.deletedAt, $1.id.uuidString)
            }
        let momentPostExports = normalizedMomentPosts.sorted {
            ($0.publishedAt, $0.updatedAt, $0.id.uuidString)
                < ($1.publishedAt, $1.updatedAt, $1.id.uuidString)
        }
        let momentInteractionExports = normalizedMomentInteractions.sorted {
            ($0.createdAt, $0.updatedAt, $0.id.uuidString)
                < ($1.createdAt, $1.updatedAt, $1.id.uuidString)
        }
        let momentAIInteractionTaskExports = canonicalMomentAIInteractionTasks(
            normalizedMomentAIInteractionTasks
        )
        let conversationReadStateExports = canonicalConversationReadStates(
            normalizedConversationReadStates
        ).sorted {
            ($0.roleID?.uuidString ?? "", $0.conversationID.uuidString)
                < ($1.roleID?.uuidString ?? "", $1.conversationID.uuidString)
        }
        let momentReadStateExports = canonicalMomentReadStates(momentReadStates).sorted {
            $0.postID.uuidString < $1.postID.uuidString
        }
        let friendApplicationExports = SchemaV11DataSupport.canonicalFriendApplications(
            normalizedFriendApplications
        )

        let suppliedProfiles = profiles
            ?? profile.map { [$0] }
            ?? []
        let canonicalProfiles = canonicalPersonas(from: suppliedProfiles)
        let selectedPersona = compatibilityPersona(from: canonicalProfiles)
            ?? fallbackPersona
            ?? legacyPersona(from: defaults)
        return AyaneDataExport(
            exportedAt: now,
            conversations: conversationExports,
            events: eventExports,
            memories: memoryExports,
            evidence: evidenceExports,
            summaries: summaryExports,
            tombstones: tombstoneExports,
            persona: selectedPersona,
            settings: settings(from: defaults),
            profiles: canonicalProfiles.isEmpty ? [selectedPersona] : canonicalProfiles,
            relationships: canonicalRelationships(relationships),
            friendApplications: friendApplicationExports,
            transitions: canonicalTransitions(transitions),
            momentTasks: canonicalMomentTasks(momentTasks),
            userProfile: normalizedUserProfile,
            momentPosts: momentPostExports,
            momentInteractions: momentInteractionExports,
            conversationReadStates: conversationReadStateExports,
            momentReadStates: momentReadStateExports,
            momentAIInteractionTasks: momentAIInteractionTaskExports,
            worldProfile: normalizedWorldProfile,
            worldProfiles: normalizedWorldProfiles,
            groupConversations: normalizedGroupConversations,
            groupParticipants: normalizedGroupParticipants,
            chatTurnPresentations: normalizedChatTurnPresentations,
            proactiveMessageTasks: normalizedProactiveMessageTasks
        )
    }

    /// Canonicalizes a previously fetched set of physical profile rows before
    /// producing the v6 profile collection. This overload is used by read-only
    /// duplicate reconciliation and never mutates its input rows.
    static func makePayload(
        profiles: [AyanePersonaExport],
        conversations: [AyaneConversationExport],
        events: [AyaneEventExport],
        memories: [AyaneMemoryExport],
        evidence: [AyaneEvidenceExport],
        summaries: [AyaneSummaryExport],
        tombstones: [AyaneTombstoneExport],
        relationships: [AyaneRelationshipExport] = [],
        friendApplications: [AyaneFriendApplicationExport] = [],
        transitions: [AyaneRelationshipTransitionExport] = [],
        momentTasks: [AyaneMomentTaskExport] = [],
        momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport] = [],
        momentInteractionTasks: [AyaneMomentAIInteractionTaskExport]? = nil,
        userProfile: AyaneUserProfileExport? = nil,
        momentPosts: [AyaneMomentPostExport] = [],
        momentInteractions: [AyaneMomentInteractionExport] = [],
        conversationReadStates: [AyaneConversationReadStateExport] = [],
        momentReadStates: [AyaneMomentReadStateExport] = [],
        worldProfile: AyaneWorldProfileExport = .realityDefault,
        worldProfiles: [AyaneWorldProfileExport]? = nil,
        groupConversations: [AyaneGroupConversationExport] = [],
        groupParticipants: [AyaneGroupParticipantExport] = [],
        chatTurnPresentations: [AyaneChatTurnPresentationExport] = [],
        proactiveMessageTasks: [AyaneProactiveMessageTaskExport] = [],
        fallbackPersona: AyanePersonaExport? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> AyaneDataExport {
        makePayload(
            conversations: conversations,
            events: events,
            memories: memories,
            evidence: evidence,
            summaries: summaries,
            tombstones: tombstones,
            relationships: relationships,
            friendApplications: friendApplications,
            transitions: transitions,
            momentTasks: momentTasks,
            momentAIInteractionTasks: momentAIInteractionTasks,
            momentInteractionTasks: momentInteractionTasks,
            userProfile: userProfile,
            momentPosts: momentPosts,
            momentInteractions: momentInteractions,
            conversationReadStates: conversationReadStates,
            momentReadStates: momentReadStates,
            worldProfile: worldProfile,
            worldProfiles: worldProfiles,
            groupConversations: groupConversations,
            groupParticipants: groupParticipants,
            chatTurnPresentations: chatTurnPresentations,
            proactiveMessageTasks: proactiveMessageTasks,
            fallbackPersona: fallbackPersona,
            profiles: profiles,
            defaults: defaults,
            now: now
        )
    }

    /// Label-order compatibility for callers that place the canonical profile
    /// before the remaining immutable records.
    static func makePayload(
        profile: AyanePersonaExport?,
        conversations: [AyaneConversationExport],
        events: [AyaneEventExport],
        memories: [AyaneMemoryExport],
        evidence: [AyaneEvidenceExport],
        summaries: [AyaneSummaryExport],
        tombstones: [AyaneTombstoneExport],
        relationships: [AyaneRelationshipExport] = [],
        friendApplications: [AyaneFriendApplicationExport] = [],
        transitions: [AyaneRelationshipTransitionExport] = [],
        momentTasks: [AyaneMomentTaskExport] = [],
        momentAIInteractionTasks: [AyaneMomentAIInteractionTaskExport] = [],
        momentInteractionTasks: [AyaneMomentAIInteractionTaskExport]? = nil,
        userProfile: AyaneUserProfileExport? = nil,
        momentPosts: [AyaneMomentPostExport] = [],
        momentInteractions: [AyaneMomentInteractionExport] = [],
        conversationReadStates: [AyaneConversationReadStateExport] = [],
        momentReadStates: [AyaneMomentReadStateExport] = [],
        worldProfile: AyaneWorldProfileExport = .realityDefault,
        worldProfiles: [AyaneWorldProfileExport]? = nil,
        groupConversations: [AyaneGroupConversationExport] = [],
        groupParticipants: [AyaneGroupParticipantExport] = [],
        chatTurnPresentations: [AyaneChatTurnPresentationExport] = [],
        proactiveMessageTasks: [AyaneProactiveMessageTaskExport] = [],
        fallbackPersona: AyanePersonaExport? = nil,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> AyaneDataExport {
        makePayload(
            conversations: conversations,
            events: events,
            memories: memories,
            evidence: evidence,
            summaries: summaries,
            tombstones: tombstones,
            relationships: relationships,
            friendApplications: friendApplications,
            transitions: transitions,
            momentTasks: momentTasks,
            momentAIInteractionTasks: momentAIInteractionTasks,
            momentInteractionTasks: momentInteractionTasks,
            userProfile: userProfile,
            momentPosts: momentPosts,
            momentInteractions: momentInteractions,
            conversationReadStates: conversationReadStates,
            momentReadStates: momentReadStates,
            worldProfile: worldProfile,
            worldProfiles: worldProfiles,
            groupConversations: groupConversations,
            groupParticipants: groupParticipants,
            chatTurnPresentations: chatTurnPresentations,
            proactiveMessageTasks: proactiveMessageTasks,
            profile: profile,
            fallbackPersona: fallbackPersona,
            profiles: profile.map { [$0] } ?? [],
            defaults: defaults,
            now: now
        )
    }

    static func export(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(makePayload(context: context, defaults: defaults, now: now))
    }

    static func makeDocument(
        context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) throws -> AyaneDataExportDocument {
        AyaneDataExportDocument(data: try export(context: context, defaults: defaults, now: now))
    }

    static func defaultFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "kin-data-\(formatter.string(from: date)).json"
    }

    /// Chooses one deterministic winner for every logical profile ID without
    /// mutating any row. The profile model uses its `id` as the role ID.
    private static func canonicalUserProfile(
        from profiles: [UserProfileRecord]
    ) -> UserProfileRecord? {
        let candidates = profiles.filter { $0.id == UserProfileRecord.singletonID }
        return candidates.max { lhs, rhs in
            if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
            let left = userProfileFingerprint(lhs)
            let right = userProfileFingerprint(rhs)
            if left != right { return left < right }
            return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
        }
    }

    private static func userProfileFingerprint(_ profile: UserProfileRecord) -> String {
        func dataHash(_ data: Data?) -> String {
            guard let data else { return "" }
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        return [
            profile.id.uuidString.lowercased(),
            profile.displayName,
            String(profile.birthdayMonth ?? 0),
            String(profile.birthdayDay ?? 0),
            profile.birthdayTimeZoneIdentifier,
            dataHash(profile.avatarImageData),
            dataHash(profile.momentsCoverImageData),
            String(profile.createdAt.timeIntervalSince1970.bitPattern, radix: 16),
            String(profile.updatedAt.timeIntervalSince1970.bitPattern, radix: 16),
            String(profile.revision),
            profile.deviceID
        ].joined(separator: "\u{001F}")
    }

    private static func canonicalProfiles(
        from profiles: [CompanionProfileRecord]
    ) -> [CompanionProfileRecord] {
        var winners: [UUID: CompanionProfileRecord] = [:]
        for candidate in profiles {
            if let current = winners[candidate.roleID] {
                if isPreferred(candidate, over: current) {
                    winners[candidate.roleID] = candidate
                }
            } else {
                winners[candidate.roleID] = candidate
            }
        }
        return winners.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { winners[$0] }
    }

    /// Relationship state is logically keyed by role ID.  Physical duplicate
    /// rows are resolved for export using a safety-first ordering so an older
    /// accepted row can never hide a newer terminal/retired row.
    private static func canonicalRelationships(
        _ relationships: [AyaneRelationshipExport]
    ) -> [AyaneRelationshipExport] {
        var winners: [UUID: AyaneRelationshipExport] = [:]
        for candidate in relationships {
            if let current = winners[candidate.roleID] {
                var winner = relationshipIsPreferred(candidate, over: current)
                    ? candidate
                    : current
                let contactWinner = relationshipContactIsPreferred(candidate, over: current)
                    ? candidate
                    : current
                winner.contactMembershipRaw = contactWinner.contactMembershipRaw
                winner.contactStateUpdatedAt = contactWinner.contactStateUpdatedAt
                winner.lastUserRemovalID = contactWinner.lastUserRemovalID
                winners[candidate.roleID] = winner
            } else {
                winners[candidate.roleID] = candidate
            }
        }
        return winners.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { winners[$0] }
    }

    /// Transitions are append-only. Keep every distinct ID in the export and
    /// sort deterministically; import/merge validation must see an identity
    /// conflict instead of silently choosing one immutable audit row.
    private static func canonicalTransitions(
        _ transitions: [AyaneRelationshipTransitionExport]
    ) -> [AyaneRelationshipTransitionExport] {
        transitions.sorted {
            ($0.occurredAt, $0.revision, $0.id.uuidString)
                < ($1.occurredAt, $1.revision, $1.id.uuidString)
        }
    }

    /// Task identity conflicts are intentionally left visible to import and
    /// merge validation.  Sorting is deterministic, but silently choosing a
    /// published result here could turn a split-brain task into a successful
    /// export. `StoreDuplicateReconciler` is the explicit safe collapse path.
    private static func canonicalMomentTasks(
        _ tasks: [AyaneMomentTaskExport]
    ) -> [AyaneMomentTaskExport] {
        tasks.sorted {
            ($0.scheduledAt, $0.updatedAt, $0.id.uuidString)
                < ($1.scheduledAt, $1.updatedAt, $1.id.uuidString)
        }
    }

    /// AI interaction tasks are retries of one logical operation. Keep one
    /// deterministic winner per idempotency key so a backup cannot recreate a
    /// duplicate reaction after a crash or a second export/import cycle.
    private static func canonicalMomentAIInteractionTasks(
        _ tasks: [AyaneMomentAIInteractionTaskExport]
    ) -> [AyaneMomentAIInteractionTaskExport] {
        var winners: [String: AyaneMomentAIInteractionTaskExport] = [:]
        for candidate in tasks {
            let key = candidate.idempotencyKey.isEmpty
                ? candidate.id.uuidString.lowercased()
                : candidate.idempotencyKey.lowercased()
            if let current = winners[key] {
                if momentAIInteractionTaskIsPreferred(candidate, over: current) {
                    winners[key] = candidate
                }
            } else {
                winners[key] = candidate
            }
        }
        return winners.values.sorted {
            ($0.nextAttemptAt, $0.updatedAt, $0.idempotencyKey, $0.id.uuidString)
                < ($1.nextAttemptAt, $1.updatedAt, $1.idempotencyKey, $1.id.uuidString)
        }
    }

    private static func momentAIInteractionTaskIsPreferred(
        _ lhs: AyaneMomentAIInteractionTaskExport,
        over rhs: AyaneMomentAIInteractionTaskExport
    ) -> Bool {
        if lhs.state.isTerminal != rhs.state.isTerminal {
            return lhs.state.isTerminal
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.attemptCount != rhs.attemptCount { return lhs.attemptCount > rhs.attemptCount }
        return lhs.id.uuidString.lowercased() > rhs.id.uuidString.lowercased()
    }

    private static func canonicalConversationReadStates(
        _ states: [AyaneConversationReadStateExport]
    ) -> [AyaneConversationReadStateExport] {
        var winners: [String: AyaneConversationReadStateExport] = [:]
        for state in states {
            var normalized = state
            normalized.roleID = RoleScope.resolve(state.roleID)
            let key = "\(normalized.roleID!.uuidString.lowercased()):\(normalized.conversationID.uuidString.lowercased())"
            if let current = winners[key] {
                if conversationReadStateIsPreferred(normalized, over: current) {
                    winners[key] = normalized
                }
            } else {
                winners[key] = normalized
            }
        }
        return winners.values.sorted {
            ($0.roleID?.uuidString ?? "", $0.conversationID.uuidString)
                < ($1.roleID?.uuidString ?? "", $1.conversationID.uuidString)
        }
    }

    private static func canonicalMomentReadStates(
        _ states: [AyaneMomentReadStateExport]
    ) -> [AyaneMomentReadStateExport] {
        var winners: [UUID: AyaneMomentReadStateExport] = [:]
        for state in states {
            if let current = winners[state.postID] {
                if momentReadStateIsPreferred(state, over: current) {
                    winners[state.postID] = state
                }
            } else {
                winners[state.postID] = state
            }
        }
        return winners.values.sorted { $0.postID.uuidString < $1.postID.uuidString }
    }

    private static func conversationReadStateIsPreferred(
        _ lhs: AyaneConversationReadStateExport,
        over rhs: AyaneConversationReadStateExport
    ) -> Bool {
        switch (conversationReadCursor(lhs), conversationReadCursor(rhs)) {
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

    private static func momentReadStateIsPreferred(
        _ lhs: AyaneMomentReadStateExport,
        over rhs: AyaneMomentReadStateExport
    ) -> Bool {
        switch (momentReadCursor(lhs), momentReadCursor(rhs)) {
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

    private static func conversationReadCursor(
        _ state: AyaneConversationReadStateExport
    ) -> ConversationReadCursor? {
        guard let occurredAt = state.lastReadOccurredAt else { return nil }
        return ConversationReadCursor(
            occurredAt: occurredAt,
            logicalTimestamp: state.lastReadLogicalTimestamp,
            eventID: state.lastReadEventID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        )
    }

    private static func momentReadCursor(
        _ state: AyaneMomentReadStateExport
    ) -> MomentReadCursor? {
        guard let createdAt = state.lastReadCreatedAt else { return nil }
        return MomentReadCursor(
            createdAt: createdAt,
            interactionID: state.lastReadInteractionID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        )
    }

    private static func relationshipIsPreferred(
        _ lhs: AyaneRelationshipExport,
        over rhs: AyaneRelationshipExport
    ) -> Bool {
        let lhsSafety = relationshipSafetyRank(lhs)
        let rhsSafety = relationshipSafetyRank(rhs)
        if lhsSafety != rhsSafety { return lhsSafety > rhsSafety }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func relationshipSafetyRank(_ value: AyaneRelationshipExport) -> Int {
        if value.retiredAt != nil { return 6 }
        switch CompanionRelationshipState(rawValue: value.stateRaw) {
        case .blocked: return 5
        case .deleted: return 4
        case .rejected: return 3
        case .recoveryPending: return 2
        case .pending: return 1
        case .accepted: return 0
        case nil: return 7
        }
    }

    private static func relationshipContactIsPreferred(
        _ lhs: AyaneRelationshipExport,
        over rhs: AyaneRelationshipExport
    ) -> Bool {
        if lhs.contactStateUpdatedAt != rhs.contactStateUpdatedAt {
            return lhs.contactStateUpdatedAt > rhs.contactStateUpdatedAt
        }
        if lhs.revision != rhs.revision { return lhs.revision > rhs.revision }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID > rhs.deviceID }
        if lhs.contactMembershipRaw != rhs.contactMembershipRaw {
            return lhs.contactMembershipRaw > rhs.contactMembershipRaw
        }
        return (lhs.lastUserRemovalID?.uuidString ?? "")
            > (rhs.lastUserRemovalID?.uuidString ?? "")
    }

    /// Canonicalizes immutable profile exports by resolved role ID. This also
    /// handles a legacy caller that supplied a nil role for the singleton.
    private static func canonicalPersonas(
        from profiles: [AyanePersonaExport]
    ) -> [AyanePersonaExport] {
        var winners: [UUID: AyanePersonaExport] = [:]
        for candidate in profiles {
            let roleID = resolvedPersonaRoleID(candidate)
            var normalizedCandidate = candidate
            normalizedCandidate.roleID = roleID
            if let current = winners[roleID] {
                if isPreferred(normalizedCandidate, over: current) {
                    winners[roleID] = normalizedCandidate
                }
            } else {
                winners[roleID] = normalizedCandidate
            }
        }
        return winners.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { winners[$0] }
    }

    private static func compatibilityPersona(
        from profiles: [AyanePersonaExport]
    ) -> AyanePersonaExport? {
        profiles.first { resolvedPersonaRoleID($0) == RoleScope.legacyRoleID }
            ?? profiles.first
    }

    private static func resolvedPersonaRoleID(_ profile: AyanePersonaExport) -> UUID {
        profile.roleID
            ?? (profile.id == AyanePersonaExport.singletonID
                ? RoleScope.legacyRoleID
                : profile.id)
    }

    private static func isPreferred(
        _ lhs: CompanionProfileRecord,
        over rhs: CompanionProfileRecord
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision > rhs.revision
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID > rhs.deviceID
        }
        return canonicalContentFingerprint(lhs) > canonicalContentFingerprint(rhs)
    }

    private static func isPreferred(
        _ lhs: AyanePersonaExport,
        over rhs: AyanePersonaExport
    ) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision > rhs.revision
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID > rhs.deviceID
        }
        return canonicalContentFingerprint(lhs) > canonicalContentFingerprint(rhs)
    }

    private static func canonicalContentFingerprint(_ profile: CompanionProfileRecord) -> String {
        canonicalContentFingerprint(
            worldProfileID: profile.worldProfileID,
            name: profile.name,
            userName: profile.userName,
            prompt: profile.prompt,
            birthdayMonth: profile.birthdayMonth,
            birthdayDay: profile.birthdayDay,
            avatarImageData: profile.avatarImageData,
            chatBackgroundImageData: profile.chatBackgroundImageData
        )
    }

    private static func canonicalContentFingerprint(_ profile: AyanePersonaExport) -> String {
        canonicalContentFingerprint(
            worldProfileID: profile.worldProfileID,
            name: profile.name,
            userName: profile.userName,
            prompt: profile.prompt,
            birthdayMonth: profile.birthdayMonth,
            birthdayDay: profile.birthdayDay,
            avatarImageData: profile.avatarImageData,
            chatBackgroundImageData: profile.chatBackgroundImageData
        )
    }

    private static func canonicalContentFingerprint(
        worldProfileID: UUID,
        name: String,
        userName: String,
        prompt: String,
        birthdayMonth: Int?,
        birthdayDay: Int?,
        avatarImageData: Data?,
        chatBackgroundImageData: Data?
    ) -> String {
        func dataHash(_ data: Data?) -> String {
            guard let data else { return "" }
            return SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        }
        let content = [
            worldProfileID.uuidString.lowercased(),
            name,
            userName,
            prompt,
            String(birthdayMonth ?? 0),
            String(birthdayDay ?? 0),
            dataHash(avatarImageData),
            dataHash(chatBackgroundImageData)
        ].joined(separator: "\u{001F}")
        return SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func legacyPersona(from defaults: UserDefaults) -> AyanePersonaExport {
        legacyPersona(from: persona(from: defaults))
    }

    private static func legacyPersona(from configuration: PersonaConfiguration) -> AyanePersonaExport {
        AyanePersonaExport(
            configuration,
            id: AyanePersonaExport.singletonID,
            createdAt: AyanePersonaExport.legacyEpoch,
            updatedAt: AyanePersonaExport.legacyEpoch,
            revision: 0,
            deviceID: "",
            roleID: RoleScope.legacyRoleID
        )
    }

    private static func persona(from defaults: UserDefaults) -> PersonaConfiguration {
        PersonaConfiguration(
            name: defaults.string(forKey: SettingsKeys.personaName) ?? "绫音",
            userName: defaults.string(forKey: SettingsKeys.userName) ?? "你",
            prompt: defaults.string(forKey: SettingsKeys.personaPrompt) ?? SettingsStore.defaultPersonaPrompt
        )
    }

    private static func settings(from defaults: UserDefaults) -> AyaneSettingsExport {
        let temperature = defaults.object(forKey: SettingsKeys.temperature) as? Double ?? 0.8
        let streamsResponses = defaults.object(forKey: SettingsKeys.streamResponses) as? Bool ?? true
        let autoExtractMemory = defaults.object(forKey: SettingsKeys.autoExtractMemory) as? Bool ?? true
        let tokenBudget = defaults.object(forKey: SettingsKeys.memoryTokenBudget) as? Int ?? 2_400
        let recentMessageLimit = defaults.object(forKey: SettingsKeys.recentMessageLimit) as? Int ?? 24
        let rawHistoryRecallEnabled = defaults.object(forKey: SettingsKeys.rawHistoryRecallEnabled) as? Bool ?? true
        let rawHistoryTokenBudget = defaults.object(forKey: SettingsKeys.rawHistoryTokenBudget) as? Int ?? 1_000
        let cloudSyncEnabled = defaults.object(forKey: SettingsKeys.cloudSyncEnabled) as? Bool ?? false
        let worldviewAutoMatchEnabled = SettingsStore.worldviewAutoMatchEnabled(defaults: defaults)
        let humanizedReplyDelayEnabled = defaults.object(forKey: SettingsKeys.humanizedReplyDelayEnabled) as? Bool ?? true
        let proactiveMessagesEnabled = defaults.object(forKey: SettingsKeys.proactiveMessagesEnabled) as? Bool ?? true
        let quietHours = SettingsStore.proactiveQuietHours(defaults: defaults)

        return AyaneSettingsExport(
            provider: AyaneProviderSettingsExport(
                providerID: SettingsStore.selectedProvider(defaults: defaults).id,
                baseURL: defaults.string(forKey: SettingsKeys.baseURL) ?? "",
                model: defaults.string(forKey: SettingsKeys.model) ?? "",
                embeddingModel: defaults.string(forKey: SettingsKeys.embeddingModel) ?? "",
                temperature: temperature,
                streamsResponses: streamsResponses
            ),
            memory: AyaneMemorySettingsExport(
                autoExtractMemory: autoExtractMemory,
                tokenBudget: tokenBudget,
                recentMessageLimit: recentMessageLimit,
                rawHistoryRecallEnabled: rawHistoryRecallEnabled,
                rawHistoryTokenBudget: rawHistoryTokenBudget
            ),
            persistence: AyanePersistenceSettingsExport(cloudSyncEnabled: cloudSyncEnabled),
            humanizedReplyDelayEnabled: humanizedReplyDelayEnabled,
            proactiveMessagesEnabled: proactiveMessagesEnabled,
            proactiveQuietStartHour: quietHours.start,
            proactiveQuietEndHour: quietHours.end,
            worldviewAutoMatchEnabled: worldviewAutoMatchEnabled
        )
    }
}

/// The document presented to SwiftUI's cross-platform file exporter.
struct AyaneDataExportDocument: FileDocument, Identifiable {
    static var readableContentTypes: [UTType] { [.json] }

    let id = UUID()
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw DataExportError.invalidDocument
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
