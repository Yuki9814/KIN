import Foundation
import SwiftData

struct BuiltInWorldDefinition: Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let worldKind: String
    let timezoneIdentifier: String
    let locationContext: String
    let commonFacts: [String]
}

/// The one role that is part of the product itself. User-created roles are
/// never represented by this catalog and are therefore not touched by its
/// migration.
struct BuiltInCompanionDefinition: Identifiable, Sendable {
    let id: UUID
    let conversationID: UUID
    let relationshipID: UUID
    let name: String
    let userName: String
    let prompt: String
    /// Kept for source compatibility with older test/support code. The new
    /// built-in has no prompt aliases.
    let legacyPromptHashes: Set<String>
    let world: BuiltInWorldDefinition
}

struct BuiltInCompanionMigrationResult: Equatable, Sendable {
    let matchedProfiles: Int
    let retiredRelationships: Int
    let archivedConversations: Int
    let archivedGroupParticipants: Int
    let cancelledMomentTasks: Int
    let cancelledMomentAIInteractionTasks: Int
    let cancelledPresentations: Int
    let cancelledProactiveTasks: Int
    let cancelledFriendApplications: Int

    var changed: Bool {
        retiredRelationships > 0
            || archivedConversations > 0
            || archivedGroupParticipants > 0
            || cancelledMomentTasks > 0
            || cancelledMomentAIInteractionTasks > 0
            || cancelledPresentations > 0
            || cancelledProactiveTasks > 0
            || cancelledFriendApplications > 0
    }

    static let none = BuiltInCompanionMigrationResult(
        matchedProfiles: 0,
        retiredRelationships: 0,
        archivedConversations: 0,
        archivedGroupParticipants: 0,
        cancelledMomentTasks: 0,
        cancelledMomentAIInteractionTasks: 0,
        cancelledPresentations: 0,
        cancelledProactiveTasks: 0,
        cancelledFriendApplications: 0
    )
}

enum BuiltInCompanionCatalog {
    static let userDisplayName = UserIdentityPolicy.displayName
    static let userDefaultAddress = UserIdentityPolicy.defaultAddress

    static let companions: [BuiltInCompanionDefinition] = [
        BuiltInCompanionDefinition(
            id: RoleScope.legacyRoleID,
            conversationID: UUID(uuidString: "7D9C7B7E-2E5A-4C7E-9B8F-7A7C3A1D4E52")!,
            relationshipID: UUID(uuidString: "1F0E6D2B-4B9C-4B5A-8B11-2A5E7C9D31F0")!,
            name: "绫音",
            userName: userDefaultAddress,
            prompt: SettingsStore.defaultPersonaPrompt,
            legacyPromptHashes: [],
            world: BuiltInWorldDefinition(
                id: WorldProfileRecord.realityID,
                displayName: "现实世界",
                worldKind: "reality",
                timezoneIdentifier: TimeZone.current.identifier,
                locationContext: "本地用户所在的现实环境",
                commonFacts: []
            )
        )
    ]

    private static let builtInRoleIDs = Set(companions.map(\.id))

    /// SHA-256 digests of the lowercased UUID text of the six retired roles.
    /// Keeping only digests in the release source avoids shipping their old
    /// names, prompts, or identifiers while still allowing late CloudKit rows
    /// to be retired safely.
    private static let retiredRoleIDSHA256: Set<String> = [
        "7777b573848bc82d3cff154b535aea2e0f2955bea30fb82fcc578b4833fc8411",
        "99082fccef3c0d9ede1b6d9d106eded163caa788435d572e0325aec8ff41d689",
        "452d951499a3814e0a68fce165f12bae635fc30ec5e41a58b08815983833bf12",
        "61bcc8756f632b7186ea8160ec8f1e0528452537b7b30c8d0379418646925424",
        "41517fa84d4361c8577504d11ada762c93059b5e7e2357c14dfe69aafeacbf70",
        "9d4fd1dac12bfe4bcc3064b277addd3e277d76d35bee0d9c8733b52458264695"
    ]

    static func contains(roleID: UUID?) -> Bool {
        builtInRoleIDs.contains(RoleScope.resolve(roleID))
    }

