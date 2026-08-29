import Foundation
import SwiftData
import XCTest
@testable import Ayane

final class AttachmentPayloadPersistenceTests: XCTestCase {
    func testFileMessagePayloadAndConversationEventRoundTrip() throws {
        let bytes = Data([0x4B, 0x49, 0x4E, 0x15])
        let payload = MessagePayload.file(
            data: bytes,
            fileName: "notes.txt",
            fileTypeIdentifier: "public.plain-text"
        )

        let payloadRoundTrip: MessagePayload = try roundTrip(payload)
        XCTAssertEqual(payloadRoundTrip, payload)
        XCTAssertTrue(payloadRoundTrip.isFile)

        let conversation = UUID()
        let event = ConversationEvent(
            conversationID: conversation,
            deviceID: "attachment-test-device",
            deviceSequence: 1,
            logicalTimestamp: "1-attachment-test-device-1",
            role: .user,
            content: "附件",
            contentHash: ContentHasher.sha256("附件"),
            payload: payload
        )

        XCTAssertEqual(event.payload, payload)
        XCTAssertEqual(event.payloadKind, .file)
        XCTAssertEqual(event.fileName, "notes.txt")
        XCTAssertEqual(event.fileTypeIdentifier, "public.plain-text")
        XCTAssertEqual(event.fileData, bytes)
        XCTAssertNil(event.imageData)

        event.payloadKind = .text
        XCTAssertNil(event.fileData)
        XCTAssertEqual(event.fileName, "")
        XCTAssertEqual(event.fileTypeIdentifier, "")
        XCTAssertNil(event.imageData)
    }

    func testAyaneEventExportFileJSONRoundTrip() throws {
        let bytes = Data([0, 1, 2, 3, 4])
        let event = ConversationEvent(
            conversationID: UUID(),
            deviceID: "attachment-export-device",
            deviceSequence: 2,
            logicalTimestamp: "2-attachment-export-device-2",
            role: .assistant,
            content: "附件已发送",
            contentHash: ContentHasher.sha256("附件已发送"),
            payloadKind: .file,
            fileName: "report.pdf",
            fileTypeIdentifier: "com.adobe.pdf",
            fileData: bytes
        )
        let export = AyaneEventExport(event)
        let decoded: AyaneEventExport = try roundTrip(export)

        XCTAssertEqual(decoded.id, export.id)
        XCTAssertEqual(decoded.roleID, export.roleID)
        XCTAssertEqual(decoded.conversationID, export.conversationID)
        XCTAssertEqual(decoded.contentHash, export.contentHash)
        XCTAssertEqual(decoded.deliveryStateRaw, export.deliveryStateRaw)
        XCTAssertEqual(decoded.payloadKind, MessagePayloadKind.file.rawValue)
        XCTAssertEqual(decoded.fileName, "report.pdf")
        XCTAssertEqual(decoded.fileTypeIdentifier, "com.adobe.pdf")
        XCTAssertEqual(decoded.fileData, bytes)
    }

    func testFilePayloadValidationRejectsMissingBytesAndOversizeData() throws {
        let missingBytes = makeExport(
            payloadKind: .file,
            fileName: "missing.bin",
            fileTypeIdentifier: "public.data",
            fileData: nil
        )
        XCTAssertThrowsError(try SchemaV11DataSupport.validateEventPayload(missingBytes))

        let oversized = makeExport(
            payloadKind: .file,
            fileName: "oversized.bin",
            fileTypeIdentifier: "public.data",
            fileData: Data(count: SchemaV11DataSupport.maxFileDataBytes + 1)
        )
        XCTAssertThrowsError(try SchemaV11DataSupport.validateEventPayload(oversized))
    }

    func testNonFilePayloadValidationRejectsFileFieldsAndBytes() throws {
        let event = ConversationEvent(
            conversationID: UUID(),
            deviceID: "attachment-invalid-device",
            deviceSequence: 3,
            logicalTimestamp: "3-attachment-invalid-device-3",
            role: .user,
            content: "文本",
            contentHash: ContentHasher.sha256("文本")
        )
        event.fileName = "should-not-be-here.txt"
        event.fileTypeIdentifier = "public.plain-text"
        event.fileData = Data([1])

        XCTAssertThrowsError(
            try SchemaV11DataSupport.validateEventPayload(AyaneEventExport(event))
        )
    }

    @MainActor
    func testReconcilerRejectsUniqueInvalidFilePayload() throws {
        let bootstrap = PersistenceController.makeContainer(inMemory: true, preferCloud: false)
        let context = ModelContext(bootstrap.container)
        let conversationID = UUID()
        context.insert(ConversationRecord(id: conversationID, title: "附件校验"))
        context.insert(ConversationEvent(
            conversationID: conversationID,
            deviceID: "attachment-reconcile-device",
            deviceSequence: 1,
            logicalTimestamp: "1-attachment-reconcile-device-1",
            role: .user,
            content: "[文件]",
            contentHash: ContentHasher.sha256("[文件]"),
            payloadKind: .file,
            fileName: "broken.bin",
            fileTypeIdentifier: "public.data",
            fileData: nil
        ))
        try context.save()

        XCTAssertThrowsError(try StoreDuplicateReconciler.reconcile(context: context))
    }

    private func makeExport(
        payloadKind: MessagePayloadKind,
        fileName: String,
        fileTypeIdentifier: String,
        fileData: Data?
    ) -> AyaneEventExport {
        let content = "附件校验"
        let event = ConversationEvent(
            conversationID: UUID(),
            deviceID: "attachment-validation-device",
            deviceSequence: 4,
            logicalTimestamp: "4-attachment-validation-device-4",
            role: .user,
            content: content,
            contentHash: ContentHasher.sha256(content),
            payloadKind: payloadKind,
            fileName: fileName,
            fileTypeIdentifier: fileTypeIdentifier,
            fileData: fileData
        )
        return AyaneEventExport(event)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
