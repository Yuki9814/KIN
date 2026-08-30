import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ChatView: View {
    private struct PendingMessageDeletion: Identifiable {
        let id: UUID
        let preview: String
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var olderMessageAnchor: UUID?
    @State private var isLoadingOlderMessages = false
    @State private var showsContactDetails = false
    @State private var showsStickerPicker = false
    @State private var showsMoreOptions = false
    @State private var showsImageGenerationPrompt = false
    @State private var imageGenerationPrompt = ""
    @State private var pendingMessageDeletion: PendingMessageDeletion?
    @State private var recentStickerIDs: [String] = StickerRecentStore.load()
    @AppStorage(SettingsKeys.typingIndicatorEnabled) private var typingIndicatorEnabled = true
    @FocusState private var inputFocused: Bool

    var onOpenSettings: () -> Void = {}

    private let bottomAnchor = "chat-bottom-anchor"

    var body: some View {
        let presentationSegments = appModel.presentationSegmentsByEventID()
        VStack(spacing: 0) {
            chatHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let warning = appModel.persistenceWarning {
                            StatusBanner(text: warning, style: .warning) {
                                appModel.clearPersistenceWarning()
                            }
                        }

                        if let error = appModel.errorMessage {
                            StatusBanner(text: error, style: .error) {
                                appModel.errorMessage = nil
                            }
                        }

                        if appModel.messages.isEmpty {
                            emptyConversation
                        } else {
                            if appModel.hasOlderMessages {
                                Button {
                                    loadOlderMessages(using: proxy)
                                } label: {
                                    if isLoadingOlderMessages {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("查看更多消息")
                                            .font(.system(size: 12))
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppTheme.secondaryText)
                                .disabled(isLoadingOlderMessages)
                                .accessibilityHint("当前仅载入最近的对话；更早原文仍保存在本机数据库中")
                            }

                            ForEach(Array(appModel.messages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowTimeSeparator(at: index, in: appModel.messages) {
                                    messageTimeSeparator(for: message.occurredAt)
                                }

                                messageBubble(
                                    for: message,
                                    persistedSegments: presentationSegments[message.id]
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .frame(maxWidth: AppTheme.contentMaxWidth)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                }
                .background(Color.clear)
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    if !appModel.isGenerating {
                        markCurrentConversationRead()
                    }
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                .onChange(of: appModel.messages.count) {
                    if !appModel.isGenerating {
                        markCurrentConversationRead()
                    }
                    if let anchor = olderMessageAnchor {
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(anchor, anchor: .top)
                            olderMessageAnchor = nil
                            isLoadingOlderMessages = false
                        }
                    } else {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                            proxy.scrollTo(bottomAnchor, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appModel.messages.last?.id) {
                    // The recent-message window is capped, so a new event can
                    // replace the last visible item without changing the count.
                    if !appModel.isGenerating {
                        markCurrentConversationRead()
                    }
                }
                .onChange(of: appModel.messages.last?.content) {
                    // A logical streaming event grows in place now that its
                    // persisted presentation units are passed to MessageBubble.
                    // Keep the newest visible unit in view without creating a
                    // second event or forcing character-level bubbles.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: appModel.presentationRevision) {
                    // A single logical reply may reveal several WeChat-style
                    // bubbles over time without inserting another event.
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: appModel.isGenerating) {
                    if !appModel.isGenerating {
                        markCurrentConversationRead()
                    }
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }

            if !appModel.canSendMessages {
                Text(appModel.relationshipStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppTheme.secondarySurface)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(AppTheme.divider)
                            .frame(height: 0.5)
                    }
                    .accessibilityIdentifier("wechat.relationship.notice")
            }

            #if os(macOS)
            if showsStickerPicker {
                stickerPicker
                    .transition(.opacity)
            }
            #endif

            if showsMoreOptions {
                attachmentPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ChatInputBar(
                text: $draft,
                isGenerating: appModel.isGenerating,
                isEnabled: composerEnabled,
                send: send,
                stop: appModel.stopGenerating,
                companionName: appModel.persona.name,
                isStickerPickerPresented: showsStickerPicker,
                isMoreOptionsPresented: showsMoreOptions,
                showStickerPicker: toggleStickerPicker,
                showMoreOptions: toggleMoreOptions,
                focused: $inputFocused
            )

            #if os(iOS)
            if showsStickerPicker {
                stickerPicker
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
        .background {
            RoleChatBackground(imageData: appModel.persona.chatBackgroundImageData)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let notice = chatActionNotice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("memory.updated.notice")
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: chatActionNotice
        )
        .confirmationDialog(
            "删除这条消息以及之后的全部内容？",
            isPresented: Binding(
                get: { pendingMessageDeletion != nil },
                set: { if !$0 { pendingMessageDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let target = pendingMessageDeletion else { return }
                pendingMessageDeletion = nil
                performMessageAction {
                    try appModel.deleteMessageAndFollowing(id: target.id)
                }
            }
            Button("取消", role: .cancel) {
                pendingMessageDeletion = nil
            }
        } message: {
            Text("“\(pendingMessageDeletion?.preview ?? "这条消息")”以及它之后你和角色的消息都会被删除，之前的内容会保留。")
        }
        .sheet(isPresented: $showsImageGenerationPrompt) {
            imageGenerationPromptSheet
        }
        #if os(iOS)
        .background(AppTheme.rootBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .restoresWeChatEdgeBackGesture()
        .wechatEdgeBackFallback()
        .navigationDestination(isPresented: $showsContactDetails) {
            CompanionContactView(roleID: appModel.currentRoleID)
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showsContactDetails) {
            NavigationStack {
                CompanionContactView(roleID: appModel.currentRoleID)
            }
            .frame(minWidth: 480, minHeight: 620)
        }
        #endif
    }

    private var imageGenerationPromptSheet: some View {
        NavigationStack {
            Form {
                Section("画面描述") {
                    TextField(
                        "例如：雨夜便利店门口，电影感，暖色灯光",
                        text: $imageGenerationPrompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("wechat.imageGeneration.prompt")
                }

                Section {
                    Text("图片由“AI 连接与订阅”中的独立生图接口生成，成功后会作为 \(appModel.persona.name) 发出的图片保存在当前聊天中。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("生成图片")
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 300)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showsImageGenerationPrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成") {
                        submitImageGeneration()
                    }
                    .disabled(
                        imageGenerationPrompt
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                    .accessibilityIdentifier("wechat.imageGeneration.submit")
                }
            }
        }
    }

    @ViewBuilder
    private var chatHeader: some View {
        #if os(iOS)
        WeChatBackHeader(
            title: chatNavigationTitle,
            trailingSystemImage: "ellipsis",
            trailingAccessibilityLabel: "聊天信息",
            trailingAction: { showsContactDetails = true }
        )
        .frame(height: 56)
        .background(AppTheme.chatBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        #else
        HStack(spacing: 12) {
            Text(chatNavigationTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            Image(systemName: "bubble.left")
            Image(systemName: "phone")
            Image(systemName: "ellipsis")
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(AppTheme.iconPrimary)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .offset(y: 4)
        .background(AppTheme.barBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "与\(appModel.persona.name)对话，\(chatNavigationTitle)，\(appModel.isProviderConfigured ? "API 已配置" : "API 未配置")，\(appModel.memoryCount) 条有效记忆"
        )
        #endif
    }

    private func messageTimeSeparator(for date: Date) -> some View {
        let label = Self.messageTimeLabel(for: date)
        return Text(label)
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .accessibilityLabel("消息时间，\(label)")
    }

    private func shouldShowTimeSeparator(
        at index: Int,
        in messages: [ConversationEvent]
    ) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        let current = messages[index].occurredAt
        let previous = messages[index - 1].occurredAt
        return !Calendar.autoupdatingCurrent.isDate(current, inSameDayAs: previous)
            || current.timeIntervalSince(previous) >= 5 * 60
    }

    static func messageTimeLabel(
        for date: Date,
        relativeTo now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let dayGap = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch dayGap {
        case 0:
            return "今天 \(time)"
        case 1:
            return "昨天 \(time)"
        case 2...10:
            return "\(dayGap)天前"
        default:
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = calendar
            dateFormatter.timeZone = calendar.timeZone
            dateFormatter.locale = Locale(identifier: "zh_CN")
            dateFormatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
                ? "M月d日 HH:mm"
                : "yyyy年M月d日 HH:mm"
            return dateFormatter.string(from: date)
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            Text(emptyConversationText)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if appModel.canSendMessages && !appModel.isProviderConfigured {
                Button("打开设置") {
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.accent)
            }
            Spacer(minLength: 70)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func messageBubble(
        for message: ConversationEvent,
        persistedSegments: [String]?
    ) -> some View {
        let pokeAction: (() -> Void)? = message.role == .assistant
            ? { appModel.pokeCurrentCompanion() }
            : nil
        let bubble = MessageBubble(
            role: message.role,
            content: message.content,
            state: message.deliveryState,
            eventID: message.id,
            persistedSegments: persistedSegments,
            payloadKind: message.payloadKind,
            stickerID: message.stickerID.isEmpty ? nil : message.stickerID,
            imageData: message.imageData,
            fileName: message.fileName,
            fileTypeIdentifier: message.fileTypeIdentifier,
            fileData: message.fileData,
            companionName: appModel.persona.name,
            companionAvatarImageData: appModel.persona.avatarImageData,
            companionAvatarAction: { showsContactDetails = true },
            companionAvatarPokeAction: pokeAction,
            userName: appModel.userProfile.displayName,
            userAvatarImageData: appModel.userProfile.avatarImageData
        )
        .id(message.id)

        if message.role == .user {
            bubble.contextMenu {
                Button("复制") {
                    copyMessageText(message.content)
                }
                if appModel.latestRecallableUserEventID == message.id {
                    Button("撤回") {
                        performMessageAction {
                            try appModel.recallUserMessage(id: message.id)
                        }
                    }
                }
                Button("删除", role: .destructive) {
                    let preview = message.content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    pendingMessageDeletion = PendingMessageDeletion(
                        id: message.id,
                        preview: String((preview.isEmpty ? "这条消息" : preview).prefix(28))
                    )
                }
            }
        } else {
            bubble
        }
    }

    private func performMessageAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func copyMessageText(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var chatActionNotice: String? {
        appModel.momentCommandNotice ?? appModel.memoryUpdateNotice
    }

    private var emptyConversationText: String {
        guard appModel.canSendMessages else {
            return appModel.relationshipStatusText
        }
        return appModel.isProviderConfigured
            ? "你们已经成为好友，现在可以开始聊天了。"
            : "先在“我－设置”中配置 API。"
    }

    private func send() {
        guard composerEnabled else { return }
        let value = draft
        draft = ""
        appModel.send(value)
    }

    private var stickerPicker: some View {
        StickerPickerView(recentStickerIDs: recentStickerIDs) { sticker in
            rememberSticker(sticker.stickerID)
            sendSticker(sticker.stickerID)
        }
    }

    private var attachmentPanel: some View {
        let targetRoleID = appModel.currentRoleID
        let targetConversationID = appModel.currentConversation.id
        return ChatAttachmentPanel(
            onImage: { imageData in
                appModel.sendImage(
                    imageData: imageData,
                    targetRoleID: targetRoleID,
                    targetConversationID: targetConversationID
                )
                showsMoreOptions = false
            },
            onFile: { attachment in
                appModel.sendFile(
                    fileData: attachment.data,
                    fileName: attachment.fileName,
                    fileTypeIdentifier: attachment.fileTypeIdentifier,
                    targetRoleID: targetRoleID,
                    targetConversationID: targetConversationID
                )
                showsMoreOptions = false
            },
            onGenerateImage: {
                imageGenerationPrompt = ""
                showsImageGenerationPrompt = true
            },
            onError: { message in
                appModel.errorMessage = message
            }
        )
    }

    private func submitImageGeneration() {
        let prompt = imageGenerationPrompt
        let targetRoleID = appModel.currentRoleID
        let targetConversationID = appModel.currentConversation.id
        showsImageGenerationPrompt = false
        showsMoreOptions = false
        imageGenerationPrompt = ""
        appModel.generateImage(
            prompt: prompt,
            targetRoleID: targetRoleID,
            targetConversationID: targetConversationID
        )
    }

    private func toggleMoreOptions() {
        guard composerEnabled else { return }
        showsMoreOptions.toggle()
        if showsMoreOptions {
            showsStickerPicker = false
            inputFocused = false
        }
    }

    private func toggleStickerPicker() {
        guard composerEnabled else { return }
        showsStickerPicker.toggle()
        if showsStickerPicker {
            showsMoreOptions = false
            inputFocused = false
        }
    }

    private func sendSticker(_ stickerID: String) {
        guard composerEnabled else { return }
        showsStickerPicker = false
        inputFocused = false
        appModel.sendSticker(stickerID: stickerID)
    }

    private func rememberSticker(_ stickerID: String) {
        recentStickerIDs = StickerRecentStore.remember(stickerID)
    }

    private var chatNavigationTitle: String {
        Self.navigationTitle(
            personaName: appModel.persona.name,
            isGenerating: appModel.isGenerating,
            typingIndicatorEnabled: typingIndicatorEnabled
        )
    }

    static func navigationTitle(
        personaName: String,
        isGenerating: Bool,
        typingIndicatorEnabled: Bool
    ) -> String {
        typingIndicatorEnabled && isGenerating ? "正在输入中…" : personaName
    }

    private func markCurrentConversationRead() {
        appModel.markConversationRead(
            conversationID: appModel.currentConversation.id,
            roleID: appModel.currentRoleID
        )
    }

    private var composerEnabled: Bool {
        appModel.canSendMessages
    }

    private func loadOlderMessages(using proxy: ScrollViewProxy) {
        guard !isLoadingOlderMessages else { return }
        let previousCount = appModel.messages.count
        olderMessageAnchor = appModel.messages.first?.id
        isLoadingOlderMessages = true
        appModel.loadOlderMessages()

        // If the store changed between displaying the button and loading, the
        // count may stay unchanged and `onChange` will not fire.
        if appModel.messages.count == previousCount {
            if let anchor = olderMessageAnchor {
                proxy.scrollTo(anchor, anchor: .top)
            }
            olderMessageAnchor = nil
            isLoadingOlderMessages = false
        }
    }
}
