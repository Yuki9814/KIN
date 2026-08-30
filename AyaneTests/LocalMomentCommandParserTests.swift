import Foundation
import XCTest
@testable import Ayane

final class LocalMomentCommandParserTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 29,
            hour: 12,
            minute: 0
        ))!
    }

    func testPlainPublishInstructionRunsImmediately() throws {
        let command = try XCTUnwrap(LocalMomentCommandParser.parse(
            "你去发一个朋友圈",
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(command.scheduledAt, now)
        XCTAssertEqual(command.instruction, "你去发一个朋友圈")

        let contentMentionsToday = try XCTUnwrap(LocalMomentCommandParser.parse(
            "你去发一个朋友圈，写写今天吹到的风",
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(contentMentionsToday.scheduledAt, now)
    }

    func testCreateWordingIsAnExplicitImmediatePublishInstruction() throws {
        for instruction in [
            "创建朋友圈",
            "创建一条朋友圈",
            "帮我创建朋友圈",
            "麻烦你帮我创建一条朋友圈，写写今天的风"
        ] {
            let command = try XCTUnwrap(
                LocalMomentCommandParser.parse(instruction, now: now, calendar: calendar),
                instruction
            )
            XCTAssertEqual(command.scheduledAt, now, instruction)
        }
    }

    func testChineseClockAndRelativeDelayAreResolvedLocally() throws {
        let tonight = try XCTUnwrap(LocalMomentCommandParser.parse(
            "今晚八点发一条朋友圈，写写今天的心情",
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(calendar.component(.hour, from: tonight.scheduledAt), 20)
        XCTAssertEqual(calendar.component(.day, from: tonight.scheduledAt), 29)

        let delayed = try XCTUnwrap(LocalMomentCommandParser.parse(
            "半小时后发个朋友圈",
            now: now,
            calendar: calendar
        ))
        XCTAssertEqual(delayed.scheduledAt.timeIntervalSince(now), 1_800, accuracy: 0.1)
    }

    func testDiscussionAndNegativeInstructionsNeverCreateTasks() {
        XCTAssertNil(LocalMomentCommandParser.parse("别发朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("怎么发朋友圈？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我刚看了朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我昨天发朋友圈了", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("她发朋友圈了吗？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("朋友圈已经发过了", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我不想让你发朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("不要真的发朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("如果你发朋友圈会怎样", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我刚才说了你去发朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("你发朋友圈了吗？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("能不能发一个朋友圈？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("可以发个朋友圈吗？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我不想发朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("不要创建朋友圈", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("怎么创建朋友圈？", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("我昨天创建朋友圈了", now: now, calendar: calendar))
        XCTAssertNil(LocalMomentCommandParser.parse("能不能创建一条朋友圈？", now: now, calendar: calendar))
    }

    func testDeletionCommandsTargetTheLatestCompanionMoment() throws {
        for instruction in [
            "删掉你刚才的朋友圈",
            "删掉你上一条朋友圈",
            "请把你刚刚发的动态删除",
            "我想让你删掉上一条朋友圈"
        ] {
            let command = try XCTUnwrap(LocalMomentCommandParser.parseDeletion(instruction))
            XCTAssertEqual(command.target, .latest, instruction)
        }
    }

    func testDeletionCommandWithoutAUniqueTargetRequiresClarification() throws {
        let command = try XCTUnwrap(
            LocalMomentCommandParser.parseDeletion("我要求你删掉某一个朋友圈")
        )
        XCTAssertEqual(command.target, .unspecified)
    }

    func testDeletionCommandsCanTargetAContentSnippet() throws {
        let described = try XCTUnwrap(
            LocalMomentCommandParser.parseDeletion("把你那条关于晚霞的朋友圈删掉")
        )
        XCTAssertEqual(described.target, .content("晚霞"))

        let quoted = try XCTUnwrap(
            LocalMomentCommandParser.parseDeletion("删除‘原文片段’那条朋友圈")
        )
        XCTAssertEqual(quoted.target, .content("原文片段"))
    }

    func testDeletionDiscussionAndPastTenseNeverCreateCommands() {
        for instruction in [
            "别删",
            "怎么删",
            "能不能删",
            "如果删",
            "你删过吗",
            "我已经删了",
            "别删掉你刚才的朋友圈",
            "怎么删除那条朋友圈",
            "我已经删除那条朋友圈",
            "我想删除那条朋友圈",
            "删掉我刚发的朋友圈",
            "把我的朋友圈删掉"
        ] {
            XCTAssertNil(LocalMomentCommandParser.parseDeletion(instruction), instruction)
        }
    }
}
