import Foundation
import SwiftData
import XCTest
@testable import Ayane

@MainActor
final class ProactiveMessagePolicyTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testInitialDelayRangeUsesTheFourAffinityBands() {
        let cases: [(score: Double, lower: TimeInterval, upper: TimeInterval)] = [
            (0, 10, 14),
            (19.999, 10, 14),
            (20, 7, 10),
            (49.999, 7, 10),
            (50, 5, 7),
            (79.999, 5, 7),
            (80, 3, 5),
            (100, 3, 5)
        ]

        for item in cases {
            let range = ProactiveMessagePolicy.initialDelayRange(for: item.score)
            XCTAssertEqual(range.lowerBound, item.lower * day, accuracy: 0.001)
            XCTAssertEqual(range.upperBound, item.upper * day, accuracy: 0.001)
        }
    }

    func testInitialScheduleUsesAffinityWindowAndFollowUpUsesOneFiveToSevenDayWindow() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let initial = ProactiveMessagePolicy.scheduledDate(
            from: base,
            affinityScore: 88,
            followUpCount: 0,
            randomUnit: 0,
            quietStartHour: 0,
            quietEndHour: 0,
            calendar: calendar
        )
        XCTAssertEqual(initial.timeIntervalSince(base), 3 * day, accuracy: 0.001)

        let followUp = ProactiveMessagePolicy.scheduledDate(
            from: base,
            affinityScore: 0,
            followUpCount: 1,
            randomUnit: 0.5,
            quietStartHour: 0,
            quietEndHour: 0,
            calendar: calendar
        )
        XCTAssertEqual(followUp.timeIntervalSince(base), 6 * day, accuracy: 0.001)

        // Once the initial message has been delivered, every positive count
        // stays on the same single follow-up window instead of returning to
        // an affinity-dependent initial cycle.
        let repeatedFollowUp = ProactiveMessagePolicy.scheduledDate(
            from: base,
            affinityScore: 100,
            followUpCount: 2,
            randomUnit: 0.5,
            quietStartHour: 0,
            quietEndHour: 0,
            calendar: calendar
        )
        XCTAssertEqual(repeatedFollowUp, followUp)
    }

    func testQuietHours23To08DeferAtBothSidesOfMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        let lateNight = try date(
            year: 2026,
            month: 8,
            day: 29,
            hour: 23,
            minute: 30,
            calendar: calendar
        )
        let lateNightDeferred = ProactiveMessagePolicy.deferredOutOfQuietHours(
            lateNight,
            startHour: 23,
            endHour: 8,
            calendar: calendar
        )
        assertDate(
            lateNightDeferred,
            year: 2026,
            month: 8,
            day: 30,
            hour: 8,
            minute: 0,
            calendar: calendar
        )

        let earlyMorning = try date(
            year: 2026,
            month: 8,
            day: 30,
            hour: 7,
            minute: 59,
            calendar: calendar
        )
        let earlyMorningDeferred = ProactiveMessagePolicy.deferredOutOfQuietHours(
            earlyMorning,
            startHour: 23,
            endHour: 8,
            calendar: calendar
        )
        assertDate(
            earlyMorningDeferred,
            year: 2026,
            month: 8,
            day: 30,
            hour: 8,
            minute: 0,
            calendar: calendar
        )

        let daytime = try date(
            year: 2026,
            month: 8,
            day: 30,
            hour: 12,
            minute: 0,
            calendar: calendar
        )
        XCTAssertEqual(
            ProactiveMessagePolicy.deferredOutOfQuietHours(
                daytime,
                startHour: 23,
                endHour: 8,
                calendar: calendar
            ),
            daytime
        )
    }

    func testScheduledDateDefersAnOvernightInitialDeliveryToEight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let base = try date(
            year: 2026,
            month: 8,
            day: 28,
            hour: 0,
            minute: 0,
            calendar: calendar
        )

        let scheduled = ProactiveMessagePolicy.scheduledDate(
            from: base,
            affinityScore: 80,
            followUpCount: 0,
            randomUnit: 0.5,
            quietStartHour: 23,
            quietEndHour: 8,
            calendar: calendar
        )
        assertDate(
            scheduled,
            year: 2026,
            month: 9,
            day: 1,
            hour: 8,
            minute: 0,
            calendar: calendar
        )
    }

    func testNotificationRouteRoundTripsUserInfoAndUsesDistinctStageIdentifiers() throws {
        let taskID = UUID()
        let roleID = UUID()
        let conversationID = UUID()
        let stages: [ProactiveNotificationStage] = [.initial, .followUp, .test]
        let routes = stages.map {
            ProactiveNotificationRoute(
                taskID: taskID,
                roleID: roleID,
                conversationID: conversationID,
                stage: $0
            )
        }

        for route in routes {
            let decoded = try XCTUnwrap(
                ProactiveNotificationRoute(userInfo: route.userInfo)
            )
            XCTAssertEqual(decoded, route)
        }

        XCTAssertEqual(Set(routes.map(\.requestIdentifier)).count, stages.count)
        XCTAssertEqual(
            routes[0].requestIdentifier,
            ProactiveNotificationRoute(
                taskID: taskID,
                roleID: roleID,
                conversationID: conversationID,
                stage: .initial
            ).requestIdentifier
        )
    }

    func testNotificationCancellationIdentifiersIncludeLegacyAndAllStages() {
        let taskID = UUID()
        let identifiers = Set(
            ProactiveNotificationRoute.cancellationIdentifiers(for: [taskID])
        )
        let legacyIdentifier = taskID.uuidString.lowercased()
        XCTAssertTrue(identifiers.contains(legacyIdentifier))

        let expectedStageIdentifiers = Set(
            [ProactiveNotificationStage.initial, .followUp, .test].map {
                ProactiveNotificationRoute(
                    taskID: taskID,
                    roleID: UUID(),
                    conversationID: UUID(),
                    stage: $0
                ).requestIdentifier
            }
        )
        XCTAssertTrue(identifiers.isSuperset(of: expectedStageIdentifiers))
    }

    func testNotificationRouteSelectsItsExactConversation() throws {
        let suiteName = "ProactiveMessagePolicyTests.RouteSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let routedConversation = ConversationRecord(
            title: "通知指定会话",
            createdAt: Date().addingTimeInterval(-60),
            roleID: appModel.currentRoleID
        )
        let context = ModelContext(bootstrap.container)
        context.insert(routedConversation)
        try context.save()
        appModel.refreshFromStore(force: true)

        try appModel.selectCompanion(
            id: appModel.currentRoleID,
            conversationID: routedConversation.id
        )

        XCTAssertEqual(appModel.currentConversation.id, routedConversation.id)
    }

    func testDueTaskSendsOneInitialAndOneFollowUpThenCompletes() throws {
        let suiteName = "ProactiveMessagePolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let context = ModelContext(bootstrap.container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let generatedText = #"{"initial":"先来问候你。","followUp":"最后再来看看你。"}"#
        let task = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(-1),
            followUpCount: 0,
            state: .scheduled,
            generatedText: generatedText,
            lastUserEventID: nil,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 1,
            deviceID: "policy-test"
        )
        context.insert(task)
        try context.save()
        appModel.refreshFromStore(force: true)

        appModel.processDueProactiveTasks(now: now)

        let firstPassTask = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
                .first { $0.id == task.id }
        )
        XCTAssertEqual(firstPassTask.followUpCount, 1)
        XCTAssertEqual(firstPassTask.state, .scheduled)
        let firstFollowUpDelay = firstPassTask.scheduledAt.timeIntervalSince(now)
        XCTAssertGreaterThanOrEqual(firstFollowUpDelay, 5 * day)
        XCTAssertLessThanOrEqual(firstFollowUpDelay, 7 * day)

        let firstMessages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
            .sorted { $0.occurredAt < $1.occurredAt }
        XCTAssertEqual(firstMessages.map(\.content), ["先来问候你。"])

        appModel.processDueProactiveTasks(now: firstPassTask.scheduledAt.addingTimeInterval(1))

        let secondPassTask = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
                .first { $0.id == task.id }
        )
        XCTAssertEqual(secondPassTask.followUpCount, 1)
        XCTAssertEqual(secondPassTask.state, .completed)
        let secondMessages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
            .sorted { $0.occurredAt < $1.occurredAt }
        XCTAssertEqual(secondMessages.map(\.content), ["先来问候你。", "最后再来看看你。"])

        appModel.processDueProactiveTasks(now: firstPassTask.scheduledAt.addingTimeInterval(8 * day))
        let thirdMessages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
        XCTAssertEqual(thirdMessages.count, 2)
    }

    func testDueTasksWithSeparateInitialAndFollowUpRecordsPersistEachStage() throws {
        let suiteName = "ProactiveMessagePolicyTests.SeparateStages.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(true, forKey: SettingsKeys.proactiveFollowUpEnabled)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let context = ModelContext(bootstrap.container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initialKey = "proactive:\(appModel.currentRoleID.uuidString.lowercased()):\(UUID().uuidString.lowercased())"
        let generatedText = #"{"initial":"首条主动消息。","followUp":"第二条主动消息。"}"#
        let initial = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(-1),
            followUpCount: 0,
            state: .scheduled,
            idempotencyKey: initialKey,
            generatedText: generatedText,
            lastUserEventID: nil,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 1,
            deviceID: "policy-test"
        )
        let followUp = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(86_400),
            followUpCount: 1,
            state: .scheduled,
            idempotencyKey: "\(initialKey):follow-up",
            generatedText: generatedText,
            lastUserEventID: nil,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 1,
            deviceID: "policy-test"
        )
        context.insert(initial)
        context.insert(followUp)
        try context.save()
        appModel.refreshFromStore(force: true)

        appModel.processDueProactiveTasks(now: now)

        let firstPassTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let firstPassInitial = try XCTUnwrap(
            firstPassTasks.first { $0.idempotencyKey == initialKey }
        )
        let firstPassFollowUp = try XCTUnwrap(
            firstPassTasks.first { $0.idempotencyKey == "\(initialKey):follow-up" }
        )
        XCTAssertEqual(firstPassInitial.state, .completed)
        XCTAssertEqual(firstPassInitial.followUpCount, 0)
        XCTAssertEqual(firstPassFollowUp.state, .scheduled)
        XCTAssertEqual(firstPassFollowUp.followUpCount, 1)
        XCTAssertEqual(firstPassTasks.count, 2)

        let firstMessages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
            .sorted { $0.occurredAt < $1.occurredAt }
        XCTAssertEqual(firstMessages.map(\.content), ["首条主动消息。"])

        appModel.processDueProactiveTasks(
            now: followUp.scheduledAt.addingTimeInterval(1)
        )

        let secondPassTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let secondPassFollowUp = try XCTUnwrap(
            secondPassTasks.first { $0.idempotencyKey == "\(initialKey):follow-up" }
        )
        XCTAssertEqual(secondPassFollowUp.state, .completed)
        XCTAssertEqual(secondPassFollowUp.followUpCount, 1)
        XCTAssertEqual(secondPassTasks.count, 2)

        let secondMessages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
            .sorted { $0.occurredAt < $1.occurredAt }
        XCTAssertEqual(
            secondMessages.map(\.content),
            ["首条主动消息。", "第二条主动消息。"]
        )
    }

    func testGeneratedTwoStageFollowUpToggleCancelsRestoresAndDeliversEachOnce() async throws {
        let suiteName = "ProactiveMessagePolicyTests.ToggleRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://unit.test/v1", forKey: SettingsKeys.baseURL)
        defaults.set("fixture-model", forKey: SettingsKeys.model)
        defaults.set(false, forKey: SettingsKeys.streamResponses)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.humanizedReplyDelayEnabled)
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(true, forKey: SettingsKeys.proactiveFollowUpEnabled)
        defaults.set(false, forKey: SettingsKeys.conversationCareEnabled)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            client: GeneratedTwoStageFixtureClient(),
            memoryIndex: LocalMemorySearchIndex(inMemory: true),
            conversationIndex: LocalConversationSearchIndex(inMemory: true),
            dataDefaults: defaults,
            apiKeyLoader: { "fixture-key" },
            performLegacyConversationMigration: false,
            seedBuiltInCompanions: false
        )

        appModel.send("触发双阶段主动消息")
        try await waitUntil {
            let context = ModelContext(bootstrap.container)
            let tasks = (try? context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())) ?? []
            return tasks.contains(where: { $0.followUpCount == 0 })
                && tasks.contains(where: { $0.followUpCount == 1 })
        }

        let context = ModelContext(bootstrap.container)
        let generatedTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let initial = try XCTUnwrap(generatedTasks.first { $0.followUpCount == 0 })
        let followUp = try XCTUnwrap(generatedTasks.first { $0.followUpCount == 1 })
        XCTAssertEqual(followUp.idempotencyKey, initial.idempotencyKey + ":follow-up")
        XCTAssertEqual(initial.state, .scheduled)
        XCTAssertEqual(followUp.state, .scheduled)

        defaults.set(false, forKey: SettingsKeys.proactiveFollowUpEnabled)
        appModel.proactiveFollowUpSettingDidChange(enabled: false)

        let cancelledTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let cancelledFollowUp = try XCTUnwrap(
            cancelledTasks.first { $0.id == followUp.id }
        )
        XCTAssertEqual(cancelledFollowUp.state, .cancelled)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<ConversationEvent>())
                .filter { $0.content == "生成初始主动消息。" || $0.content == "生成跟进主动消息。" }
                .count,
            0
        )

        defaults.set(true, forKey: SettingsKeys.proactiveFollowUpEnabled)
        appModel.proactiveFollowUpSettingDidChange(enabled: true)

        let restoredTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        let restoredFollowUp = try XCTUnwrap(
            restoredTasks.first { $0.id == followUp.id }
        )
        XCTAssertEqual(restoredFollowUp.state, .scheduled)
        XCTAssertEqual(restoredFollowUp.followUpCount, 1)

        let deliveryNow = Date()
        let currentInitial = try XCTUnwrap(
            restoredTasks.first { $0.id == initial.id }
        )
        currentInitial.scheduledAt = deliveryNow.addingTimeInterval(-2)
        restoredFollowUp.scheduledAt = deliveryNow.addingTimeInterval(-1)
        try context.save()
        appModel.processDueProactiveTasks(now: deliveryNow)

        let proactiveContents = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.content == "生成初始主动消息。"
                    || $0.content == "生成跟进主动消息。"
            }
            .sorted { $0.occurredAt < $1.occurredAt }
            .map(\.content)
        XCTAssertEqual(
            proactiveContents,
            ["生成初始主动消息。", "生成跟进主动消息。"]
        )

        let completedTasks = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        XCTAssertEqual(
            try XCTUnwrap(completedTasks.first { $0.id == initial.id }).state,
            .completed
        )
        XCTAssertEqual(
            try XCTUnwrap(completedTasks.first { $0.id == followUp.id }).state,
            .completed
        )

        appModel.processDueProactiveTasks(now: deliveryNow.addingTimeInterval(86_400))
        let afterRetryContents = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.content == "生成初始主动消息。"
                    || $0.content == "生成跟进主动消息。"
            }
        XCTAssertEqual(afterRetryContents.count, 2)
    }

    func testCancelledFollowUpSiblingDoesNotPermanentlySwallowFollowUp() throws {
        let suiteName = "ProactiveMessagePolicyTests.CancelledSibling.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(true, forKey: SettingsKeys.proactiveFollowUpEnabled)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(false, forKey: SettingsKeys.conversationCareEnabled)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let context = ModelContext(bootstrap.container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let initialKey = "proactive:\(appModel.currentRoleID.uuidString.lowercased()):\(UUID().uuidString.lowercased())"
        let generatedText = #"{"initial":"孤立初始主动消息。","followUp":"孤立跟进主动消息。"}"#
        let initial = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(-1),
            followUpCount: 0,
            state: .scheduled,
            idempotencyKey: initialKey,
            generatedText: generatedText,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 1,
            deviceID: "policy-test"
        )
        let cancelledSibling = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(86_400),
            followUpCount: 1,
            state: .cancelled,
            idempotencyKey: initialKey + ":follow-up",
            generatedText: generatedText,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 2,
            deviceID: "policy-test"
        )
        context.insert(initial)
        context.insert(cancelledSibling)
        try context.save()
        appModel.refreshFromStore(force: true)

        appModel.processDueProactiveTasks(now: now)

        let firstContents = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.content == "孤立初始主动消息。"
                    || $0.content == "孤立跟进主动消息。"
            }
            .map(\.content)
        XCTAssertEqual(firstContents, ["孤立初始主动消息。"])

        let afterFirst = try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
        XCTAssertEqual(
            try XCTUnwrap(afterFirst.first { $0.id == cancelledSibling.id }).state,
            .cancelled
        )
        let activeFollowUpDates = afterFirst
            .filter { !$0.state.isTerminal && $0.followUpCount > 0 }
            .map(\.scheduledAt)
        let followUpDue = try XCTUnwrap(activeFollowUpDates.max())
        appModel.processDueProactiveTasks(now: followUpDue.addingTimeInterval(1))

        let secondContents = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter {
                $0.content == "孤立初始主动消息。"
                    || $0.content == "孤立跟进主动消息。"
            }
            .map(\.content)
        XCTAssertEqual(secondContents.count, 2)
        XCTAssertEqual(
            secondContents.filter { $0 == "孤立初始主动消息。" }.count,
            1
        )
        XCTAssertEqual(
            secondContents.filter { $0 == "孤立跟进主动消息。" }.count,
            1
        )
    }

    func testNewBehaviorDefaultsAndConfiguredFollowUpRange() throws {
        let suiteName = "ProactiveMessagePolicyTests.Settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(SettingsStore.timeInjectionEnabled(defaults: defaults))
        XCTAssertTrue(SettingsStore.proactiveFollowUpEnabled(defaults: defaults))
        XCTAssertEqual(
            SettingsStore.proactiveFollowUpDayRange(defaults: defaults),
            ProactiveMessagePolicy.defaultFollowUpMinDays...ProactiveMessagePolicy.defaultFollowUpMaxDays
        )

        defaults.set(false, forKey: SettingsKeys.timeInjectionEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveFollowUpEnabled)
        defaults.set(9, forKey: SettingsKeys.proactiveFollowUpMinDays)
        defaults.set(3, forKey: SettingsKeys.proactiveFollowUpMaxDays)
        XCTAssertFalse(SettingsStore.timeInjectionEnabled(defaults: defaults))
        XCTAssertFalse(SettingsStore.proactiveFollowUpEnabled(defaults: defaults))
        XCTAssertEqual(SettingsStore.proactiveFollowUpDayRange(defaults: defaults), 9...9)
        XCTAssertEqual(
            SettingsStore.proactiveFollowUpDelayRange(defaults: defaults).lowerBound,
            9 * day,
            accuracy: 0.001
        )
    }

    func testGlobalProactiveOffCannotBeOverriddenByRoleOptIn() throws {
        let suiteName = "ProactiveMessagePolicyTests.GlobalGate.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let roleID = UUID()

        defaults.set(false, forKey: SettingsKeys.proactiveMessagesEnabled)
        SettingsStore.setProactiveMessagesEnabled(true, roleID: roleID, defaults: defaults)
        XCTAssertFalse(SettingsStore.proactiveMessagesEnabled(roleID: roleID, defaults: defaults))

        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        XCTAssertTrue(SettingsStore.proactiveMessagesEnabled(roleID: roleID, defaults: defaults))
    }

    func testConfiguredFollowUpRangeIsUsedByScheduler() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let configured = ProactiveMessagePolicy.followUpDelayRange(minDays: 2, maxDays: 4)
        let scheduled = ProactiveMessagePolicy.scheduledDate(
            from: base,
            affinityScore: 0,
            followUpCount: 1,
            randomUnit: 0.5,
            followUpDelayRange: configured,
            quietStartHour: 0,
            quietEndHour: 0
        )
        XCTAssertEqual(scheduled.timeIntervalSince(base), 3 * day, accuracy: 0.001)
    }

    func testDisablingFollowUpCompletesInitialTaskWithoutSchedulingSecondMessage() throws {
        let suiteName = "ProactiveMessagePolicyTests.NoFollowUp.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: SettingsKeys.proactiveMessagesEnabled)
        defaults.set(false, forKey: SettingsKeys.proactiveFollowUpEnabled)
        defaults.set(false, forKey: SettingsKeys.autoExtractMemory)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietStartHour)
        defaults.set(0, forKey: SettingsKeys.proactiveQuietEndHour)

        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let appModel = AppModel(
            bootstrap: bootstrap,
            dataDefaults: defaults,
            apiKeyLoader: { nil }
        )
        let context = ModelContext(bootstrap.container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let task = ProactiveMessageTaskRecord(
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            scheduledAt: now.addingTimeInterval(-1),
            followUpCount: 0,
            state: .scheduled,
            generatedText: #"{"initial":"只来一次。","follow_up":"不应发送。"}"#,
            lastUserEventID: nil,
            scheduledFromUserAt: now.addingTimeInterval(-86_400),
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-86_400),
            revision: 1,
            deviceID: "policy-test"
        )
        context.insert(task)
        try context.save()
        appModel.refreshFromStore(force: true)

        appModel.processDueProactiveTasks(now: now)

        let savedTask = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ProactiveMessageTaskRecord>())
                .first { $0.id == task.id }
        )
        XCTAssertEqual(savedTask.state, .completed)
        XCTAssertEqual(savedTask.followUpCount, 0)
        let messages = try context.fetch(FetchDescriptor<ConversationEvent>())
            .filter { $0.conversationID == appModel.currentConversation.id }
        XCTAssertEqual(messages.map(\.content), ["只来一次。"])
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
        XCTFail("Timed out waiting for proactive task generation")
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }

    private func assertDate(
        _ date: Date,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) {
        let values = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        XCTAssertEqual(values.year, year)
        XCTAssertEqual(values.month, month)
        XCTAssertEqual(values.day, day)
        XCTAssertEqual(values.hour, hour)
        XCTAssertEqual(values.minute, minute)
    }
}

private final class GeneratedTwoStageFixtureClient: AIClientProtocol, @unchecked Sendable {
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
        if messages.contains(where: { $0.content.contains("只输出 JSON") }) {
            return #"{"initial":"生成初始主动消息。","follow_up":"生成跟进主动消息。"}"#
        }
        return "普通回复，不属于主动消息。"
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
