import Foundation
import XCTest
@testable import Ayane

final class MomentTaskRecurrenceTests: XCTestCase {
    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        timezoneIdentifier: String
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func components(
        _ value: Date,
        timezoneIdentifier: String
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezoneIdentifier)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: value)
    }

    func testOnceHasNoSuccessor() {
        let rule = MomentTaskRecurrenceRule(
            frequency: .once,
            scheduledAt: date(2024, 1, 1, 10, 0, timezoneIdentifier: "Asia/Shanghai")
        )

        XCTAssertNil(rule.nextOccurrence(after: Date.distantPast))
        XCTAssertEqual(rule.chineseTitle, "仅一次")
    }

    func testHourlyUsesCalendarInterval() {
        let anchor = date(2024, 1, 1, 10, 15, timezoneIdentifier: "Asia/Shanghai")
        let rule = MomentTaskRecurrenceRule(
            frequency: .hourly,
            interval: 2,
            hour: 10,
            minute: 15,
            timezoneIdentifier: "Asia/Shanghai",
            scheduledAt: anchor
        )

        let next = try! XCTUnwrap(rule.nextOccurrence(after: anchor))
        let value = components(next, timezoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(value.hour, 12)
        XCTAssertEqual(value.minute, 15)
    }

    func testDailyAsiaShanghaiKeepsWallClockTime() {
        let anchor = date(2024, 1, 1, 9, 30, timezoneIdentifier: "Asia/Shanghai")
        let rule = MomentTaskRecurrenceRule(
            frequency: .daily,
            hour: 9,
            minute: 30,
            timezoneIdentifier: "Asia/Shanghai",
            scheduledAt: anchor
        )

        let next = try! XCTUnwrap(rule.nextOccurrence(after: anchor))
        let value = components(next, timezoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(value.year, 2024)
        XCTAssertEqual(value.month, 1)
        XCTAssertEqual(value.day, 2)
        XCTAssertEqual(value.hour, 9)
        XCTAssertEqual(value.minute, 30)
    }

    func testWeeklyUsesSundayBasedCalendarWeekday() {
        let anchor = date(2024, 1, 1, 8, 0, timezoneIdentifier: "Asia/Shanghai")
        let rule = MomentTaskRecurrenceRule(
            frequency: .weekly,
            interval: 1,
            weekday: 2, // Monday in Calendar's 1...7 convention.
            hour: 8,
            minute: 0,
            timezoneIdentifier: "Asia/Shanghai",
            scheduledAt: anchor
        )

        let next = try! XCTUnwrap(rule.nextOccurrence(after: anchor))
        let value = components(next, timezoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(value.year, 2024)
        XCTAssertEqual(value.month, 1)
        XCTAssertEqual(value.day, 8)
    }

    func testMonthlyClampsDayThirtyOneToMonthEnd() {
        let anchor = date(2024, 1, 31, 10, 0, timezoneIdentifier: "Asia/Shanghai")
        let rule = MomentTaskRecurrenceRule(
            frequency: .monthly,
            dayOfMonth: 31,
            hour: 10,
            minute: 0,
            timezoneIdentifier: "Asia/Shanghai",
            scheduledAt: anchor
        )

        let february = try! XCTUnwrap(rule.nextOccurrence(after: anchor))
        let februaryValue = components(february, timezoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(februaryValue.month, 2)
        XCTAssertEqual(februaryValue.day, 29)

        let march = try! XCTUnwrap(rule.nextOccurrence(after: february))
        let marchValue = components(march, timezoneIdentifier: "Asia/Shanghai")
        XCTAssertEqual(marchValue.month, 3)
        XCTAssertEqual(marchValue.day, 31)
    }

    func testNewYorkDSTMissingTimeMovesForwardAndRepeatedTimeUsesFirst() {
        let springAnchor = date(2024, 3, 9, 2, 30, timezoneIdentifier: "America/New_York")
        let springRule = MomentTaskRecurrenceRule(
            frequency: .daily,
            hour: 2,
            minute: 30,
            timezoneIdentifier: "America/New_York",
            scheduledAt: springAnchor
        )
        let spring = try! XCTUnwrap(springRule.nextOccurrence(after: springAnchor))
        let springValue = components(spring, timezoneIdentifier: "America/New_York")
        XCTAssertEqual(springValue.month, 3)
        XCTAssertEqual(springValue.day, 10)
        XCTAssertEqual(springValue.hour, 3)
        XCTAssertEqual(springValue.minute, 30)

        let autumnAnchor = date(2024, 11, 2, 1, 30, timezoneIdentifier: "America/New_York")
        let autumnRule = MomentTaskRecurrenceRule(
            frequency: .daily,
            hour: 1,
            minute: 30,
            timezoneIdentifier: "America/New_York",
            scheduledAt: autumnAnchor
        )
        let autumn = try! XCTUnwrap(autumnRule.nextOccurrence(after: autumnAnchor))
        let autumnValue = components(autumn, timezoneIdentifier: "America/New_York")
        XCTAssertEqual(autumnValue.month, 11)
        XCTAssertEqual(autumnValue.day, 3)
        XCTAssertEqual(autumnValue.hour, 1)
        XCTAssertEqual(autumnValue.minute, 30)
        XCTAssertEqual(TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: autumn), -14_400)
    }

    func testOccurrenceKeyIsStableInPersistedTimezone() {
        let anchor = date(2024, 1, 31, 10, 5, timezoneIdentifier: "Asia/Shanghai")
        let seriesID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let rule = MomentTaskRecurrenceRule(
            frequency: .monthly,
            dayOfMonth: 31,
            hour: 10,
            minute: 5,
            timezoneIdentifier: "Asia/Shanghai",
            scheduledAt: anchor,
            seriesID: seriesID
        )

        XCTAssertEqual(
            rule.occurrenceKey,
            "00000000-0000-0000-0000-000000000001|2024-01-31T10:05|Asia/Shanghai"
        )
        XCTAssertEqual(rule.occurrenceKey, rule.stableOccurrenceKey(for: anchor))
    }

    func testLegacyTaskDefaultsToOneShotRecurrence() {
        let task = CompanionMomentTaskRecord(instruction: "legacy")

        XCTAssertNil(task.seriesID)
        XCTAssertEqual(task.occurrenceKey, "")
        XCTAssertEqual(task.recurrenceRaw, MomentTaskRecurrenceFrequency.once.rawValue)
        XCTAssertEqual(task.recurrenceInterval, 1)
        XCTAssertNil(task.recurrenceWeekday)
        XCTAssertNil(task.recurrenceDayOfMonth)
        XCTAssertEqual(task.recurrenceHour, 0)
        XCTAssertEqual(task.recurrenceMinute, 0)
        XCTAssertEqual(task.timezoneIdentifier, TimeZone.current.identifier)
        XCTAssertNil(task.nextAttemptAt)
    }
}
