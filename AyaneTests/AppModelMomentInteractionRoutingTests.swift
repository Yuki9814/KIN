import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelMomentInteractionRoutingTests: XCTestCase {
    func testCompanionPostCommentAndLikeScheduleOnlyTheAuthor() throws {
        let fixture = try makeFixture(configureProvider: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.appModel.createCompanion(name: "旁观者", userName: "你", prompt: "不会越界回复")
        let authorRoleID = RoleScope.legacyRoleID
        let post = try insertCompanionPost(
            body: "作者自己的朋友圈正文",
            authorRoleID: authorRoleID,
            bootstrap: fixture.bootstrap
        )
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.toggleUserMomentLike(postID: post.id)
        try fixture.appModel.addUserMomentComment(postID: post.id, body: "只问作者的问题")

        let tasks = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            .filter { $0.postID == post.id }
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(Set(tasks.map(\.resolvedRoleID)), [authorRoleID])
        XCTAssertEqual(Set(tasks.map(\.kind)), [.replyLike, .replyComment])
    }

    func testUserPostSchedulesReactionAndRequiredCommentForEveryEligibleCompanion() throws {
        let fixture = try makeFixture(configureProvider: false)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.appModel.createCompanion(name: "甲", userName: "你", prompt: "甲的性格")
        _ = try fixture.appModel.createCompanion(name: "乙", userName: "你", prompt: "乙的性格")
        let expectedRoleIDs = Set(fixture.appModel.companions.map { RoleScope.resolve($0.id) })

        let postID = try fixture.appModel.publishUserMoment(
            body: "今天第一次看见雨后的双虹。",
            imageData: nil
        )

        let tasks = try ModelContext(fixture.bootstrap.container)
            .fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            .filter { $0.postID == postID }
        XCTAssertEqual(Set(tasks.map(\.resolvedRoleID)), expectedRoleIDs)
        XCTAssertEqual(tasks.count, expectedRoleIDs.count * 2)
        for roleID in expectedRoleIDs {
            XCTAssertEqual(
                Set(tasks.filter { $0.resolvedRoleID == roleID }.map(\.kind)),
                [.reactionLike, .reactionComment]
            )
        }
    }

    func testLikeAndCommentPromptsContainPostAuthorActionAndFullText() async throws {
        let client = CapturingMomentInteractionClient()
        let fixture = try makeFixture(configureProvider: true, client: client)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        _ = try fixture.appModel.createCompanion(name: "旁观者", userName: "你", prompt: "不回复别人的动态")
        try fixture.appModel.selectCompanion(id: RoleScope.legacyRoleID)
        let postBody = "傍晚的窗边有一束很长的金色光，落在翻到一半的书页上。"
        let post = try insertCompanionPost(
            body: postBody,
            authorRoleID: RoleScope.legacyRoleID,
            bootstrap: fixture.bootstrap
        )
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.toggleUserMomentLike(postID: post.id)
        try await waitUntil { client.requestCount >= 1 }
        try fixture.appModel.addUserMomentComment(
            postID: post.id,
            body: "你也看见那束光了吗？"
        )
        try await waitUntil { client.requestCount >= 2 }

        let prompts = client.userPrompts
        let likePrompt = try XCTUnwrap(prompts.first { $0.contains("用户动作：点赞") })
        XCTAssertTrue(likePrompt.contains(postBody))
        XCTAssertTrue(likePrompt.contains("朋友圈发布者：绫音（AI角色）"))
        XCTAssertTrue(likePrompt.contains("用户评论：（无）"))

        let commentPrompt = try XCTUnwrap(prompts.first { $0.contains("用户动作：评论") })
        XCTAssertTrue(commentPrompt.contains(postBody))
        XCTAssertTrue(commentPrompt.contains("你也看见那束光了吗？"))
        XCTAssertFalse(commentPrompt.contains("旁观者（AI角色）"))
    }

    func testUnlikeCancelsLateAuthorReplyAndRelikeCreatesFreshReply() async throws {
        let client = BlockingMomentInteractionClient()
        let fixture = try makeFixture(configureProvider: true, client: client)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let post = try insertCompanionPost(
            body: "等待点赞回应的动态",
            authorRoleID: RoleScope.legacyRoleID,
            bootstrap: fixture.bootstrap
        )
        fixture.appModel.refreshFromStore(force: true)

        try fixture.appModel.toggleUserMomentLike(postID: post.id)
        try await waitUntil { client.requestCount == 1 }
        try fixture.appModel.toggleUserMomentLike(postID: post.id)
        client.releaseNext(with: "这条迟到回复不应出现。")
        try await Task.sleep(for: .milliseconds(80))

        var context = ModelContext(fixture.bootstrap.container)
        var tasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            .filter { $0.postID == post.id && $0.kind == .replyLike }
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.state, .cancelled)
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<MomentInteractionRecord>()).contains {
                $0.postID == post.id && $0.actorKind == .companion && $0.kind == .comment
            }
        )

        try fixture.appModel.toggleUserMomentLike(postID: post.id)
        try await waitUntil { client.requestCount == 2 }
        client.releaseNext(with: "重新点赞后，这条新回复应出现。")
        try await waitUntil {
            fixture.appModel.momentFeed.first { $0.id == post.id }?
                .interactions.contains {
                    $0.actorKind == .companion
                        && $0.kind == .comment
                        && $0.body.contains("重新点赞")
                } == true
        }

        context = ModelContext(fixture.bootstrap.container)
        tasks = try context.fetch(FetchDescriptor<MomentAIInteractionTaskRecord>())
            .filter { $0.postID == post.id && $0.kind == .replyLike }
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks.filter { $0.state == .cancelled }.count, 1)
        XCTAssertEqual(tasks.filter { $0.state == .succeeded }.count, 1)
    }

    private func makeFixture(
        configureProvider: Bool,
        client: any AIClientProtocol = CapturingMomentInteractionClient()
    ) throws -> MomentRoutingFixture {
        let suiteName = "AppModelMomentInteractionRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        if configureProvider {
            defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
            defaults.set("fixture-model", forKey: SettingsKeys.model)
            defaults.set(false, forKey: SettingsKeys.streamResponses)
        }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { configureProvider ? "fixture-key" : nil }
        )
        return MomentRoutingFixture(
            appModel: appModel,
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func insertCompanionPost(
        body: String,
        authorRoleID: UUID,
        bootstrap: PersistenceBootstrap
    ) throws -> MomentPostRecord {
        let context = ModelContext(bootstrap.container)
        let post = MomentPostRecord(
            authorKind: .companion,
            authorRoleID: authorRoleID,
            body: body,
            publishedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            revision: 1,
            deviceID: "fixture"
        )
        context.insert(post)
        try context.save()
        return post
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
        XCTFail("Timed out waiting for Moments interaction")
    }
}

