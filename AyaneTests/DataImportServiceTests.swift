import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class DataImportServiceTests: XCTestCase {
    func testValidatedBackupRoundTripsAllRecordsAndPreservesLocalCloudToggle() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        let fixture = try insertCompleteFixture(into: sourceContext)
        let relationship = CompanionRelationshipRecord(
            roleID: RoleScope.legacyRoleID,
            affinityScore: 68,
            affinityTier: 2,
            manualAffinityScore: 42,
            manualAffinityUpdatedAt: Date(timeIntervalSince1970: 1_700_000_020),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            revision: 7,
            deviceID: "source-device"
        )
        sourceContext.insert(relationship)
        try sourceContext.save()
        configureSourceDefaults(sourceDefaults)

        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults,
            now: exportedAt
        )
        let inspection = try DataImportService.inspect(data)
        XCTAssertEqual(inspection.exportedAt, exportedAt)
        XCTAssertEqual(inspection.profiles, 1)
        XCTAssertEqual(inspection.events, 1)
        XCTAssertEqual(inspection.memories, 1)
        XCTAssertEqual(inspection.relationships, 1)
        XCTAssertEqual(inspection.totalRecords, 7)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults()
        destinationDefaults.set(false, forKey: SettingsKeys.cloudSyncEnabled)
        destinationDefaults.set("本机角色", forKey: SettingsKeys.personaName)
        destinationDefaults.set("本机用户", forKey: SettingsKeys.userName)
        destinationDefaults.set("本机提示", forKey: SettingsKeys.personaPrompt)
        let stale = ConversationRecord(title: "应被替换")
        destinationContext.insert(stale)
        try destinationContext.save()

        let summary = try DataImportService.replaceAll(
            with: data,
            context: destinationContext,
            defaults: destinationDefaults
        )

        XCTAssertEqual(summary, inspection)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationRecord>()).map(\.id), [fixture.conversationID])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.id), [fixture.eventID])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>()).map(\.id), [fixture.memoryID])
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemorySummaryRecord>()).count, 1)
        XCTAssertEqual(try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count, 1)
        let restoredRelationship = try XCTUnwrap(
            try destinationContext.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first
        )
        XCTAssertEqual(restoredRelationship.affinityScore, 68)
        XCTAssertEqual(restoredRelationship.manualAffinityScore, 42)
        XCTAssertEqual(
            restoredRelationship.manualAffinityUpdatedAt,
            Date(timeIntervalSince1970: 1_700_000_020)
        )
        XCTAssertEqual(restoredRelationship.revision, 7)
        let profiles = try destinationContext.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, CompanionProfileRecord.singletonID)

        let sourcePayload = try decode(data)
        let restoredData = try DataExportService.export(
            context: destinationContext,
            defaults: destinationDefaults,
            now: exportedAt
        )
        let restoredPayload = try decode(restoredData)
        XCTAssertEqual(restoredPayload.conversations, sourcePayload.conversations)
        XCTAssertEqual(restoredPayload.events, sourcePayload.events)
        XCTAssertEqual(restoredPayload.memories, sourcePayload.memories)
        XCTAssertEqual(restoredPayload.evidence, sourcePayload.evidence)
        XCTAssertEqual(restoredPayload.summaries, sourcePayload.summaries)
        XCTAssertEqual(restoredPayload.tombstones, sourcePayload.tombstones)
        XCTAssertEqual(restoredPayload.relationships, sourcePayload.relationships)
        XCTAssertEqual(restoredPayload.persona, sourcePayload.persona)
        XCTAssertEqual(restoredPayload.settings.provider, sourcePayload.settings.provider)
        XCTAssertEqual(restoredPayload.settings.memory, sourcePayload.settings.memory)
        XCTAssertFalse(destinationDefaults.bool(forKey: SettingsKeys.cloudSyncEnabled))
        XCTAssertEqual(destinationDefaults.string(forKey: SettingsKeys.personaName), "本机角色")
        XCTAssertEqual(destinationDefaults.string(forKey: SettingsKeys.userName), "本机用户")
        XCTAssertEqual(destinationDefaults.string(forKey: SettingsKeys.personaPrompt), "本机提示")
        XCTAssertEqual(
            destinationDefaults.string(forKey: SettingsKeys.providerID),
            ProviderPreset.custom.rawValue
        )
    }

    func testSchema18ImportPreservesExplicitManualAffinityClear() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        let relationship = CompanionRelationshipRecord(
            roleID: RoleScope.legacyRoleID,
            affinityScore: 68,
            affinityTier: 2,
            manualAffinityScore: 42,
            manualAffinityUpdatedAt: Date(timeIntervalSince1970: 1_700_000_020),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            revision: 7,
            deviceID: "source-device"
        )
        sourceContext.insert(relationship)
        try sourceContext.save()
        configureSourceDefaults(sourceDefaults)

        let original = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults
        )
        let explicitClear = try changingJSON(original) { root in
            var relationships = try XCTUnwrap(root["relationships"] as? [[String: Any]])
            relationships[0]["manual_affinity_score"] = NSNull()
            root["relationships"] = relationships
        }
        let expectedClearTime = try XCTUnwrap(
            try decode(explicitClear).relationships.first?.manualAffinityUpdatedAt
        )

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        _ = try DataImportService.replaceAll(
            with: explicitClear,
            context: destinationContext
        )

        let restoredRelationship = try XCTUnwrap(
            try destinationContext.fetch(FetchDescriptor<CompanionRelationshipRecord>()).first
        )
        XCTAssertNil(restoredRelationship.manualAffinityScore)
        XCTAssertEqual(restoredRelationship.manualAffinityUpdatedAt, expectedClearTime)
    }

    func testLegacyBackupInfersProviderNamespaceFromRestoredURL() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        sourceDefaults.set("https://api.deepseek.com", forKey: SettingsKeys.baseURL)
        sourceDefaults.set(ProviderPreset.deepSeek.rawValue, forKey: SettingsKeys.providerID)
        let current = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let legacy = try changingJSON(current) { root in
            var settings = try XCTUnwrap(root["settings"] as? [String: Any])
            var provider = try XCTUnwrap(settings["provider"] as? [String: Any])
            provider.removeValue(forKey: "provider_id")
            settings["provider"] = provider
            root["settings"] = settings
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults()
        destinationDefaults.set(ProviderPreset.openAI.rawValue, forKey: SettingsKeys.providerID)
        try DataImportService.replaceAll(
            with: legacy,
            context: destinationContext,
            defaults: destinationDefaults
        )

        XCTAssertEqual(
            destinationDefaults.string(forKey: SettingsKeys.providerID),
            ProviderPreset.deepSeek.rawValue
        )
    }

    func testV4ImportNormalizesLegacyPersonaMetadataDeterministically() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let v5Data = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let v4Data = try changingJSON(v5Data) { root in
            root["schema_version"] = AyaneDataExport.legacySchemaVersion
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona.removeValue(forKey: "id")
            persona.removeValue(forKey: "created_at")
            persona.removeValue(forKey: "updated_at")
            persona.removeValue(forKey: "revision")
            persona.removeValue(forKey: "device_id")
            root["persona"] = persona
        }

        let inspection = try DataImportService.inspect(v4Data)
        XCTAssertEqual(inspection.profiles, 1)
        XCTAssertEqual(inspection.totalRecords, 7)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults()
        destinationDefaults.set("不应被旧备份覆盖", forKey: SettingsKeys.personaName)
        _ = try DataImportService.replaceAll(
            with: v4Data,
            context: destinationContext,
            defaults: destinationDefaults
        )

        let profiles = try destinationContext.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, CompanionProfileRecord.singletonID)
        XCTAssertEqual(profiles.first?.createdAt, AyanePersonaExport.legacyEpoch)
        XCTAssertEqual(profiles.first?.updatedAt, AyanePersonaExport.legacyEpoch)
        XCTAssertEqual(profiles.first?.revision, 0)
        XCTAssertEqual(profiles.first?.deviceID, "")
        XCTAssertEqual(destinationDefaults.string(forKey: SettingsKeys.personaName), "不应被旧备份覆盖")
    }

    func testInvalidPersonaIsRejectedBeforeReplacingAnyStoreData() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let original = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let invalid = try changingJSON(original) { root in
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona["id"] = UUID().uuidString
            root["persona"] = persona
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        let existingProfile = CompanionProfileRecord(
            id: CompanionProfileRecord.singletonID,
            name: "现有角色",
            userName: "现有用户",
            prompt: "现有提示",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            revision: 3,
            deviceID: "existing-device"
        )
        let existingConversation = ConversationRecord(title: "现有会话")
        context.insert(existingProfile)
        context.insert(existingConversation)
        try context.save()

        XCTAssertThrowsError(
            try DataImportService.replaceAll(with: invalid, context: context)
        ) { error in
            guard case DataImportError.invalidValue = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let profiles = try context.fetch(FetchDescriptor<CompanionProfileRecord>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "现有角色")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ConversationRecord>()).first?.title, "现有会话")
    }

    func testPersonaValidationRejectsEmptyOversizedAndInvalidMetadata() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let defaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(defaults)
        let original = try DataExportService.export(context: sourceContext, defaults: defaults)

        let emptyName = try changingJSON(original) { root in
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona["name"] = "  \n  "
            root["persona"] = persona
        }
        XCTAssertThrowsError(try DataImportService.inspect(emptyName)) { error in
            XCTAssertEqual(error as? DataImportError, .invalidValue("人物名称为空或过长"))
        }

        let oversizedName = try changingJSON(original) { root in
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona["name"] = String(repeating: "名", count: 81)
            root["persona"] = persona
        }
        XCTAssertThrowsError(try DataImportService.inspect(oversizedName)) { error in
            XCTAssertEqual(error as? DataImportError, .invalidValue("人物名称为空或过长"))
        }

        let negativeRevision = try changingJSON(original) { root in
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona["revision"] = -1
            root["persona"] = persona
        }
        XCTAssertThrowsError(try DataImportService.inspect(negativeRevision)) { error in
            XCTAssertEqual(error as? DataImportError, .invalidValue("人物设定 revision 无效"))
        }

        let reversedDates = try changingJSON(original) { root in
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona["created_at"] = "2025-01-02T00:00:00Z"
            persona["updated_at"] = "2025-01-01T00:00:00Z"
            root["persona"] = persona
        }
        XCTAssertThrowsError(try DataImportService.inspect(reversedDates)) { error in
            XCTAssertEqual(error as? DataImportError, .invalidValue("人物设定时间顺序错误"))
        }
    }

    func testTamperedEventHashIsRejectedBeforeExistingStoreChanges() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let original = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let tampered = try changingJSON(original) { root in
            var events = try XCTUnwrap(root["events"] as? [[String: Any]])
            events[0]["content"] = "被篡改的原文"
            root["events"] = events
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        let existing = ConversationRecord(title: "仍应保留")
        context.insert(existing)
        try context.save()

        XCTAssertThrowsError(try DataImportService.replaceAll(with: tampered, context: context)) { error in
            guard case DataImportError.invalidValue = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, existing.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ConversationEvent>()), 0)
    }

    func testInvalidEvidenceRangeAndDuplicateIDsAreRejected() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(source.container)
        let defaults = try makeDefaults()
        _ = try insertCompleteFixture(into: context)
        configureSourceDefaults(defaults)
        let original = try DataExportService.export(context: context, defaults: defaults)

        let invalidEvidence = try changingJSON(original) { root in
            var evidence = try XCTUnwrap(root["evidence"] as? [[String: Any]])
            evidence[0]["end_utf16"] = 999_999
            root["evidence"] = evidence
        }
        XCTAssertThrowsError(try DataImportService.inspect(invalidEvidence)) { error in
            guard case DataImportError.invalidValue = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let duplicateEvent = try changingJSON(original) { root in
            var events = try XCTUnwrap(root["events"] as? [[String: Any]])
            events.append(events[0])
            root["events"] = events
        }
        XCTAssertThrowsError(try DataImportService.inspect(duplicateEvent)) { error in
            XCTAssertEqual(error as? DataImportError, .duplicateRecord("事件 ID"))
        }
    }

    func testRestoreRejectsTrimCaseAndBOMDuplicateActiveCanonicalKeysAtomically() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let original = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults
        )
        let invalid = try changingJSON(original) { root in
            var memories = try XCTUnwrap(root["memories"] as? [[String: Any]])
            memories[0]["canonical_key"] = "  User.Favorite  "
            var duplicate = memories[0]
            duplicate["id"] = UUID().uuidString
            duplicate["canonical_key"] = "\u{FEFF}USER.FAVORITE\u{FEFF}"
            memories.append(duplicate)
            root["memories"] = memories
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        let existing = try insertCompleteFixture(into: context)
        let existingKey = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first?.canonicalKey
        )

        XCTAssertThrowsError(try DataImportService.replaceAll(with: invalid, context: context)) { error in
            XCTAssertEqual(error as? DataImportError, .duplicateRecord("活动记忆规范键"))
        }

        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationRecord>()).map(\.id),
            [existing.conversationID]
        )
        let memories = try context.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(memories.map(\.id), [existing.memoryID])
        XCTAssertEqual(memories.first?.canonicalKey, existingKey)
        XCTAssertEqual(memories.first?.state, .active)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MemoryTombstoneRecord>()).count, 1)
    }

    func testRestoreWritesStronglyNormalizedMemoryCanonicalKey() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let defaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(defaults)
        let original = try DataExportService.export(context: sourceContext, defaults: defaults)
        let normalizedInput = try changingJSON(original) { root in
            var memories = try XCTUnwrap(root["memories"] as? [[String: Any]])
            memories[0]["canonical_key"] = "\u{FEFF}  USER.FAVORITE  \u{FEFF}"
            root["memories"] = memories
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(destination.container)
        _ = try DataImportService.replaceAll(with: normalizedInput, context: context)

        let memory = try XCTUnwrap(
            try context.fetch(FetchDescriptor<MemoryAssertionRecord>()).first
        )
        XCTAssertEqual(memory.canonicalKey, "user.favorite")
    }

    func testV6AllowsSameCanonicalKeyAcrossRolesAndRejectsCrossRoleReferences() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        let fixture = try insertCompleteFixture(into: sourceContext)
        let secondRoleID = UUID(uuidString: "3B5A7D9E-37DE-4AF2-BE3C-7BA5A29C0B41")!
        let secondProfile = CompanionProfileRecord(
            id: secondRoleID,
            name: "另一角色",
            userName: "用户",
            prompt: "second",
            revision: 1,
            deviceID: "second-device"
        )
        let secondConversation = ConversationRecord(
            title: "另一角色会话",
            roleID: secondRoleID
        )
        let secondContent = "我也喜欢乌龙茶"
        let secondEvent = ConversationEvent(
            conversationID: secondConversation.id,
            deviceID: "second-device",
            deviceSequence: 1,
            logicalTimestamp: "1-second-device-1",
            role: .user,
            content: secondContent,
            contentHash: ContentHasher.sha256(secondContent),
            roleID: secondRoleID
        )
        let secondMemory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "乌龙茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.9,
            importance: 0.8,
            sensitive: false,
            sourceRank: 100,
            observedAt: secondEvent.occurredAt,
            extractorID: "fixture",
            deviceID: "second-device",
            roleID: secondRoleID
        )
        sourceContext.insert(secondProfile)
        sourceContext.insert(secondConversation)
        sourceContext.insert(secondEvent)
        sourceContext.insert(secondMemory)
        try sourceContext.save()
        configureSourceDefaults(sourceDefaults)

        let data = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let inspection = try DataImportService.inspect(data)
        XCTAssertEqual(inspection.profiles, 2)
        XCTAssertEqual(inspection.memories, 2)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        _ = try DataImportService.replaceAll(with: data, context: destinationContext)
        let restoredMemories = try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
        XCTAssertEqual(Set(restoredMemories.map(\.resolvedRoleID)), [RoleScope.legacyRoleID, secondRoleID])
        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
                .first(where: { $0.id == fixture.eventID })?.resolvedRoleID,
            RoleScope.legacyRoleID
        )

        let tampered = try changingJSON(data) { root in
            var events = try XCTUnwrap(root["events"] as? [[String: Any]])
            events[0]["role_id"] = secondRoleID.uuidString
            root["events"] = events
        }
        XCTAssertThrowsError(try DataImportService.inspect(tampered)) { error in
            guard case DataImportError.invalidReference = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testV4AndV5BackupsWithoutRoleIDsMapEveryRecordToLegacyRole() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        _ = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let current = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)
        let legacy = try changingJSON(current) { root in
            root["schema_version"] = 5
            root.removeValue(forKey: "profiles")
            var persona = try XCTUnwrap(root["persona"] as? [String: Any])
            persona.removeValue(forKey: "role_id")
            root["persona"] = persona
            for key in ["conversations", "events", "memories", "evidence", "summaries", "tombstones"] {
                var records = try XCTUnwrap(root[key] as? [[String: Any]])
                records = records.map { record in
                    var copy = record
                    copy.removeValue(forKey: "role_id")
                    return copy
                }
                root[key] = records
            }
        }

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        _ = try DataImportService.replaceAll(with: legacy, context: destinationContext)
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<ConversationRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<ConversationEvent>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryAssertionRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryEvidenceRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemorySummaryRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
        XCTAssertTrue(
            try destinationContext.fetch(FetchDescriptor<MemoryTombstoneRecord>())
                .allSatisfy { $0.roleID == RoleScope.legacyRoleID }
        )
    }

    func testUnsupportedSchemaAndInvalidJSONAreRejected() throws {
        XCTAssertThrowsError(try DataImportService.inspect(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? DataImportError, .invalidDocument)
        }

        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(source.container)
        let defaults = try makeDefaults()
        _ = try insertCompleteFixture(into: context)
        configureSourceDefaults(defaults)
        let original = try DataExportService.export(context: context, defaults: defaults)
        let future = try changingJSON(original) { root in
            root["schema_version"] = 999
        }
        XCTAssertThrowsError(try DataImportService.inspect(future)) { error in
            XCTAssertEqual(error as? DataImportError, .unsupportedSchema(999))
        }
    }

    func testAppModelRestoreRebindsConversationAndRebuildsRawHistoryIndex() async throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        let fixture = try insertCompleteFixture(into: sourceContext)
        configureSourceDefaults(sourceDefaults)
        let data = try DataExportService.export(context: sourceContext, defaults: sourceDefaults)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationDefaults = try makeDefaults()
        let rawIndex = LocalConversationSearchIndex(inMemory: true)
        let appModel = AppModel(
            bootstrap: destination,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: rawIndex,
            dataDefaults: destinationDefaults
        )

        let summary = try await appModel.restoreData(from: data)

        XCTAssertEqual(summary.events, 1)
        XCTAssertEqual(appModel.currentConversation.id, fixture.conversationID)
        XCTAssertEqual(appModel.messages.map(\.id), [fixture.eventID])
        XCTAssertEqual(appModel.messages.first?.content, "我最喜欢乌龙茶")
        XCTAssertEqual(appModel.memoryCount, 1)
        XCTAssertEqual(appModel.pendingMemoryCount, 0)
        let rawIndexCount = await rawIndex.count()
        let rawHits = await rawIndex.search("乌龙茶").map(\.eventID)
        XCTAssertEqual(rawIndexCount, 1)
        XCTAssertEqual(rawHits, [fixture.eventID])
    }

    func testReadStateImportMigrationSeparatesLegacyBaselineFromCurrentEmptyMarkers() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let sourceDefaults = try makeDefaults()
        let fixture = try insertCompleteFixture(into: sourceContext)
        let reply = ConversationEvent(
            conversationID: fixture.conversationID,
            deviceID: "source-device",
            deviceSequence: 8,
            logicalTimestamp: "1700000020000-source-device-8",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_020),
            role: .assistant,
            content: "新回复",
            contentHash: ContentHasher.sha256("新回复"),
            deliveryState: .complete,
            roleID: RoleScope.legacyRoleID
        )
        sourceContext.insert(reply)
        try sourceContext.save()
        configureSourceDefaults(sourceDefaults)
        let currentPayload = try DataExportService.export(
            context: sourceContext,
            defaults: sourceDefaults
        )

        let legacyPayload = try changingJSON(currentPayload) { root in
            root["schema_version"] = 9
            root.removeValue(forKey: "conversation_read_states")
            root.removeValue(forKey: "moment_read_states")
        }
        let currentPayloadWithoutMarkers = try changingJSON(currentPayload) { root in
            root.removeValue(forKey: "conversation_read_states")
            root.removeValue(forKey: "moment_read_states")
        }

        let legacyBootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let legacyContext = ModelContext(legacyBootstrap.container)
        let legacyDefaults = try makeDefaults()
        legacyDefaults.set(
            SettingsStore.readStateStorageMigrationVersion,
            forKey: SettingsKeys.readStateStorageMigrationVersion
        )
        _ = try DataImportService.replaceAll(
            with: legacyPayload,
            context: legacyContext,
            defaults: legacyDefaults
        )
        XCTAssertNil(legacyDefaults.object(forKey: SettingsKeys.readStateStorageMigrationVersion))

        let legacyApp = AppModel(
            bootstrap: legacyBootstrap,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: legacyDefaults
        )
        XCTAssertEqual(
            legacyDefaults.integer(forKey: SettingsKeys.readStateStorageMigrationVersion),
            SettingsStore.readStateStorageMigrationVersion
        )
        XCTAssertEqual(
            legacyApp.unreadCount(
                forConversationID: fixture.conversationID,
                roleID: RoleScope.legacyRoleID
            ),
            0
        )

        let currentBootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let currentContext = ModelContext(currentBootstrap.container)
        let currentDefaults = try makeDefaults()
        currentDefaults.set(
            0,
            forKey: SettingsKeys.readStateStorageMigrationVersion
        )
        _ = try DataImportService.replaceAll(
            with: currentPayloadWithoutMarkers,
            context: currentContext,
            defaults: currentDefaults
        )
        XCTAssertEqual(
            currentDefaults.integer(forKey: SettingsKeys.readStateStorageMigrationVersion),
            SettingsStore.readStateStorageMigrationVersion
        )

        let currentApp = AppModel(
            bootstrap: currentBootstrap,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: currentDefaults
        )
        XCTAssertEqual(
            currentApp.unreadCount(
                forConversationID: fixture.conversationID,
                roleID: RoleScope.legacyRoleID
            ),
            1
        )
        XCTAssertEqual(currentApp.chatUnreadCount, 1)
    }

    private struct FixtureIDs {
        let conversationID: UUID
        let eventID: UUID
        let memoryID: UUID
    }

    private func insertCompleteFixture(into context: ModelContext) throws -> FixtureIDs {
        let conversation = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "恢复测试",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        conversation.updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let content = "我最喜欢乌龙茶"
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "source-device",
            deviceSequence: 7,
            logicalTimestamp: "1700000010000-source-device-7",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_010),
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content)
        )
        event.memoryProcessedAt = Date(timeIntervalSince1970: 1_700_000_020)
        event.memoryProcessingVersion = 1
        let memory = MemoryAssertionRecord(
            kind: .preference,
            subject: "user",
            predicate: "favorite_drink",
            value: "乌龙茶",
            canonicalKey: "user.favorite_drink",
            state: .active,
            confidence: 0.98,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            observedAt: event.occurredAt,
            extractorID: "fixture",
            deviceID: "source-device"
        )
        memory.embeddingData = MemoryEmbeddingCodec.encode([0.1, 0.2, 0.3])
        memory.embeddingModelID = "fixture-embedding"
        let evidence = MemoryEvidenceRecord(
            memoryID: memory.id,
            eventID: event.id,
            startUTF16: 0,
            endUTF16: content.utf16.count,
            relation: .supports,
            quoteHash: ContentHasher.sha256(content),
            confidence: 0.98
        )
        let summary = MemorySummaryRecord(
            conversationID: conversation.id,
            scope: "session",
            content: "用户最喜欢乌龙茶。",
            firstEventID: event.id,
            lastEventID: event.id,
            coveredEventCount: 1,
            extractorID: "fixture"
        )
        let tombstone = MemoryTombstoneRecord(
            entityID: UUID(),
            entityType: "memory",
            canonicalKey: "user.old_preference",
            sourceEventIDs: [event.id],
            deviceID: "source-device",
            reason: "user_requested"
        )

        context.insert(conversation)
        context.insert(event)
        context.insert(memory)
        context.insert(evidence)
        context.insert(summary)
        context.insert(tombstone)
        try context.save()
        return FixtureIDs(conversationID: conversation.id, eventID: event.id, memoryID: memory.id)
    }

    private func configureSourceDefaults(_ defaults: UserDefaults) {
        defaults.set("https://example.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set(ProviderPreset.custom.rawValue, forKey: SettingsKeys.providerID)
        defaults.set("fixture-chat", forKey: SettingsKeys.model)
        defaults.set("fixture-embedding", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.4, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(12, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(800, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(true, forKey: SettingsKeys.cloudSyncEnabled)
        defaults.set("绫音测试", forKey: SettingsKeys.personaName)
        defaults.set("测试者", forKey: SettingsKeys.userName)
        defaults.set("保持清醒", forKey: SettingsKeys.personaPrompt)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AyaneTests.DataImport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func decode(_ data: Data) throws -> AyaneDataExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AyaneDataExport.self, from: data)
    }

    private func changingJSON(
        _ data: Data,
        change: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try change(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}