    static func isRetiredRoleID(_ roleID: UUID?) -> Bool {
        isRetiredRoleID(roleID, matching: retiredRoleIDSHA256)
    }

    private static func isRetiredRoleID(
        _ roleID: UUID?,
        matching digests: Set<String>
    ) -> Bool {
        guard let roleID else { return false }
        return digests.contains(roleDigest(roleID))
    }

    private static func roleDigest(_ roleID: UUID) -> String {
        ContentHasher.sha256(roleID.uuidString.lowercased())
    }

    @discardableResult
    @MainActor
    static func seedIfNeeded(
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        deviceID: String = "",
        forceAddressLabelMigration: Bool = false,
        now: Date? = nil
    ) throws -> Bool {
        let definition = companions[0]
        var changed = false
        let seedDate = now ?? Date()

        let worlds = try context.fetch(FetchDescriptor<WorldProfileRecord>())
        if worlds.first(where: { $0.id == definition.world.id }) == nil {
            context.insert(WorldProfileRecord(
                id: definition.world.id,
                displayName: definition.world.displayName,
                worldKind: definition.world.worldKind,
                timezoneIdentifier: definition.world.timezoneIdentifier,
                locationContext: definition.world.locationContext,
                commonFacts: definition.world.commonFacts,
                createdAt: seedDate,
                updatedAt: seedDate,
                revision: 1,
                deviceID: deviceID
            ))
            changed = true
        }

        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        if profiles.first(where: { $0.id == definition.id }) == nil {
            context.insert(CompanionProfileRecord(
                id: definition.id,
                worldProfileID: definition.world.id,
                name: definition.name,
                userName: definition.userName,
                prompt: definition.prompt,
                createdAt: seedDate,
                updatedAt: seedDate,
                revision: 1,
                deviceID: deviceID
            ))
            changed = true
        }

        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        if conversations.first(where: { $0.id == definition.conversationID }) == nil {
            context.insert(ConversationRecord(
                id: definition.conversationID,
                title: definition.name,
                createdAt: seedDate,
                roleID: definition.id
            ))
            changed = true
        }

        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
        if relationships.first(where: { $0.roleID == definition.id }) == nil {
            context.insert(CompanionRelationshipRecord(
                id: definition.relationshipID,
                roleID: definition.id,
                state: .accepted,
                affinityScore: 100,
                affinityTier: 3,
                createdAt: seedDate,
                updatedAt: seedDate,
                revision: 1,
                deviceID: deviceID
            ))
            changed = true
        }

        // This runs every time so a delayed sync row cannot resurrect a
        // retired role after the one-time marker has advanced. Existing
        // canonical profile values are deliberately not rewritten.
        let migration = try retireLegacyCompanions(
            in: context,
            deviceID: deviceID,
            now: seedDate
        )
        changed = changed || migration.changed
        if changed {
            try context.save()
        }
        if defaults.integer(forKey: SettingsKeys.builtInCompanionCatalogMigrationVersion)
            < SettingsStore.builtInCompanionCatalogMigrationVersion {
            defaults.set(
                SettingsStore.builtInCompanionCatalogMigrationVersion,
                forKey: SettingsKeys.builtInCompanionCatalogMigrationVersion
            )
        }
        _ = forceAddressLabelMigration
        return changed
    }

    @discardableResult
    @MainActor
    static func migrateImportedUserIdentity(
        in context: ModelContext,
        deviceID: String = ""
    ) throws -> Bool {
        try retireLegacyCompanions(in: context, deviceID: deviceID).changed
    }

    /// Retires only the old six role-owned lifecycle rows. Profile, message,
    /// event, memory and attachment rows are never deleted or rewritten.
    @discardableResult
    @MainActor
    static func retireLegacyCompanions(
        in context: ModelContext,
        deviceID: String = "",
        now: Date = Date(),
        retiredRoleDigests: Set<String>? = nil
    ) throws -> BuiltInCompanionMigrationResult {
        let digests = retiredRoleDigests ?? retiredRoleIDSHA256
        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        let relationships = try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let groupParticipants = try context.fetch(FetchDescriptor<GroupParticipantRecord>())
        let momentTasks = try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>())
        let momentAIInteractionTasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
        let presentations = try context.fetch(FetchDescriptor<ChatTurnPresentationRecord>())
        let proactiveTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let friendApplications = try context.fetch(FetchDescriptor<FriendApplicationRecord>())
        let readStates = try context.fetch(FetchDescriptor<ConversationReadStateRecord>())

