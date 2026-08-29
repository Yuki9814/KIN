import Foundation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct CompanionAvatar: View {
    var size: CGFloat = 42
    var name: String = "绫音"
    var imageData: Data? = nil

    var body: some View {
        Group {
            if let image = PlatformRoleImage.image(from: imageData) {
                image
                    .resizable()
                    .scaledToFill()
            } else if let assetName = BuiltInCompanionAvatarCatalog.assetName(for: name) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AyaneAvatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size * 2.4, height: size * 2.4)
                    .offset(y: size * 0.64)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.09), style: .continuous))
        .accessibilityLabel(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "绫音" : name)
    }
}

/// A deliberately simple local avatar for the user's side of the transcript.
/// It is hidden from accessibility because the enclosing event already exposes
/// one complete message label.
struct UserAvatar: View {
    var size: CGFloat = 30
    var name: String = "我"
    var imageData: Data? = nil

    var body: some View {
        Group {
            if let image = PlatformRoleImage.image(from: imageData) {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: max(4, size * 0.09),
                        style: .continuous
                    )
                    .fill(Color(red: 0.43, green: 0.58, blue: 0.67))
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.52, weight: .regular))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.09), style: .continuous))
        .accessibilityLabel(name)
    }
}

struct StatusBanner: View {
    enum Style {
        case information
        case warning
        case error

        var icon: String {
            switch self {
            case .information: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .information: .blue
            case .warning: .orange
            case .error: .red
            }
        }
    }

    let text: String
    var style: Style = .information
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style.icon)
                .foregroundStyle(style.color)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let dismiss {
                Button("关闭", systemImage: "xmark", action: dismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(style.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(style.color.opacity(0.18), lineWidth: 1)
        }
    }
}

struct MessageBubble: View {
    let role: EventRole
    let content: String
    var state: EventDeliveryState = .complete
    var eventID: UUID? = nil
    /// Optional display units supplied by an upstream presentation layer.
    ///
    /// ConversationEvent currently exposes only its logical content, so the
    /// default is intentionally nil and this view renders that event once.
    /// When a caller already has persisted presentation segments, it may pass
    /// them here; MessageBubble never derives new segments from message text.
    var persistedSegments: [String]? = nil
    /// Text and stickers are separate persisted payloads. Keeping this value
    /// explicit prevents message copy from accidentally rendering as a sticker.
    var payloadKind: MessagePayloadKind = .text
    var stickerID: String? = nil
    /// Image payload bytes are supplied by the already-loaded conversation
    /// event. This view only decodes and presents them; it never writes image
    /// data back to the store.
    var imageData: Data? = nil
    /// File payload metadata and bytes are supplied by the already-loaded
    /// conversation event. The bytes are kept in memory only for presentation
    /// and are written to an app-owned temporary URL when Quick Look opens.
    var fileName: String = ""
    var fileTypeIdentifier: String = UTType.data.identifier
    var fileData: Data? = nil
    var companionName: String = "绫音"
    var companionAvatarImageData: Data? = nil
    var companionAvatarAction: (() -> Void)? = nil
    /// Presentation-only user profile values. The source ConversationEvent remains
    /// the sole input for message text and delivery state.
    var userName: String = "我"
    var userAvatarImageData: Data? = nil

    private var displayUnits: [String] {
        Self.resolvedDisplayUnits(
            content: content,
            role: role,
            persistedSegments: persistedSegments
        )
    }

    private var stickerDefinition: StickerDefinition? {
        guard payloadKind == .sticker else { return nil }
        return StickerCatalog.sticker(stickerID: stickerID ?? "")
    }

