import Foundation
import ImageIO
import XCTest
@testable import Ayane

final class ChatAttachmentProcessorTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        for url in temporaryURLs {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testImageProcessingRejectsBadData() {
        XCTAssertThrowsError(
            try ChatAttachmentProcessor.normalizedImageData(from: Data("not an image".utf8))
        ) { error in
            XCTAssertEqual(error as? ChatAttachmentProcessorError, .unreadableImage)
        }
    }

    func testImageProcessingProducesDecodableJPEG() throws {
        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlzsL8AAAAASUVORK5CYII="
        ))
        let normalized = try ChatAttachmentProcessor.normalizedImageData(from: png)

        XCTAssertFalse(normalized.isEmpty)
        XCTAssertLessThanOrEqual(normalized.count, SchemaV11DataSupport.maxImageDataBytes)
        XCTAssertNotNil(CGImageSourceCreateWithData(normalized as CFData, nil))
    }

    func testImageProcessingRejectsOversizedInput() {
        let oversized = Data(
            repeating: 0,
            count: SchemaV11DataSupport.maxImageDataBytes + 1
        )
        XCTAssertThrowsError(
            try ChatAttachmentProcessor.normalizedImageData(from: oversized)
        )
    }

    func testFileReadReturnsBytesAndSafeMetadata() throws {
        let url = makeTemporaryURL(fileName: "notes.txt")
        let source = Data("hello KIN".utf8)
        try source.write(to: url, options: .atomic)

        let attachment = try ChatAttachmentProcessor.readFile(at: url)
        XCTAssertEqual(attachment.data, source)
        XCTAssertEqual(attachment.fileName, "notes.txt")
        XCTAssertFalse(attachment.fileTypeIdentifier.isEmpty)
    }

    func testFileReadRejectsDirectory() throws {
        let url = makeTemporaryURL(fileName: "folder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try ChatAttachmentProcessor.readFile(at: url)) { error in
            XCTAssertEqual(error as? ChatAttachmentProcessorError, .directoryNotAllowed)
        }
    }

    func testFileReadRejectsEmptyFile() throws {
        let url = makeTemporaryURL(fileName: "empty.bin")
        try Data().write(to: url, options: .atomic)

        XCTAssertThrowsError(try ChatAttachmentProcessor.readFile(at: url)) { error in
            XCTAssertEqual(error as? ChatAttachmentProcessorError, .emptyFile)
        }
    }

    func testFileReadRejectsOversizedFile() throws {
        let url = makeTemporaryURL(fileName: "large.bin")
        let oversized = Data(
            repeating: 1,
            count: SchemaV11DataSupport.maxFileDataBytes + 1
        )
        try oversized.write(to: url, options: .atomic)

        XCTAssertThrowsError(try ChatAttachmentProcessor.readFile(at: url)) { error in
            XCTAssertEqual(error as? ChatAttachmentProcessorError, .fileTooLarge)
        }
    }

    func testFileNameSanitizationRemovesPathTraversal() {
        XCTAssertEqual(
            ChatAttachmentProcessor.sanitizedFileName("../../private/report.pdf"),
            "report.pdf"
        )
        XCTAssertEqual(
            ChatAttachmentProcessor.sanitizedFileName("..\\private\\secret.txt"),
            "secret.txt"
        )
        XCTAssertFalse(
            ChatAttachmentProcessor.sanitizedFileName("/tmp/../report.pdf").contains("/")
        )
        XCTAssertEqual(ChatAttachmentProcessor.sanitizedFileName(".."), "未命名文件")
    }

    @discardableResult
    private func makeTemporaryURL(
        fileName: String,
        isDirectory: Bool = false
    ) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KINChatAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(fileName, isDirectory: isDirectory)
        temporaryURLs.append(directory)
        return url
    }
}