        var oldRoleIDs = Set<UUID>()
        for profile in profiles where isRetiredRoleID(profile.id, matching: digests) {
            oldRoleIDs.insert(profile.id)
        }
        for relationship in relationships where isRetiredRoleID(relationship.roleID, matching: digests) {
            oldRoleIDs.insert(relationship.roleID)
        }
        for conversation in conversations
        where isRetiredRoleID(conversation.resolvedRoleID, matching: digests) {
            oldRoleIDs.insert(conversation.resolvedRoleID)
        }
        // CloudKit can deliver lifecycle rows before their profile,
        // relationship, or conversation anchor. Discover those explicit role
        // IDs too so an orphan task can never keep running until a later sync.
        for participant in groupParticipants {
            if let roleID = participant.participantRoleID,
               isRetiredRoleID(roleID, matching: digests) {
                oldRoleIDs.insert(roleID)
            }
        }
        for task in momentTasks where isRetiredRoleID(task.roleID, matching: digests) {
            oldRoleIDs.insert(task.roleID)
        }
        for task in momentAIInteractionTasks where isRetiredRoleID(task.roleID, matching: digests) {
            oldRoleIDs.insert(task.roleID)
        }
        for presentation in presentations {
            if let roleID = presentation.roleID,
               isRetiredRoleID(roleID, matching: digests) {
                oldRoleIDs.insert(roleID)
            }
        }
        for task in proactiveTasks {
            if let roleID = task.roleID,
               isRetiredRoleID(roleID, matching: digests) {
                oldRoleIDs.insert(roleID)
            }
        }
        for application in friendApplications
        where isRetiredRoleID(application.roleID, matching: digests) {
            oldRoleIDs.insert(application.roleID)
        }
        for readState in readStates where isRetiredRoleID(readState.roleID, matching: digests) {
            oldRoleIDs.insert(readState.roleID)
        }
        guard !oldRoleIDs.isEmpty else { return .none }

        var retiredRelationships = 0
        var archivedConversations = 0
        var archivedGroupParticipants = 0
        var cancelledMomentTasks = 0
        var cancelledMomentAIInteractionTasks = 0
        var cancelledPresentations = 0
        var cancelledProactiveTasks = 0
        var cancelledFriendApplications = 0

        var relationshipRoles = Set<UUID>()
        for relationship in relationships where oldRoleIDs.contains(relationship.roleID) {
            relationshipRoles.insert(relationship.roleID)
            let needsRetire = relationship.retiredAt == nil
                || relationship.state != .deleted
                || relationship.contactMembership != .archivedByUser
            guard needsRetire else { continue }
            relationship.retiredAt = relationship.retiredAt ?? now
            relationship.state = .deleted
            relationship.contactMembership = .archivedByUser
            relationship.contactStateUpdatedAt = now
            relationship.updatedAt = now
            relationship.revision = max(0, relationship.revision) + 1
            relationship.deviceID = deviceID
            retiredRelationships += 1
        }

        // A profile/conversation may arrive without its relationship row. Add
        // one retired tombstone rather than deleting or activating the role.
        for roleID in oldRoleIDs where !relationshipRoles.contains(roleID) {
            context.insert(CompanionRelationshipRecord(
                roleID: roleID,
                state: .deleted,
                affinityScore: 0,
                affinityTier: 0,
                createdAt: now,
                updatedAt: now,
                revision: 1,
                deviceID: deviceID,
                retiredAt: now,
                contactMembership: .archivedByUser,
                contactStateUpdatedAt: now
            ))
            retiredRelationships += 1
        }

