import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelMomentTests: XCTestCase {
    func testDirectChatPublishCommandCreatesAndPublishesDurableTask() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        fixture.appModel.send("你去发一个朋友圈，写写今天吹到的风")
        XCTAssertEqual(
            fixture.appModel.momentTasks.count,
            1,
            fixture.appModel.momentCommandNotice ?? "朋友圈命令没有生成任务，也没有返回原因"
        )
        let queuedTask = try XCTUnwrap(fixture.appModel.momentTasks.first)
        let queuedNotice = fixture.appModel.momentCommandNotice ?? ""
        let queuedStatus = fixture.appModel.momentStatusText ?? ""
        XCTAssertTrue(
            fixture.appModel.isProcessingMoments,
            "immediate task was not claimed: scheduledDelta=\(queuedTask.scheduledAt.timeIntervalSinceNow), notice=\(queuedNotice), status=\(queuedStatus)"
        )
        try await waitUntil {
            !fixture.appModel.isGenerating
                && !fixture.appModel.isProcessingMoments
                && fixture.appModel.momentTasks.first?.state == .published
        }
        let completedTask = try XCTUnwrap(fixture.appModel.momentTasks.first)
        XCTAssertEqual(
            completedTask.state,
            .published,
            "state=\(completedTask.state.rawValue), error=\(completedTask.lastError), requests=\(fixture.client.completionRequests)"
        )

        let context = ModelContext(fixture.bootstrap.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionMomentTaskRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MomentPostRecord>()), 1)
        XCTAssertEqual(fixture.appModel.momentFeed.first?.authorKind, .companion)
        XCTAssertEqual(fixture.appModel.momentFeed.first?.body, "今天吹到的风很温柔。")
        XCTAssertTrue(
            fixture.appModel.messages.contains { $0.content.contains("已创建朋友圈任务") },
            "chat command must persist the scheduling receipt"
        )
        XCTAssertTrue(
            fixture.appModel.messages.contains { $0.content.contains("已实际发布朋友圈") },
            "published task must persist a separate completion receipt"
        )
    }

    func testUserMomentCommentDeletionIsOwnedSoftDeleteAndCancelsReplies() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        let context = ModelContext(fixture.bootstrap.container)
        let now = Date()
        let postID = UUID()
        let commentID = UUID()
        let aiCommentID = UUID()
        let post = MomentPostRecord(
            id: postID,
            authorKind: .user,
            body: "用户的朋友圈",
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        let userComment = MomentInteractionRecord(
            id: commentID,
            postID: postID,
            kind: .comment,
            actorKind: .user,
            body: "我的评论",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        let aiComment = MomentInteractionRecord(
            id: aiCommentID,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: fixture.appModel.currentRoleID,
            body: "AI 的评论",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        let replyTask = MomentAIInteractionTaskRecord(
            postID: postID,
            targetInteractionID: commentID,
            parentInteractionID: commentID,
            rootInteractionID: commentID,
            roleID: fixture.appModel.currentRoleID,
            state: .pending,
            idempotencyKey: "delete-comment-test",
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        context.insert(post)
        context.insert(userComment)
        context.insert(aiComment)
        context.insert(replyTask)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.deleteUserMomentComment(id: commentID, postID: postID)

        let verification = ModelContext(fixture.bootstrap.container)
        let storedComment = try XCTUnwrap(
            try verification.fetch(FetchDescriptor<MomentInteractionRecord>())
                .first { $0.id == commentID }
        )
        XCTAssertNotNil(storedComment.deletedAt)
        XCTAssertGreaterThan(storedComment.revision, 1)
        XCTAssertEqual(
            try verification.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
                .first { $0.id == replyTask.id }?.state,
            .cancelled
        )
        XCTAssertFalse(
            fixture.appModel.momentFeed
                .flatMap(\.interactions)
                .contains { $0.id == commentID }
        )
        XCTAssertThrowsError(
            try fixture.appModel.deleteUserMomentComment(id: aiCommentID, postID: postID)
        )
        try fixture.appModel.deleteUserMomentComment(id: commentID, postID: postID)
    }

    func testFutureChatCommandPersistsWithoutConfiguredAIConnection() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("", forKey: SettingsKeys.baseURL)
        fixture.defaults.set("", forKey: SettingsKeys.model)

        fixture.appModel.send("明天晚上八点发一条朋友圈")

        let task = try XCTUnwrap(fixture.appModel.momentTasks.first)
        XCTAssertEqual(task.state, .scheduled)
        XCTAssertGreaterThan(task.scheduledAt, Date())
        XCTAssertEqual(fixture.client.completionRequests, 0)
        XCTAssertFalse(fixture.appModel.isGenerating)
    }

    func testDirectChatDeleteCommandOnlyRemovesMatchingCurrentRolePost() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("", forKey: SettingsKeys.baseURL)
        fixture.defaults.set("", forKey: SettingsKeys.model)

        let context = ModelContext(fixture.bootstrap.container)
        let now = Date()
        let matchingPost = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: fixture.appModel.currentRoleID,
            body: "傍晚的晚霞像一封没有寄出的信。",
            publishedAt: now.addingTimeInterval(-30),
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-30),
            revision: 1,
            deviceID: "fixture"
        )
        let newerCurrentRolePost = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: fixture.appModel.currentRoleID,
            body: "早餐很好吃。",
            publishedAt: now.addingTimeInterval(-10),
            createdAt: now.addingTimeInterval(-10),
            updatedAt: now.addingTimeInterval(-10),
            revision: 1,
            deviceID: "fixture"
        )
        let otherRolePost = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: UUID(),
            body: "晚霞也很好看。",
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        let userPost = MomentPostRecord(
            authorKind: .user,
            body: "我也拍到了晚霞。",
            publishedAt: now,
            createdAt: now,
            updatedAt: now,
            revision: 1,
            deviceID: "fixture"
        )
        for post in [matchingPost, newerCurrentRolePost, otherRolePost, userPost] {
            context.insert(post)
        }
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        fixture.appModel.send("把你那条关于晚霞的朋友圈删掉")

        let verificationContext = ModelContext(fixture.bootstrap.container)
        let posts = try verificationContext.fetch(FetchDescriptor<MomentPostRecord>())
        XCTAssertNotNil(posts.first { $0.id == matchingPost.id }?.deletedAt)
        XCTAssertNil(posts.first { $0.id == newerCurrentRolePost.id }?.deletedAt)
        XCTAssertNil(posts.first { $0.id == otherRolePost.id }?.deletedAt)
        XCTAssertNil(posts.first { $0.id == userPost.id }?.deletedAt)
        XCTAssertFalse(fixture.appModel.momentFeed.contains { $0.id == matchingPost.id })
        XCTAssertEqual(fixture.client.completionRequests, 0)
        XCTAssertTrue(fixture.appModel.messages.last?.content.contains("已经删掉") == true)
    }

    func testDirectChatDeleteCommandDoesNotGuessBetweenMatchingPosts() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("", forKey: SettingsKeys.baseURL)
        fixture.defaults.set("", forKey: SettingsKeys.model)

        let context = ModelContext(fixture.bootstrap.container)
        let now = Date()
        let first = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: fixture.appModel.currentRoleID,
            body: "今晚的晚霞很安静。",
            publishedAt: now.addingTimeInterval(-20),
            createdAt: now.addingTimeInterval(-20),
            updatedAt: now.addingTimeInterval(-20),
            revision: 1,
            deviceID: "fixture"
        )
        let second = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: fixture.appModel.currentRoleID,
            body: "昨天的晚霞也很漂亮。",
            publishedAt: now.addingTimeInterval(-10),
            createdAt: now.addingTimeInterval(-10),
            updatedAt: now.addingTimeInterval(-10),
            revision: 1,
            deviceID: "fixture"
        )
        context.insert(first)
        context.insert(second)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        fixture.appModel.send("把你那条关于晚霞的朋友圈删掉")

        let verificationContext = ModelContext(fixture.bootstrap.container)
        let posts = try verificationContext.fetch(FetchDescriptor<MomentPostRecord>())
        XCTAssertNil(posts.first { $0.id == first.id }?.deletedAt)
        XCTAssertNil(posts.first { $0.id == second.id }?.deletedAt)
        XCTAssertTrue(fixture.appModel.messages.last?.content.contains("唯一对应") == true)
        XCTAssertEqual(fixture.client.completionRequests, 0)
    }

    func testSchedulePersistsFutureTextTask() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let scheduledAt = Date().addingTimeInterval(3_600)

        try fixture.appModel.scheduleMoment(
            roleID: fixture.appModel.currentRoleID,
            instruction: "写一条关于傍晚散步的朋友圈",
            scheduledAt: scheduledAt
        )

        let summary = try XCTUnwrap(fixture.appModel.momentTasks.first)
        XCTAssertEqual(summary.roleID, fixture.appModel.currentRoleID)
        XCTAssertEqual(summary.state, .scheduled)
        XCTAssertEqual(summary.instruction, "写一条关于傍晚散步的朋友圈")
        XCTAssertEqual(summary.scheduledAt.timeIntervalSince1970, scheduledAt.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(fixture.client.completionRequests, 0)

        let context = ModelContext(fixture.bootstrap.container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CompanionMomentTaskRecord>()), 1)
    }

    func testDueTaskForRejectedRoleDoesNotReadKeyOrPublish() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let roleID = try fixture.appModel.createCompanion(
            name: "边界角色",
            userName: "你",
            prompt: "有清晰边界"
        )
        let context = ModelContext(fixture.bootstrap.container)
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { $0.roleID == roleID }
        )
        relationship.state = .rejected
        relationship.revision += 1
        let task = CompanionMomentTaskRecord(
            roleID: roleID,
            instruction: "发一条文字朋友圈",
            scheduledAt: .distantPast,
            state: .scheduled,
            deviceID: "fixture",
            revision: 1
        )
        context.insert(task)
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        fixture.appModel.processDueMomentTasks()
        try await waitUntil { !fixture.appModel.isProcessingMoments }

        XCTAssertEqual(fixture.keyReads(), 0)
        XCTAssertEqual(fixture.client.completionRequests, 0)
        let stored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionMomentTaskRecord>())
                .first { $0.id == task.id }
        )
        XCTAssertEqual(stored.state, .scheduled)
        XCTAssertFalse(stored.lastError.isEmpty)
        XCTAssertEqual(stored.resultText, "")
    }

    func testDueTaskPublishesOnlyOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        try fixture.appModel.scheduleMoment(
            roleID: fixture.appModel.currentRoleID,
            instruction: "写一条今天很开心的朋友圈",
            scheduledAt: .distantPast
        )
        try await waitUntil {
            fixture.appModel.momentTasks.first?.state == .published
                && !fixture.appModel.isProcessingMoments
        }
        XCTAssertEqual(fixture.client.completionRequests, 1)
        XCTAssertEqual(fixture.appModel.momentTasks.first?.resultText, "今天吹到的风很温柔。")

        fixture.appModel.processDueMomentTasks(now: Date().addingTimeInterval(86_400))
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.client.completionRequests, 1)
    }

    func testDailySeriesPublishesOneOccurrenceAndCreatesExactlyOneSuccessor() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let seriesID = UUID()
        let firstDate = Date().addingTimeInterval(0.15)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents([.hour, .minute], from: firstDate)
        let rule = MomentTaskRecurrenceRule(
            frequency: .daily,
            interval: 1,
            hour: try XCTUnwrap(components.hour),
            minute: try XCTUnwrap(components.minute),
            timezoneIdentifier: "UTC",
            scheduledAt: firstDate,
            seriesID: seriesID
        )

        try fixture.appModel.scheduleMoment(
            roleID: fixture.appModel.currentRoleID,
            instruction: "每天分享今天的心情",
            scheduledAt: firstDate,
            recurrence: rule,
            taskID: seriesID
        )
        try await Task.sleep(for: .milliseconds(220))
        fixture.appModel.processDueMomentTasks()
        try await waitUntil {
            fixture.appModel.momentTasks.filter { $0.seriesID == seriesID }.count == 2
                && !fixture.appModel.isProcessingMoments
        }

        let occurrences = fixture.appModel.momentTasks.filter { $0.seriesID == seriesID }
        XCTAssertEqual(occurrences.filter { $0.state == .published }.count, 1)
        XCTAssertEqual(occurrences.filter { $0.state == .scheduled }.count, 1)
        XCTAssertEqual(Set(occurrences.map(\.occurrenceKey)).count, 2)
        XCTAssertEqual(fixture.client.completionRequests, 1)

        fixture.appModel.processDueMomentTasks()
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(fixture.client.completionRequests, 1)
    }

    func testRecurringSeriesCanPauseAndResumeWithoutLosingItsRule() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let seriesID = UUID()
        let firstDate = Date().addingTimeInterval(3_600)
        let rule = MomentTaskRecurrenceRule(
            frequency: .weekly,
            interval: 2,
            weekday: Calendar(identifier: .gregorian).component(.weekday, from: firstDate),
            hour: Calendar(identifier: .gregorian).component(.hour, from: firstDate),
            minute: Calendar(identifier: .gregorian).component(.minute, from: firstDate),
            timezoneIdentifier: TimeZone.current.identifier,
            scheduledAt: firstDate,
            seriesID: seriesID
        )
        try fixture.appModel.scheduleMoment(
            roleID: fixture.appModel.currentRoleID,
            instruction: "隔周分享一次近况",
            scheduledAt: firstDate,
            recurrence: rule,
            taskID: seriesID
        )

        try fixture.appModel.setMomentSeriesEnabled(seriesID: seriesID, enabled: false)
        XCTAssertEqual(
            fixture.appModel.momentTasks.first { $0.seriesID == seriesID }?.state,
            .cancelled
        )
        try fixture.appModel.setMomentSeriesEnabled(seriesID: seriesID, enabled: true)
        let resumed = try XCTUnwrap(
            fixture.appModel.momentTasks.first {
                $0.seriesID == seriesID && $0.state == .scheduled
            }
        )
        XCTAssertEqual(resumed.recurrenceRaw, MomentTaskRecurrenceFrequency.weekly.rawValue)
        XCTAssertEqual(resumed.recurrenceInterval, 2)
        XCTAssertEqual(resumed.recurrenceWeekday, rule.weekday)
    }

    func testLegacyRecurringTaskWithoutSeriesIDCanPauseAndResume() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let taskID = UUID()
        let now = Date()
        let firstDate = now.addingTimeInterval(3_600)
        let calendar = Calendar(identifier: .gregorian)
        let context = ModelContext(fixture.bootstrap.container)
        context.insert(CompanionMomentTaskRecord(
            id: taskID,
            roleID: fixture.appModel.currentRoleID,
            instruction: "旧版每日任务",
            scheduledAt: firstDate,
            recurrenceRaw: MomentTaskRecurrenceFrequency.daily.rawValue,
            recurrenceInterval: 1,
            recurrenceHour: calendar.component(.hour, from: firstDate),
            recurrenceMinute: calendar.component(.minute, from: firstDate),
            timezoneIdentifier: TimeZone.current.identifier,
            state: .scheduled,
            createdAt: now,
            updatedAt: now,
            deviceID: "legacy-fixture",
            revision: 1
        ))
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.setMomentSeriesEnabled(seriesID: taskID, enabled: false)
        XCTAssertEqual(
            fixture.appModel.momentTasks.first { $0.id == taskID }?.state,
            .cancelled
        )

        try fixture.appModel.setMomentSeriesEnabled(seriesID: taskID, enabled: true)
        let resumed = try XCTUnwrap(
            fixture.appModel.momentTasks.first { $0.id == taskID }
        )
        XCTAssertEqual(resumed.state, .scheduled)
        XCTAssertEqual(resumed.recurrenceRaw, MomentTaskRecurrenceFrequency.daily.rawValue)
    }

    func testRetryDelayDoesNotMoveRecurringOccurrenceAnchor() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set("", forKey: SettingsKeys.model)
        let seriesID = UUID()
        let firstDate = Date().addingTimeInterval(0.12)
        let rule = MomentTaskRecurrenceRule(
            frequency: .daily,
            hour: Calendar.current.component(.hour, from: firstDate),
            minute: Calendar.current.component(.minute, from: firstDate),
            timezoneIdentifier: TimeZone.current.identifier,
            scheduledAt: firstDate,
            seriesID: seriesID
        )
        try fixture.appModel.scheduleMoment(
            roleID: fixture.appModel.currentRoleID,
            instruction: "连接恢复后再发",
            scheduledAt: firstDate,
            recurrence: rule,
            taskID: seriesID
        )
        let persistedAnchor = try XCTUnwrap(
            fixture.appModel.momentTasks.first { $0.seriesID == seriesID }
        ).scheduledAt
        try await Task.sleep(for: .milliseconds(180))
        fixture.appModel.processDueMomentTasks()
        try await waitUntil { !fixture.appModel.isProcessingMoments }

        let delayed = try XCTUnwrap(
            fixture.appModel.momentTasks.first { $0.seriesID == seriesID }
        )
        XCTAssertEqual(delayed.state, .scheduled)
        XCTAssertEqual(delayed.scheduledAt, persistedAnchor)
        XCTAssertNotNil(delayed.nextAttemptAt)
        XCTAssertGreaterThan(try XCTUnwrap(delayed.nextAttemptAt), delayed.scheduledAt)
        XCTAssertEqual(fixture.client.completionRequests, 0)

        let retryAt = try XCTUnwrap(delayed.nextAttemptAt)
        try fixture.appModel.scheduleMoment(
            roleID: delayed.roleID,
            instruction: "连接恢复后再发，文案已调整",
            scheduledAt: delayed.scheduledAt,
            recurrence: delayed.recurrenceRule,
            taskID: delayed.id
        )
        let edited = try XCTUnwrap(
            fixture.appModel.momentTasks.first { $0.id == delayed.id }
        )
        XCTAssertEqual(edited.instruction, "连接恢复后再发，文案已调整")
        XCTAssertEqual(edited.scheduledAt, persistedAnchor)
        XCTAssertEqual(edited.nextAttemptAt, retryAt)
        XCTAssertEqual(edited.attemptCount, delayed.attemptCount)
        XCTAssertEqual(edited.lastError, delayed.lastError)
        XCTAssertEqual(fixture.client.completionRequests, 0)
    }

    private func makeFixture() throws -> MomentFixture {
        let suiteName = "AppModelMomentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set("", forKey: SettingsKeys.embeddingModel)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = MomentCountingClient()
        let keyCounter = LockedCounter()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: {
                keyCounter.increment()
                return "fixture-key"
            }
        )
        return MomentFixture(
            appModel: appModel,
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName,
            client: client,
            keyReads: { keyCounter.value }
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for Moments state")
    }
}

@MainActor
private struct MomentFixture {
    let appModel: AppModel
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
    let client: MomentCountingClient
    let keyReads: () -> Int
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }
}

private final class MomentCountingClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCompletionRequests = 0

    var completionRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCompletionRequests
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
        storedCompletionRequests += 1
        lock.unlock()
        return "今天吹到的风很温柔。"
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
