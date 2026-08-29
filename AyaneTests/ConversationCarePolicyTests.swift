import Foundation
import XCTest
@testable import Ayane

final class ConversationCarePolicyTests: XCTestCase {
    private let minute: TimeInterval = 60
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testExactlyTwentyMinutesStaysInOneSessionButALargerGapStartsAnother() {
        let events = [
            event("00000000-0000-0000-0000-000000000001", minutes: 0, user: true),
            event("00000000-0000-0000-0000-000000000002", minutes: 20, user: false),
            event("00000000-0000-0000-0000-000000000003", minutes: 40, user: true),
            event("00000000-0000-0000-0000-000000000004", minutes: 60, user: false),
            event("00000000-0000-0000-0000-000000000005", minutes: 80.001, user: true)
        ]

        let sessions = ConversationCarePolicy.sessions(from: events)

        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].events.count, 4)
        XCTAssertEqual(sessions[1].events.count, 1)
        XCTAssertEqual(sessions[0].startDate, base)
        XCTAssertEqual(sessions[0].lastEventDate, date(minutes: 60))
    }

    func testInterleavedUserAndAssistantEventsKeepAllActivityAndTrackLastUser() {
        let events = [
            event("00000000-0000-0000-0000-000000000011", minutes: 0, user: true),
            event("00000000-0000-0000-0000-000000000012", minutes: 5, user: false),
            event("00000000-0000-0000-0000-000000000013", minutes: 10, user: true),
            event("00000000-0000-0000-0000-000000000014", minutes: 15, user: false),
            event("00000000-0000-0000-0000-000000000015", minutes: 20, user: true),
            event("00000000-0000-0000-0000-000000000016", minutes: 25, user: false),
            event("00000000-0000-0000-0000-000000000017", minutes: 30, user: true),
            event("00000000-0000-0000-0000-000000000018", minutes: 35, user: false)
        ]
        let session = try! XCTUnwrap(ConversationCarePolicy.latestSession(from: events))

        XCTAssertEqual(session.startEvent.id.uuidString.lowercased(), "00000000-0000-0000-0000-000000000011")
        XCTAssertEqual(session.startDate, base)
        XCTAssertEqual(session.lastEvent.id.uuidString.lowercased(), "00000000-0000-0000-0000-000000000018")
        XCTAssertEqual(session.lastEventDate, date(minutes: 35))
        XCTAssertEqual(session.lastUserEvent?.id.uuidString.lowercased(), "00000000-0000-0000-0000-000000000017")
        XCTAssertEqual(session.lastUserEventDate, date(minutes: 30))
        XCTAssertEqual(session.userTurnCount, 4)
        XCTAssertEqual(session.elapsed(at: date(minutes: 90)), 90 * minute, accuracy: 0.001)
        XCTAssertEqual(session.elapsedMinutes(at: date(minutes: 90)), 90)
        XCTAssertTrue(session.isActive(at: date(minutes: 50)))
        XCTAssertFalse(session.isActive(at: date(minutes: 50.001)))
    }

    func testFewerThanFourUserTurnsAreNotEligible() {
        let events = [
            event("00000000-0000-0000-0000-000000000021", minutes: 0, user: true),
            event("00000000-0000-0000-0000-000000000022", minutes: 1, user: false),
            event("00000000-0000-0000-0000-000000000023", minutes: 2, user: true),
            event("00000000-0000-0000-0000-000000000024", minutes: 3, user: false),
            event("00000000-0000-0000-0000-000000000025", minutes: 4, user: true)
        ]
        let session = try! XCTUnwrap(ConversationCarePolicy.latestSession(from: events))

        XCTAssertEqual(session.userTurnCount, 3)
        XCTAssertFalse(session.isEligible)
        XCTAssertFalse(session.isEligible(at: date(minutes: 4)))
    }

    func testActiveSessionRequiresBothLastActivityAndLastUserToBeWithinTwentyMinutes() {
        let events = [
            event("00000000-0000-0000-0000-000000000031", minutes: 0, user: true),
            event("00000000-0000-0000-0000-000000000032", minutes: 1, user: false),
            event("00000000-0000-0000-0000-000000000033", minutes: 2, user: true),
            event("00000000-0000-0000-0000-000000000034", minutes: 3, user: false),
            event("00000000-0000-0000-0000-000000000035", minutes: 4, user: true),
            event("00000000-0000-0000-0000-000000000036", minutes: 5, user: false),
            event("00000000-0000-0000-0000-000000000037", minutes: 6, user: true),
            event("00000000-0000-0000-0000-000000000038", minutes: 7, user: false)
        ]
        // The last user message is at minute 6, so minute 26 is the exact
        // inclusive 20-minute boundary. The assistant activity at minute 7
        // is still within the same window.
        let exactlyAtBoundary = date(minutes: 26)
        let justTooLate = date(minutes: 26.001)

        XCTAssertNotNil(ConversationCarePolicy.activeSession(from: events, now: exactlyAtBoundary))
        XCTAssertNil(ConversationCarePolicy.activeSession(from: events, now: justTooLate))
    }

    func testDefaultMilestonesAndScheduleDatesAreNinetyAndOneHundredEightyMinutesFromSessionStart() {
        let session = try! XCTUnwrap(ConversationCareSession(events: [
            event("00000000-0000-0000-0000-000000000041", minutes: 0, user: true)
        ]))
        let milestones = ConversationCarePolicy.defaultMilestones

        XCTAssertEqual(milestones.firstReminderMinutes, 90)
        XCTAssertEqual(milestones.minutes, [90, 180])
        XCTAssertEqual(
            ConversationCarePolicy.scheduleDates(for: session),
            [date(minutes: 90), date(minutes: 180)]
        )
        XCTAssertEqual(
            ConversationCarePolicy.scheduleDate(for: session, stage: .first),
            date(minutes: 90)
        )
        XCTAssertEqual(
            ConversationCarePolicy.scheduleDate(for: session, stage: .final),
            date(minutes: 180)
        )
        XCTAssertFalse(ConversationCarePolicy.isDue(stage: .first, for: session, at: date(minutes: 89.999)))
        XCTAssertTrue(ConversationCarePolicy.isDue(stage: .first, for: session, at: date(minutes: 90)))
        XCTAssertTrue(ConversationCarePolicy.isDue(stage: .final, for: session, at: date(minutes: 180)))
    }

    func testFirstReminderIsClampedAndMilestonesAreDeduplicatedWithoutStepRounding() {
        XCTAssertEqual(ConversationCarePolicy.milestones(firstReminderMinutes: 1).minutes, [60, 180])
        XCTAssertEqual(ConversationCarePolicy.milestones(firstReminderMinutes: 181).minutes, [180])
        XCTAssertEqual(ConversationCarePolicy.milestones(firstReminderMinutes: 180).minutes, [180])
        XCTAssertEqual(ConversationCarePolicy.milestones(firstReminderMinutes: 61).minutes, [61, 180])
        XCTAssertEqual(ConversationCarePolicy.normalizedFirstReminderMinutes(0), 60)
        XCTAssertEqual(ConversationCarePolicy.normalizedFirstReminderMinutes(240), 180)
    }

    func testShuffledInputProducesTheSameUuidTieBrokenSessions() {
        let first = event("00000000-0000-0000-0000-000000000052", minutes: 0, user: true)
        let second = event("00000000-0000-0000-0000-000000000051", minutes: 0, user: false)
        let third = event("00000000-0000-0000-0000-000000000053", minutes: 20, user: true)
        let fourth = event("00000000-0000-0000-0000-000000000054", minutes: 40.001, user: false)
        let ordered = ConversationCarePolicy.sessions(from: [first, second, third, fourth])
        let shuffled = ConversationCarePolicy.sessions(from: [fourth, first, third, second])

        XCTAssertEqual(shuffled, ordered)
        XCTAssertEqual(
            ordered[0].events.map { $0.id.uuidString.lowercased() },
            [second, first, third].map { $0.id.uuidString.lowercased() }
        )
        XCTAssertEqual(ordered[1].events, [fourth])
    }

    private func event(_ id: String, minutes: Double, user: Bool) -> ConversationCareEvent {
        ConversationCareEvent(
            id: UUID(uuidString: id)!,
            occurredAt: date(minutes: minutes),
            isUser: user
        )
    }

    private func date(minutes: Double) -> Date {
        base.addingTimeInterval(minutes * minute)
    }
}
