import SwiftData
import SwiftUI

#if os(iOS)
import PhotosUI
#endif

/// The lightweight recipient picker used by the WeChat plus menu's
/// “发起聊天” action.  It deliberately reuses the same role snapshots as the
/// contacts list, so a pending or retired role can never be selected as a
/// chat recipient.
struct WeChatStartChatView: View {
    @Environment(AppModel.self) private var appModel

    let openSettings: () -> Void

    @State private var searchText = ""
    @State private var showsChat = false

    var body: some View {
        List {
            Section("好友") {
                if filteredCompanions.isEmpty {
                    Text("没有可发起聊天的好友")
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredCompanions) { companion in
                        Button {
                            openCompanion(companion.id)
                        } label: {
                            HStack(spacing: 12) {
                                CompanionAvatar(
                                    size: 42,
                                    name: companion.name,
                                    imageData: companion.avatarImageData
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(companion.name)
                                        .foregroundStyle(.primary)
                                    Text(companion.userName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wechat.start-chat." + companion.id.uuidString)
                    }
                }
            }
        }
        .kinGroupedListStyle()
        .navigationTitle("发起聊天")
        .kinInlineNavigationTitle()
        #if os(iOS)
        .searchable(text: $searchText, prompt: "搜索好友")
        #endif
        .navigationDestination(isPresented: $showsChat) {
            ChatView(onOpenSettings: openSettings)
        }
    }

    private var filteredCompanions: [CompanionProfileSummary] {
        let accepted = appModel.companions
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return accepted }
        return accepted.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.userName.localizedCaseInsensitiveContains(query)
        }
    }

    private func openCompanion(_ id: UUID) {
        do {
            try appModel.selectCompanion(id: id)
            showsChat = true
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }
}

/// A hub rather than a dead-end placeholder: existing groups stay visible and
/// the create action is always reachable from the Contacts tab.
struct GroupChatHubView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedGroup: GroupConversationSummary?
    @State private var groupPendingDissolve: GroupConversationSummary?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GroupChatCreateView()
                } label: {
                    HStack(spacing: 12) {
                        GroupChatIconTile(systemImage: "plus", color: AppTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("创建群聊")
                                .foregroundStyle(.primary)
                            Text("选择至少两位已接受的角色")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if appModel.groupConversations.isEmpty {
                Section {
                    VStack(spacing: 9) {
                        Image(systemName: "person.3")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("还没有群聊")
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("创建后会显示在消息列表中")
                            .font(.caption)
                            .foregroundStyle(AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section("已创建") {
                    ForEach(appModel.groupConversations) { group in
                        Button {
                            selectedGroup = group
                        } label: {
                            GroupConversationRow(group: group)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if appModel.isGroupOwner(conversationID: group.conversationID) {
                                Button("解散", role: .destructive) {
                                    groupPendingDissolve = group
                                }
                                .accessibilityIdentifier(
                                    "wechat.group.dissolve." + group.conversationID.uuidString
                                )
                            }
                        }
                    }
                }
            }
        }
        .kinGroupedListStyle()
        .navigationTitle("群聊")
        .kinInlineNavigationTitle()
        .navigationDestination(item: $selectedGroup) { group in
            GroupChatPreviewView(group: group)
        }
        .confirmationDialog(
            groupPendingDissolve.map { "解散“\($0.name)”？" } ?? "解散群聊",
            isPresented: Binding(
                get: { groupPendingDissolve != nil },
                set: { if !$0 { groupPendingDissolve = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("解散群聊", role: .destructive) {
                guard let groupPendingDissolve else { return }
                do {
                    try appModel.dissolveGroup(
                        conversationID: groupPendingDissolve.conversationID
                    )
                    self.groupPendingDissolve = nil
                } catch {
                    appModel.errorMessage = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {
                groupPendingDissolve = nil
            }
        } message: {
            Text("群聊会从列表移除；已有消息和长期记忆仍会保留。")
        }
        .accessibilityIdentifier("wechat.group-chats")
    }
}

/// The creation flow is intentionally local and explicit.  The model owns
/// persistence and validation; this screen only stages the selected accepted
/// role IDs and sends the one create request.
struct GroupChatCreateView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var selectedRoleIDs = Set<UUID>()
    @State private var errorText: String?
    @State private var isCreating = false

    var body: some View {
        List {
            Section {
                TextField("群聊名称（可选）", text: $groupName)

                HStack {
                    Text("已选择")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(selectedRoleIDs.count) 位角色")
                        .foregroundStyle(canCreate ? AppTheme.accent : .secondary)
                }
            } header: {
                Text("群聊信息")
            }

            Section {
                if acceptedCompanions.isEmpty {
                    Text("目前没有处于好友状态的角色。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(acceptedCompanions) { companion in
                        roleSelectionRow(companion)
                    }
                }
            } header: {
                Text("选择成员")
            } footer: {
                Text("至少选择两位已接受的角色。你会自动加入新群聊。")
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .kinGroupedListStyle()
        .navigationTitle("创建群聊")
        .kinInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isCreating ? "创建中…" : "创建") {
                    createGroup()
                }
                .disabled(!canCreate || isCreating)
                .accessibilityIdentifier("wechat.group.create")
            }
        }
        .accessibilityIdentifier("wechat.group.create-screen")
    }

    private var acceptedCompanions: [CompanionProfileSummary] {
        appModel.companions.filter { $0.relationshipState == .accepted }
    }

    private var canCreate: Bool {
        selectedRoleIDs.count >= 2
    }

    private func roleSelectionRow(_ companion: CompanionProfileSummary) -> some View {
        let selected = selectedRoleIDs.contains(companion.id)
        return Button {
            if selected {
                selectedRoleIDs.remove(companion.id)
            } else {
                selectedRoleIDs.insert(companion.id)
            }
        } label: {
            HStack(spacing: 12) {
                CompanionAvatar(
                    size: 42,
                    name: companion.name,
                    imageData: companion.avatarImageData
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(companion.name)
                        .foregroundStyle(.primary)
                    Text("已接受好友")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier("wechat.group.role." + companion.id.uuidString)
    }

    private func createGroup() {
        guard canCreate, !isCreating else { return }
        isCreating = true
        let selectedIDs = acceptedCompanions
            .filter { selectedRoleIDs.contains($0.id) }
            .map(\.id)
        do {
            _ = try appModel.createGroup(
                name: groupName,
                participantRoleIDs: selectedIDs
            )
            errorText = nil
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isCreating = false
    }
}

/// A real WeChat-style group transcript backed by the durable group pipeline.
/// The model selects one or two responders and delivers them sequentially.
struct GroupChatPreviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let group: GroupConversationSummary

    @State private var draft = ""
    @State private var selectedMentionRoleIDs: Set<UUID> = []
    @State private var showsStickerPicker = false
    @State private var showsMoreOptions = false
    @State private var showsGroupInfo = false
    @State private var selectedProfileRoute: GroupProfileRoute?
    @State private var recentStickerIDs: [String] = StickerRecentStore.load()
    @AppStorage(SettingsKeys.typingIndicatorEnabled) private var typingIndicatorEnabled = true
    @FocusState private var inputFocused: Bool

    private let bottomAnchor = "group-chat-bottom"

    var body: some View {
        let presentationSegments = appModel.presentationSegmentsByEventID()
        VStack(spacing: 0) {
            #if os(iOS)
            groupChatHeader
            #endif

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if let error = appModel.errorMessage {
                            StatusBanner(text: error, style: .error) {
                                appModel.errorMessage = nil
                            }
                        }

                        if appModel.groupMessages.isEmpty {
                            Text("群聊已创建，可以开始聊天。")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    AppTheme.secondarySurface,
                                    in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                                )
                                .padding(.top, 28)
                        } else {
                            ForEach(appModel.groupMessages) { message in
                                groupMessage(
                                    message,
                                    persistedSegments: presentationSegments[message.id]
                                )
                                    .id(message.id)
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .frame(maxWidth: AppTheme.contentMaxWidth)
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    appModel.openGroup(conversationID: group.conversationID)
                    if !appModel.isGeneratingGroupReply {
                        markRead()
                    }
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
                .onChange(of: appModel.groupMessages.count) {
                    if !appModel.isGeneratingGroupReply {
                        markRead()
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: appModel.presentationRevision) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: appModel.isGeneratingGroupReply) {
                    if !appModel.isGeneratingGroupReply {
                        markRead()
                    }
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }

            #if os(macOS)
            if showsStickerPicker {
                stickerPicker
                    .transition(.opacity)
            }
            #endif

            if activeMentionQuery != nil {
                GroupMentionPicker(
                    members: mentionCandidates,
                    selectedRoleIDs: selectedMentionRoleIDs,
                    select: insertMention
                )
            }

            if showsMoreOptions {
                attachmentPanel
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ChatInputBar(
                text: $draft,
                isGenerating: appModel.isGeneratingGroupReply,
                isEnabled: true,
                send: send,
                stop: appModel.stopGroupGenerating,
                companionName: displayedGroup.name,
                isStickerPickerPresented: showsStickerPicker,
                isMoreOptionsPresented: showsMoreOptions,
                showStickerPicker: toggleStickerPicker,
                showMoreOptions: toggleMoreOptions,
                focused: $inputFocused
            )
            .onChange(of: draft) { _, _ in
                pruneSelectedMentionRoleIDs()
            }

            #if os(iOS)
            if showsStickerPicker {
                stickerPicker
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
        .background(AppTheme.chatBackground.ignoresSafeArea())
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .restoresWeChatEdgeBackGesture()
        .wechatEdgeBackFallback()
        #else
        .navigationTitle(groupNavigationTitle)
        .kinInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsGroupInfo = true
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("群聊信息")
                .accessibilityIdentifier("wechat.group.info")
            }
        }
        #endif
        .navigationDestination(isPresented: $showsGroupInfo) {
            GroupChatInfoView(group: displayedGroup, onDissolved: closeDissolvedGroup)
        }
        .navigationDestination(item: $selectedProfileRoute) { route in
            CompanionContactView(roleID: route.roleID)
        }
        .onDisappear {
            appModel.closeGroup()
        }
        .accessibilityIdentifier("wechat.group.chat")
    }

    #if os(iOS)
    private var groupChatHeader: some View {
        WeChatBackHeader(
            title: groupNavigationTitle,
            trailingSystemImage: "ellipsis",
            trailingAccessibilityLabel: "群聊信息",
            trailingAction: { showsGroupInfo = true }
        )
        .frame(height: 56)
        .background(AppTheme.chatBackground.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
    }
    #endif

    private var groupNavigationTitle: String {
        typingIndicatorEnabled && appModel.isGeneratingGroupReply
            ? "成员正在输入…"
            : displayedGroup.name
    }

    private var displayedGroup: GroupConversationSummary {
        appModel.groupConversations.first {
            $0.conversationID == group.conversationID
        } ?? group
    }

    private var mentionMembers: [GroupMentionMember] {
        var seen: Set<UUID> = []
        return appModel.groupParticipants(
            conversationID: displayedGroup.conversationID
        ).compactMap { participant in
            guard participant.kind == .companion,
                  let roleID = participant.roleID else {
                return nil
            }
            let resolvedID = RoleScope.resolve(roleID)
            guard seen.insert(resolvedID).inserted else { return nil }
            let companion = (appModel.companions + appModel.archivedCompanions).first {
                RoleScope.resolve($0.id) == resolvedID
            }
            let summaryName = participant.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let name = summaryName.isEmpty ? (companion?.name ?? "群成员") : summaryName
            return GroupMentionMember(
                roleID: resolvedID,
                name: name,
                avatarImageData: companion?.avatarImageData
            )
        }
    }

    /// The picker is intentionally driven by the final token only. A trailing
    /// space closes it after insertion, allowing the next `@` to start a
    /// second, independent selection while retaining the IDs already chosen.
    private var activeMentionQuery: String? {
        guard let last = draft.last, !last.isWhitespace else { return nil }
        guard let token = draft.split(whereSeparator: { $0.isWhitespace }).last,
              token.first == "@" else {
            return nil
        }
        return String(token.dropFirst())
    }

    private var mentionCandidates: [GroupMentionMember] {
        guard let query = activeMentionQuery else { return [] }
        let filtered = mentionMembers.filter { member in
            query.isEmpty || member.name.localizedCaseInsensitiveContains(query)
        }
        return filtered
    }

    private var stickerPicker: some View {
        StickerPickerView(recentStickerIDs: recentStickerIDs) { sticker in
            rememberSticker(sticker.stickerID)
            sendSticker(sticker.stickerID)
        }
    }

    private var attachmentPanel: some View {
        ChatAttachmentPanel(
            onImage: { imageData in
                appModel.sendGroupImage(
                    imageData: imageData,
                    conversationID: group.conversationID
                )
                showsMoreOptions = false
            },
            onFile: { attachment in
                appModel.sendGroupFile(
                    fileData: attachment.data,
                    fileName: attachment.fileName,
                    fileTypeIdentifier: attachment.fileTypeIdentifier,
                    conversationID: group.conversationID
                )
                showsMoreOptions = false
            },
            onError: { message in
                appModel.errorMessage = message
            }
        )
    }

    @ViewBuilder
    private func groupMessage(
        _ message: ConversationEvent,
        persistedSegments: [String]?
    ) -> some View {
        let companion = message.senderRoleID.flatMap { roleID in
            (appModel.companions + appModel.archivedCompanions).first { $0.id == roleID }
        }
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            if message.role == .assistant {
                Text(companion?.name ?? "群成员")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.leading, 48)
            }
            MessageBubble(
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
                companionName: companion?.name ?? "群成员",
                companionAvatarImageData: companion?.avatarImageData,
                companionAvatarAction: message.senderRoleID.map { roleID in
                    { selectedProfileRoute = GroupProfileRoute(roleID: RoleScope.resolve(roleID)) }
                },
                companionAvatarPokeAction: message.senderRoleID.map { roleID in
                    {
                        appModel.pokeGroupCompanion(
                            roleID: RoleScope.resolve(roleID),
                            conversationID: displayedGroup.conversationID
                        )
                    }
                },
                userName: appModel.userProfile.displayName,
                userAvatarImageData: appModel.userProfile.avatarImageData
            )
        }
    }

    private func send() {
        guard appModel.isProviderConfigured else {
            appModel.errorMessage = "请先在设置中填写 API 地址和模型名称。"
            return
        }
        let value = draft
        let mentionedRoleIDs = selectedMentionRoleIDs.intersection(
            Set(mentionMembers.map(\.roleID))
        )
        draft = ""
        selectedMentionRoleIDs = []
        showsStickerPicker = false
        appModel.sendGroupMessage(
            value,
            conversationID: group.conversationID,
            mentionedRoleIDs: mentionedRoleIDs
        )
    }

    private func insertMention(_ member: GroupMentionMember) {
        guard activeMentionQuery != nil else { return }
        let text = draft
        let tokenStart = text.lastIndex(where: { $0.isWhitespace })
            .map { text.index(after: $0) }
            ?? text.startIndex
        guard text[tokenStart...].first == "@" else { return }

        draft = String(text[..<tokenStart]) + "@\(member.name) "
        selectedMentionRoleIDs.insert(member.roleID)
        DispatchQueue.main.async {
            inputFocused = true
        }
    }

    private func pruneSelectedMentionRoleIDs() {
        selectedMentionRoleIDs = selectedMentionRoleIDs.filter { roleID in
            guard let member = mentionMembers.first(where: { $0.roleID == roleID }) else {
                return false
            }
            return draftContainsMention(member)
        }
    }

    private func draftContainsMention(_ member: GroupMentionMember) -> Bool {
        let token = "@\(member.name)"
        guard !token.isEmpty, !draft.isEmpty else { return false }
        var searchStart = draft.startIndex
        while searchStart < draft.endIndex,
              let range = draft.range(
                  of: token,
                  range: searchStart..<draft.endIndex
              ) {
            let leadingBoundary: Bool
            if range.lowerBound == draft.startIndex {
                leadingBoundary = true
            } else {
                let previous = draft[draft.index(before: range.lowerBound)]
                leadingBoundary = previous != "@" && isMentionBoundary(previous)
            }

            let trailingBoundary: Bool
            if range.upperBound == draft.endIndex {
                trailingBoundary = true
            } else {
                let next = draft[range.upperBound]
                trailingBoundary = next != "@" && isMentionBoundary(next)
            }
            if leadingBoundary && trailingBoundary { return true }

            guard range.lowerBound < draft.endIndex else { return false }
            searchStart = draft.index(after: range.lowerBound)
        }
        return false
    }

    private func isMentionBoundary(_ character: Character) -> Bool {
        character.isWhitespace || character.isPunctuation || character.isSymbol
    }

    private func toggleStickerPicker() {
        showsStickerPicker.toggle()
        if showsStickerPicker {
            showsMoreOptions = false
            inputFocused = false
        }
    }

    private func toggleMoreOptions() {
        showsMoreOptions.toggle()
        if showsMoreOptions {
            showsStickerPicker = false
            inputFocused = false
        }
    }

    private func sendSticker(_ stickerID: String) {
        showsStickerPicker = false
        inputFocused = false
        appModel.sendGroupSticker(
            stickerID: stickerID,
            conversationID: group.conversationID
        )
    }

    private func rememberSticker(_ stickerID: String) {
        recentStickerIDs = StickerRecentStore.remember(stickerID)
    }

    private func markRead() {
        appModel.markConversationRead(conversationID: group.conversationID)
    }

    private func closeDissolvedGroup() {
        showsGroupInfo = false
        Task { @MainActor in
            await Task.yield()
            dismiss()
        }
    }
}

private struct GroupProfileRoute: Identifiable, Hashable {
    let roleID: UUID
    var id: UUID { roleID }
}

private struct GroupChatInfoView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext

    let group: GroupConversationSummary
    let onDissolved: () -> Void

    @State private var groupName: String
    @State private var avatarImageData: Data?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var participantPendingRemoval: GroupParticipantSummary?
    @State private var showsMemberPicker = false
    @State private var showsDissolveConfirmation = false

    #if os(iOS)
    @State private var avatarSelection: PhotosPickerItem?
    @State private var avatarLoadID = UUID()
    @State private var isLoadingAvatar = false
    #endif

    init(group: GroupConversationSummary, onDissolved: @escaping () -> Void = {}) {
        self.group = group
        self.onDissolved = onDissolved
        _groupName = State(initialValue: group.name)
        _avatarImageData = State(initialValue: group.avatarImageData)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    GroupAvatarView(
                        group: draftGroup,
                        companions: appModel.companions + appModel.archivedCompanions,
                        userProfile: appModel.userProfile,
                        size: 88
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayedName)
                            .font(.headline)
                            .lineLimit(2)
                        Text("群聊头像")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)

                #if os(iOS)
                PhotosPicker(selection: $avatarSelection, matching: .images) {
                    Label(
                        isLoadingAvatar ? "正在处理…" : "选择群聊头像",
                        systemImage: "photo"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(isLoadingAvatar)
                .accessibilityIdentifier("wechat.group.info.avatar-picker")
                #else
                Text("macOS 当前使用成员合成头像；可在 iPhone 上选择自定义头像。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                #endif

                if avatarImageData != nil {
                    Button("使用成员合成头像", role: .destructive) {
                        avatarImageData = nil
                        markChanged()
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityIdentifier("wechat.group.info.reset-avatar")
                }
            } header: {
                Text("群聊头像")
            } footer: {
                Text("未设置自定义头像时，将显示群成员合成头像。")
            }

            Section("群聊信息") {
                TextField("群聊名称", text: $groupName)
                    .onChange(of: groupName) { _, _ in
                        markChanged()
                    }
                    .accessibilityIdentifier("wechat.group.info.name")
                LabeledContent("创建后更新", value: currentGroup.updatedAt.formatted())
            }

            Section("群成员（\(participants.count)）") {
                ForEach(participants) { participant in
                    participantRow(participant)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canRemove(participant) {
                                Button("移出", role: .destructive) {
                                    participantPendingRemoval = participant
                                }
                                .accessibilityIdentifier(
                                    "wechat.group.member.remove." + participant.id.uuidString
                                )
                            }
                        }
                        .contextMenu {
                            if canRemove(participant) {
                                Button("移出群聊", role: .destructive) {
                                    participantPendingRemoval = participant
                                }
                            }
                        }
                }

                if isGroupOwner {
                    Button {
                        showsMemberPicker = true
                    } label: {
                        Label("添加群成员", systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("wechat.group.member.add")
                }
            }

            if isGroupOwner {
                Section {
                    LabeledContent("我的身份", value: "群主")
                    Button("解散群聊", role: .destructive) {
                        showsDissolveConfirmation = true
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("wechat.group.dissolve")
                } header: {
                    Text("群管理")
                } footer: {
                    Text("解散后，群聊会从列表移除；已有消息和长期记忆仍保留在本机数据中。")
                }
            }

            if let errorText {
                Section {
                    StatusBanner(text: errorText, style: .error) {
                        self.errorText = nil
                    }
                }
            } else if let statusText {
                Section {
                    StatusBanner(text: statusText) {
                        self.statusText = nil
                    }
                }
            }
        }
        .kinGroupedListStyle()
        .navigationTitle("群聊信息")
        .kinInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "保存中…" : "保存", action: save)
                    .disabled(!canSave)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("wechat.group.info.save")
            }
        }
        #if os(iOS)
        .onChange(of: avatarSelection) { _, selection in
            importAvatar(selection)
        }
        #endif
        .confirmationDialog(
            participantPendingRemoval.map { "将“\($0.displayName)”移出群聊？" } ?? "移出群聊",
            isPresented: Binding(
                get: { participantPendingRemoval != nil },
                set: { if !$0 { participantPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移出群聊", role: .destructive) {
                removePendingParticipant()
            }
            Button("取消", role: .cancel) {
                participantPendingRemoval = nil
            }
        } message: {
            Text("移出后，该角色不再接收或回复这个群聊中的新消息。")
        }
        .confirmationDialog(
            "解散“\(currentGroup.name)”？",
            isPresented: $showsDissolveConfirmation,
            titleVisibility: .visible
        ) {
            Button("解散群聊", role: .destructive, action: dissolveGroup)
            Button("取消", role: .cancel) {}
        } message: {
            Text("群聊将从所有聊天入口移除。已有消息和长期记忆不会被物理删除。")
        }
        .sheet(isPresented: $showsMemberPicker) {
            NavigationStack {
                GroupMemberAddView(
                    conversationID: currentGroup.conversationID,
                    onAdded: { count in
                        errorText = nil
                        statusText = "已添加 \(count) 位群成员。"
                    }
                )
            }
        }
        .accessibilityIdentifier("wechat.group.info-screen")
    }

    private var displayedName: String {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? group.name : trimmed
    }

    private var currentGroup: GroupConversationSummary {
        appModel.groupConversations.first {
            $0.conversationID == group.conversationID
        } ?? group
    }

    private var draftGroup: GroupConversationSummary {
        GroupConversationSummary(
            id: currentGroup.id,
            conversationID: currentGroup.conversationID,
            name: displayedName,
            avatarImageData: avatarImageData,
            participantRoleIDs: currentGroup.participantRoleIDs,
            participantNames: currentGroup.participantNames,
            updatedAt: currentGroup.updatedAt
        )
    }

    private var participants: [GroupParticipantSummary] {
        appModel.groupParticipants(conversationID: currentGroup.conversationID)
    }

    private var isGroupOwner: Bool {
        appModel.isGroupOwner(conversationID: currentGroup.conversationID)
    }

    private func canRemove(_ participant: GroupParticipantSummary) -> Bool {
        isGroupOwner && participant.kind == .companion && participant.roleID != nil
    }

    private func participantRow(_ participant: GroupParticipantSummary) -> some View {
        HStack(spacing: 12) {
            if participant.kind == .user {
                UserAvatar(
                    size: 40,
                    name: participant.displayName,
                    imageData: appModel.userProfile.avatarImageData
                )
            } else {
                CompanionAvatar(
                    size: 40,
                    name: participant.displayName,
                    imageData: participant.avatarImageData
                )
            }

            Text(participant.displayName)
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 8)

            if participant.kind == .user {
                Text("群主")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier("wechat.group.member." + participant.id.uuidString)
    }

    private func removePendingParticipant() {
        guard let participant = participantPendingRemoval,
              let roleID = participant.roleID else {
            participantPendingRemoval = nil
            return
        }
        do {
            try appModel.removeGroupParticipant(
                roleID: roleID,
                conversationID: currentGroup.conversationID
            )
            participantPendingRemoval = nil
            errorText = nil
            statusText = "已将“\(participant.displayName)”移出群聊。"
        } catch {
            errorText = error.localizedDescription
            statusText = nil
        }
    }

    private func dissolveGroup() {
        do {
            try appModel.dissolveGroup(conversationID: currentGroup.conversationID)
            errorText = nil
            onDissolved()
        } catch {
            errorText = error.localizedDescription
            statusText = nil
        }
    }

    private var canSave: Bool {
        #if os(iOS)
        let loading = isLoadingAvatar
        #else
        let loading = false
        #endif
        return hasChanges
            && !isSaving
            && !loading
            && !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func markChanged() {
        hasChanges = true
        errorText = nil
        statusText = nil
    }

    private func save() {
        guard !isSaving else { return }
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorText = "群聊名称不能为空。"
            statusText = nil
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let groups = try modelContext.fetch(FetchDescriptor<GroupConversationRecord>())
            guard let record = groups
                .filter({ $0.conversationID == group.conversationID })
                .max(by: isOlderGroupRecord(_:than:)) else {
                errorText = "这个群聊已不存在，请返回后重试。"
                statusText = nil
                return
            }

            let now = Date()
            let title = String(trimmedName.prefix(80))
            record.groupName = title
            record.avatarImageData = avatarImageData
            record.updatedAt = now
            record.revision = max(0, record.revision) + 1

            // ConversationRecord currently has only a visible title field;
            // the durable group avatar lives on GroupConversationRecord.
            let conversations = try modelContext.fetch(
                FetchDescriptor<ConversationRecord>()
            )
            for conversation in conversations where conversation.id == group.conversationID {
                conversation.title = title
                conversation.updatedAt = now
            }

            try modelContext.save()
            appModel.refreshFromStore(force: true)
            groupName = title
            hasChanges = false
            errorText = nil
            statusText = "群聊资料已保存。"
        } catch {
            errorText = "保存群聊资料失败：\(error.localizedDescription)"
            statusText = nil
        }
    }

    private func isOlderGroupRecord(
        _ lhs: GroupConversationRecord,
        than rhs: GroupConversationRecord
    ) -> Bool {
        if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
        return lhs.deviceID < rhs.deviceID
    }

    #if os(iOS)
    private func importAvatar(_ selection: PhotosPickerItem?) {
        guard let selection else { return }
        let loadID = UUID()
        avatarLoadID = loadID
        isLoadingAvatar = true

        Task {
            do {
                guard let source = try await selection.loadTransferable(type: Data.self) else {
                    throw RoleImageProcessorError.unreadableImage
                }
                let processed = try RoleImageProcessor.normalizedJPEG(
                    from: source,
                    kind: .avatar
                )
                guard avatarLoadID == loadID else { return }
                avatarImageData = processed
                markChanged()
            } catch {
                guard avatarLoadID == loadID else { return }
                errorText = error.localizedDescription
                statusText = nil
            }
            guard avatarLoadID == loadID else { return }
            isLoadingAvatar = false
        }
    }
    #endif
}

private struct GroupMemberAddView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let conversationID: UUID
    var onAdded: (Int) -> Void = { _ in }

    @State private var selectedRoleIDs = Set<UUID>()
    @State private var errorText: String?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                if candidates.isEmpty {
                    Text("通讯录里暂时没有可添加的新成员。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(candidates) { companion in
                        selectionRow(companion)
                    }
                }
            } header: {
                Text("选择成员")
            } footer: {
                Text("只能添加已接受的联系人；已在群里的成员不会重复出现。")
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .kinGroupedListStyle()
        .navigationTitle("添加群成员")
        .kinInlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isAdding ? "添加中…" : "添加", action: addSelectedMembers)
                    .disabled(selectedRoleIDs.isEmpty || isAdding)
                    .accessibilityIdentifier("wechat.group.member.add-confirm")
            }
        }
        .accessibilityIdentifier("wechat.group.member.add-screen")
    }

    private var candidates: [CompanionProfileSummary] {
        let existingRoleIDs = Set(appModel.groupParticipants(conversationID: conversationID)
            .compactMap(\.roleID))
        return appModel.companions.filter {
            $0.relationshipState == .accepted && !existingRoleIDs.contains($0.id)
        }
    }

    private func selectionRow(_ companion: CompanionProfileSummary) -> some View {
        let selected = selectedRoleIDs.contains(companion.id)
        return Button {
            if selected {
                selectedRoleIDs.remove(companion.id)
            } else {
                selectedRoleIDs.insert(companion.id)
            }
        } label: {
            HStack(spacing: 12) {
                CompanionAvatar(
                    size: 42,
                    name: companion.name,
                    imageData: companion.avatarImageData
                )
                Text(companion.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23))
                    .foregroundStyle(selected ? AppTheme.accent : AppTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier("wechat.group.member.add." + companion.id.uuidString)
    }

    private func addSelectedMembers() {
        guard !selectedRoleIDs.isEmpty, !isAdding else { return }
        isAdding = true
        do {
            let selectedIDs = candidates
                .filter { selectedRoleIDs.contains($0.id) }
                .map(\.id)
            try appModel.addGroupParticipants(
                roleIDs: selectedIDs,
                conversationID: conversationID
            )
            onAdded(selectedIDs.count)
            dismiss()
        } catch {
            errorText = error.localizedDescription
            isAdding = false
        }
    }
}

/// Shared row used in both the main messages list and the Contacts group hub.
struct GroupConversationRow: View {
    enum Style {
        case list
        case home
    }

    @Environment(AppModel.self) private var appModel

    let group: GroupConversationSummary
    var style: Style = .list
    var isPinned = false

    @ViewBuilder
    var body: some View {
        switch style {
        case .list:
            listRow
        case .home:
            homeRow
        }
    }

    private var listRow: some View {
        rowContent
            .padding(.vertical, 5)
            .contentShape(Rectangle())
    }

    private var homeRow: some View {
        VStack(spacing: 0) {
            rowContent
                .padding(.horizontal, 12)
                .frame(height: 72)
                .background(isPinned ? AppTheme.secondarySurface : AppTheme.rowBackground)

            #if os(iOS)
            WeChatRowDivider(leading: 72)
            #endif
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            GroupAvatarView(
                group: group,
                companions: appModel.companions + appModel.archivedCompanions,
                userProfile: appModel.userProfile,
                size: 48
            )
            .overlay(alignment: .topTrailing) {
                let unread = appModel.unreadCount(forConversationID: group.conversationID)
                if unread > 0 {
                    unreadBadge(unread)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.name)
                        .font(.system(size: 17))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(group.updatedAt, style: .time)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                HStack(spacing: 5) {
                    Text("群聊 · \(group.participantNames.count) 位成员")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .accessibilityLabel("已置顶")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unreadBadge(_ unread: Int) -> some View {
        switch style {
        case .list:
            Text(unread > 99 ? "99+" : "\(unread)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, unread > 9 ? 5 : 0)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red, in: Capsule())
                .offset(x: 6, y: -6)
                .accessibilityLabel("\(unread) 条未读消息")
        case .home:
            Text(unread > 99 ? "99+" : "\(unread)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, unread > 99 ? 4 : 2)
                .background(Color.red, in: Capsule())
                .offset(x: 6, y: -6)
                .accessibilityLabel("\(unread) 条未读消息")
        }
    }
}

private struct GroupAvatarView: View {
    let group: GroupConversationSummary
    let companions: [CompanionProfileSummary]
    let userProfile: UserProfileSummary
    var size: CGFloat

    var body: some View {
        Group {
            if let image = PlatformRoleImage.image(from: group.avatarImageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 2),
                    spacing: 2
                ) {
                    ForEach(Array(members.prefix(4))) { member in
                        if member.isUser {
                            UserAvatar(
                                size: (size - 6) / 2,
                                name: member.name,
                                imageData: member.imageData
                            )
                        } else {
                            CompanionAvatar(
                                size: (size - 6) / 2,
                                name: member.name,
                                imageData: member.imageData
                            )
                        }
                    }
                }
                .padding(2)
                .frame(width: size, height: size)
                .background(AppTheme.secondarySurface)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityLabel("群聊头像")
    }

    private var members: [GroupAvatarMember] {
        let user = GroupAvatarMember(
            id: userProfile.id,
            name: userProfile.displayName,
            imageData: userProfile.avatarImageData,
            isUser: true
        )
        let roles = group.participantRoleIDs.prefix(3).compactMap { roleID in
            companions.first { $0.id == roleID }
        }.map { companion in
            GroupAvatarMember(
                id: companion.id,
                name: companion.name,
                imageData: companion.avatarImageData,
                isUser: false
            )
        }
        return [user] + roles
    }
}

private struct GroupAvatarMember: Identifiable {
    let id: UUID
    let name: String
    let imageData: Data?
    let isUser: Bool
}

private struct GroupMentionMember: Identifiable {
    let roleID: UUID
    let name: String
    let avatarImageData: Data?

    var id: UUID { roleID }
}

private struct GroupMentionPicker: View {
    let members: [GroupMentionMember]
    let selectedRoleIDs: Set<UUID>
    let select: (GroupMentionMember) -> Void

    var body: some View {
        Group {
            if members.isEmpty {
                Text("没有匹配的群成员")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(members) { member in
                            Button {
                                select(member)
                            } label: {
                                HStack(spacing: 6) {
                                    CompanionAvatar(
                                        size: 28,
                                        name: member.name,
                                        imageData: member.avatarImageData
                                    )
                                    Text("@\(member.name)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .lineLimit(1)
                                    if selectedRoleIDs.contains(member.roleID) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    AppTheme.secondarySurface,
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedRoleIDs.contains(member.roleID))
                            .opacity(selectedRoleIDs.contains(member.roleID) ? 0.62 : 1)
                            .accessibilityLabel("提及\(member.name)")
                            .accessibilityIdentifier("wechat.group.mention.\(member.roleID.uuidString)")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.composerBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wechat.group.mention-picker")
    }
}

private struct GroupChatIconTile: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.49, weight: .medium))
            .foregroundStyle(AppTheme.iconOnAccent)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func kinGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func kinInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