        let oldConversationIDs = Set(
            conversations
                .filter { oldRoleIDs.contains($0.resolvedRoleID) }
                .map(\.id)
        )
        for conversation in conversations where oldConversationIDs.contains(conversation.id) {
            if !conversation.archived {
                conversation.archived = true
                conversation.updatedAt = now
                archivedConversations += 1
            }
        }

        if !oldConversationIDs.isEmpty {
            // Group metadata is a separate durable row from the conversation.
            // Archive it as well so a retired role cannot remain visible in a
            // group shell, while preserving its name, avatar, and history.
            for group in try context.fetch(FetchDescriptor<GroupConversationRecord>())
            where oldConversationIDs.contains(group.conversationID)
                && group.lifecycle != .archived {
                group.lifecycle = .archived
                group.updatedAt = now
                group.revision = max(0, group.revision) + 1
                group.deviceID = deviceID
                archivedConversations += 1
            }

        }

        // A participant row may sync before its ConversationRecord. Archive
        // an explicitly retired role even when the group anchor is absent.
        for participant in groupParticipants
        where oldRoleIDs.contains(participant.participantRoleID ?? RoleScope.legacyRoleID)
            || oldConversationIDs.contains(participant.conversationID)
            || oldConversationIDs.contains(participant.groupConversationID) {
            guard participant.lifecycle != .archived else { continue }
            participant.lifecycle = .archived
            participant.leftAt = participant.leftAt ?? now
            participant.updatedAt = now
            participant.revision = max(0, participant.revision) + 1
            participant.deviceID = deviceID
            archivedGroupParticipants += 1
        }

        for task in momentTasks
        where oldRoleIDs.contains(task.roleID) && !task.state.isTerminal {
            task.state = .cancelled
            task.leaseOwner = ""
            task.leaseExpiresAt = nil
            task.updatedAt = now
            task.revision = max(0, task.revision) + 1
            task.deviceID = deviceID
            cancelledMomentTasks += 1
        }

        for task in momentAIInteractionTasks
        where oldRoleIDs.contains(task.roleID) && !task.state.isTerminal {
            task.state = .cancelled
            task.nextAttemptAt = now
            task.lastError = "角色已停用。"
            task.leaseOwner = ""
            task.leaseExpiresAt = nil
            task.updatedAt = now
            task.revision = max(0, task.revision) + 1
            task.deviceID = deviceID
            cancelledMomentAIInteractionTasks += 1
        }

        for presentation in presentations
        where oldRoleIDs.contains(RoleScope.resolve(presentation.roleID))
            && !presentation.state.isTerminal {
            presentation.state = .cancelled
            presentation.cancelledAt = now
            presentation.updatedAt = now
            presentation.revision = max(0, presentation.revision) + 1
            presentation.deviceID = deviceID
            cancelledPresentations += 1
        }

        for task in proactiveTasks
        where oldRoleIDs.contains(RoleScope.resolve(task.roleID)) && !task.state.isTerminal {
            task.state = .cancelled
            task.leaseOwner = ""
            task.leaseExpiresAt = nil
            task.updatedAt = now
            task.revision = max(0, task.revision) + 1
            task.deviceID = deviceID
            cancelledProactiveTasks += 1
        }

        for application in friendApplications
        where oldRoleIDs.contains(application.roleID) && !application.status.isTerminal {
            application.status = .cancelled
            application.resolvedAt = now
            application.revision = max(0, application.revision) + 1
            application.deviceID = deviceID
            cancelledFriendApplications += 1
        }

        let result = BuiltInCompanionMigrationResult(
            matchedProfiles: profiles.filter { oldRoleIDs.contains($0.id) }.count,
            retiredRelationships: retiredRelationships,
            archivedConversations: archivedConversations,
            archivedGroupParticipants: archivedGroupParticipants,
            cancelledMomentTasks: cancelledMomentTasks,
            cancelledMomentAIInteractionTasks: cancelledMomentAIInteractionTasks,
            cancelledPresentations: cancelledPresentations,
            cancelledProactiveTasks: cancelledProactiveTasks,
            cancelledFriendApplications: cancelledFriendApplications
        )
        if result.changed {
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        return result
    }
}
