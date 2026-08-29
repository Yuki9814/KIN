import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The in-memory representation handed from the picker to a chat screen.
/// The source URL is deliberately absent so security-scoped picker URLs never
/// become part of a persisted message or a view model.
struct ChatFileAttachment: Equatable, Sendable {
    let data: Data
    let fileName: String
    let fileTypeIdentifier: String

    var byteCount: Int { data.count }
    var fileSize: Int { data.count }
}

enum ChatAttachmentProcessorError: LocalizedError, Equatable {
    case emptyImage
    case unreadableImage
    case imageTooLarge
    case directoryNotAllowed
    case nonRegularFile
    case emptyFile
    case fileTooLarge
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "图片内容为空，请重新选择。"
        case .unreadableImage:
            return "无法读取这张图片，请换一张再试。"
        case .imageTooLarge:
            return "图片处理后仍过大，请选择更小的图片。"
        case .directoryNotAllowed:
            return "不能发送文件夹，请选择普通文件。"
        case .nonRegularFile:
            return "只能发送普通文件，请重新选择。"
        case .emptyFile:
            return "文件内容为空，请重新选择。"
        case .fileTooLarge:
            return "文件过大，请选择不超过 20 MB 的文件。"
        case .unreadableFile:
            return "无法读取这个文件，请重新选择。"
        }
    }
}

/// Pure-ish attachment normalization shared by the picker and unit tests.
/// It only returns bytes and safe metadata; it never stores or returns the
/// source URL after a read completes.
enum ChatAttachmentProcessor {
    static func normalizedImageData(from data: Data) throws -> Data {
        guard !data.isEmpty else {
            throw ChatAttachmentProcessorError.emptyImage
        }

        do {
            let normalized = try RoleImageProcessor.normalizedJPEG(
                from: data,
                kind: .chatBackground
            )
            guard normalized.count <= SchemaV11DataSupport.maxImageDataBytes else {
                throw ChatAttachmentProcessorError.imageTooLarge
            }
            return normalized
        } catch let error as ChatAttachmentProcessorError {
            throw error
        } catch let error as RoleImageProcessorError {
            switch error {
            case .imageTooLarge:
                throw ChatAttachmentProcessorError.imageTooLarge
            case .unreadableImage, .encodingFailed:
                throw ChatAttachmentProcessorError.unreadableImage
            }
        } catch {
            throw ChatAttachmentProcessorError.unreadableImage
        }
    }

    /// Compatibility spelling for callers that prefer a processing verb.
    static func processImageData(_ data: Data) throws -> Data {
        try normalizedImageData(from: data)
    }

    static func makeFileAttachment(
        data: Data,
        fileName rawFileName: String,
        fileTypeIdentifier rawFileTypeIdentifier: String
    ) throws -> ChatFileAttachment {
        guard !data.isEmpty else {
            throw ChatAttachmentProcessorError.emptyFile
        }
        guard data.count <= SchemaV11DataSupport.maxFileDataBytes else {
            throw ChatAttachmentProcessorError.fileTooLarge
        }

        let fileName = sanitizedFileName(rawFileName)
        let fileTypeIdentifier = normalizedTypeIdentifier(rawFileTypeIdentifier)
        return ChatFileAttachment(
            data: data,
            fileName: fileName,
            fileTypeIdentifier: fileTypeIdentifier
        )
    }

    /// Reads a security-scoped picker URL while keeping access strictly
    /// balanced. The URL is used only during this call and is never retained.
    static func readFile(at url: URL) throws -> ChatFileAttachment {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard url.isFileURL else {
            throw ChatAttachmentProcessorError.unreadableFile
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .fileSizeKey,
                .contentTypeKey
            ])
        } catch {
            throw ChatAttachmentProcessorError.unreadableFile
        }

        if resourceValues.isDirectory == true {
            throw ChatAttachmentProcessorError.directoryNotAllowed
        }
        if resourceValues.isRegularFile == false {
            throw ChatAttachmentProcessorError.nonRegularFile
        }
        if let fileSize = resourceValues.fileSize {
            guard fileSize > 0 else {
                throw ChatAttachmentProcessorError.emptyFile
            }
            guard fileSize <= SchemaV11DataSupport.maxFileDataBytes else {
                throw ChatAttachmentProcessorError.fileTooLarge
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ChatAttachmentProcessorError.unreadableFile
        }

        let inferredType = UTType(filenameExtension: url.pathExtension)?.identifier
            ?? resourceValues.contentType?.identifier
            ?? UTType.data.identifier
        return try makeFileAttachment(
            data: data,
            fileName: url.lastPathComponent,
            fileTypeIdentifier: inferredType
        )
    }

    /// Compatibility spelling for tests and non-UI callers.
    static func processFile(at url: URL) throws -> ChatFileAttachment {
        try readFile(at: url)
    }

    /// Removes every path component and control character. A fallback keeps a
    /// nameless but valid picker item displayable without exposing a path.
    static func sanitizedFileName(_ rawName: String) -> String {
        let slashNormalized = rawName.replacingOccurrences(of: "\\", with: "/")
        let leaf = slashNormalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init) ?? ""
        let printableScalars = leaf.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }
        let trimmed = String(String.UnicodeScalarView(printableScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else {
            return "未命名文件"
        }
        return String(trimmed.prefix(255))
    }

    /// Compatibility spelling for presentation code that wants to sanitize a
    /// persisted filename again before using it as a display or temp path.
    static func safeFileName(_ rawName: String) -> String {
        sanitizedFileName(rawName)
    }

    private static func normalizedTypeIdentifier(_ rawIdentifier: String) -> String {
        let identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return UTType(identifier)?.identifier ?? UTType.data.identifier
    }
}

