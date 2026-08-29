import XCTest
@testable import Ayane

final class MemoryExtractionTests: XCTestCase {
    func testHighConfidenceDirectUserStatementBecomesExplicit() throws {
        let eventID = UUID()
        let content = "我住在上海。"
        let raw = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":0.95,"importance":0.8,"explicit":false,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"我住在上海",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            raw,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.first?.explicit, true)
    }

    func testLowConfidenceInferenceRemainsCandidateMaterial() throws {
        let eventID = UUID()
        let content = "我可能更喜欢上海。"
        let raw = """
        {"memories":[{
          "operation":"upsert","kind":"preference","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city.preference",
          "confidence":0.6,"importance":0.8,"explicit":false,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"可能更喜欢上海",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            raw,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.first?.explicit, false)
    }

    func testHighConfidenceHedgedStatementStillRemainsCandidateMaterial() throws {
        let eventID = UUID()
        let content = "我可能会搬去上海。"
        let raw = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":0.99,"importance":0.9,"explicit":false,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"我可能会搬去上海",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            raw,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.first?.explicit, false)
    }

    func testSensitiveDirectStatementIsNotAutoPromoted() throws {
        let eventID = UUID()
        let content = "我的身份证号是保密内容。"
        let raw = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"government_id","value":"保密内容","canonical_key":"user.government_id",
          "confidence":0.99,"importance":0.9,"explicit":false,"sensitive":true,
          "source_event_id":"\(eventID.uuidString)","source_quote":"我的身份证号是保密内容",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            raw,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.first?.explicit, false)
    }

    func testParserRequiresExactSourceEvidence() throws {
        let eventID = UUID()
        let content = "我现在最喜欢的饮料是乌龙茶。"
        let quote = "最喜欢的饮料是乌龙茶"
        let range = try XCTUnwrap(content.range(of: quote))
        let utf16 = content.utf16
        let start = try XCTUnwrap(range.lowerBound.samePosition(in: utf16)).utf16Offset(in: content)
        let end = try XCTUnwrap(range.upperBound.samePosition(in: utf16)).utf16Offset(in: content)
        let json = """
        {"memories":[{
          "operation":"upsert",
          "kind":"preference",
          "subject":"user",
          "predicate":"favorite_drink",
          "value":"乌龙茶",
          "canonical_key":"user.favorite_drink",
          "confidence":1.4,
          "importance":0.8,
          "explicit":true,
          "sensitive":false,
          "source_event_id":"\(eventID.uuidString)",
          "source_quote":"\(quote)",
          "start_utf16":\(start),
          "end_utf16":\(end),
          "valid_from":null,
          "valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            json,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, "乌龙茶")
        XCTAssertEqual(result[0].confidence, 1)
        XCTAssertEqual(result[0].startUTF16, start)
        XCTAssertEqual(result[0].endUTF16, end)
    }

    func testParserRejectsFabricatedQuote() {
        let eventID = UUID()
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":0.9,"importance":0.7,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"我住在上海",
          "start_utf16":0,"end_utf16":5,"valid_from":null,"valid_to":null
        }]}
        """
        XCTAssertThrowsError(
            try MemoryExtractionParser.parse(
                json,
                eventSources: [eventID: MemoryExtractionSource(role: .user, content: "今天天气很好")]
            )
        ) { error in
            XCTAssertEqual(error as? MemoryExtractionError, .noValidEvidence)
        }
    }

    func testParserAcceptsJSONCodeFence() throws {
        let eventID = UUID()
        let quote = "请记住"
        let raw = """
        ```json
        {"memories":[{"operation":"upsert","kind":"boundary","subject":"user","predicate":"remember_request","value":"重要","canonical_key":"user.boundary.important","confidence":1,"importance":1,"explicit":true,"sensitive":false,"source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)","start_utf16":0,"end_utf16":\(quote.utf16.count),"valid_from":null,"valid_to":null}]}
        ```
        """
        XCTAssertEqual(
            try MemoryExtractionParser.parse(
                raw,
                eventSources: [eventID: MemoryExtractionSource(role: .user, content: "请记住，这很重要")]
            ).count,
            1
        )
    }

    func testParserAcceptsExplicitEmptyMemoryList() throws {
        XCTAssertEqual(
            try MemoryExtractionParser.parse("{\"memories\":[]}", eventSources: [:]),
            []
        )
    }

    func testParserRejectsAssistantForgedUserExplicitFact() {
        let eventID = UUID()
        let content = "我已经确认你住在上海。"
        let quote = "你住在上海"
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":" USER ",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":1,"importance":1,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        XCTAssertThrowsError(
            try MemoryExtractionParser.parse(
                json,
                eventSources: [eventID: MemoryExtractionSource(role: .assistant, content: content)]
            )
        ) { error in
            XCTAssertEqual(error as? MemoryExtractionError, .noValidEvidence)
        }
    }

    func testParserAcceptsExplicitUserFact() throws {
        let eventID = UUID()
        let content = "我住在上海。"
        let quote = "我住在上海"
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"profile","subject":"user",
          "predicate":"city","value":"上海","canonical_key":"user.city",
          "confidence":1,"importance":1,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            json,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].subject, "user")
        XCTAssertEqual(result[0].value, "上海")
    }

    func testParserStronglyNormalizesCanonicalKey() throws {
        let eventID = UUID()
        let content = "我最喜欢乌龙茶。"
        let quote = "我最喜欢乌龙茶"
        let rawCanonicalKey = "\u{FEFF} USER.\u{200B}Favorite_Drink\u{2060} "
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"preference","subject":"user",
          "predicate":"favorite_drink","value":"乌龙茶","canonical_key":"\(rawCanonicalKey)",
          "confidence":1,"importance":1,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            json,
            eventSources: [eventID: MemoryExtractionSource(role: .user, content: content)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].canonicalKey, "user.favorite_drink")
    }

    func testParserAcceptsAssistantCompanionCommitment() throws {
        let eventID = UUID()
        let content = "我会在下次对话里提醒你带伞。"
        let quote = "我会在下次对话里提醒你带伞"
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"commitment","subject":"companion",
          "predicate":"remind_next_time","value":"提醒你带伞","canonical_key":"companion.commitment.remind_next_time",
          "confidence":1,"importance":0.8,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        let result = try MemoryExtractionParser.parse(
            json,
            eventSources: [eventID: MemoryExtractionSource(role: .assistant, content: content)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].subject, "companion")
        XCTAssertEqual(result[0].kind, .commitment)
    }

    func testParserRejectsAssistantNonCommitmentEvenForCompanion() {
        let eventID = UUID()
        let content = "我猜你更喜欢上海。"
        let quote = "我猜你更喜欢上海"
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"preference","subject":"companion",
          "predicate":"favorite_city","value":"上海","canonical_key":"companion.favorite_city",
          "confidence":1,"importance":1,"explicit":true,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        XCTAssertThrowsError(
            try MemoryExtractionParser.parse(
                json,
                eventSources: [eventID: MemoryExtractionSource(role: .assistant, content: content)]
            )
        ) { error in
            XCTAssertEqual(error as? MemoryExtractionError, .noValidEvidence)
        }
    }

    func testParserRejectsAssistantImplicitCommitment() {
        let eventID = UUID()
        let content = "也许下次可以提醒你带伞。"
        let quote = "也许下次可以提醒你带伞"
        let json = """
        {"memories":[{
          "operation":"upsert","kind":"commitment","subject":"companion",
          "predicate":"remind_next_time","value":"提醒带伞","canonical_key":"companion.commitment.remind_next_time",
          "confidence":0.6,"importance":0.8,"explicit":false,"sensitive":false,
          "source_event_id":"\(eventID.uuidString)","source_quote":"\(quote)",
          "valid_from":null,"valid_to":null
        }]}
        """

        XCTAssertThrowsError(
            try MemoryExtractionParser.parse(
                json,
                eventSources: [eventID: MemoryExtractionSource(role: .assistant, content: content)]
            )
        ) { error in
            XCTAssertEqual(error as? MemoryExtractionError, .noValidEvidence)
        }
    }

    func testSingleEventExtractionPromptPreservesRawEventIdentity() throws {
        let event = ConversationEvent(
            conversationID: UUID(),
            deviceID: "test-device",
            deviceSequence: 1,
            logicalTimestamp: "1-test-device-1",
            role: .user,
            content: "即使回复失败，也请记住我喜欢乌龙茶。",
            contentHash: "hash"
        )

        let prompt = MemoryExtractionParser.extractionPrompt(events: [event])
        XCTAssertEqual(prompt.count, 2)
        XCTAssertTrue(prompt[1].content.contains(event.id.uuidString))
        XCTAssertTrue(prompt[1].content.contains("乌龙茶"))
    }
}