    @State private var showsImageViewer = false
    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if payloadKind == .file {
                fileMessage
            } else if payloadKind == .image {
                imageMessage
            } else if let stickerDefinition {
                stickerMessage(definition: stickerDefinition)
            } else if role == .system || role == .manual {
                systemMessage
            } else {
                conversationMessage
            }
        }
        .frame(maxWidth: .infinity)
        // One ConversationEvent remains one accessible message even when its
        // assistant text is drawn as several short, sequential bubbles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .quickLookPreview($quickLookURL)
        .onChange(of: quickLookURL) { oldURL, newURL in
            guard newURL == nil, let oldURL else { return }
            try? FileManager.default.removeItem(at: oldURL)
        }
        .onDisappear {
            if let quickLookURL {
                try? FileManager.default.removeItem(at: quickLookURL)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showsImageViewer) {
            if let imageData {
                MessageImageViewer(imageData: imageData)
            }
        }
        #else
        .sheet(isPresented: $showsImageViewer) {
            if let imageData {
                MessageImageViewer(imageData: imageData)
            }
        }
        #endif
    }

    private var conversationMessage: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
            ForEach(Array(displayUnits.enumerated()), id: \.offset) { _, segment in
                bubbleRow(for: segment)
            }

            if state == .undelivered {
                deliveryStatus
            }
        }
    }

    private var imageMessage: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if role == .user {
                    Spacer(minLength: 56)
                    if state == .failed || state == .undelivered {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                            .frame(height: avatarSize)
                            .accessibilityHidden(true)
                    }
                } else {
                    companionAvatar
                }

                imagePayload

                if role == .user {
                    UserAvatar(
                        size: avatarSize,
                        name: userName,
                        imageData: userAvatarImageData
                    )
                } else {
                    Spacer(minLength: 56)
                }
            }

            if state == .undelivered {
                deliveryStatus
            }
        }
    }

    private var fileMessage: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if role == .user {
                    Spacer(minLength: 56)
                    if state == .failed || state == .undelivered {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                            .frame(height: avatarSize)
                            .accessibilityHidden(true)
                    }
                } else {
                    companionAvatar
                }

                filePayload

                if role == .user {
                    UserAvatar(
                        size: avatarSize,
                        name: userName,
                        imageData: userAvatarImageData
                    )
                } else {
                    Spacer(minLength: 56)
                }
            }

            if state == .failed || state == .undelivered {
                deliveryStatus
            }
        }
    }

    private var filePayload: some View {
        Button(action: openFilePreview) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(role == .user ? AppTheme.messageTextOnOutgoing : AppTheme.accent)
                    .frame(width: 32, height: 38)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayedFileName)
                        .font(.system(size: messageFontSize, weight: .medium))
                        .foregroundStyle(role == .user ? AppTheme.messageTextOnOutgoing : AppTheme.messageText)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(displayedFileSize)
                        .font(.system(size: max(11, messageFontSize - 3)))
                        .foregroundStyle(
                            role == .user
                                ? AppTheme.messageTextOnOutgoing.opacity(0.72)
                                : AppTheme.secondaryText
                        )
                }
                .frame(maxWidth: bubbleMaxWidth - 54, alignment: .leading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: role == .user ? .topTrailing : .topLeading) {
                WeChatBubbleTail(pointsRight: role == .user)
                    .fill(bubbleColor)
                    .frame(width: 7, height: 11)
                    .offset(x: role == .user ? 5.5 : -5.5, y: 10)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(fileAccessibilityLabel)
        .accessibilityIdentifier("wechat.message.file")
        #if os(macOS)
        .help(fileData == nil || fileData?.isEmpty == true ? "文件内容不可用" : "打开文件")
        #endif
    }

    private var displayedFileName: String {
        ChatAttachmentProcessor.sanitizedFileName(fileName)
    }

    private var displayedFileSize: String {
        guard let fileData, !fileData.isEmpty else { return "大小未知" }
        return ByteCountFormatter.string(
            fromByteCount: Int64(fileData.count),
            countStyle: .file
        )
    }

    private var fileAccessibilityLabel: String {
        let action = fileData?.isEmpty == false ? "，点按打开" : "，内容不可用"
        return "文件，\(displayedFileName)，\(displayedFileSize)\(action)"
    }

    private func openFilePreview() {
        guard let fileData, !fileData.isEmpty else { return }
        do {
            if let quickLookURL {
                try? FileManager.default.removeItem(at: quickLookURL)
            }
            quickLookURL = try ChatAttachmentPreviewWriter.write(
                data: fileData,
                fileName: displayedFileName,
                fileTypeIdentifier: fileTypeIdentifier
            )
        } catch {
            // The message remains visible and actionable through its
            // accessibility value even if the temporary preview file fails.
            quickLookURL = nil
        }
    }

    @ViewBuilder
    private var imagePayload: some View {
        if let image = PlatformRoleImage.image(from: imageData) {
            Button {
                showsImageViewer = true
            } label: {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageMaxDimension, height: imageMaxDimension)
                    .padding(3)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("查看图片")
            .accessibilityIdentifier("wechat.message.image")
            #if os(macOS)
            .help("查看原图")
            #endif
        } else {
            Label("图片无法显示", systemImage: "photo")
                .font(.system(size: messageFontSize))
                .foregroundStyle(role == .user ? AppTheme.messageTextOnOutgoing : AppTheme.messageText)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    private func stickerMessage(definition: StickerDefinition) -> some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if role == .user {
                    Spacer(minLength: 56)
                } else {
                    companionAvatar
                }

                StickerAssetView(definition: definition, size: 96)

                if role == .user {
                    UserAvatar(
                        size: avatarSize,
                        name: userName,
                        imageData: userAvatarImageData
                    )
                } else {
                    Spacer(minLength: 56)
                }
            }

            if state == .undelivered {
                deliveryStatus
            }
        }
    }

    private func bubbleRow(for segment: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if role == .user {
                Spacer(minLength: 56)
                if state == .failed || state == .undelivered {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red)
                        .frame(height: avatarSize)
                        .accessibilityHidden(true)
                }
            } else {
                companionAvatar
            }

            bubble(for: segment)

            if role == .user {
                UserAvatar(
                    size: avatarSize,
                    name: userName,
                    imageData: userAvatarImageData
                )
            } else {
                Spacer(minLength: 56)
            }
        }
    }

    @ViewBuilder
    private var companionAvatar: some View {
        if let companionAvatarAction {
            Button(action: companionAvatarAction) {
                CompanionAvatar(
                    size: avatarSize,
                    name: companionName,
                    imageData: companionAvatarImageData
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(companionName)的详细资料")
            .accessibilityIdentifier("wechat.message.avatar.companion")
        } else {
            CompanionAvatar(
                size: avatarSize,
                name: companionName,
                imageData: companionAvatarImageData
            )
        }
    }

    private var systemMessage: some View {
        Text(systemMessageText)
            .font(.system(size: 12))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 3))
    }

    private var systemMessageText: String {
        let visible = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !visible.isEmpty { return visible }
        return role == .manual ? "手动记录" : "系统消息"
    }

    @ViewBuilder
    private func bubble(for segment: String) -> some View {
        let visibleText = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !visibleText.isEmpty {
            Text(visibleText)
                .font(.system(size: messageFontSize))
                .lineSpacing(2)
                .textSelection(.enabled)
                .foregroundStyle(role == .user ? AppTheme.messageTextOnOutgoing : AppTheme.messageText)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(alignment: role == .user ? .topTrailing : .topLeading) {
                    WeChatBubbleTail(pointsRight: role == .user)
                        .fill(bubbleColor)
                        .frame(width: 7, height: 11)
                        .offset(x: role == .user ? 5.5 : -5.5, y: 10)
                }
                .frame(maxWidth: bubbleMaxWidth, alignment: role == .user ? .trailing : .leading)
        }
    }

    private var deliveryStatus: some View {
        Label(deliveryText, systemImage: deliveryIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(deliveryColor)
            .padding(.horizontal, 2)
    }

    private var bubbleColor: Color {
        role == .user
            ? AppTheme.outgoingBubble
            : AppTheme.incomingBubble
    }

    private var avatarSize: CGFloat {
        #if os(iOS)
        40
        #else
        36
        #endif
    }

    private var messageFontSize: CGFloat {
        #if os(iOS)
        17
        #else
        14
        #endif
    }

    private var bubbleMaxWidth: CGFloat {
        #if os(iOS)
        268
        #else
        460
        #endif
    }

    private var imageMaxDimension: CGFloat {
        #if os(iOS)
        260
        #else
        360
        #endif
    }

    private var deliveryText: String {
        switch state {
        case .complete: return ""
        case .streaming, .cancelled: return ""
        case .failed: return "回复失败，内容未完整"
        case .undelivered: return "对方已删除你，这条消息未送达"
        }
    }

    private var deliveryIcon: String {
        switch state {
        case .complete: return "checkmark"
        case .streaming: return "ellipsis"
        case .cancelled: return "stop.circle"
        case .failed: return "exclamationmark.triangle"
        case .undelivered: return "exclamationmark.circle.fill"
        }
    }

    private var deliveryColor: Color {
        switch state {
        case .complete: return .secondary
        case .streaming: return .secondary
        case .cancelled: return .orange
        case .failed: return .red
        case .undelivered: return .red
        }
    }

    private var accessibilityText: String {
        Self.makeAccessibilityText(
            role: role,
            content: payloadKind == .file
                ? "文件，\(displayedFileName)，\(displayedFileSize)"
                : (payloadKind == .image
                    ? "图片"
                    : (stickerDefinition != nil ? "" : content)),
            state: state,
            companionName: companionName,
            stickerLabel: stickerDefinition.map(\.alternativeText)
        )
    }

    /// Resolves display units without interpreting or re-segmenting logical
    /// event content. A persisted/upstream plan is trusted as-is; otherwise a
    /// non-empty event remains one unit, including code, lists, and long-form
    /// text. This keeps one ConversationEvent aligned with one visible row.
    static func resolvedDisplayUnits(
        content: String,
        role: EventRole = .assistant,
        persistedSegments: [String]? = nil
    ) -> [String] {
        guard role == .assistant else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [content]
        }

        if let persistedSegments {
            let visibleSegments = persistedSegments.filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            // An explicit empty prefix means the durable presentation queue
            // has not delivered its first bubble yet. Never fall back to the
            // full logical reply, which would flash as one long bubble before
            // the persisted segments become visible.
            return visibleSegments
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [content]
    }

    /// Builds the single accessibility label for one ConversationEvent. Sticker
    /// decoration is appended here because the enclosing message intentionally
    /// ignores child accessibility elements to avoid splitting one event into
    /// several VoiceOver messages.
    static func makeAccessibilityText(
        role: EventRole,
        content: String,
        state: EventDeliveryState,
        companionName: String = "绫音",
        stickerLabel: String? = nil
    ) -> String {
        let speaker: String
        switch role {
        case .user: speaker = "你的消息"
        case .assistant: speaker = "\(companionName)的消息"
        case .system: speaker = "系统消息"
        case .manual: speaker = "手动记录"
        }
        let delivery: String
        switch state {
        case .complete: delivery = ""
        case .streaming, .cancelled: delivery = ""
        case .failed: delivery = "，回复失败，内容未完整"
        case .undelivered: delivery = "，对方已删除你，消息未送达"
        }
        let sticker = stickerLabel.map { "，\($0)" } ?? ""
        let message = content.isEmpty && !sticker.isEmpty ? sticker.dropFirst() : Substring(content + sticker)
        return "\(speaker)：\(message)\(delivery)"
    }
}

