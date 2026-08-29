import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class MomentAIInteractionTaskPersistenceTests: XCTestCase {
    private let roleID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    func testRecordExportImportRoundTripPreservesDurableFields() throws {
        let source = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let sourceContext = ModelContext(source.container)
        let defaults = try makeDefaults(prefix: "roundtrip")
        configureValidDefaults(defaults)

        let postID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let targetID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let parentID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let rootID = targetID
        let resultID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_060)
        let nextAttemptAt = Date(timeIntervalSince1970: 1_700_000_120)
        let leaseExpiresAt = Date(timeIntervalSince1970: 1_700_000_180)

        let profile = CompanionProfileRecord(
            id: roleID,
            name: "测试角色",
            userName: "测试者",
            prompt: "只用于持久化测试",
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 2,
            deviceID: "fixture-device"
        )
        let conversation = ConversationRecord(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            title: "互动任务测试会话",
            createdAt: createdAt,
            roleID: roleID
        )
        let post = MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "一条用于互动任务恢复的朋友圈",
            publishedAt: createdAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 1,
            deviceID: "fixture-device"
        )
        let target = MomentInteractionRecord(
            id: targetID,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleID,
            body: "角色的原评论",
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 1,
            deviceID: "fixture-device"
        )
        let parent = MomentInteractionRecord(
            id: parentID,
            postID: postID,
            kind: .comment,
            actorKind: .user,
            parentInteractionID: targetID,
            rootInteractionID: rootID,
            body: "用户的回复",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            revision: 1,
            deviceID: "fixture-device"
        )
        let result = MomentInteractionRecord(
            id: resultID,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleID,
            parentInteractionID: parentID,
            rootInteractionID: rootID,
            body: "这是持久化后的回复结果。",
            createdAt: updatedAt,
            updatedAt: updatedAt,
            revision: 1,
            deviceID: "fixture-device"
        )
        let task = MomentAIInteractionTaskRecord(
            id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
            kind: .replyComment,
            postID: postID,
            targetInteractionID: targetID,
            parentInteractionID: parentID,
            rootInteractionID: rootID,
            roleID: roleID,
            state: .succeeded,
            attemptCount: 4,
            nextAttemptAt: nextAttemptAt,
            lastError: "上一次失败信息也要保留",
            idempotencyKey: "fixture-idempotency-key",
            timezoneIdentifier: "Asia/Shanghai",
            inputText: "用户希望继续这一轮对话",
            generatedText: "这是持久化后的回复结果。",
            generatedLike: false,
            resultInteractionID: resultID,
            leaseOwner: "fixture-worker",
            leaseExpiresAt: leaseExpiresAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 9,
            deviceID: "fixture-device"
        )

        sourceContext.insert(profile)
        sourceContext.insert(conversation)
        sourceContext.insert(post)
        sourceContext.insert(target)
        sourceContext.insert(parent)
        sourceContext.insert(result)
        sourceContext.insert(task)
        try sourceContext.save()

        let data = try DataExportService.export(
            context: sourceContext,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 1_700_000_240)
        )
        let exported = try decode(data)
        let exportedTask = try XCTUnwrap(exported.momentAIInteractionTasks.first)
        assertTask(exportedTask, matches: task)

        let destination = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let destinationContext = ModelContext(destination.container)
        let destinationDefaults = try makeDefaults(prefix: "roundtrip-destination")
        configureValidDefaults(destinationDefaults)
        let summary = try DataImportService.replaceAll(
            with: data,
            context: destinationContext,
            defaults: destinationDefaults
        )

        XCTAssertEqual(summary.momentAIInteractionTasks, 1)
        let restored = try XCTUnwrap(
            destinationContext.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>()).first
        )
        assertTask(restored, matches: task)

        let restoredData = try DataExportService.export(
            context: destinationContext,
            defaults: destinationDefaults,
            now: Date(timeIntervalSince1970: 1_700_000_240)
        )
        let restoredPayload = try decode(restoredData)
        XCTAssertEqual(restoredPayload.momentAIInteractionTasks, exported.momentAIInteractionTasks)
    }

    func testRunningTaskIsRecoveredAndDeferredWhenConfigurationIsMissing() async throws {
        let defaults = try makeDefaults(prefix: "startup-recovery")
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let beforeLaunch = Date()
        let taskID = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let context = ModelContext(bootstrap.container)
        context.insert(MomentPostRecord(
            id: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            authorKind: .user,
            body: "等待恢复的朋友圈",
            publishedAt: beforeLaunch.addingTimeInterval(-180),
            createdAt: beforeLaunch.addingTimeInterval(-180),
            updatedAt: beforeLaunch.addingTimeInterval(-180),
            revision: 1,
            deviceID: "old-device"
        ))
        let task = MomentAIInteractionTaskRecord(
            id: taskID,
            kind: .reactionComment,
            postID: UUID(uuidString: "13131313-1313-1313-1313-131313131313")!,
            roleID: RoleScope.legacyRoleID,
            state: .running,
            attemptCount: 2,
            nextAttemptAt: beforeLaunch.addingTimeInterval(-60),
            lastError: "进程中断",
            idempotencyKey: "startup-recovery-key",
            timezoneIdentifier: "Asia/Shanghai",
            inputText: "恢复后继续",
            leaseOwner: "crashed-worker",
            leaseExpiresAt: beforeLaunch.addingTimeInterval(120),
            createdAt: beforeLaunch.addingTimeInterval(-120),
            updatedAt: beforeLaunch.addingTimeInterval(-30),
            revision: 3,
            deviceID: "old-device"
        )
        context.insert(task)
        try context.save()

        let appModel = AppModel(
            bootstrap: bootstrap,
            client: PersistenceTestAIClient(response: "ignored"),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        _ = appModel

        let deadline = Date().addingTimeInterval(2)
        var recovered: MomentAIInteractionTaskRecord?
        while Date() < deadline {
            let observationContext = ModelContext(bootstrap.container)
            let records = try observationContext.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            recovered = records.first(where: { $0.id == taskID })
            if recovered?.state == .pending,
               recovered?.nextAttemptAt ?? .distantPast > beforeLaunch,
               recovered?.lastError.contains("配置") == true {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let persisted = try XCTUnwrap(recovered)
        XCTAssertEqual(persisted.id, taskID)
        XCTAssertEqual(persisted.state, .pending)
        XCTAssertEqual(persisted.attemptCount, 2)
        XCTAssertEqual(persisted.idempotencyKey, "startup-recovery-key")
        XCTAssertGreaterThan(persisted.nextAttemptAt, beforeLaunch)
        XCTAssertTrue(persisted.lastError.contains("配置"))
        let finalContext = ModelContext(bootstrap.container)
        XCTAssertEqual(
            try finalContext.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>()).filter { $0.id == taskID }.count,
            1
        )
    }

    func testRetryPolicyUsesThirtySixtyOneTwentySecondsAndStopsAtFifthAttempt() {
        XCTAssertEqual(MomentAIInteractionTaskPolicy.retryDelay(afterAttemptCount: 1), 30)
        XCTAssertEqual(MomentAIInteractionTaskPolicy.retryDelay(afterAttemptCount: 2), 60)
        XCTAssertEqual(MomentAIInteractionTaskPolicy.retryDelay(afterAttemptCount: 3), 120)
        XCTAssertEqual(MomentAIInteractionTaskPolicy.nextAttemptAt(
            now: Date(timeIntervalSince1970: 1_000),
            attemptCount: 3
        ), Date(timeIntervalSince1970: 1_120))

        XCTAssertTrue(MomentAIInteractionTaskPolicy.canAttempt(0))
        XCTAssertTrue(MomentAIInteractionTaskPolicy.canAttempt(4))
        XCTAssertFalse(MomentAIInteractionTaskPolicy.canAttempt(5))
        XCTAssertFalse(MomentAIInteractionTaskPolicy.canAttempt(6))
    }

    func testRepeatedPublicRefreshDoesNotCreateDuplicateVisibleInteraction() async throws {
        let defaults = try makeDefaults(prefix: "idempotency")
        configureValidDefaults(defaults)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = PersistenceTestAIClient(
            response: "{\"like\":true,\"comment\":\"看到啦，今天也要好好生活。\"}"
        )
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" }
        )

        let postID = try appModel.publishUserMoment(
            body: "绫音，今天在阳光下散步。",
            imageData: nil
        )
        let context = ModelContext(bootstrap.container)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let observationContext = ModelContext(bootstrap.container)
            let tasks = try observationContext.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            if tasks.count == 2,
               tasks.allSatisfy({ $0.state == .succeeded }),
               !appModel.isGeneratingMomentInteractions {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        let initialTasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
        XCTAssertEqual(initialTasks.count, 2)
        XCTAssertTrue(initialTasks.allSatisfy { $0.state == .succeeded })
        XCTAssertEqual(client.completionCount, 1)
        let initialInteractions = try context.fetch(FetchDescriptor<MomentInteractionRecord>())
        XCTAssertEqual(initialInteractions.count, 2)
        XCTAssertEqual(
            appModel.momentFeed.first(where: { $0.id == postID })?.interactions.count,
            2
        )

        appModel.refreshFromStore(force: true)
        appModel.refreshFromStore(force: true)
        try await Task.sleep(for: .milliseconds(80))

        let finalTasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
        let finalInteractions = try context.fetch(FetchDescriptor<MomentInteractionRecord>())
        XCTAssertEqual(finalTasks.count, 2)
        XCTAssertTrue(finalTasks.allSatisfy { $0.state == .succeeded })
        XCTAssertEqual(Set(finalInteractions.map(\.id)), Set(initialInteractions.map(\.id)))
        XCTAssertEqual(client.completionCount, 1)
        XCTAssertEqual(
            appModel.momentFeed.first(where: { $0.id == postID })?.interactions.count,
            2
        )
    }

    private func assertTask(
        _ exported: AyaneMomentAIInteractionTaskExport,
        matches record: MomentAIInteractionTaskRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(exported.id, record.id, file: file, line: line)
        XCTAssertEqual(exported.kindRaw, record.kindRaw, file: file, line: line)
        XCTAssertEqual(exported.postID, record.postID, file: file, line: line)
        XCTAssertEqual(exported.targetInteractionID, record.targetInteractionID, file: file, line: line)
        XCTAssertEqual(exported.parentInteractionID, record.parentInteractionID, file: file, line: line)
        XCTAssertEqual(exported.rootInteractionID, record.rootInteractionID, file: file, line: line)
        XCTAssertEqual(exported.roleID, record.roleID, file: file, line: line)
        XCTAssertEqual(exported.stateRaw, record.stateRaw, file: file, line: line)
        XCTAssertEqual(exported.attemptCount, record.attemptCount, file: file, line: line)
        XCTAssertEqual(exported.nextAttemptAt, record.nextAttemptAt, file: file, line: line)
        XCTAssertEqual(exported.lastError, record.lastError, file: file, line: line)
        XCTAssertEqual(exported.idempotencyKey, record.idempotencyKey, file: file, line: line)
        XCTAssertEqual(exported.timezoneIdentifier, record.timezoneIdentifier, file: file, line: line)
        XCTAssertEqual(exported.inputText, record.inputText, file: file, line: line)
        XCTAssertEqual(exported.generatedText, record.generatedText, file: file, line: line)
        XCTAssertEqual(exported.generatedLike, record.generatedLike, file: file, line: line)
        XCTAssertEqual(exported.resultInteractionID, record.resultInteractionID, file: file, line: line)
        XCTAssertEqual(exported.leaseOwner, record.leaseOwner, file: file, line: line)
        XCTAssertEqual(exported.leaseExpiresAt, record.leaseExpiresAt, file: file, line: line)
        XCTAssertEqual(exported.createdAt, record.createdAt, file: file, line: line)
        XCTAssertEqual(exported.updatedAt, record.updatedAt, file: file, line: line)
        XCTAssertEqual(exported.revision, record.revision, file: file, line: line)
        XCTAssertEqual(exported.deviceID, record.deviceID, file: file, line: line)
    }

    private func assertTask(
        _ restored: MomentAIInteractionTaskRecord,
        matches record: MomentAIInteractionTaskRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(restored.id, record.id, file: file, line: line)
        XCTAssertEqual(restored.kindRaw, record.kindRaw, file: file, line: line)
        XCTAssertEqual(restored.postID, record.postID, file: file, line: line)
        XCTAssertEqual(restored.targetInteractionID, record.targetInteractionID, file: file, line: line)
        XCTAssertEqual(restored.parentInteractionID, record.parentInteractionID, file: file, line: line)
        XCTAssertEqual(restored.rootInteractionID, record.rootInteractionID, file: file, line: line)
        XCTAssertEqual(restored.roleID, record.roleID, file: file, line: line)
        XCTAssertEqual(restored.stateRaw, record.stateRaw, file: file, line: line)
        XCTAssertEqual(restored.attemptCount, record.attemptCount, file: file, line: line)
        XCTAssertEqual(restored.nextAttemptAt, record.nextAttemptAt, file: file, line: line)
        XCTAssertEqual(restored.lastError, record.lastError, file: file, line: line)
        XCTAssertEqual(restored.idempotencyKey, record.idempotencyKey, file: file, line: line)
        XCTAssertEqual(restored.timezoneIdentifier, record.timezoneIdentifier, file: file, line: line)
        XCTAssertEqual(restored.inputText, record.inputText, file: file, line: line)
        XCTAssertEqual(restored.generatedText, record.generatedText, file: file, line: line)
        XCTAssertEqual(restored.generatedLike, record.generatedLike, file: file, line: line)
        XCTAssertEqual(restored.resultInteractionID, record.resultInteractionID, file: file, line: line)
        XCTAssertEqual(restored.leaseOwner, record.leaseOwner, file: file, line: line)
        XCTAssertEqual(restored.leaseExpiresAt, record.leaseExpiresAt, file: file, line: line)
        XCTAssertEqual(restored.createdAt, record.createdAt, file: file, line: line)
        XCTAssertEqual(restored.updatedAt, record.updatedAt, file: file, line: line)
        XCTAssertEqual(restored.revision, record.revision, file: file, line: line)
        XCTAssertEqual(restored.deviceID, record.deviceID, file: file, line: line)
    }

    private func makeDefaults(prefix: String) throws -> UserDefaults {
        let suiteName = "MomentAIInteractionTaskPersistenceTests.\(prefix).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func configureValidDefaults(_ defaults: UserDefaults) {
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(0.4, forKey: SettingsKeys.temperature)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(1_200, forKey: SettingsKeys.memoryTokenBudget)
        defaults.set(12, forKey: SettingsKeys.recentMessageLimit)
        defaults.set(false, forKey: SettingsKeys.rawHistoryRecallEnabled)
        defaults.set(800, forKey: SettingsKeys.rawHistoryTokenBudget)
        defaults.set(false, forKey: SettingsKeys.cloudSyncEnabled)
    }
}

private final class PersistenceTestAIClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let storedResponse: String
    private var storedCompletionCount = 0

    init(response: String) {
        storedResponse = response
    }

    var completionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletionCount
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        lock.lock()
        storedCompletionCount += 1
        lock.unlock()
        return storedResponse
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] {
        []
    }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}

private extension MomentAIInteractionTaskPersistenceTests {
    func decode(_ data: Data) throws -> AyaneDataExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AyaneDataExport.self, from: data)
    }
}
