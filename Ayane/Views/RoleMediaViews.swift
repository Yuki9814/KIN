import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum RoleImageKind {
    case avatar
    case chatBackground

    var maximumPixelSize: Int {
        switch self {
        case .avatar: 640
        case .chatBackground: 2_048
        }
    }
}

enum RoleImageProcessorError: LocalizedError {
    case unreadableImage
    case imageTooLarge
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "无法读取这张图片，请换一张再试。"
        case .imageTooLarge: "图片文件过大，请选择小于 50 MB 的图片。"
        case .encodingFailed: "图片处理失败，请换一张再试。"
        }
    }
}

enum RoleImageProcessor {
    static func normalizedJPEG(from data: Data, kind: RoleImageKind) throws -> Data {
        guard data.count <= 50 * 1_024 * 1_024 else {
            throw RoleImageProcessorError.imageTooLarge
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: kind.maximumPixelSize,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
              ) else {
            throw RoleImageProcessorError.unreadableImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw RoleImageProcessorError.encodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw RoleImageProcessorError.encodingFailed
        }
        return output as Data
    }
}

struct RoleChatBackground: View {
    let imageData: Data?

    var body: some View {
        GeometryReader { proxy in
            if let image = PlatformRoleImage.image(from: imageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay(Color.white.opacity(0.12))
            } else {
                AppTheme.chatBackground
            }
        }
        .accessibilityHidden(true)
    }
}

struct RoleMediaPicker: View {
    @Binding var avatarImageData: Data?
    @Binding var chatBackgroundImageData: Data?

    var name: String
    var onChange: () -> Void = {}

    @State private var avatarSelection: PhotosPickerItem?
    @State private var backgroundSelection: PhotosPickerItem?
    @State private var avatarLoadID = UUID()
    @State private var backgroundLoadID = UUID()
    @State private var errorText: String?
    @State private var loadingAvatar = false
    @State private var loadingBackground = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CompanionAvatar(size: 64, name: name, imageData: avatarImageData)

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $avatarSelection, matching: .images) {
                        Label(loadingAvatar ? "正在处理" : "选择角色头像", systemImage: "photo")
                    }
                    .disabled(loadingAvatar)
                    .accessibilityIdentifier("role-media.avatar-picker")

                    if avatarImageData != nil {
                        Button("恢复默认头像", role: .destructive) {
                            avatarImageData = nil
                            onChange()
                        }
                        .font(.caption)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("聊天背景")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoleChatBackground(imageData: chatBackgroundImageData)
                    PhotosPicker(selection: $backgroundSelection, matching: .images) {
                        Label(loadingBackground ? "正在处理" : "选择聊天背景", systemImage: "photo.on.rectangle")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(.primary)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(loadingBackground)
                    .accessibilityIdentifier("role-media.background-picker")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if chatBackgroundImageData != nil {
                    Button("清除聊天背景", role: .destructive) {
                        chatBackgroundImageData = nil
                        onChange()
                    }
                    .font(.caption)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: avatarSelection) { _, selection in
            importSelection(selection, kind: .avatar)
        }
        .onChange(of: backgroundSelection) { _, selection in
            importSelection(selection, kind: .chatBackground)
        }
    }

    private func importSelection(_ selection: PhotosPickerItem?, kind: RoleImageKind) {
        guard let selection else { return }
        let loadID = UUID()
        switch kind {
        case .avatar:
            avatarLoadID = loadID
            loadingAvatar = true
        case .chatBackground:
            backgroundLoadID = loadID
            loadingBackground = true
        }

        Task {
            do {
                guard let source = try await selection.loadTransferable(type: Data.self) else {
                    throw RoleImageProcessorError.unreadableImage
                }
                let processed = try RoleImageProcessor.normalizedJPEG(from: source, kind: kind)
                guard isCurrent(loadID, for: kind) else { return }
                switch kind {
                case .avatar: avatarImageData = processed
                case .chatBackground: chatBackgroundImageData = processed
                }
                errorText = nil
                onChange()
            } catch {
                guard isCurrent(loadID, for: kind) else { return }
                errorText = error.localizedDescription
            }
            finishLoading(loadID, for: kind)
        }
    }

    private func isCurrent(_ id: UUID, for kind: RoleImageKind) -> Bool {
        switch kind {
        case .avatar: avatarLoadID == id
        case .chatBackground: backgroundLoadID == id
        }
    }

    private func finishLoading(_ id: UUID, for kind: RoleImageKind) {
        guard isCurrent(id, for: kind) else { return }
        switch kind {
        case .avatar: loadingAvatar = false
        case .chatBackground: loadingBackground = false
        }
    }
}

enum PlatformRoleImage {
    static func image(from data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #endif
    }
}