/// Writes bytes to an app-owned temporary directory for Quick Look. A UUID
/// prevents collisions, and the staging write plus move keeps a partially
/// written file away from the preview URL.
enum ChatAttachmentPreviewWriter {
    static func write(
        data: Data,
        fileName rawFileName: String,
        fileTypeIdentifier: String = UTType.data.identifier
    ) throws -> URL {
        guard !data.isEmpty else {
            throw ChatAttachmentProcessorError.emptyFile
        }
        guard data.count <= SchemaV11DataSupport.maxFileDataBytes else {
            throw ChatAttachmentProcessorError.fileTooLarge
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KINChatAttachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let safeFileName = ChatAttachmentProcessor.sanitizedFileName(rawFileName)
        let previewFileName: String
        if URL(fileURLWithPath: safeFileName).pathExtension.isEmpty,
           let fileExtension = UTType(fileTypeIdentifier)?.preferredFilenameExtension {
            previewFileName = "\(safeFileName).\(fileExtension)"
        } else {
            previewFileName = safeFileName
        }
        let token = UUID().uuidString
        let destination = directory.appendingPathComponent("\(token)-\(previewFileName)")
        let staging = directory.appendingPathComponent(".\(token).tmp")

        do {
            try data.write(to: staging, options: .atomic)
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }

        return destination
    }
}

/// Shared two-choice attachment surface for one-to-one and group chats.
/// The panel owns picker selection and processing state; callers only receive
/// normalized in-memory values and surface errors in their app model.
struct ChatAttachmentPanel: View {
    let onImage: (Data) -> Void
    let onFile: (ChatFileAttachment) -> Void
    let onError: (String) -> Void

    @State private var photoSelection: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var processingID: UUID?
    @State private var localError: String?

    init(
        onImage: @escaping (Data) -> Void,
        onFile: @escaping (ChatFileAttachment) -> Void,
        onError: @escaping (String) -> Void = { _ in }
    ) {
        self.onImage = onImage
        self.onFile = onFile
        self.onError = onError
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    attachmentTile(
                        title: "上传图片",
                        systemImage: "photo"
                    )
                }
                .disabled(isProcessing)
                .accessibilityIdentifier("wechat.chat.attachment.image")

                Button {
                    guard !isProcessing else { return }
                    localError = nil
                    isFileImporterPresented = true
                } label: {
                    attachmentTile(
                        title: "上传文件",
                        systemImage: "doc"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .accessibilityIdentifier("wechat.chat.attachment.file")
            }
            .frame(maxWidth: .infinity)

            if isProcessing {
                ProgressView("处理中")
                    .controlSize(.small)
                    .accessibilityIdentifier("wechat.chat.attachment.processing")
            }

            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("wechat.chat.attachment.error")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.composerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .onChange(of: photoSelection) { _, selection in
            processPhoto(selection)
        }
    }

    private var isProcessing: Bool { processingID != nil }

    private func attachmentTile(title: String, systemImage: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .background(
            AppTheme.secondarySurface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.divider, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }

    private func processPhoto(_ selection: PhotosPickerItem?) {
        guard let selection, !isProcessing else { return }
        let id = UUID()
        processingID = id
        localError = nil

        Task { @MainActor in
            defer {
                if processingID == id {
                    processingID = nil
                    photoSelection = nil
                }
            }

            do {
                guard let source = try await selection.loadTransferable(type: Data.self) else {
                    throw ChatAttachmentProcessorError.unreadableImage
                }
                let normalized = try await Task.detached(priority: .userInitiated) {
                    try ChatAttachmentProcessor.normalizedImageData(from: source)
                }.value
                guard processingID == id else { return }
                onImage(normalized)
            } catch {
                guard processingID == id else { return }
                report(error)
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard !isProcessing else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let id = UUID()
            processingID = id
            localError = nil
            Task { @MainActor in
                defer {
                    if processingID == id {
                        processingID = nil
                    }
                }
                do {
                    let attachment = try await Task.detached(priority: .userInitiated) {
                        try ChatAttachmentProcessor.readFile(at: url)
                    }.value
                    guard processingID == id else { return }
                    onFile(attachment)
                } catch {
                    guard processingID == id else { return }
                    report(error)
                }
            }
        case .failure(let error):
            report(error)
        }
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        localError = message
        onError(message)
    }
}
