import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MomentInteractionTombstoneTests: XCTestCase {
    private struct DefaultsFixture {
        let values: UserDefaults
        let suiteName: String
    }

    private struct Fixture {
        let context: ModelContext
        let roleID: UUID
        let postID: UUID
        let interactionID: UUID
    }

    func testSoftDeleteIsIdempotentAndAdvancesTheSyncVersion() throws {
        let createdAt = date(10)
        let deletedAt = date(20)
        let record = MomentInteractionRecord(
            postID: UUID(),
            kind: .comment,
            actorKind: .user,
            body: "可删除评论",
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 4,
            deviceID: "writer"
        )

        record.softDelete(at: deletedAt, deviceID: "delete-device")
        XCTAssertEqual(record.deletedAt, deletedAt)
        XCTAssertTrue(record.isDeleted)
        XCTAssertEqual(record.updatedAt, deletedAt)
        XCTAssertEqual(record.revision, 5)
        XCTAssertEqual(record.deviceID, "delete-device")

        record.softDelete(at: date(30), deviceID: "another-device")
        XCTAssertEqual(record.deletedAt, deletedAt)
        XCTAssertEqual(record.revision, 5)
        XCTAssertEqual(record.deviceID, "delete-device")
    }

    func testExportImportPreservesDeletionAndLegacyMissingFieldReadsLive() throws {
        let fixture = try makeFixture(deletedAt: date(20), revision: 2)
        let sourceDefaults = try makeDefaults(prefix: "source")
        defer { sourceDefaults.values.removePersistentDomain(forName: sourceDefaults.suiteName) }

        let exported = try DataExportService.export(
            context: fixture.context,
            defaults: sourceDefaults.values,
            now: date(100)
        )
        let payload = try decodePayload(exported)
        let exportedInteraction = try XCTUnwrap(
            payload.momentInteractions.first(where: { $0.id == fixture.interactionID })
        )
        XCTAssertEqual(exportedInteraction.deletedAt, date(20))
        XCTAssertTrue(String(decoding: exported, as: UTF8.self).contains("deleted_at"))

        let imported = makeContext()
        let importedDefaults = try makeDefaults(prefix: "imported")
        defer { importedDefaults.values.removePersistentDomain(forName: importedDefaults.suiteName) }
        _ = try DataImportService.replaceAll(
            with: exported,
            context: imported,
            defaults: importedDefaults.values
        )
        XCTAssertEqual(
            try XCTUnwrap(
                imported.fetch(FetchDescriptor<MomentInteractionRecord>())
                    .first(where: { $0.id == fixture.interactionID })
            ).deletedAt,
            date(20)
        )

        // A pre-tombstone v4-v16 writer did not emit deleted_at. Removing the
        // optional key models that old wire shape and must remain a live
        // interaction rather than failing decode/import.
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: exported) as? [String: Any]
        )
        legacyObject["schema_version"] = 16
        var legacyInteractions = try XCTUnwrap(
            legacyObject["moment_interactions"] as? [[String: Any]]
        )
        legacyInteractions[0].removeValue(forKey: "deleted_at")
        legacyObject["moment_interactions"] = legacyInteractions
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject,
            options: [.sortedKeys]
        )
        XCTAssertNil(try XCTUnwrap(decodePayload(legacyData).momentInteractions.first).deletedAt)

        let legacyDestination = makeContext()
        let legacyDefaults = try makeDefaults(prefix: "legacy")
        defer { legacyDefaults.values.removePersistentDomain(forName: legacyDefaults.suiteName) }
        _ = try DataImportService.replaceAll(
            with: legacyData,
            context: legacyDestination,
            defaults: legacyDefaults.values
        )
        XCTAssertNil(
            try XCTUnwrap(
                legacyDestination.fetch(FetchDescriptor<MomentInteractionRecord>())
                    .first(where: { $0.id == fixture.interactionID })
            ).deletedAt
        )
    }

    func testMergeRetainsTombstoneEvenWhenAStaleLiveCopyHasHigherRevision() throws {
        let source = try makeFixture(deletedAt: date(20), revision: 2)
        let sourceDefaults = try makeDefaults(prefix: "merge-source")
        defer { sourceDefaults.values.removePersistentDomain(forName: sourceDefaults.suiteName) }
        let deletedPayload = try DataExportService.makePayload(
            context: source.context,
            defaults: sourceDefaults.values,
            now: date(100)
        )

        let destination = try makeFixture(
            deletedAt: nil,
            revision: 99,
            context: makeContext(),
            roleID: source.roleID,
            postID: source.postID,
            interactionID: source.interactionID
        )
        let report = try DataMergeService.merge(deletedPayload, into: destination.context)
        XCTAssertEqual(report.momentInteractions, .init(inserted: 0, updated: 1, unchanged: 0))
        let merged = try XCTUnwrap(
            destination.context.fetch(FetchDescriptor<MomentInteractionRecord>())
                .first(where: { $0.id == source.interactionID })
        )
        XCTAssertEqual(merged.deletedAt, date(20))

        var staleLivePayload = deletedPayload
        staleLivePayload.momentInteractions[0].deletedAt = nil
        staleLivePayload.momentInteractions[0].revision = 10_000
        staleLivePayload.momentInteractions[0].updatedAt = date(10_000)
        _ = try DataMergeService.merge(staleLivePayload, into: destination.context)
        let afterStaleLiveCopy = try XCTUnwrap(
            destination.context.fetch(FetchDescriptor<MomentInteractionRecord>())
                .first(where: { $0.id == source.interactionID })
        )
        XCTAssertEqual(afterStaleLiveCopy.deletedAt, date(20))
        XCTAssertEqual(afterStaleLiveCopy.revision, 10_000)
    }

    func testDuplicateReconciliationKeepsDeletionTombstone() throws {
        let context = makeContext()
        let postID = UUID()
        context.insert(MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "用户动态",
            publishedAt: date(1),
            createdAt: date(1),
            updatedAt: date(1),
            revision: 1,
            deviceID: "post"
        ))
        let interactionID = UUID()
        context.insert(MomentInteractionRecord(
            id: interactionID,
            postID: postID,
            kind: .comment,
            actorKind: .user,
            body: "相同评论",
            createdAt: date(2),
            updatedAt: date(5),
            revision: 9,
            deviceID: "live-copy"
        ))
        context.insert(MomentInteractionRecord(
            id: interactionID,
            postID: postID,
            kind: .comment,
            actorKind: .user,
            body: "相同评论",
            createdAt: date(2),
            updatedAt: date(4),
            deletedAt: date(4),
            revision: 1,
            deviceID: "delete-copy"
        ))
        try context.save()

        let preflight = try StoreDuplicateReconciler.preflight(context: context)
        XCTAssertEqual(preflight.momentInteractions.removed, 1)
        XCTAssertNil(
            try XCTUnwrap(
                context.fetch(FetchDescriptor<MomentInteractionRecord>())
                    .first(where: { $0.id == interactionID && $0.revision == 9 })
            ).deletedAt
        )

        let result = try StoreDuplicateReconciler.reconcile(context: context)
        XCTAssertEqual(result.momentInteractions.removed, 1)
        XCTAssertEqual(result.momentInteractions.updated, 1)
        let canonical = try XCTUnwrap(
            context.fetch(FetchDescriptor<MomentInteractionRecord>())
                .first(where: { $0.id == interactionID })
        )
        XCTAssertEqual(canonical.deletedAt, date(4))
    }

    func testUnreadMomentCountExcludesDeletedCompanionInteraction() throws {
        let context = makeContext()
        let postID = UUID()
        context.insert(MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "用户动态",
            publishedAt: date(1),
            createdAt: date(1),
            updatedAt: date(1),
            revision: 1,
            deviceID: "post"
        ))
        context.insert(MomentInteractionRecord(
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: RoleScope.legacyRoleID,
            body: "已经撤回的评论",
            createdAt: date(3),
            updatedAt: date(4),
            deletedAt: date(4),
            revision: 2,
            deviceID: "companion"
        ))
        try context.save()

        let readState = ReadStateService(context: context)
        XCTAssertEqual(try readState.unreadMomentCount(postID: postID), 0)
        XCTAssertEqual(try readState.unreadMomentCounts()[postID], 0)
    }

    func testPortableArchiveRoundTripPreservesCommentTombstone() throws {
        let source = try makeFixture(deletedAt: date(20), revision: 2)
        let sourceDefaults = try makeDefaults(prefix: "portable-source")
        defer { sourceDefaults.values.removePersistentDomain(forName: sourceDefaults.suiteName) }
        let archive = try KINPortableArchiveV1.makeArchive(
            context: source.context,
            defaults: sourceDefaults.values,
            password: "comment-tombstone-password",
            now: date(100)
        )

        let destination = makeContext()
        let destinationDefaults = try makeDefaults(prefix: "portable-destination")
        defer { destinationDefaults.values.removePersistentDomain(forName: destinationDefaults.suiteName) }
        _ = try KINPortableArchiveV1.restoreArchive(
            archive,
            password: "comment-tombstone-password",
            context: destination,
            defaults: destinationDefaults.values
        )
        XCTAssertEqual(
            try XCTUnwrap(
                destination.fetch(FetchDescriptor<MomentInteractionRecord>())
                    .first(where: { $0.id == source.interactionID })
            ).deletedAt,
            date(20)
        )
    }

    func testPortableAffinityTierUses20_50_80Boundaries() {
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 0), 0)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 19), 0)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 20), 1)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 49), 1)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 50), 2)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 79), 2)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 80), 3)
        XCTAssertEqual(KINPortableArchiveV1.affinityTier(for: 100), 3)
    }

    private func makeFixture(
        deletedAt: Date?,
        revision: Int,
        context: ModelContext? = nil,
        roleID: UUID = UUID(),
        postID: UUID = UUID(),
        interactionID: UUID = UUID()
    ) throws -> Fixture {
        let context = context ?? makeContext()
        let createdAt = date(1)
        context.insert(CompanionProfileRecord(
            id: roleID,
            name: "评论测试角色",
            userName: "主人",
            prompt: "保持自然交流。",
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 1,
            deviceID: "profile"
        ))
        let conversation = ConversationRecord(
            id: UUID(),
            title: "评论测试会话",
            createdAt: createdAt,
            roleID: roleID
        )
        context.insert(conversation)
        context.insert(MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "用户动态",
            publishedAt: createdAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            revision: 1,
            deviceID: "post"
        ))
        context.insert(MomentInteractionRecord(
            id: interactionID,
            postID: postID,
            kind: .comment,
            actorKind: .user,
            body: "可同步的评论",
            createdAt: date(2),
            updatedAt: deletedAt ?? date(2),
            deletedAt: deletedAt,
            revision: revision,
            deviceID: deletedAt == nil ? "live" : "delete-device"
        ))
        try context.save()
        return Fixture(
            context: context,
            roleID: roleID,
            postID: postID,
            interactionID: interactionID
        )
    }

    private func makeContext() -> ModelContext {
        ModelContext(PersistenceController.makeContainer(inMemory: true, preferCloud: false).container)
    }

    private func makeDefaults(prefix: String) throws -> DefaultsFixture {
        let suite = "AyaneTests.MomentInteractionTombstone.\(prefix).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        SettingsStore.registerDefaults(defaults: defaults)
        return DefaultsFixture(values: defaults, suiteName: suite)
    }

    private func decodePayload(_ data: Data) throws -> AyaneDataExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AyaneDataExport.self, from: data)
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }
}
