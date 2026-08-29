import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class AppModelBirthdayAutomationTests: XCTestCase {
    func testUserBirthdayCreatesOneGreetingTaskForEveryEligibleCompanion() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let components = calendar.dateComponents([.month, .day], from: tomorrow)
        let eligibleRoleIDs = Set(fixture.appModel.companions.compactMap { companion in
            companion.relationshipState == .accepted && companion.contactMembership == .active
                ? companion.id
                : nil
        })

        try fixture.appModel.saveUserBirthday(
            month: try XCTUnwrap(components.month),
            day: try XCTUnwrap(components.day),
            timeZoneIdentifier: "Asia/Shanghai"
        )

        let tasks = birthdayTasks(
            in: fixture.bootstrap.container,
            prefix: "birthday:user:"
        )
        XCTAssertEqual(Set(tasks.map(\.resolvedRoleID)), eligibleRoleIDs)
        XCTAssertEqual(tasks.count, eligibleRoleIDs.count)
        XCTAssertTrue(tasks.allSatisfy { $0.state == .scheduled })
        XCTAssertEqual(
            fixture.appModel.userProfile.birthdayTimeZoneIdentifier,
            "Asia/Shanghai"
        )
    }

    func testNewCompanionDoesNotInheritCurrentCompanionBirthday() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let existingRoleID = try fixture.appModel.createCompanion(
            name: "已有角色",
            userName: "主人",
            prompt: "保持独立的人格"
        )
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        let birthday = Calendar.current.dateComponents([.month, .day], from: tomorrow)
        try fixture.appModel.saveCompanionBirthday(
            roleID: existingRoleID,
            month: try XCTUnwrap(birthday.month),
            day: try XCTUnwrap(birthday.day)
        )

        let newRoleID = try fixture.appModel.createCompanion(
            name: "新角色",
            userName: "主人",
            prompt: "保持独立的人格"
        )

        let created = try XCTUnwrap(
            fixture.appModel.companions.first { $0.id == newRoleID }
        )
        XCTAssertNil(created.birthdayMonth)
        XCTAssertNil(created.birthdayDay)
    }

    func testRoleBirthdayCancellationUsesOnlyTheTaskConversation() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let birthdayComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        let localYear = try XCTUnwrap(birthdayComponents.year)

        var selectedRoleID: UUID?
        for index in 0..<12 {
            let roleID = try fixture.appModel.createCompanion(
                name: "生日角色\(index)",
                userName: "主人",
                prompt: "保持真实和独立"
            )
            if BirthdayAutomationPolicy.roleBirthdayCheckInHour(
                roleID: roleID,
                localYear: localYear
            ) == 2 {
                selectedRoleID = roleID
                break
            }
        }
        let roleID = try XCTUnwrap(selectedRoleID)
        try fixture.appModel.selectCompanion(id: roleID)
        let targetConversationID = fixture.appModel.currentConversation.id

        let otherConversationID = UUID()
        let context = ModelContext(fixture.bootstrap.container)
        context.insert(ConversationRecord(
            id: otherConversationID,
            title: "其他会话",
            createdAt: Date().addingTimeInterval(1),
            roleID: roleID
        ))
        try context.save()

        try fixture.appModel.saveCompanionBirthday(
            roleID: roleID,
            month: try XCTUnwrap(birthdayComponents.month),
            day: try XCTUnwrap(birthdayComponents.day)
        )
        let initialTask = try XCTUnwrap(
            birthdayTasks(
                in: fixture.bootstrap.container,
                prefix: "birthday:role:"
            ).first { $0.resolvedRoleID == roleID }
        )
        XCTAssertEqual(initialTask.conversationID, targetConversationID)

        let birthdayStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: birthdayComponents.year,
            month: birthdayComponents.month,
            day: birthdayComponents.day,
            hour: 0,
            minute: 0
        )))
        let checkNow = birthdayStart.addingTimeInterval(30 * 60)
        try insertUserEvent(
            into: fixture.bootstrap.container,
            conversationID: otherConversationID,
            roleID: roleID,
            occurredAt: birthdayStart.addingTimeInterval(10 * 60),
            sequence: 1
        )
        fixture.appModel.processDueProactiveTasks(now: checkNow)
        XCTAssertEqual(
            birthdayTasks(
                in: fixture.bootstrap.container,
                prefix: "birthday:role:"
            ).first { $0.resolvedRoleID == roleID }?.state,
            .scheduled
        )

        try insertUserEvent(
            into: fixture.bootstrap.container,
            conversationID: targetConversationID,
            roleID: roleID,
            occurredAt: birthdayStart.addingTimeInterval(20 * 60),
            sequence: 2
        )
        fixture.appModel.processDueProactiveTasks(now: checkNow)
        XCTAssertEqual(
            birthdayTasks(
                in: fixture.bootstrap.container,
                prefix: "birthday:role:"
            ).first { $0.resolvedRoleID == roleID }?.state,
            .cancelled
        )
        XCTAssertEqual(fixture.client.completeRequestCount, 0)
    }

    func testUnavailableCompanionBirthdayCannotBeSaved() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let roleID = try fixture.appModel.createCompanion(
            name: "不可用角色",
            userName: "主人",
            prompt: "保持独立"
        )
        let context = ModelContext(fixture.bootstrap.container)
        let relationship = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionRelationshipRecord>())
                .first { RoleScope.resolve($0.roleID) == RoleScope.resolve(roleID) }
        )
        relationship.state = .rejected
        relationship.revision += 1
        relationship.updatedAt = Date()
        try context.save()
        fixture.appModel.refreshFromStore(force: true)

        XCTAssertThrowsError(
            try fixture.appModel.saveCompanionBirthday(
                roleID: roleID,
                month: 9,
                day: 12
            )
        )
        let profile = try XCTUnwrap(
            try context.fetch(FetchDescriptor<CompanionProfileRecord>())
                .first { RoleScope.resolve($0.id) == RoleScope.resolve(roleID) }
        )
        XCTAssertNil(profile.birthdayMonth)
        XCTAssertNil(profile.birthdayDay)
    }

    private func makeFixture() throws -> BirthdayFixture {
        let suiteName = "AppModelBirthdayAutomationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set("", forKey: SettingsKeys.baseURL)
        defaults.set("", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let client = BirthdayCountingClient()
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: client,
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        return BirthdayFixture(
            bootstrap: bootstrap,
            defaults: defaults,
            suiteName: suiteName,
            client: client,
            appModel: appModel
        )
    }

    private func birthdayTasks(
        in container: ModelContainer,
        prefix: String
    ) -> [ProactiveMessageTaskRecord] {
        let context = ModelContext(container)
        return ((try? context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())) ?? [])
            .filter { $0.idempotencyKey.hasPrefix(prefix) }
    }

    private func insertUserEvent(
        into container: ModelContainer,
        conversationID: UUID,
        roleID: UUID,
        occurredAt: Date,
        sequence: Int
    ) throws {
        let context = ModelContext(container)
        let content = "生日当天的用户消息"
        context.insert(ConversationEvent(
            conversationID: conversationID,
            deviceID: "birthday-test",
            deviceSequence: sequence,
            logicalTimestamp: "birthday-test-\(sequence)",
            occurredAt: occurredAt,
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            deliveryState: .complete,
            roleID: roleID
        ))
        try context.save()
    }
}

@MainActor
private struct BirthdayFixture {
    let bootstrap: PersistenceBootstrap
    let defaults: UserDefaults
    let suiteName: String
    let client: BirthdayCountingClient
    let appModel: AppModel
}

private final class BirthdayCountingClient: AIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var requests = 0

    var completeRequestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
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
        recordRequest()
        return "生日快乐。"
    }

    private func recordRequest() {
        lock.lock()
        requests += 1
        lock.unlock()
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
