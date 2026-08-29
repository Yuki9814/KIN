import Foundation
import XCTest
@testable import Ayane

final class SchemaV11FeatureTests: XCTestCase {
    func testMessagePayloadTextAndStickerRoundTrip() throws {
        let text = MessagePayload.text("我喜欢雨天")
        let decodedText: MessagePayload = try roundTrip(text)
        XCTAssertEqual(decodedText, text)
        XCTAssertEqual(decodedText.kind, .text)
        XCTAssertEqual(decodedText.text, "我喜欢雨天")
        XCTAssertNil(decodedText.stickerID)

        let sticker = MessagePayload.sticker(stickerID: "ayane.exclusive.02")
        let decodedSticker: MessagePayload = try roundTrip(sticker)
        XCTAssertEqual(decodedSticker, sticker)
        XCTAssertEqual(decodedSticker.kind, .sticker)
        XCTAssertNil(decodedSticker.text)
        XCTAssertEqual(decodedSticker.stickerID, "ayane.exclusive.02")
    }

    func testWorldProfileDefaultIsTheSharedRealityMode() throws {
        let record = WorldProfileRecord.realityDefault
        XCTAssertEqual(record.id, WorldProfileRecord.realityID)
        XCTAssertEqual(record.worldKind, "reality")
        XCTAssertEqual(record.timezoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(record.locationContext, "")
        XCTAssertEqual(record.commonFacts, [])
        XCTAssertEqual(record.createdAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(record.updatedAt, Date(timeIntervalSince1970: 0))

        let export = AyaneWorldProfileExport(record)
        let decoded: AyaneWorldProfileExport = try roundTrip(export)
        XCTAssertEqual(decoded, export)
        XCTAssertEqual(decoded.id, WorldProfileRecord.realityID)
        XCTAssertEqual(decoded.worldKind, "reality")
    }

    func testMomentReplyRoundTripPreservesParentAndRootInteractionIDs() throws {
        let postID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let parentID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let rootID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let roleID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let updatedAt = createdAt.addingTimeInterval(90)
        let record = MomentInteractionRecord(
            id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
            postID: postID,
            kind: .comment,
            actorKind: .companion,
            actorRoleID: roleID,
            parentInteractionID: parentID,
            rootInteractionID: rootID,
            body: "我也记得这件事。",
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 4,
            deviceID: "moments-device"
        )
        let export = AyaneMomentInteractionExport(record)
        let decoded: AyaneMomentInteractionExport = try roundTrip(export)

        XCTAssertEqual(decoded.postID, postID)
        XCTAssertEqual(decoded.parentInteractionID, parentID)
        XCTAssertEqual(decoded.rootInteractionID, rootID)
        XCTAssertEqual(decoded.kind, .comment)
        XCTAssertEqual(decoded.actorKind, .companion)
        XCTAssertEqual(decoded.actorRoleID, roleID)
        XCTAssertEqual(decoded.body, "我也记得这件事。")
        XCTAssertEqual(decoded.revision, 4)

        let encoded = try encode(export)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNotNil(object["parent_interaction_id"])
        XCTAssertNotNil(object["root_interaction_id"])
    }

    func testGroupParticipantDTORoundTripPreservesMembershipScope() throws {
        let conversationID = UUID(uuidString: "60000000-0000-0000-0000-000000000006")!
        let groupID = UUID(uuidString: "70000000-0000-0000-0000-000000000007")!
        let roleID = UUID(uuidString: "80000000-0000-0000-0000-000000000008")!
        let joinedAt = Date(timeIntervalSince1970: 1_800_001_000)
        let leftAt = joinedAt.addingTimeInterval(3_600)
        let record = GroupParticipantRecord(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000009")!,
            conversationID: conversationID,
            groupConversationID: groupID,
            participantRoleID: roleID,
            participantKind: .companion,
            displayName: "绫音",
            joinedAt: joinedAt,
            leftAt: leftAt,
            lifecycle: .active,
            createdAt: joinedAt,
            updatedAt: leftAt,
            revision: 2,
            deviceID: "group-device"
        )
        let export = AyaneGroupParticipantExport(record)
        let decoded: AyaneGroupParticipantExport = try roundTrip(export)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.conversationID, conversationID)
        XCTAssertEqual(decoded.groupConversationID, groupID)
        XCTAssertEqual(decoded.participantRoleID, roleID)
        XCTAssertEqual(decoded.participantKind, .companion)
        XCTAssertEqual(decoded.displayName, "绫音")
        XCTAssertEqual(decoded.joinedAt, joinedAt)
        XCTAssertEqual(decoded.leftAt, leftAt)
        XCTAssertEqual(decoded.lifecycleRaw, GroupConversationLifecycle.active.rawValue)
        XCTAssertEqual(decoded.revision, 2)
    }

    func testChatTurnPresentationDTORoundTripPreservesDeliveryState() throws {
        let conversationID = UUID(uuidString: "A0000000-0000-0000-0000-00000000000A")!
        let roleID = UUID(uuidString: "B0000000-0000-0000-0000-00000000000B")!
        let replyEventID = UUID(uuidString: "C0000000-0000-0000-0000-00000000000C")!
        let createdAt = Date(timeIntervalSince1970: 1_800_002_000)
        let plannedAt = createdAt.addingTimeInterval(2)
        let startedAt = plannedAt.addingTimeInterval(5)
        let updatedAt = startedAt.addingTimeInterval(8)
        let record = ChatTurnPresentationRecord(
            id: UUID(uuidString: "D0000000-0000-0000-0000-00000000000D")!,
            conversationID: conversationID,
            roleID: roleID,
            logicalReplyEventID: replyEventID,
            segments: ["第一句", "第二句"],
            displayProgress: 0.5,
            displayedSegmentCount: 1,
            state: .delivering,
            plannedAt: plannedAt,
            startedAt: startedAt,
            failureMessage: "",
            idempotencyKey: "presentation-key",
            createdAt: createdAt,
            updatedAt: updatedAt,
            revision: 3,
            deviceID: "presentation-device"
        )
        let export = AyaneChatTurnPresentationExport(record)
        let decoded: AyaneChatTurnPresentationExport = try roundTrip(export)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.conversationID, conversationID)
        XCTAssertEqual(decoded.roleID, roleID)
        XCTAssertEqual(decoded.logicalReplyEventID, replyEventID)
        XCTAssertEqual(decoded.segments, ["第一句", "第二句"])
        XCTAssertEqual(decoded.displayProgress, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(decoded.displayedSegmentCount, 1)
        XCTAssertEqual(decoded.state, .delivering)
        XCTAssertEqual(decoded.plannedAt, plannedAt)
        XCTAssertEqual(decoded.startedAt, startedAt)
        XCTAssertEqual(decoded.idempotencyKey, "presentation-key")
        XCTAssertEqual(decoded.revision, 3)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let data = try encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
