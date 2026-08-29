import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class CloudSourceDrainAppModelTests: XCTestCase {
    func testDrainStateIsVisibleAndRequiresExplicitStop() throws {
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
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )

        XCTAssertTrue(appModel.isCloudSourceDrainActive)
        XCTAssertNil(
            appModel.pendingStorageTarget,
            "The local target is already active; the remaining state is a source drain, not a future switch."
        )

        _ = try appModel.prepareStorageSwitch(toCloud: false)
        XCTAssertNotNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNotNil(try CloudSourceDrainJournal.load(defaults: defaults))

        let message = appModel.confirmCloudSourceDrainStop()
        XCTAssertFalse(appModel.isCloudSourceDrainActive)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNil(try CloudSourceDrainJournal.load(defaults: defaults))
        XCTAssertTrue(message.contains("停止"))
    }

    func testAttachedDrainMergesLateEventAndPublishesStatus() throws {
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
        let appModel = AppModel(
            bootstrap: destination,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )

        let sourceBase = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(sourceBase.container)
        let conversation = ConversationRecord(id: AppModel.defaultConversationID, title: "云端源")
        let content = "首次切换后延迟到达的内容"
        let event = ConversationEvent(
            conversationID: conversation.id,
            deviceID: "drain-test",
            deviceSequence: 1,
            logicalTimestamp: "drain-test-1",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content)
        )
        sourceContext.insert(conversation)
        sourceContext.insert(event)
        try sourceContext.save()

        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { requestedCloud in
                XCTAssertTrue(requestedCloud)
                return PersistenceBootstrap(
                    container: sourceBase.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: sourceBase.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )
        appModel.attachCloudSourceDrainSession(session)
        let result = session.drainNow()

        XCTAssertEqual(result.status, .waiting)
        XCTAssertTrue(appModel.isCloudSourceDrainActive)
        XCTAssertTrue(appModel.cloudSourceDrainStatusText?.contains("成功检查 1 次") == true)
        XCTAssertTrue(appModel.messages.contains { $0.content == content })
    }

    func testSourceConflictBlocksAppUntilExplicitDrainStop() throws {
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
        let appModel = AppModel(
            bootstrap: destination,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )

        let sourceBase = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(sourceBase.container)
        let conversation = ConversationRecord(id: AppModel.defaultConversationID, title: "冲突源")
        let eventID = UUID()
        let firstContent = "冲突原文一"
        let secondContent = "冲突原文二"
        let first = ConversationEvent(
            id: eventID,
            conversationID: conversation.id,
            deviceID: "drain-conflict",
            deviceSequence: 1,
            logicalTimestamp: "drain-conflict-1",
            role: .user,
            content: firstContent,
            contentHash: ContentHasher.sha256(firstContent)
        )
        let second = ConversationEvent(
            id: eventID,
            conversationID: conversation.id,
            deviceID: "drain-conflict",
            deviceSequence: 1,
            logicalTimestamp: "drain-conflict-1",
            role: .user,
            content: secondContent,
            contentHash: ContentHasher.sha256(secondContent)
        )
        sourceContext.insert(conversation)
        sourceContext.insert(first)
        sourceContext.insert(second)
        try sourceContext.save()

        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in
                PersistenceBootstrap(
                    container: sourceBase.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: sourceBase.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )
        appModel.attachCloudSourceDrainSession(session)

        let result = session.drainNow()

        XCTAssertEqual(result.status, .failed(StoreDuplicateReconcileError.eventConflict(eventID).localizedDescription))
        XCTAssertTrue(appModel.hasIntegrityConflict)
        XCTAssertEqual(appModel.integrityConflict, .eventConflict(eventID))
        XCTAssertTrue(appModel.conflictedEventIDs.contains(eventID))

        _ = appModel.confirmCloudSourceDrainStop()
        XCTAssertFalse(appModel.hasIntegrityConflict)
        XCTAssertFalse(session.snapshot.sourceContainerRetained)
    }

    func testStartDefersFirstDrainAndCancelReleasesSource() async throws {
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
        let sourceBase = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(sourceBase.container)
        sourceContext.insert(ConversationRecord(id: AppModel.defaultConversationID, title: "云端源"))
        try sourceContext.save()

        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in
                PersistenceBootstrap(
                    container: sourceBase.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: sourceBase.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )

        session.start()
        XCTAssertEqual(session.snapshot.attempts, 0, "start() must return before the first CloudKit drain.")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(session.snapshot.attempts, 1)
        XCTAssertTrue(session.snapshot.sourceContainerRetained)

        session.cancel()
        XCTAssertFalse(session.snapshot.sourceContainerRetained)
    }

    func testErrorCallbackConfirmedStopReturnsStoppedResult() throws {
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
        var sourceFactoryCalled = false
        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in
                sourceFactoryCalled = true
                return destination
            },
            pollInterval: nil
        )
        session.onError = { [weak session] _ in
            session?.confirmStopAfterUserConfirmation()
        }

        let result = session.drainNow()

        XCTAssertTrue(sourceFactoryCalled)
        XCTAssertEqual(result.status, .stopped)
        XCTAssertEqual(session.status, .stopped)
        XCTAssertFalse(session.snapshot.sourceContainerRetained)
        XCTAssertNil(try StorageMigrationJournal.load(defaults: defaults))
        XCTAssertNil(try CloudSourceDrainJournal.load(defaults: defaults))
    }

    func testDirectSessionCancelMarksAppModelDrainInactive() throws {
        let defaults = try makeDefaults()
        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: destination,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in destination },
            pollInterval: nil
        )

        appModel.attachCloudSourceDrainSession(session)
        XCTAssertTrue(appModel.isCloudSourceDrainActive)

        session.cancel()

        XCTAssertFalse(appModel.isCloudSourceDrainActive)
        XCTAssertEqual(appModel.cloudSourceDrainStatusText, "补收已暂停，记录仍保留")
    }

    func testDeferredStartDoesNotRepeatAfterManualDrain() async throws {
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
        let sourceBase = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(sourceBase.container)
        sourceContext.insert(ConversationRecord(id: AppModel.defaultConversationID, title: "手动补收源"))
        try sourceContext.save()

        let session = CloudSourceDrainSession(
            destination: destination,
            defaults: defaults,
            sourceFactory: { _ in
                PersistenceBootstrap(
                    container: sourceBase.container,
                    cloudRequested: true,
                    usingCloud: true,
                    configurationName: "TestCloud",
                    storageURL: sourceBase.storageURL,
                    warning: nil
                )
            },
            pollInterval: nil
        )

        session.start()
        XCTAssertEqual(session.snapshot.attempts, 0)
        let manualResult = session.drainNow()
        XCTAssertEqual(manualResult.status, .waiting)
        XCTAssertEqual(session.snapshot.attempts, 1)

        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(session.snapshot.attempts, 1)
        session.cancel()
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "CloudSourceDrainAppModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }
}
