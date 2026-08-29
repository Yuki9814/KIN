import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelMemorySearchScaleTests: XCTestCase {
    func testTenThousandEmbeddingScanFindsOldSemanticTargetWithBoundedResult() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let total = 10_001
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<total {
            let isTarget = index == total - 1
            let record = makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "scale_\(index)",
                value: isTarget ? "雨天一起听那张旧唱片" : "无关记录 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            record.embeddingData = MemoryEmbeddingCodec.encode(
                isTarget ? [1, 0, 0] : [0, 1, 0]
            )
            record.embeddingModelID = "fixture-embedding"
            writeContext.insert(record)
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "只有我们知道的约定",
            queryEmbedding: [1, 0, 0],
            embeddingModelID: "fixture-embedding"
        )

        XCTAssertTrue(snapshots.contains { $0.id == targetID.uuidString })
        XCTAssertLessThanOrEqual(snapshots.count, 848)
    }

    func testUnavailableFTSUsesBoundedSourceScanAndStillFindsOldLexicalTarget() async throws {
        let fixture = try makeFixture(
            index: LocalMemorySearchIndex(
                databaseURL: URL(fileURLWithPath: "/dev/null/ayane-memory-scale.sqlite")
            )
        )
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let total = 1_001
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<total {
            let isTarget = index == total - 1
            writeContext.insert(makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "fallback_\(index)",
                value: isTarget ? "用户最喜欢凤凰单丛乌龙茶" : "普通事项 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            ))
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "凤凰单丛乌龙茶",
            queryEmbedding: nil
        )

        XCTAssertTrue(snapshots.contains { $0.id == targetID.uuidString })
        XCTAssertLessThanOrEqual(snapshots.count, 288)
    }

    func testLargeLexicalPathUsesSharedKoreanTokenizerThroughFinalCandidates() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<1_001 {
            let isTarget = index == 1_000
            writeContext.insert(makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "korean_\(index)",
                value: isTarget ? "한국어를 함께 공부하고 싶어" : "无关事项 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            ))
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "한국어",
            queryEmbedding: nil
        )

        XCTAssertTrue(snapshots.contains { $0.id == targetID.uuidString })
        let ranked = MemoryEngine.shared.search("한국어", in: snapshots)
        XCTAssertEqual(ranked.first?.memory.id, targetID.uuidString)
    }

    func testLargeSemanticPathRejectsEmbeddingFromDifferentModel() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<1_001 {
            let isTarget = index == 1_000
            let record = makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "model_switch_\(index)",
                value: isTarget ? "雨天听旧唱片" : "普通事项 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            record.embeddingData = MemoryEmbeddingCodec.encode(
                isTarget ? [1, 0, 0] : [0, 1, 0]
            )
            record.embeddingModelID = "old-embedding-model"
            writeContext.insert(record)
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "只有语义能够命中",
            queryEmbedding: [1, 0, 0],
            embeddingModelID: "new-embedding-model"
        )

        XCTAssertFalse(snapshots.contains { $0.id == targetID.uuidString })
        XCTAssertTrue(snapshots.allSatisfy { $0.embedding == nil })
    }

    func testForcedStoreRevisionRebuildsFTSWhenTextChangesAtSameTimestamp() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var target: MemoryAssertionRecord?

        for index in 0..<1_001 {
            let isTarget = index == 1_000
            let record = makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "revision_\(index)",
                value: isTarget ? "旧暗号青石桥" : "普通事项 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            if isTarget { target = record }
            writeContext.insert(record)
        }
        try writeContext.save()

        let before = try await fixture.appModel.memorySnapshotsForSearch(
            query: "青石桥",
            queryEmbedding: nil
        )
        XCTAssertTrue(before.contains { $0.id == targetID.uuidString })

        let originalTimestamp = try XCTUnwrap(target).updatedAt
        target?.value = "新暗号白鹭洲"
        target?.updatedAt = originalTimestamp
        try writeContext.save()
        fixture.appModel.refreshFromStore(force: true)

        let after = try await fixture.appModel.memorySnapshotsForSearch(
            query: "白鹭洲",
            queryEmbedding: nil
        )
        XCTAssertTrue(after.contains { $0.id == targetID.uuidString })
        let stale = try await fixture.appModel.memorySnapshotsForSearch(
            query: "青石桥",
            queryEmbedding: nil
        )
        XCTAssertFalse(stale.contains { $0.id == targetID.uuidString })
    }

    func testMiddleActiveRecordChangeAtSameCountAndBoundariesRebuildsFTS() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let fixture = try makeFixture(index: index)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let total = 1_001
        let middleIndex = 500
        let targetID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var target: MemoryAssertionRecord?

        for index in 0..<total {
            let isTarget = index == middleIndex
            let record = makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: "middle_\(index)",
                value: isTarget ? "legacyquartzsignal" : "普通事项 \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            if isTarget { target = record }
            writeContext.insert(record)
        }
        try writeContext.save()

        let before = try await fixture.appModel.memorySnapshotsForSearch(
            query: "legacyquartzsignal",
            queryEmbedding: nil
        )
        XCTAssertTrue(before.contains { $0.id == targetID.uuidString })

        let originalTimestamp = try XCTUnwrap(target).updatedAt
        target?.value = "currenttopazsignal"
        target?.canonicalKey = "scale.middle.replaced"
        // Keep this row strictly between its neighbors so both source
        // boundaries and the active count remain unchanged.
        target?.updatedAt = originalTimestamp.addingTimeInterval(0.25)
        try writeContext.save()
        fixture.appModel.refreshFromStore(force: true)

        let after = try await fixture.appModel.memorySnapshotsForSearch(
            query: "currenttopazsignal",
            queryEmbedding: nil
        )
        XCTAssertTrue(after.contains { $0.id == targetID.uuidString })

        let stale = try await fixture.appModel.memorySnapshotsForSearch(
            query: "legacyquartzsignal",
            queryEmbedding: nil
        )
        XCTAssertFalse(stale.contains { $0.id == targetID.uuidString })
        let staleIndex = await index.search("legacyquartzsignal")
        XCTAssertFalse(staleIndex.contains { $0.assertionID == targetID })

        let activeState = MemoryState.active.rawValue
        let sourceRecords = try writeContext.fetch(
            FetchDescriptor<MemoryAssertionRecord>(
                predicate: #Predicate { $0.stateRaw == activeState },
                sortBy: [
                    SortDescriptor(\MemoryAssertionRecord.updatedAt, order: .reverse),
                    SortDescriptor(\MemoryAssertionRecord.id, order: .reverse)
                ]
            )
        )
        XCTAssertEqual(sourceRecords.count, total)
        XCTAssertEqual(sourceRecords.first?.updatedAt, now)
        XCTAssertEqual(sourceRecords.last?.updatedAt, now.addingTimeInterval(Double(-(total - 1))))
    }

    func testMemoryIndexDeduplicatesPhysicalCopiesWithSameIDAndTimestamp() async throws {
        let index = LocalMemorySearchIndex(inMemory: true)
        let fixture = try makeFixture(index: index)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let duplicateID = UUID()

        // Two physical rows represent one application UUID and have identical
        // timestamp ordering. The user-verified winner must be selected during
        // every batch/manifest pass, without counting both copies.
        let alpha = makeMemory(
            id: duplicateID,
            predicate: "duplicate",
            value: "currenttopazsignal",
            updatedAt: now
        )
        let omega = makeMemory(
            id: duplicateID,
            predicate: "duplicate",
            value: "legacyquartzsignal",
            updatedAt: now
        )
        alpha.userVerified = true
        writeContext.insert(alpha)
        writeContext.insert(omega)

        for index in 0..<1_000 {
            writeContext.insert(makeMemory(
                id: UUID(),
                predicate: "duplicate_fill_\(index)",
                value: "ordinary_fill_\(index)",
                updatedAt: now.addingTimeInterval(Double(-(index + 1)))
            ))
        }
        try writeContext.save()

        // A large lexical request forces the staged index path. The direct
        // index assertions isolate deterministic physical-row resolution from
        // MemoryLibrary's separate visible-record policy.
        _ = try await fixture.appModel.memorySnapshotsForSearch(
            query: "no_index_match",
            queryEmbedding: nil
        )

        let indexedCount = await index.count()
        let alphaMatches = await index.search("currenttopazsignal")
        let omegaMatches = await index.search("legacyquartzsignal")
        XCTAssertEqual(indexedCount, 1_001)
        XCTAssertEqual(alphaMatches.map(\.assertionID), [duplicateID])
        XCTAssertFalse(omegaMatches.contains { $0.assertionID == duplicateID })
    }

    func testSmallSearchRejectsActiveCopyWhenForgottenPhysicalCopyExists() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let memoryID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_100_000)

        let active = makeMemory(
            id: memoryID,
            predicate: "small_mixed",
            value: "small-private-token",
            updatedAt: now
        )
        let forgotten = makeMemory(
            id: memoryID,
            predicate: "small_mixed",
            value: "must-not-return",
            updatedAt: now.addingTimeInterval(-1),
            state: .forgotten
        )
        writeContext.insert(active)
        writeContext.insert(forgotten)
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "small-private-token",
            queryEmbedding: nil
        )

        XCTAssertFalse(snapshots.contains { $0.id == memoryID.uuidString })
    }

    func testBoundedWindowRejectsActiveCopyWhenForgottenPhysicalCopyExists() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let total = 1_001
        let mixedID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_200_000)
        let active = makeMemory(
            id: mixedID,
            predicate: "bounded_mixed",
            value: "bounded-private-token",
            updatedAt: now
        )
        active.isPinned = true
        let forgotten = makeMemory(
            id: mixedID,
            predicate: "bounded_mixed",
            value: "must-not-return",
            updatedAt: now.addingTimeInterval(-1),
            state: .forgotten
        )
        writeContext.insert(active)
        writeContext.insert(forgotten)
        for index in 0..<(total - 1) {
            writeContext.insert(makeMemory(
                id: UUID(),
                predicate: "bounded_fill_\(index)",
                value: "ordinary bounded item \(index)",
                updatedAt: now.addingTimeInterval(Double(-(index + 1)))
            ))
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "bounded-private-token",
            queryEmbedding: nil
        )

        XCTAssertFalse(snapshots.contains { $0.id == mixedID.uuidString })
    }

    func testStreamedScanRejectsOldActiveCopyWhenForgottenPhysicalCopyExists() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let total = 1_001
        let mixedID = UUID()
        let now = Date(timeIntervalSince1970: 1_800_300_000)
        let active = makeMemory(
            id: mixedID,
            predicate: "streamed_mixed",
            value: "streamed-private-token",
            updatedAt: now.addingTimeInterval(Double(-total)),
            state: .active
        )
        active.embeddingData = MemoryEmbeddingCodec.encode([1, 0, 0])
        active.embeddingModelID = "fixture-embedding"
        let forgotten = makeMemory(
            id: mixedID,
            predicate: "streamed_mixed",
            value: "must-not-return",
            updatedAt: now.addingTimeInterval(Double(-total - 1)),
            state: .forgotten
        )
        forgotten.embeddingData = MemoryEmbeddingCodec.encode([1, 0, 0])
        forgotten.embeddingModelID = "fixture-embedding"
        writeContext.insert(active)
        writeContext.insert(forgotten)
        for index in 0..<(total - 1) {
            let filler = makeMemory(
                id: UUID(),
                predicate: "streamed_fill_\(index)",
                value: "ordinary streamed item \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            filler.embeddingData = MemoryEmbeddingCodec.encode([0, 1, 0])
            filler.embeddingModelID = "fixture-embedding"
            writeContext.insert(filler)
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "no-lexical-match",
            queryEmbedding: [1, 0, 0],
            embeddingModelID: "fixture-embedding"
        )

        XCTAssertFalse(snapshots.contains { $0.id == mixedID.uuidString })
    }

    func testRoleScopedSearchKeepsActiveCopyWhenOtherRoleForgottenCopySharesID() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let targetRole = UUID()
        let otherRole = UUID()
        let sharedID = UUID()
        let total = 1_001
        let now = Date(timeIntervalSince1970: 1_800_500_000)

        let forgottenCopy = makeMemory(
            id: sharedID,
            predicate: "shared_uuid",
            value: "role-a-forgotten-copy",
            updatedAt: now.addingTimeInterval(1),
            state: .forgotten
        )
        forgottenCopy.roleID = otherRole
        writeContext.insert(forgottenCopy)

        for index in 0..<total {
            let isTarget = index == total - 1
            let record = makeMemory(
                id: isTarget ? sharedID : UUID(),
                predicate: isTarget ? "shared_uuid" : "target_role_fill_\(index)",
                value: isTarget ? "role-b-active-target" : "ordinary target-role item \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            record.roleID = targetRole
            writeContext.insert(record)
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: "role-b-active-target",
            queryEmbedding: nil,
            roleID: targetRole
        )

        XCTAssertTrue(snapshots.contains { $0.id == sharedID.uuidString })
    }

    func testRoleScopedFTSRetainsTargetWhenOtherRoleFillsLexicalCandidateLimit() async throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let writeContext = ModelContext(fixture.bootstrap.container)
        let targetRole = UUID()
        let otherRole = UUID()
        let targetID = UUID()
        let targetCount = 1_001
        let otherRoleMatchCount = 241
        let query = "rolescopecollisiontoken"
        let now = Date(timeIntervalSince1970: 1_800_600_000)

        for index in 0..<otherRoleMatchCount {
            let record = makeMemory(
                id: UUID(),
                predicate: "other_role_match_\(index)",
                value: Array(repeating: query, count: 4).joined(separator: " "),
                updatedAt: now.addingTimeInterval(Double(targetCount + index + 1))
            )
            record.roleID = otherRole
            writeContext.insert(record)
        }

        for index in 0..<targetCount {
            let isTarget = index == targetCount - 1
            let record = makeMemory(
                id: isTarget ? targetID : UUID(),
                predicate: isTarget ? "target_role_match" : "target_role_fill_\(index)",
                value: isTarget ? query : "unrelated target-role item \(index)",
                updatedAt: now.addingTimeInterval(Double(-index))
            )
            record.roleID = targetRole
            writeContext.insert(record)
        }
        try writeContext.save()

        let snapshots = try await fixture.appModel.memorySnapshotsForSearch(
            query: query,
            queryEmbedding: nil,
            roleID: targetRole
        )

        XCTAssertTrue(snapshots.contains { $0.id == targetID.uuidString })
    }

    func testHistoricalForgottenMemoryEvidenceSuppressesCandidateEvent() throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = ModelContext(fixture.bootstrap.container)
        let eventID = UUID()
        let memoryID = UUID()
        let forgotten = makeMemory(
            id: memoryID,
            predicate: "forgotten_evidence",
            value: "historical-private-token",
            updatedAt: Date(timeIntervalSince1970: 1_800_400_000),
            state: .forgotten
        )
        let evidence = MemoryEvidenceRecord(
            memoryID: memoryID,
            eventID: eventID,
            startUTF16: 0,
            endUTF16: 22,
            relation: .supports,
            quoteHash: ContentHasher.sha256("historical-private-token"),
            confidence: 1
        )
        context.insert(forgotten)
        context.insert(evidence)
        try context.save()

        let suppressed = try fixture.appModel.fetchHistoricalForgottenMemoryEvidenceEventIDs(
            forEventIDs: Set([eventID]),
            context: context
        )

        XCTAssertEqual(suppressed, Set([eventID]))
    }

    func testHistoricalTombstonesMatchLowercaseSplitPhysicalCopiesPerCandidate() throws {
        let fixture = try makeFixture(index: LocalMemorySearchIndex(inMemory: true))
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let context = ModelContext(fixture.bootstrap.container)
        let tombstoneID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let firstEventID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let secondEventID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
        let memoryID = UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!

        let firstCopy = MemoryTombstoneRecord(
            entityID: memoryID,
            entityType: "memory",
            canonicalKey: "split.sources",
            sourceEventIDs: [firstEventID],
            deviceID: "fixture"
        )
        firstCopy.id = tombstoneID
        firstCopy.sourceEventIDsRaw = firstEventID.uuidString.lowercased()
        firstCopy.deletedAt = Date(timeIntervalSince1970: 100)

        let secondCopy = MemoryTombstoneRecord(
            entityID: memoryID,
            entityType: "memory",
            canonicalKey: "split.sources",
            sourceEventIDs: [secondEventID],
            deviceID: "fixture"
        )
        secondCopy.id = tombstoneID
        secondCopy.sourceEventIDsRaw = secondEventID.uuidString
        secondCopy.deletedAt = Date(timeIntervalSince1970: 101)

        context.insert(firstCopy)
        context.insert(secondCopy)
        try context.save()

        let suppressed = try fixture.appModel.fetchHistoricalSuppressedEventIDs(
            forEventIDs: Set([firstEventID, secondEventID]),
            context: context
        )

        XCTAssertEqual(suppressed, Set([firstEventID, secondEventID]))
    }

    private func makeFixture(
        index: LocalMemorySearchIndex
    ) throws -> (
        bootstrap: PersistenceBootstrap,
        appModel: AppModel,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "AppModelMemorySearchScaleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            memoryIndex: index,
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "" }
        )
        return (bootstrap, appModel, defaults, suiteName)
    }

    private func makeMemory(
        id: UUID,
        predicate: String,
        value: String,
        updatedAt: Date,
        state: MemoryState = .active
    ) -> MemoryAssertionRecord {
        let record = MemoryAssertionRecord(
            id: id,
            kind: .preference,
            subject: "user",
            predicate: predicate,
            value: value,
            canonicalKey: "scale.\(predicate)",
            state: state,
            confidence: 1,
            importance: 0.8,
            sensitive: false,
            sourceRank: 300,
            extractorID: "scale-test",
            deviceID: "scale-device"
        )
        record.createdAt = updatedAt
        record.updatedAt = updatedAt
        return record
    }
}
