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
