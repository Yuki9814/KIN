import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class StorageMigrationCoordinatorTests: XCTestCase {
    func testJournalRoundTripAndClear() throws {
        let defaults = try makeDefaults()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let staged = try StorageMigrationJournal.stage(
            source: .local,
            target: .cloud,
            defaults: defaults,
            now: now
        )

        XCTAssertEqual(staged.source, .local)
        XCTAssertEqual(staged.target, .cloud)
        XCTAssertEqual(staged.requestedAt, now)
        XCTAssertEqual(try StorageMigrationJournal.load(defaults: defaults), staged)

        StorageMigrationJournal.clear(defaults: defaults)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
    }

    func testUnreadableJournalIsRejectedWithoutDeletion() throws {
        let defaults = try makeDefaults()
        let invalid = Data("not-a-property-list".utf8)
        defaults.set(invalid, forKey: StorageMigrationJournal.defaultsKey)

        XCTAssertThrowsError(try StorageMigrationJournal.load(defaults: defaults)) { error in
            XCTAssertEqual(error as? StorageMigrationJournalError, .unreadableJournal)
        }
        XCTAssertEqual(defaults.data(forKey: StorageMigrationJournal.defaultsKey), invalid)
    }

    func testAppModelStagesLiveSourceDirectionAndCanCancelBeforeRestart() throws {
        let defaults = try makeDefaults()
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )

        let message = try appModel.prepareStorageSwitch(toCloud: true)
        let pending = try XCTUnwrap(StorageMigrationJournal.load(defaults: defaults))
        XCTAssertEqual(pending.source, .local)
        XCTAssertEqual(pending.target, .cloud)
        XCTAssertEqual(appModel.pendingStorageTarget, .cloud)
        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.cloudSyncEnabled))
        XCTAssertFalse(appModel.isUsingCloud, "Staging must not pretend the live container already switched.")
        XCTAssertTrue(message.contains("下次启动"))

        _ = try appModel.prepareStorageSwitch(toCloud: false)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNil(appModel.pendingStorageTarget)
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.cloudSyncEnabled))
        XCTAssertFalse(appModel.isUsingCloud)
    }

    func testResumeDefersWhenRequestedCloudFellBackToLocal() throws {
        let defaults = try makeDefaults()
        _ = try StorageMigrationJournal.stage(
            source: .local,
            target: .cloud,
            defaults: defaults
        )
        let actualLocal = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        var factoryWasCalled = false

        let result = StorageMigrationCoordinator.resumeIfNeeded(
            destination: actualLocal,
            defaults: defaults,
            sourceFactory: { _ in
                factoryWasCalled = true
                return actualLocal
            }
        )

        XCTAssertEqual(result.state, .deferred)
        XCTAssertFalse(factoryWasCalled)
        XCTAssertNotNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertTrue(result.message?.contains("尚不可用") == true)
    }

    func testResumeMergesLiveSourceThenClearsJournalAndKeepsSource() throws {
        let defaults = try makeDefaults()
        _ = try StorageMigrationJournal.stage(
            source: .local,
            target: .cloud,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let conversation = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "迁移源"
        )
        sourceContext.insert(conversation)
        try sourceContext.save()

        // This event is written after the switch was staged. Startup migration
        // must read the live source store rather than an earlier JSON snapshot.
        let lateContent = "确认切换后仍然新增的消息"
        let lateEvent = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "source-device",
            deviceSequence: 1,
            logicalTimestamp: "1700000001000-source-device-1",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_001),
            role: .user,
            content: lateContent,
            contentHash: ContentHasher.sha256(lateContent)
        )
        sourceContext.insert(lateEvent)
        try sourceContext.save()

        let destinationBase = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destination = PersistenceBootstrap(
            container: destinationBase.container,
            cloudRequested: true,
            usingCloud: true,
            configurationName: "TestCloud",
            storageURL: destinationBase.storageURL,
            warning: nil
        )

        let result = StorageMigrationCoordinator.resumeIfNeeded(
            destination: destination,
            defaults: defaults,
            sourceFactory: { requestedCloud in
                XCTAssertFalse(requestedCloud)
                return source
            }
        )

        XCTAssertEqual(result.state, .completed)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.cloudSyncEnabled))

        let destinationContext = ModelContext(destination.container)
        XCTAssertEqual(
            try destinationContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.content),
            [lateContent]
        )
        XCTAssertEqual(
            try sourceContext.fetch(FetchDescriptor<ConversationEvent>()).map(\.content),
            [lateContent],
            "Successful migration must not delete or rewrite the source store."
        )
    }

    func testCloudFallbackStagesJournalAndLaterCloudResumeIncludesFallbackWrites() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: SettingsKeys.cloudSyncEnabled)

        let local = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let fallback = PersistenceBootstrap(
            container: local.container,
            cloudRequested: true,
            usingCloud: false,
            configurationName: local.configurationName,
            storageURL: local.storageURL,
            warning: local.warning
        )
        let staged = StorageMigrationCoordinator.ensureFallbackJournalIfNeeded(
            destination: fallback,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_800_000_100)
        )

        XCTAssertEqual(staged.state, .deferred)
        let migration = try XCTUnwrap(StorageMigrationJournal.load(defaults: defaults))
        XCTAssertEqual(migration.source, .local)
        XCTAssertEqual(migration.target, .cloud)

        let sourceContext = ModelContext(local.container)
        let conversation = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "回退期间写入"
        )
        sourceContext.insert(conversation)
        let content = "云端恢复后应包含的本机回退期间消息"
        sourceContext.insert(ConversationEvent(
            conversationID: conversation.id,
            deviceID: "fallback-device",
            deviceSequence: 1,
            logicalTimestamp: "1800000100000-fallback-device-1",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_101),
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content)
        ))
        try sourceContext.save()

        let cloud = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let cloudDestination = PersistenceBootstrap(
            container: cloud.container,
            cloudRequested: true,
            usingCloud: true,
            configurationName: "TestCloud",
            storageURL: cloud.storageURL,
            warning: nil
        )
        let result = StorageMigrationCoordinator.resumeIfNeeded(
            destination: cloudDestination,
            defaults: defaults,
            sourceFactory: { requestedCloud in
                XCTAssertFalse(requestedCloud)
                return local
            }
        )

        XCTAssertEqual(result.state, .completed)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertEqual(
            try ModelContext(cloud.container).fetch(FetchDescriptor<ConversationEvent>()).map(\.content),
            [content]
        )
    }

    func testCloudToLocalResumeRetainsDrainJournalAndSessionDrainsLateSourceEventIdempotently() throws {
        let defaults = try makeDefaults()
        let migration = try StorageMigrationJournal.stage(
            source: .cloud,
            target: .local,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_800_000_200)
        )

        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let conversation = ConversationRecord(
            id: AppModel.defaultConversationID,
            title: "延迟云端源"
        )
        sourceContext.insert(conversation)
        let firstContent = "首个云端事件"
        sourceContext.insert(ConversationEvent(
            conversationID: conversation.id,
            deviceID: "cloud-device",
            deviceSequence: 1,
            logicalTimestamp: "1800000200000-cloud-device-1",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_201),
            role: .user,
            content: firstContent,
            contentHash: ContentHasher.sha256(firstContent)
        ))
        try sourceContext.save()

        let local = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let result = StorageMigrationCoordinator.resumeIfNeeded(
            destination: local,
            defaults: defaults,
            sourceFactory: { requestedCloud in
                XCTAssertTrue(requestedCloud)
                return PersistenceBootstrap(
                    container: source.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: source.storageURL,
                    warning: nil
                )
            }
        )

        XCTAssertEqual(result.state, .draining)
        XCTAssertEqual(try StorageMigrationJournal.load(defaults: defaults), migration)
        let drainState = try XCTUnwrap(CloudSourceDrainJournal.load(defaults: defaults))
        XCTAssertEqual(drainState.migrationID, migration.id)
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.cloudSyncEnabled))

        let lateContent = "首次快照之后才到达的云端事件"
        sourceContext.insert(ConversationEvent(
            conversationID: conversation.id,
            deviceID: "cloud-device",
            deviceSequence: 2,
            logicalTimestamp: "1800000200001-cloud-device-2",
            occurredAt: Date(timeIntervalSince1970: 1_800_000_202),
            role: .assistant,
            content: lateContent,
            contentHash: ContentHasher.sha256(lateContent)
        ))
        try sourceContext.save()

        let session = CloudSourceDrainSession(
            destination: local,
            defaults: defaults,
            sourceFactory: { _ in
                PersistenceBootstrap(
                    container: source.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: source.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )
        let firstDrain = session.drainNow(now: Date(timeIntervalSince1970: 1_800_000_203))
        let secondDrain = session.drainNow(now: Date(timeIntervalSince1970: 1_800_000_204))

        XCTAssertEqual(firstDrain.status, .waiting)
        XCTAssertEqual(secondDrain.status, .waiting)
        XCTAssertEqual(firstDrain.report?.events.inserted, 1)
        XCTAssertEqual(secondDrain.report?.events.unchanged, 2)
        XCTAssertTrue(session.snapshot.sourceContainerRetained)
        XCTAssertEqual(
            try ModelContext(local.container)
                .fetch(FetchDescriptor<ConversationEvent>())
                .map(\.content),
            [firstContent, lateContent]
        )
        XCTAssertNotNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNotNil(try CloudSourceDrainJournal.load(defaults: defaults))
    }

    func testAutomaticFallbackNeverOverwritesExistingOrCorruptJournal() throws {
        let defaults = try makeDefaults()
        let local = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let fallback = PersistenceBootstrap(
            container: local.container,
            cloudRequested: true,
            usingCloud: false,
            configurationName: local.configurationName,
            storageURL: local.storageURL,
            warning: nil
        )

        _ = try StorageMigrationJournal.stage(
            source: .cloud,
            target: .local,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_800_000_300)
        )
        let existingBytes = try XCTUnwrap(defaults.data(forKey: StorageMigrationJournal.defaultsKey))
        _ = StorageMigrationCoordinator.ensureFallbackJournalIfNeeded(
            destination: fallback,
            defaults: defaults
        )
        XCTAssertEqual(defaults.data(forKey: StorageMigrationJournal.defaultsKey), existingBytes)

        let corrupt = Data("corrupt-journal".utf8)
        defaults.set(corrupt, forKey: StorageMigrationJournal.defaultsKey)
        _ = StorageMigrationCoordinator.ensureFallbackJournalIfNeeded(
            destination: fallback,
            defaults: defaults
        )
        XCTAssertEqual(defaults.data(forKey: StorageMigrationJournal.defaultsKey), corrupt)
    }

    func testDrainMarkerRequiresMatchingCloudToLocalMigration() throws {
        let missingDefaults = try makeDefaults()
        _ = try CloudSourceDrainJournal.beginIfAbsent(
            migrationID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_000_400),
            defaults: missingDefaults
        )
        let missingMarkerBytes = try XCTUnwrap(
            missingDefaults.data(forKey: CloudSourceDrainJournal.defaultsKey)
        )
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        var missingFactoryCalled = false
        let missingSession = CloudSourceDrainSession(
            destination: destination,
            defaults: missingDefaults,
            sourceFactory: { _ in
                missingFactoryCalled = true
                return destination
            },
            pollInterval: nil
        )

        let missingResult = missingSession.drainNow()

        XCTAssertEqual(
            missingResult.status,
            .failed(CloudSourceDrainJournalError.missingMigration.localizedDescription)
        )
        XCTAssertFalse(missingFactoryCalled)
        XCTAssertEqual(
            missingDefaults.data(forKey: CloudSourceDrainJournal.defaultsKey),
            missingMarkerBytes
        )

        let mismatchDefaults = try makeDefaults()
        _ = try StorageMigrationJournal.stage(
            source: .cloud,
            target: .local,
            defaults: mismatchDefaults
        )
        _ = try CloudSourceDrainJournal.beginIfAbsent(
            migrationID: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_800_000_401),
            defaults: mismatchDefaults
        )
        let migrationBytes = try XCTUnwrap(
            mismatchDefaults.data(forKey: StorageMigrationJournal.defaultsKey)
        )
        let mismatchMarkerBytes = try XCTUnwrap(
            mismatchDefaults.data(forKey: CloudSourceDrainJournal.defaultsKey)
        )
        var mismatchFactoryCalled = false
        let mismatchSession = CloudSourceDrainSession(
            destination: destination,
            defaults: mismatchDefaults,
            sourceFactory: { _ in
                mismatchFactoryCalled = true
                return destination
            },
            pollInterval: nil
        )

        let mismatchResult = mismatchSession.drainNow()

        XCTAssertEqual(
            mismatchResult.status,
            .failed(CloudSourceDrainJournalError.migrationMismatch.localizedDescription)
        )
        XCTAssertFalse(mismatchFactoryCalled)
        XCTAssertEqual(
            mismatchDefaults.data(forKey: StorageMigrationJournal.defaultsKey),
            migrationBytes
        )
        XCTAssertEqual(
            mismatchDefaults.data(forKey: CloudSourceDrainJournal.defaultsKey),
            mismatchMarkerBytes
        )
    }

    func testReentrantConfirmedStopPreventsDrainWrite() throws {
        let defaults = try makeDefaults()
        let migration = try StorageMigrationJournal.stage(
            source: .cloud,
            target: .local,
            defaults: defaults
        )
        _ = try CloudSourceDrainJournal.beginIfAbsent(
            migrationID: migration.id,
            startedAt: migration.requestedAt,
            defaults: defaults
        )

        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let conversation = ConversationRecord(id: AppModel.defaultConversationID, title: "重入源")
        let content = "停止后不应写入"
        sourceContext.insert(conversation)
        sourceContext.insert(ConversationEvent(
            conversationID: conversation.id,
            deviceID: "reentrant-stop",
            deviceSequence: 1,
            logicalTimestamp: "reentrant-stop-1",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content)
        ))
        try sourceContext.save()

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        var sourceFactoryCalled = false
        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in
                sourceFactoryCalled = true
                return PersistenceBootstrap(
                    container: source.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: source.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )
        session.onUpdate = { snapshot in
            if snapshot.status == .draining {
                session.confirmStopAfterUserConfirmation()
            }
        }

        let result = session.drainNow()

        XCTAssertEqual(result.status, .stopped)
        XCTAssertFalse(sourceFactoryCalled)
        XCTAssertEqual(
            try ModelContext(destination.container).fetch(FetchDescriptor<ConversationEvent>()).count,
            0
        )
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNil(try CloudSourceDrainJournal.load(defaults: defaults))
    }

    func testHugeFinitePollIntervalIsSafelyClamped() throws {
        let defaults = try makeDefaults()
        let migration = try StorageMigrationJournal.stage(
            source: .cloud,
            target: .local,
            defaults: defaults
        )
        _ = try CloudSourceDrainJournal.beginIfAbsent(
            migrationID: migration.id,
            startedAt: migration.requestedAt,
            defaults: defaults
        )
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in destination },
            pollInterval: .greatestFiniteMagnitude
        )

        session.start()
        session.cancel()

        XCTAssertEqual(session.status, .cancelled)
        XCTAssertEqual(session.snapshot.attempts, 0)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "AyaneTests.StorageMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