private struct WeChatBubbleTail: Shape {
    let pointsRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointsRight {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.18)
            )
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.maxY),
                control: CGPoint(x: rect.width * 0.55, y: rect.height * 0.82)
            )
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.midY),
                control: CGPoint(x: rect.width * 0.45, y: rect.height * 0.18)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.width * 0.45, y: rect.height * 0.82)
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct MessageImageViewer: View {
    let imageData: Data

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            if let image = PlatformRoleImage.image(from: imageData) {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(
                                minWidth: geometry.size.width,
                                minHeight: geometry.size.height
                            )
                    }
                }
            } else {
                Text("图片无法显示")
                    .foregroundStyle(.white.opacity(0.82))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 12)
            .accessibilityLabel("关闭图片")
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 520)
        #endif
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    var isEnabled: Bool = true
    let send: () -> Void
    let stop: () -> Void
    var companionName: String = "绫音"
    var isStickerPickerPresented: Bool = false
    var isMoreOptionsPresented: Bool = false
    var showStickerPicker: () -> Void = {}
    var showMoreOptions: () -> Void = {}
    /// Voice input is not implemented in this surface. A future caller may
    /// provide a real action; until then the affordance is informational and
    /// non-interactive instead of a button whose action silently does nothing.
    var voiceAction: (() -> Void)? = nil
    @FocusState.Binding var focused: Bool

    var body: some View {
        #if os(iOS)
        iOSComposer
        #else
        macComposer
        #endif
    }

    #if os(iOS)
    private var iOSComposer: some View {
        HStack(alignment: .center, spacing: 0) {
            if let voiceAction {
                Button(action: voiceAction) {
                    Image(systemName: "speaker.wave.2.circle")
                        .font(.system(size: 29, weight: .regular))
                        .foregroundStyle(AppTheme.composerIcon)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("语音输入")
                .accessibilityIdentifier("wechat.chat.voice")
            } else {
                Image(systemName: "speaker.wave.2.circle")
                    .font(.system(size: 29, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(width: 44, height: 44)
                    .opacity(0.62)
                    .accessibilityLabel("语音输入")
                    .accessibilityValue("暂未开放")
                    .accessibilityHint("语音输入功能暂未开放")
                    .accessibilityIdentifier("wechat.chat.voice")
                    .disabled(true)
            }

            TextField("", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 17))
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.messageText)
                .tint(AppTheme.accent)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(minHeight: 36)
                .background(AppTheme.composerFieldBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("发送给\(companionName)的消息")
                .disabled(!isEnabled)
                .submitLabel(.send)
                .onSubmit {
                    if isEnabled && canSend {
                        send()
                    }
                }

            // Keep the visual four-point separation outside the button so the
            // tappable label remains exactly the standard 44×44 points.
            Spacer(minLength: 4)
                .frame(width: 4, height: 44)
                .accessibilityHidden(true)

            Button(action: showStickerPicker) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(isStickerPickerPresented ? AppTheme.accent : AppTheme.composerIcon)
                    .frame(width: 44, height: 44)
                    .background(
                        isStickerPickerPresented ? AppTheme.accent.opacity(0.12) : Color.clear,
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(isStickerPickerPresented ? "关闭表情面板" : "打开表情面板")
            .accessibilityIdentifier("wechat.chat.sticker-picker")

            if canSend {
                Button(action: send) {
                    Text("发送")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 32)
                        .background(
                            AppTheme.accent,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .frame(minWidth: 54, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("发送")
                .accessibilityIdentifier("wechat.chat.send")
            } else {
                Button(action: showMoreOptions) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 29, weight: .regular))
                        .foregroundStyle(
                            isMoreOptionsPresented
                                ? AppTheme.accent
                                : AppTheme.composerIcon
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            isMoreOptionsPresented
                                ? AppTheme.accent.opacity(0.12)
                                : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(
                    isMoreOptionsPresented ? "关闭附件面板" : "打开附件面板"
                )
                .accessibilityIdentifier("wechat.chat.more")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 60)
        .background(AppTheme.composerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.58)
    }
    #endif

    #if os(macOS)
    private var macComposer: some View {
        VStack(spacing: 0) {
            TextField("想和\(companionName)说什么…", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
                .foregroundStyle(AppTheme.messageText)
                .focused($focused)
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .disabled(!isEnabled)
                .onSubmit {
                    if isEnabled && canSend {
                        send()
                    }
                }

            HStack(spacing: 18) {
                Button(action: showStickerPicker) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(
                            isStickerPickerPresented ? AppTheme.accent : AppTheme.composerIcon
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            isStickerPickerPresented ? AppTheme.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isStickerPickerPresented ? "关闭表情面板" : "打开表情面板")
                .accessibilityIdentifier("wechat.chat.sticker-picker")

                Button(action: showMoreOptions) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(
                            isMoreOptionsPresented
                                ? AppTheme.accent
                                : AppTheme.composerIcon
                        )
                        .frame(width: 44, height: 44)
                        .background(
                            isMoreOptionsPresented
                                ? AppTheme.accent.opacity(0.12)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel(
                    isMoreOptionsPresented ? "关闭附件面板" : "打开附件面板"
                )
                .accessibilityIdentifier("wechat.chat.more")

                Image(systemName: "shippingbox")
                Image(systemName: "folder")
                Image(systemName: "scissors")
                Image(systemName: "pencil.tip")
                Image(systemName: "mic")

                Spacer()

                if isEnabled && canSend {
                    Button(action: send) {
                        Text("发送")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 26)
                            .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("发送")
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Image(systemName: "speaker.wave.2.circle")
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: 26, height: 26)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(AppTheme.composerIcon)
            .padding(.horizontal, 13)
            .padding(.bottom, 20)
            .accessibilityElement(children: .contain)
        }
        .frame(height: 150)
        .background(AppTheme.composerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        .opacity(isEnabled ? 1 : 0.58)
    }
    #endif

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MemoryStateBadge: View {
    let state: MemoryState

    var body: some View {
        Text(state.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.10), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .active: .green
        case .candidate: .orange
        case .contested: .red
        case .superseded: .secondary
        case .forgotten: .secondary
        }
    }
}

#Preview("Messages") {
    VStack(spacing: 16) {
        MessageBubble(role: .assistant, content: "我记得你更喜欢雨天散步。今天也想聊聊吗？")
        MessageBubble(role: .user, content: "想，今天发生了一件很有意思的事。")
    }
    .padding()
    .frame(width: 540)
}
