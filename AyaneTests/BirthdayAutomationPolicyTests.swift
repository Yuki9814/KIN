import Foundation
import XCTest
@testable import Ayane

final class BirthdayAutomationPolicyTests: XCTestCase {
    private let roleID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let otherRoleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let conversationID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let otherConversationID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func birthday(_ month: Int, _ day: Int) -> BirthdayMonthDay {
        BirthdayMonthDay(month: month, day: day)!
    }

    private func date(
        _ policy: BirthdayAutomationPolicy,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) throws -> Date {
        try XCTUnwrap(policy.calendar.date(from: DateComponents(
            calendar: policy.calendar,
            timeZone: policy.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )))
    }

    private func localComponents(
        _ date: Date,
        policy: BirthdayAutomationPolicy
    ) -> DateComponents {
        policy.calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }

    func testMonthDayValidatesGregorianMonthLengthsAndKeepsFebruary29() throws {
        XCTAssertNotNil(BirthdayMonthDay(month: 2, day: 29))
        XCTAssertNil(BirthdayMonthDay(month: 2, day: 30))
        XCTAssertNil(BirthdayMonthDay(month: 4, day: 31))
        XCTAssertNil(BirthdayMonthDay(month: 0, day: 1))
        XCTAssertNil(BirthdayMonthDay(month: 13, day: 1))

        let value = birthday(2, 29)
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(BirthdayMonthDay.self, from: encoded), value)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                BirthdayMonthDay.self,
                from: Data(#"{"month":2,"day":30}"#.utf8)
            )
        )
    }

    func testShanghaiGreetingUsesLocalYearAndStableKey() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Shanghai")
        let occurrence = try XCTUnwrap(policy.userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday(8, 30),
            localYear: 2026
        ))

        let components = localComponents(occurrence.scheduledAt, policy: policy)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 30)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
        XCTAssertTrue(occurrence.occurrenceKey.contains(BirthdayAutomationKind.userBirthdayGreeting.rawValue))
        XCTAssertTrue(occurrence.occurrenceKey.contains(roleID.uuidString.lowercased()))
        XCTAssertTrue(occurrence.occurrenceKey.contains("2026"))
        XCTAssertTrue(occurrence.occurrenceKey.contains("08-30"))
    }

    func testFebruary29UsesFebruary28InNonLeapYearAndKeepsBirthdayKey() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Shanghai")
        let occurrence = try XCTUnwrap(policy.userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday(2, 29),
            localYear: 2025
        ))
        let components = localComponents(occurrence.scheduledAt, policy: policy)

        // Product rule: in a non-leap Gregorian year, 02-29 is observed on
        // 02-28.  The key retains the configured birthday month/day so a
        // recurring 02-29 profile has one stable identity across years.
        XCTAssertEqual(components.month, 2)
        XCTAssertEqual(components.day, 28)
        XCTAssertTrue(occurrence.occurrenceKey.contains("2025|02-29"))

        let leap = try XCTUnwrap(policy.roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday(2, 29),
            localYear: 2024
        ))
        XCTAssertEqual(localComponents(leap.scheduledAt, policy: policy).day, 29)
    }

    func testRoleCheckInHourIsStableAcrossPoliciesAndAlwaysUsesZeroOneOrTwo() throws {
        let shanghai = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Shanghai")
        let newYork = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let shanghaiOccurrence = try XCTUnwrap(shanghai.roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday(8, 30),
            localYear: 2026
        ))
        let newYorkOccurrence = try XCTUnwrap(newYork.roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday(8, 30),
            localYear: 2026
        ))

        let shanghaiHour = try XCTUnwrap(localComponents(
            shanghaiOccurrence.scheduledAt,
            policy: shanghai
        ).hour)
        let newYorkHour = try XCTUnwrap(localComponents(
            newYorkOccurrence.scheduledAt,
            policy: newYork
        ).hour)
        XCTAssertEqual(shanghaiHour, newYorkHour)
        XCTAssertTrue(BirthdayAutomationPolicy.roleCheckInHours.contains(shanghaiHour))
        XCTAssertEqual(
            BirthdayAutomationPolicy.roleBirthdayCheckInHour(
                roleID: roleID,
                localYear: 2026
            ),
            shanghaiHour
        )
        XCTAssertEqual(shanghaiOccurrence.occurrenceKey, newYorkOccurrence.occurrenceKey)
    }

    func testNextOccurrenceUsesLocalBirthdayAndMovesToFollowingYearAfterDueTime() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let before = try date(policy, year: 2026, month: 8, day: 30, hour: 8, minute: 59)
        let first = try XCTUnwrap(policy.nextOccurrence(
            kind: .userBirthdayGreeting,
            roleID: roleID,
            birthday: birthday(8, 30),
            onOrAfter: before
        ))
        XCTAssertEqual(localComponents(first.scheduledAt, policy: policy).year, 2026)

        let after = try date(policy, year: 2026, month: 8, day: 30, hour: 9, minute: 1)
        let following = try XCTUnwrap(policy.nextOccurrence(
            kind: .userBirthdayGreeting,
            roleID: roleID,
            birthday: birthday(8, 30),
            onOrAfter: after
        ))
        XCTAssertEqual(localComponents(following.scheduledAt, policy: policy).year, 2027)
        XCTAssertGreaterThanOrEqual(following.scheduledAt, after)
    }

    func testDSTMissingTimeMovesForwardAndRepeatedTimeUsesFirstInstance() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let missing = try XCTUnwrap(policy.userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday(3, 8),
            localYear: 2026,
            hour: 2,
            minute: 30
        ))
        let missingComponents = localComponents(missing.scheduledAt, policy: policy)
        XCTAssertEqual(missingComponents.month, 3)
        XCTAssertEqual(missingComponents.day, 8)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(missingComponents.hour), 3)

        let repeated = try XCTUnwrap(policy.userBirthdayGreetingOccurrence(
            roleID: roleID,
            birthday: birthday(11, 1),
            localYear: 2026,
            hour: 1,
            minute: 30
        ))
        XCTAssertEqual(policy.timeZone.secondsFromGMT(for: repeated.scheduledAt), -4 * 60 * 60)
    }

    func testBirthdayLocalDayIntervalRetainsDSTDayLength() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let spring = try XCTUnwrap(policy.birthdayLocalDayInterval(
            for: birthday(3, 8),
            in: 2026
        ))
        let fall = try XCTUnwrap(policy.birthdayLocalDayInterval(
            for: birthday(11, 1),
            in: 2026
        ))
        XCTAssertEqual(spring.duration, 23 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(fall.duration, 25 * 60 * 60, accuracy: 0.001)
    }

    func testRoleCheckInCancellationRequiresCompleteUnretractedUserMessageInBirthdayChat() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Shanghai")
        let now = try date(policy, year: 2026, month: 8, day: 30, hour: 12)
        let valid = BirthdayAutomationEvent(
            roleID: roleID,
            conversationID: conversationID,
            occurredAt: now.addingTimeInterval(-60),
            isUser: true,
            isComplete: true,
            isRetracted: false
        )
        XCTAssertTrue(policy.shouldCancelRoleCheckIn(
            roleID: roleID,
            conversationID: conversationID,
            birthday: birthday(8, 30),
            events: [valid],
            now: now
        ))

        let rejected: [BirthdayAutomationEvent] = [
            BirthdayAutomationEvent(
                roleID: otherRoleID,
                conversationID: conversationID,
                occurredAt: now,
                isUser: true
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: otherConversationID,
                occurredAt: now,
                isUser: true
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: conversationID,
                occurredAt: now,
                isUser: false
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: conversationID,
                occurredAt: now,
                isUser: true,
                isComplete: false
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: conversationID,
                occurredAt: now,
                isUser: true,
                isRetracted: true
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: conversationID,
                occurredAt: now,
                isUser: true,
                isGroup: true
            ),
            BirthdayAutomationEvent(
                roleID: roleID,
                conversationID: conversationID,
                occurredAt: now.addingTimeInterval(60),
                isUser: true
            )
        ]
        XCTAssertFalse(policy.shouldCancelRoleCheckIn(
            roleID: roleID,
            conversationID: conversationID,
            birthday: birthday(8, 30),
            events: rejected,
            now: now
        ))
    }

    func testCancellationRejectsMessageOutsideBirthdayLocalDayAndGroupConversation() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let birthdayDay = try date(policy, year: 2026, month: 8, day: 30, hour: 12)
        let event = BirthdayAutomationEvent(
            roleID: roleID,
            conversationID: conversationID,
            occurredAt: birthdayDay,
            isUser: true
        )
        XCTAssertFalse(policy.shouldCancelRoleCheckIn(
            roleID: roleID,
            conversationID: conversationID,
            birthday: birthday(8, 29),
            events: [event],
            now: birthdayDay
        ))
        XCTAssertFalse(policy.shouldCancelRoleCheckIn(
            roleID: roleID,
            conversationID: conversationID,
            birthday: birthday(8, 30),
            events: [event],
            now: birthdayDay,
            conversationIsGroup: true
        ))
    }

    func testOccurrenceValidityIsBoundToScheduledLocalBirthdayDay() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Shanghai")
        let scheduled = try date(policy, year: 2026, month: 8, day: 30, hour: 9)
        let sameDayCatchUp = try date(policy, year: 2026, month: 8, day: 30, hour: 23, minute: 59)
        let nextDay = try date(policy, year: 2026, month: 8, day: 31, hour: 0)
        let beforeDue = try date(policy, year: 2026, month: 8, day: 30, hour: 8, minute: 59)

        XCTAssertTrue(policy.isOccurrenceStillValid(
            now: sameDayCatchUp,
            scheduledAt: scheduled,
            kind: .roleBirthdayCheckIn
        ))
        XCTAssertTrue(policy.isOccurrenceStillValid(
            now: sameDayCatchUp,
            scheduledAt: scheduled,
            kind: .userBirthdayGreeting
        ))
        XCTAssertFalse(policy.isOccurrenceStillValid(
            now: nextDay,
            scheduledAt: scheduled,
            kind: .roleBirthdayCheckIn
        ))
        XCTAssertFalse(policy.isOccurrenceStillValid(
            now: beforeDue,
            scheduledAt: scheduled,
            kind: .userBirthdayGreeting
        ))
    }

    func testPolicyPersistsOnlyTimezoneIdentifierAndRecreatesGregorianCalendar() throws {
        let original = BirthdayAutomationPolicy(timeZoneIdentifier: "America/New_York")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(BirthdayAutomationPolicy.self, from: data)

        XCTAssertEqual(restored.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(restored.calendar.identifier, .gregorian)
        XCTAssertEqual(restored.calendar.timeZone.identifier, "America/New_York")
        XCTAssertEqual(restored, original)
    }

    func testBirthdayOccurrenceProjectsToTheDeviceCalendarDay() throws {
        let policy = BirthdayAutomationPolicy(timeZoneIdentifier: "Asia/Tokyo")
        let occurrence = try XCTUnwrap(policy.roleBirthdayCheckInOccurrence(
            roleID: roleID,
            birthday: birthday(1, 1),
            localYear: 2027
        ))
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let components = deviceCalendar.dateComponents(
            [.year, .month, .day],
            from: occurrence.scheduledAt
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 31)
    }
}
