import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum SocialSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondarySurface = Color(nsColor: .underPageBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    #else
    static let page = AppTheme.rootBackground
    static let surface = AppTheme.rowBackground
    static let secondarySurface = AppTheme.secondarySurface
    static let separator = AppTheme.divider
    static let secondaryText = AppTheme.secondaryText
    #endif
}

struct ConversationListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""

    let openSettings: () -> Void

    var body: some View {
        List {
            if matchesSearch {
                NavigationLink {
                    ChatView(onOpenSettings: openSettings)
                } label: {
                    ConversationListRow(
                        name: appModel.persona.name,
                        avatarImageData: appModel.persona.avatarImageData,
                        preview: latestPreview,
                        date: appModel.messages.last?.occurredAt,
                        isWorking: appModel.isGenerating
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle("消息")
        .socialInlineNavigationTitle()
        #if os(iOS)
        .searchable(text: $searchText, prompt: "搜索")
        #endif
        .overlay {
            if !matchesSearch {
                ContentUnavailableView(
                    "没有找到会话",
                    systemImage: "magnifyingglass",
                    description: Text("换一个关键词再试。")
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var matchesSearch: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return appModel.persona.name.localizedCaseInsensitiveContains(query)
            || latestPreview.localizedCaseInsensitiveContains(query)
    }

    private var latestPreview: String {
        guard let message = appModel.messages.last else {
            return appModel.isProviderConfigured ? "我在这里。" : "先配置 API 后开始对话"
        }
        return message.content.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct ConversationListRow: View {
    let name: String
    let avatarImageData: Data?
    let preview: String
    let date: Date?
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 12) {
            CompanionAvatar(size: 48, name: name, imageData: avatarImageData)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if let date {
                        Text(date, style: .time)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

struct ContactsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""

    let openChat: () -> Void

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NewFriendsMigrationView()
                } label: {
                    SocialMenuRow(
                        title: "新的朋友",
                        subtitle: "添加角色、设定人格与相处方式",
                        systemImage: "person.badge.plus",
                        color: .orange
                    )
                }

                NavigationLink {
                    GroupChatHubView()
                } label: {
                    SocialMenuRow(
                        title: "群聊",
                        subtitle: "选择已接受的角色创建群聊",
                        systemImage: "person.3.fill",
                        color: AppTheme.accent
                    )
                }
            }

            Section("联系人") {
                if contactMatchesSearch {
                    NavigationLink {
                        CompanionContactView(
                            roleID: appModel.currentRoleID,
                            openChat: openChat
                        )
                    } label: {
                        HStack(spacing: 12) {
                            CompanionAvatar(
                                size: 42,
                                name: appModel.persona.name,
                                imageData: appModel.persona.avatarImageData
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(appModel.persona.name)
                                    .foregroundStyle(.primary)
                                Text("长期记忆已连接")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .socialGroupedListStyle()
        .navigationTitle("通讯录")
        .socialInlineNavigationTitle()
        #if os(iOS)
        .searchable(text: $searchText, prompt: "搜索角色")
        #endif
    }

    private var contactMatchesSearch: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || appModel.persona.name.localizedCaseInsensitiveContains(query)
    }
}

private struct SocialMenuRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CompanionContactView: View {
    private enum DataAction: String, Identifiable {
        case clearChat
        case clearMemory

        var id: String { rawValue }
        var buttonTitle: String {
            switch self {
            case .clearChat: "清空聊天记录"
            case .clearMemory: "清除全部记忆"
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDeleteConfirmation = false
    @State private var showsPersonaEditor = false
    @State private var recoveryMessage = "我想重新加你为好友。"
    @State private var pendingDataAction: DataAction?
    @State private var dataActionNotice: String?

    let roleID: UUID
    let openChat: (() -> Void)?

    init(roleID: UUID, openChat: (() -> Void)? = nil) {
        self.roleID = RoleScope.resolve(roleID)
        self.openChat = openChat
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView {
                    VStack(spacing: 16) {
                        profileHeader(profile)

                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("角色关系")
                            VStack(spacing: 0) {
                                detailRow("当前状态", value: profile.relationshipState.title)
                                divider
                                detailRow("亲密度", value: affinityDisplayText)
                                divider
                                detailRow(
                                    "世界观",
                                    value: appModel.worldProfileDisplayName(for: roleID)
                                )
                            }
                            .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("动态")
                            NavigationLink {
                                CompanionMomentsTimelineView(
                                    roleID: roleID,
                                    name: profile.name,
                                    avatarImageData: profile.avatarImageData
                                )
                            } label: {
                                momentsRow
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("wechat.contact.moments")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("角色服务")
                            VStack(spacing: 0) {
                                detailRow("长期记忆", value: "\(memoryCount) 条")
                                divider
                                detailRow("AI 连接", value: currentConnectionName)
                            }
                            .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 10))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            sectionTitle("数据管理")
                            VStack(spacing: 0) {
                                dataActionRow("清空聊天记录") {
                                    pendingDataAction = .clearChat
                                }
                                divider
                                dataActionRow("清除全部记忆") {
                                    pendingDataAction = .clearMemory
                                }
                            }
                            .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 10))
                            if let dataActionNotice {
                                Text(dataActionNotice)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .padding(.horizontal, 4)
                            }
                        }

                        VStack(spacing: 10) {
                            if openChat != nil {
                                Button(action: openSelectedChat) {
                                    Label("发消息", systemImage: "bubble.left.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppTheme.accent)
                                .accessibilityIdentifier("wechat.contact.send-message")
                            }

                            Button(action: openPersonaEditor) {
                                Label("角色卡与世界观", systemImage: "person.text.rectangle")
                                    .font(.system(size: 15, weight: .medium))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.primaryText)
                        }

                        if profile.relationshipState == .deleted {
                            recoveryCard
                        }
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                }
                .background(AppTheme.rootBackground.ignoresSafeArea())
            } else {
                ContentUnavailableView("角色资料不可用", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationDestination(isPresented: $showsPersonaEditor) {
            PersonaView()
        }
        .toolbar {
            if appModel.canArchiveCompanion(roleID: roleID) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("删除联系人", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多操作")
                }
            }
        }
        .confirmationDialog(
            "删除联系人后，聊天、记忆和群聊数据会保留。",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除联系人", role: .destructive) {
                do {
                    try appModel.archiveCompanion(roleID: roleID)
                    dismiss()
                } catch {
                    appModel.errorMessage = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert(item: $pendingDataAction) { action in
            Alert(
                title: Text(dataActionTitle(action)),
                message: Text(dataActionMessage(action)),
                primaryButton: .destructive(Text(action.buttonTitle)) {
                    performDataAction(action)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
#if os(iOS)
        .wechatDetailShell(title: "详细资料")
#else
        .navigationTitle("详细资料")
#endif
    }

    private var profile: CompanionProfileSummary? {
        appModel.companionSummary(for: roleID)
    }

    private var roleMoments: [MomentPostSummary] {
        appModel.momentFeed.filter {
            $0.authorKind == .companion && $0.authorRoleID.map(RoleScope.resolve) == RoleScope.resolve(roleID)
        }
    }

    private var memoryCount: Int {
        appModel.activeMemoryCount(for: roleID)
    }

    private func profileHeader(_ profile: CompanionProfileSummary) -> some View {
        HStack(spacing: 16) {
            CompanionAvatar(size: 76, name: profile.name, imageData: profile.avatarImageData)
            VStack(alignment: .leading, spacing: 7) {
                Text(profile.name)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("称呼你为：\(profile.userName)")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(profile.relationshipState.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(profile.relationshipState == .accepted ? AppTheme.accent : AppTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.leading, 4)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 50)
    }

    private func dataActionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.red)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dataActionTitle(_ action: DataAction) -> String {
        let name = profile?.name ?? "该角色"
        switch action {
        case .clearChat:
            return "清空与“\(name)”的聊天记录？"
        case .clearMemory:
            return "清除“\(name)”的全部记忆？"
        }
    }

    private func dataActionMessage(_ action: DataAction) -> String {
        switch action {
        case .clearChat:
            return "只清空该角色的单聊内容。长期记忆、群聊、关系和朋友圈都会保留。此操作不可撤销。"
        case .clearMemory:
            return "清除该角色的长期记忆、记忆证据和摘要。聊天记录、群聊、关系和朋友圈都会保留。此操作不可撤销。"
        }
    }

    private func performDataAction(_ action: DataAction) {
        do {
            switch action {
            case .clearChat:
                let count = try appModel.clearDirectChatHistory(roleID: roleID)
                dataActionNotice = count == 0
                    ? "当前没有可清空的单聊记录。"
                    : "已清空该角色的单聊记录。"
            case .clearMemory:
                let count = try appModel.clearAllMemories(roleID: roleID)
                dataActionNotice = count == 0
                    ? "当前没有长期记忆，已写入防恢复标记。"
                    : "已清除该角色的全部长期记忆。"
            }
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    private var momentsRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 19))
                .foregroundStyle(AppTheme.momentsAccent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text("朋友圈")
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.primaryText)
                Text(momentPreviewText)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("\(roleMoments.count)")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.tertiaryText)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 64)
        .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var momentPreviewText: String {
        guard let latest = roleMoments.max(by: { $0.publishedAt < $1.publishedAt }) else {
            return "还没有动态"
        }
        let text = latest.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "图片动态" : text
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("恢复好友")
                .font(.system(size: 15, weight: .semibold))
            TextField("验证消息", text: $recoveryMessage)
                .textFieldStyle(.roundedBorder)
            Button("添加到通讯录", action: submitRecovery)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
        .padding(16)
        .background(AppTheme.rowBackground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func openSelectedChat() {
        guard let openChat else { return }
        do {
            try appModel.selectCompanion(id: roleID)
            dismiss()
            openChat()
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func openPersonaEditor() {
        do {
            try appModel.selectCompanion(id: roleID)
            showsPersonaEditor = true
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func submitRecovery() {
        do {
            try appModel.submitFriendApplication(roleID: roleID, message: recoveryMessage)
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private var affinityDisplayText: String {
        let score = appModel.effectiveAffinityScore(for: roleID)
        if score.isInfinite {
            return "∞ / 100"
        }
        if AffinityPolicy.band(for: score) == .absoluteObedience {
            return "100 / 100 · 绝对顺从"
        }
        // The strategy layer floors finite scores (e.g. 19.75 -> 19), so the
        // contact card must render the same normalized value rather than
        // rounding up into the next visible number.
        return "\(AffinityPolicy.parameters(for: score).normalizedScore) / 100"
    }

    private var currentConnectionName: String {
        let id = AIConnectionStore.selectedConnectionID(for: roleID)
        return AIConnectionStore.connection(id: id)?.displayName ?? "未配置"
    }
}

struct NewFriendsMigrationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Query private var storedWorldProfiles: [WorldProfileRecord]
    @AppStorage(SettingsKeys.worldviewAutoMatchEnabled)
    private var automaticallyMatchWorldview = true

    var onCreated: (() -> Void)? = nil

    @State private var name = ""
    @State private var relationshipSearchText = ""
    @State private var userName = UserIdentityPolicy.defaultAddress
    @State private var prompt = SettingsStore.defaultPersonaPrompt
    @State private var requestMessage = "你好，可以加个好友吗？"
    @State private var avatarImageData: Data?
    @State private var chatBackgroundImageData: Data?
    @State private var selectedWorldProfileID = WorldProfileRecord.realityID
    @State private var errorText: String?
    @State private var isSaving = false

    var body: some View {
        #if os(iOS)
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    relationshipHub

                    VStack(alignment: .leading, spacing: 10) {
                        Text("创建 AI 角色")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                        RoleMediaPicker(
                            avatarImageData: $avatarImageData,
                            chatBackgroundImageData: $chatBackgroundImageData,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新角色" : name
                        )
                        .padding(12)
                        .background(AppTheme.rowBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 0) {
                        inputRow(title: "角色名", placeholder: "例如：绫音", text: $name)
                        WeChatRowDivider(leading: 92)
                        inputRow(title: "称呼你", placeholder: "例如：主人", text: $userName)
                        WeChatRowDivider(leading: 92)
                        inputRow(title: "申请留言", placeholder: "写一句申请说明", text: $requestMessage)
                    }
                    .background(AppTheme.rowBackground)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("角色卡")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.secondaryText)
                        TextEditor(text: $prompt)
                            .font(.system(size: 16))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .padding(10)
                            .background(AppTheme.rowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("自动匹配世界观", isOn: $automaticallyMatchWorldview)
                            .tint(AppTheme.accent)
                        if automaticallyMatchWorldview {
                            Text("当前匹配：\(automaticWorldProfileName)。创建后仍可为这个角色单独改选。")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondaryText)
                        } else {
                            Picker("指定世界观", selection: $selectedWorldProfileID) {
                                ForEach(availableWorldProfiles, id: \.id) { world in
                                    Text(world.displayName).tag(world.id)
                                }
                            }
                            .pickerStyle(.menu)
                            Text("世界观与角色卡分开保存，同一个世界观可以分配给多个角色。")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    .padding(12)
                    .background(AppTheme.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .padding(.horizontal, 16)

                    Text("创建后立即加入通讯录，并保存一条已接受的好友申请记录。")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }

                    Button(action: submit) {
                        Text(isSaving ? "正在创建…" : "创建 AI 角色")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                canSubmit ? AppTheme.accent : Color.gray.opacity(0.45),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isSaving)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .background(AppTheme.rootBackground.ignoresSafeArea())
        .wechatDetailShell(title: "新的朋友")
        .accessibilityIdentifier("wechat.add-companion")
        #else
        Form {
            Section("搜索角色") {
                TextField("搜索已有角色", text: $relationshipSearchText)
                ForEach(matchingExistingRoles) { role in
                    LabeledContent(role.name, value: role.contactMembership.title)
                }
            }
            if !pendingIncomingApplications.isEmpty {
                Section("收到的申请") {
                    ForEach(pendingIncomingApplications) { application in
                        applicationRow(application)
                    }
                }
            }
            if !appModel.archivedCompanions.isEmpty {
                Section("已归档好友") {
                    ForEach(appModel.archivedCompanions) { role in
                        archivedRoleRow(role)
                    }
                }
            }
            Section("头像与聊天背景") {
                RoleMediaPicker(
                    avatarImageData: $avatarImageData,
                    chatBackgroundImageData: $chatBackgroundImageData,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新角色" : name
                )
                .padding(.vertical, 6)
            }
            Section("创建 AI 角色") {
                TextField("角色名", text: $name)
                TextField("她如何称呼你", text: $userName)
                TextField("申请留言", text: $requestMessage)
            }
            Section("角色卡") {
                TextEditor(text: $prompt)
                    .frame(minHeight: 180)
                Text("新角色使用独立会话、角色卡和长期记忆。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("世界观") {
                Toggle("自动匹配世界观", isOn: $automaticallyMatchWorldview)
                if automaticallyMatchWorldview {
                    Text("当前匹配：\(automaticWorldProfileName)。创建后可随时为该角色单独改选。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("指定世界观", selection: $selectedWorldProfileID) {
                        ForEach(availableWorldProfiles, id: \.id) { world in
                            Text(world.displayName).tag(world.id)
                        }
                    }
                    Text("世界观与角色设定分开保存，也可以被多个角色复用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            Section {
                Button(isSaving ? "正在创建…" : "创建 AI 角色", action: submit)
                    .disabled(!canSubmit || isSaving)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("新的朋友")
        #endif
    }

    private var matchingExistingRoles: [CompanionProfileSummary] {
        let roles = appModel.companions + appModel.archivedCompanions
        let query = relationshipSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(roles.prefix(8)) }
        return roles.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.userName.localizedCaseInsensitiveContains(query)
        }
    }

    private var availableWorldProfiles: [WorldProfileRecord] {
        var winners: [UUID: WorldProfileRecord] = [:]
        for record in storedWorldProfiles {
            guard let current = winners[record.id] else {
                winners[record.id] = record
                continue
            }
            if record.revision > current.revision
                || (record.revision == current.revision && record.updatedAt > current.updatedAt)
                || (record.revision == current.revision
                    && record.updatedAt == current.updatedAt
                    && record.deviceID > current.deviceID) {
                winners[record.id] = record
            }
        }
        return winners.values.sorted {
            if ($0.id == WorldProfileRecord.realityID) != ($1.id == WorldProfileRecord.realityID) {
                return $0.id == WorldProfileRecord.realityID
            }
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var automaticWorldProfileName: String {
        let id = WorldProfileCatalog.bestMatchID(
            roleName: name,
            prompt: prompt,
            worlds: availableWorldProfiles.map(AyaneWorldProfileExport.init)
        )
        return availableWorldProfiles.first { $0.id == id }?.displayName ?? "现实世界"
    }

    private var pendingIncomingApplications: [FriendApplicationSummary] {
        appModel.friendApplications.filter {
            $0.direction == .incoming && $0.status == .pending
        }
    }

    private func roleName(_ roleID: UUID) -> String {
        (appModel.companions + appModel.archivedCompanions)
            .first { $0.id == roleID }?.name ?? "好友"
    }

    @ViewBuilder
    private var relationshipHub: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("搜索已有角色", text: $relationshipSearchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(AppTheme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if !pendingIncomingApplications.isEmpty {
                Text("收到的申请")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                ForEach(pendingIncomingApplications) { application in
                    applicationRow(application)
                }
            }

            if !appModel.archivedCompanions.isEmpty {
                Text("已归档好友")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                ForEach(appModel.archivedCompanions) { role in
                    archivedRoleRow(role)
                }
            }

            if !matchingExistingRoles.isEmpty {
                Text("角色")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                ForEach(matchingExistingRoles) { role in
                    HStack {
                        CompanionAvatar(size: 34, name: role.name, imageData: role.avatarImageData)
                        Text(role.name)
                        Spacer()
                        Text(role.contactMembership.title)
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(AppTheme.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func applicationRow(_ application: FriendApplicationSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(roleName(application.roleID))
                .font(.system(size: 16, weight: .medium))
            if !application.message.isEmpty {
                Text(application.message)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            HStack {
                Button("拒绝") {
                    do { try appModel.resolveFriendApplication(id: application.id, accept: false) }
                    catch { errorText = error.localizedDescription }
                }
                .buttonStyle(.bordered)
                Button("接受") {
                    do { try appModel.resolveFriendApplication(id: application.id, accept: true) }
                    catch { errorText = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
        .padding(12)
        .background(AppTheme.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func archivedRoleRow(_ role: CompanionProfileSummary) -> some View {
        HStack {
            CompanionAvatar(size: 34, name: role.name, imageData: role.avatarImageData)
            Text(role.name)
            Spacer()
            Button("重新添加") {
                do { try appModel.restoreArchivedCompanion(roleID: role.id) }
                catch { errorText = error.localizedDescription }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
    }

    #if os(iOS)
    private func inputRow(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.primaryText)
                .frame(width: 68, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }
    #endif

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requestMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (automaticallyMatchWorldview
                || availableWorldProfiles.contains { $0.id == selectedWorldProfileID })
    }

    private func submit() {
        guard canSubmit, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try appModel.createCompanion(
                name: name,
                userName: userName,
                prompt: prompt,
                avatarImageData: avatarImageData,
                chatBackgroundImageData: chatBackgroundImageData,
                requestMessage: requestMessage,
                worldProfileID: automaticallyMatchWorldview ? nil : selectedWorldProfileID
            )
            errorText = nil
            if appModel.canSendMessages, let onCreated {
                onCreated()
            } else if appModel.canSendMessages {
                dismiss()
            } else {
                errorText = appModel.relationshipStatusText
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct DeferredGroupChatView: View {
    var body: some View {
        ContentUnavailableView {
            Label("群聊稍后开放", systemImage: "person.3")
        } description: {
            Text("需要先确定谁应回复、回复顺序、沉默条件和共享记忆范围；当前版本不会用随机点名冒充完成。")
        }
#if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wechatDetailShell(title: "群聊")
#else
        .navigationTitle("群聊")
#endif
    }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        #if os(macOS)
        macDiscover
        #else
        List {
            NavigationLink {
                MomentsMigrationView()
            } label: {
                SocialMenuRow(
                    title: "朋友圈",
                    subtitle: "角色动态与定时发布",
                    systemImage: "camera.fill",
                    color: .blue
                )
            }
        }
        .socialGroupedListStyle()
        .navigationTitle("发现")
        .socialInlineNavigationTitle()
        #endif
    }

    #if os(macOS)
    private var macDiscover: some View {
        VStack(spacing: 0) {
            HStack {
                Text("发现")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
            .background(SocialSemantic.surface)

            Rectangle()
                .fill(SocialSemantic.separator)
                .frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        Group {
                            if let image = PlatformRoleImage.image(
                                from: appModel.userProfile.momentsCoverImageData
                            ) {
                                image.resizable().scaledToFill()
                            } else {
                                Image("MomentsCover").resizable().scaledToFill()
                            }
                        }
                        .frame(width: 190, height: 112)
                        .clipped()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("朋友圈")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("角色动态、图片和定时发布")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            NavigationLink {
                                MomentsMigrationView()
                            } label: {
                                Label("打开朋友圈", systemImage: "arrow.right.circle")
                                    .font(.callout.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityIdentifier("wechat.discover.open-moments")
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(20)

                    Rectangle()
                        .fill(SocialSemantic.separator)
                        .frame(height: 0.5)

                    Text("发现入口")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                    macDiscoverEntry(
                        title: "朋友圈",
                        subtitle: "角色动态与互动消息",
                        systemImage: "camera.fill",
                        tint: AppTheme.accent,
                        active: true
                    )

                    ForEach(macDeferredDiscoverItems, id: \.title) { item in
                        macDiscoverEntry(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            tint: item.tint,
                            active: false
                        )
                    }

                    Text("当前版本先聚焦可核对的朋友圈与角色关系；其余入口会在对应能力准备好后开放。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .padding(.bottom, 26)
                }
                .frame(maxWidth: 760, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(SocialSemantic.page)
        }
        .background(SocialSemantic.page)
        .navigationTitle("发现")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    MomentsMigrationView()
                } label: {
                    Label("朋友圈", systemImage: "camera.fill")
                }
                .accessibilityIdentifier("wechat.discover.toolbar-moments")
            }
        }
    }

    private var macDeferredDiscoverItems: [(title: String, subtitle: String, systemImage: String, tint: Color)] {
        [
            ("视频号", "视频内容稍后开放", "play.rectangle", .orange),
            ("扫一扫", "本机二维码入口稍后开放", "qrcode.viewfinder", .blue),
            ("听一听", "声音内容稍后开放", "music.note", .pink),
            ("看一看", "精选内容稍后开放", "sparkles", .yellow),
            ("搜一搜", "本地搜索稍后开放", "magnifyingglass", .red),
            ("附近的人", "位置能力稍后开放", "location.circle", .cyan)
        ]
    }

    @ViewBuilder
    private func macDiscoverEntry(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        active: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? .white : tint)
                .frame(width: 36, height: 36)
                .background(active ? tint : tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: active ? .medium : .regular))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: active ? "chevron.right" : "lock")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .background(active ? AppTheme.accent.opacity(0.10) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SocialSemantic.separator.opacity(0.72))
                .frame(height: 0.5)
                .padding(.leading, 68)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(active ? "可打开" : "稍后开放")
    }
    #endif
}

private struct LegacyMomentsMigrationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRoleID = RoleScope.legacyRoleID
    @State private var instruction = ""
    @State private var scheduledAt = Date().addingTimeInterval(5 * 60)
    @State private var localStatus: String?
    @State private var showsScheduler = false

    var body: some View {
        #if os(iOS)
        iOSMoments
        #else
        macMoments
        #endif
    }

    #if os(iOS)
    private var iOSMoments: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        momentsCover

                        if let status = localStatus ?? appModel.momentStatusText {
                            Text(status)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 72)
                                .padding(.bottom, 18)
                        }

                        if !pendingTasks.isEmpty {
                            momentSection(title: "待发布", tasks: pendingTasks)
                            Color.clear.frame(height: 10)
                        }

                        if publishedTasks.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "camera")
                                    .font(.system(size: 31, weight: .light))
                                Text("还没有朋友圈")
                                    .font(.system(size: 14))
                            }
                            .foregroundStyle(AppTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 62)
                        } else {
                            ForEach(publishedTasks) { task in
                                MomentFeedRow(
                                    task: task,
                                    companionName: companionName(for: task.roleID),
                                    avatarImageData: companionAvatar(for: task.roleID)
                                )
                                WeChatRowDivider(leading: 70)
                            }
                        }

                        Text("定时任务会持久保存；应用再次打开时会补执行。当前仅生成文字动态。")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 72)
                            .padding(.vertical, 24)
                    }
                }
                .background(AppTheme.rowBackground)
                .ignoresSafeArea(edges: .top)

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")

                    Spacer()

                    Button {
                        showsScheduler = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("创建定时朋友圈")
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(.horizontal, 2)
                .padding(.top, geometry.safeAreaInsets.top)
            }
        }
        .background(AppTheme.rowBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showsScheduler) {
            schedulerSheet
        }
        .onAppear(perform: chooseInitialRole)
    }

    private var momentsCover: some View {
        ZStack(alignment: .bottomTrailing) {
            Image("MomentsCover")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 350)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.30), .clear, .black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 12) {
                Spacer()
                Text(appModel.persona.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    .padding(.bottom, 34)

                CompanionAvatar(
                    size: 72,
                    name: appModel.persona.name,
                    imageData: appModel.persona.avatarImageData
                )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.white.opacity(0.78), lineWidth: 1)
                    }
                    .offset(y: 28)
            }
            .padding(.trailing, 20)
        }
        .frame(height: 350)
        .padding(.bottom, 44)
    }

    private var schedulerSheet: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("定时发布")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)

                HStack {
                    Button("取消") {
                        showsScheduler = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    Spacer()
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 8)
            .background(AppTheme.barBackground)
            .overlay(alignment: .bottom) {
                Rectangle().fill(AppTheme.divider).frame(height: 0.5)
            }

            ScrollView {
                VStack(spacing: 14) {
                    scheduleCard

                    Text("iOS 无法保证应用退出后准点运行；再次打开应用时会自动补执行。当前只生成文字，不请求图片。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }
                .padding(.top, 12)
            }
        }
        .background(AppTheme.rootBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
    #endif

    #if os(macOS)
    private var macMoments: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                scheduleCard

                if let status = localStatus ?? appModel.momentStatusText {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                if !pendingTasks.isEmpty {
                    momentSection(title: "待执行", tasks: pendingTasks)
                }

                if !publishedTasks.isEmpty {
                    momentSection(title: "朋友圈", tasks: publishedTasks)
                }

                if pendingTasks.isEmpty && publishedTasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "camera")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("还没有朋友圈")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }

                Text("任务会持久保存。iOS 无法保证应用退出后准点运行；再次打开应用时会自动补执行。当前只生成文字，不请求图片。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
        .background(AppTheme.rootBackground)
        .onAppear(perform: chooseInitialRole)
        .navigationTitle("朋友圈")
    }
    #endif

    private var acceptedCompanions: [CompanionProfileSummary] {
        appModel.companions
    }

    private var pendingTasks: [CompanionMomentTaskSummary] {
        appModel.momentTasks
            .filter { $0.state == .scheduled || $0.state == .running }
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private var publishedTasks: [CompanionMomentTaskSummary] {
        appModel.momentTasks
            .filter { $0.state == .published }
            .sorted {
                ($0.publishedAt ?? $0.scheduledAt) > ($1.publishedAt ?? $1.scheduledAt)
            }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("定时发布")
                    .font(.headline)
                Spacer()
                if appModel.isProcessingMoments {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if acceptedCompanions.isEmpty {
                Text("目前没有可用角色，暂时不能创建任务。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("角色", selection: $selectedRoleID) {
                    ForEach(acceptedCompanions) { companion in
                        Text(companion.name).tag(companion.id)
                    }
                }

                TextField("例如：傍晚发一条关于今天心情的朋友圈", text: $instruction, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)

                DatePicker(
                    "发布时间",
                    selection: $scheduledAt,
                    displayedComponents: [.date, .hourAndMinute]
                )

                Button("保存定时任务") {
                    if scheduleMoment() {
                        #if os(iOS)
                        showsScheduler = false
                        #endif
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .background(AppTheme.rowBackground)
    }

    @ViewBuilder
    private func momentSection(
        title: String,
        tasks: [CompanionMomentTaskSummary]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            ForEach(tasks) { task in
                MomentTaskRow(
                    task: task,
                    companionName: companionName(for: task.roleID),
                    avatarImageData: companionAvatar(for: task.roleID),
                    cancel: task.state == .published ? nil : {
                        do {
                            try appModel.cancelMoment(id: task.id)
                            localStatus = "已取消定时任务。"
                        } catch {
                            localStatus = error.localizedDescription
                        }
                    }
                )
                if task.id != tasks.last?.id {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(AppTheme.rowBackground)
    }

    private func companionName(for roleID: UUID) -> String {
        appModel.companions.first { $0.id == roleID }?.name ?? "角色"
    }

    private func companionAvatar(for roleID: UUID) -> Data? {
        appModel.companions.first { $0.id == roleID }?.avatarImageData
    }

    private func chooseInitialRole() {
        if acceptedCompanions.contains(where: { $0.id == appModel.currentRoleID }) {
            selectedRoleID = appModel.currentRoleID
        } else if let first = acceptedCompanions.first {
            selectedRoleID = first.id
        }
    }

    @discardableResult
    private func scheduleMoment() -> Bool {
        do {
            try appModel.scheduleMoment(
                roleID: selectedRoleID,
                instruction: instruction,
                scheduledAt: scheduledAt
            )
            instruction = ""
            scheduledAt = Date().addingTimeInterval(5 * 60)
            localStatus = "定时任务已保存。"
            return true
        } catch {
            localStatus = error.localizedDescription
            return false
        }
    }
}

#if os(iOS)
private struct MomentFeedRow: View {
    let task: CompanionMomentTaskSummary
    let companionName: String
    let avatarImageData: Data?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanionAvatar(size: 44, name: companionName, imageData: avatarImageData)

            VStack(alignment: .leading, spacing: 7) {
                Text(companionName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.56, blue: 0.70))

                Text(task.resultText)
                    .font(.system(size: 16))
                    .lineSpacing(3)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(momentDateText)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.rowBackground)
        .accessibilityElement(children: .combine)
    }

    private var momentDateText: String {
        (task.publishedAt ?? task.scheduledAt)
            .formatted(date: .abbreviated, time: .shortened)
    }
}
#endif

private struct MomentTaskRow: View {
    let task: CompanionMomentTaskSummary
    let companionName: String
    let avatarImageData: Data?
    let cancel: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompanionAvatar(size: 40, name: companionName, imageData: avatarImageData)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(companionName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(task.state.title)
                        .font(.caption)
                        .foregroundStyle(task.state == .published ? AppTheme.accent : .secondary)
                }

                Text(task.state == .published ? task.resultText : task.instruction)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(momentDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !task.lastError.isEmpty, task.state != .published {
                    Text(task.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let cancel {
                    Button("取消任务", action: cancel)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var momentDateText: String {
        let date = task.publishedAt ?? task.scheduledAt
        let prefix = task.state == .published ? "实际发布" : "计划发布"
        return "\(prefix)：\(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct MeView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    UserAvatar(
                        size: 62,
                        name: appModel.userProfile.displayName,
                        imageData: appModel.userProfile.avatarImageData
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(appModel.userProfile.displayName)
                            .font(.title3.weight(.semibold))
                        Text("仅本机个人使用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                NavigationLink {
                    UserMomentsTimelineView()
                } label: {
                    SocialMenuRow(
                        title: "我的朋友圈",
                        subtitle: "查看自己发布的全部动态",
                        systemImage: "photo.on.rectangle",
                        color: .blue
                    )
                }

                NavigationLink {
                    MemoryView()
                } label: {
                    SocialMenuRow(
                        title: "世界书与长期记忆",
                        subtitle: "查看证据、冲突与遗忘记录",
                        systemImage: "books.vertical.fill",
                        color: .brown
                    )
                }

                NavigationLink {
                    PersonaView()
                } label: {
                    SocialMenuRow(
                        title: "角色与对话方式",
                        subtitle: "人格提示、称呼与行为边界",
                        systemImage: "person.text.rectangle.fill",
                        color: .purple
                    )
                }
            }

            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    SocialMenuRow(
                        title: "设置",
                        subtitle: "API、同步、隐私与数据管理",
                        systemImage: "gearshape.fill",
                        color: .gray
                    )
                }
            }
        }
        .socialGroupedListStyle()
        .navigationTitle("我")
        .socialInlineNavigationTitle()
    }
}

private extension View {
    @ViewBuilder
    func socialGroupedListStyle() -> some View {
        #if os(macOS)
        listStyle(.inset)
        #else
        listStyle(.insetGrouped)
        #endif
    }

    @ViewBuilder
    func socialInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