@MainActor
private struct MomentRoutingFixture {
    let appModel: AppModel
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
}

private final class CapturingMomentInteractionClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedPrompts: [String] = []

    var userPrompts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return capturedPrompts
    }

    var requestCount: Int { userPrompts.count }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        let userPrompt = messages.last(where: { $0.role == "user" })?.content ?? ""
        lock.lock()
        capturedPrompts.append(userPrompt)
        lock.unlock()
        return "我也很喜欢这一刻。"
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] { [] }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}

private final class BlockingMomentInteractionClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0
    private var continuations: [CheckedContinuation<String, Never>] = []

    var requestCount: Int {
        lock.withLock { requests }
    }

    func streamChat(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(
        messages: [APIChatMessage],
        configuration: ProviderConfiguration,
        apiKey: String,
        temperature: Double?,
        maxTokens: Int?
    ) async throws -> String {
        await withCheckedContinuation { continuation in
            lock.withLock {
                requests += 1
                continuations.append(continuation)
            }
        }
    }

    func releaseNext(with response: String) {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Never>? in
            guard !continuations.isEmpty else { return nil }
            return continuations.removeFirst()
        }
        continuation?.resume(returning: response)
    }

    func embedding(
        for text: String,
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> [Float] { [] }

    func testConnection(
        configuration: ProviderConfiguration,
        apiKey: String
    ) async throws -> ConnectionTestResult {
        ConnectionTestResult(latency: 0, reply: "OK")
    }
}
