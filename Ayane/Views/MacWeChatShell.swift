import SwiftUI

#if os(macOS)

/// A compact macOS WeChat-shaped frame for the local Ayane experience.
///
/// The frame deliberately owns only the navigation chrome. Conversation,
/// contacts, discovery, profile, memory and settings remain the app's existing
/// views so the shell cannot accidentally invent a second source of truth.
struct MacWeChatShellView: View {
    @Binding private var selection: AppSection

    @State private var destination: MacWeChatDestination
    @State private var searchText = ""

    init(selection: Binding<AppSection>) {
        _selection = selection
        _destination = State(initialValue: .chat)
    }

    var body: some View {
        HStack(spacing: 0) {
            MacWeChatRail(
                selection: $selection,
                openSettings: openSettings
            )

            MacWeChatSessionColumn(
                section: $selection,
                destination: $destination,
                searchText: $searchText
            )

            MacWeChatDetailColumn(
                destination: destination,
                openChat: openChat,
                openSettings: openSettings
            )
        }
        // Keep the approved 946×642 design as the minimum while allowing the
        // detail column to grow naturally on larger windows.
        .frame(minWidth: 946, minHeight: 642)
        .background(MacWeChatStyle.detailBackground)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            destination = defaultDestination(for: selection)
        }
        .onChange(of: selection) { _, newSelection in
            destination = defaultDestination(for: newSelection)
            searchText = ""
        }
    }

    private func defaultDestination(for section: AppSection) -> MacWeChatDestination {
        switch section {
        case .chats: .chat
        case .contacts: .companionContact
        case .discover: .moments
        case .me: .meHome
        }
    }

    private func openChat() {
        selection = .chats
        destination = .chat
    }

    private func openSettings() {
        selection = .me
        // Chat's empty-state action is specifically asking for the provider
        // setup, so land on the service-only form rather than the full
        // personal settings document.
        destination = .settingsAPI
    }
}

private enum MacWeChatDestination: Hashable {
    case chat
    case companionContact
    case newFriends
    case groupChat
    case groupChatCreate
    case groupChatPreview(UUID)
    case startChat
    case discoverHome
    case moments
    case meHome
    case scheduledTasks
    case memory
    case persona
    case settings
    case settingsAPI
    case settingsChat
    case settingsProactive
    case settingsData
    case worldProfile
}

private enum MacWeChatStyle {
    static let selectedGreen = AppTheme.accent
    static let selectedGreenSoft = AppTheme.accent.opacity(0.12)
    static let railBackground = AppTheme.railBackground
    static let sessionBackground = AppTheme.sessionBackground
    static let detailBackground = AppTheme.chatBackground
    static let secondarySurface = AppTheme.secondarySurface
    static let separator = AppTheme.divider
    static let incomingBubble = AppTheme.incomingBubble
    static let outgoingBubble = AppTheme.outgoingBubble
    static let primaryText = AppTheme.primaryText
    static let secondaryText = AppTheme.secondaryText
    static let iconOnAccent = AppTheme.iconOnAccent
    // Keep system semantic colors dynamic so feature tiles and badges remain
    // legible across the user's current macOS appearance.
    static let badgeBackground = Color(nsColor: .systemRed)
    static let featureOrange = Color(nsColor: .systemOrange)
    static let featureBlue = Color(nsColor: .systemBlue)
    static let featureBrown = Color(nsColor: .systemBrown)
    static let featurePurple = Color(nsColor: .systemPurple)
    static let featureTeal = Color(nsColor: .systemTeal)
}

private struct MacWeChatRail: View {
    @Binding var selection: AppSection

    let openSettings: () -> Void

    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            Button {
                selection = .me
            } label: {
                CompanionAvatar(size: 36, name: appModel.userProfile.displayName)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(MacWeChatStyle.iconOnAccent.opacity(0.75), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我")
            .help("我")

            Spacer()
                .frame(height: 20)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    railButton(for: section)
                }
            }

            Spacer(minLength: 12)

            Button(action: openSettings) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(MacWeChatStyle.primaryText.opacity(0.72))
                    .frame(width: 42, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("设置")
            .help("设置")
        }
        .padding(.top, 40)
        .padding(.bottom, 10)
        .frame(width: 60)
        .background {
            Rectangle()
                .fill(MacWeChatStyle.railBackground)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MacWeChatStyle.separator.opacity(0.82))
                .frame(width: 1)
        }
    }

    private func railButton(for section: AppSection) -> some View {
        Button {
            selection = section
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(railAssetName(for: section))
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 23, height: 23)
                    .foregroundStyle(
                        selection == section
                            ? MacWeChatStyle.selectedGreen
                            : MacWeChatStyle.primaryText.opacity(0.65)
                    )

                if let unread = unreadCount(for: section), unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MacWeChatStyle.iconOnAccent)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, unread > 9 ? 3 : 2)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(MacWeChatStyle.badgeBackground, in: Capsule())
                        .offset(x: 8, y: -5)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 42, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .help(section.title)
    }

    private func railAssetName(for section: AppSection) -> String {
        switch section {
        case .chats: "WeChatTabChats"
        case .contacts: "WeChatTabContacts"
        case .discover: "WeChatTabDiscover"
        case .me: "WeChatTabMe"
        }
    }

    private func unreadCount(for section: AppSection) -> Int? {
        switch section {
        case .chats:
            appModel.chatUnreadCount
        case .discover:
            appModel.momentsUnreadCount
        case .contacts, .me:
            nil
        }
    }
}

private struct MacWeChatSessionColumn: View {
    @Environment(AppModel.self) private var appModel

    @Binding var section: AppSection

    @Binding var destination: MacWeChatDestination
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            switch section {
            case .chats:
                MacWeChatSearchHeader(
                    text: $searchText,
                    prompt: "搜索",
                    actions: chatHeaderActions
                )
            case .contacts:
                MacWeChatSearchHeader(
                    text: $searchText,
                    prompt: "搜索联系人",
                    title: "通讯录",
                    actions: [],
                    directAction: { destination = .newFriends },
                    directActionAccessibilityLabel: "添加角色",
                    directActionIdentifier: "wechat.mac.contacts.add"
                )
            case .discover:
                MacWeChatTitleHeader(title: "发现")
            case .me:
                MacWeChatTitleHeader(title: "我")
            }

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    sectionContent
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 240)
        .background(MacWeChatStyle.sessionBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MacWeChatStyle.separator)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .chats:
            if matchingGroups.isEmpty && matchingCompanions.isEmpty {
                emptySearchResult
            } else {
                ForEach(matchingGroups) { group in
                    groupConversationRow(group)
                }
                if !matchingGroups.isEmpty && !matchingCompanions.isEmpty {
                    Rectangle()
                        .fill(MacWeChatStyle.separator)
                        .frame(height: 0.5)
                }
                ForEach(matchingCompanions) { companion in
                    conversationRow(companion)
                }
            }
        case .contacts:
            contactsContent
        case .discover:
            discoverContent
        case .me:
            meContent
        }
    }

    private func conversationRow(_ companion: CompanionProfileSummary) -> some View {
        Button {
            do {
                try appModel.selectCompanion(id: companion.id)
                destination = .chat
            } catch {
                appModel.errorMessage = error.localizedDescription
            }
        } label: {
            MacWeChatConversationRow(
                name: companion.name,
                avatarImageData: companion.avatarImageData,
                preview: latestPreview(for: companion),
                date: appModel.directConversationActivity(roleID: companion.id)?.lastActivityAt,
                isSelected: destination == .chat && companion.id == appModel.currentRoleID,
                isWorking: companion.id == appModel.currentRoleID && appModel.isGenerating,
                unreadCount: appModel.unreadCount(forConversationID: nil, roleID: companion.id)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("与\(companion.name)的会话")
        .accessibilityValue(latestPreview(for: companion))
        .accessibilityAddTraits(
            destination == .chat && companion.id == appModel.currentRoleID ? .isSelected : []
        )
    }

    private func groupConversationRow(_ group: GroupConversationSummary) -> some View {
        Button {
            destination = .groupChatPreview(group.id)
        } label: {
            MacWeChatGroupRow(
                group: group,
                isSelected: destination == .groupChatPreview(group.id),
                unreadCount: appModel.unreadCount(forConversationID: group.conversationID)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(group.name)
        .accessibilityValue("群聊，\(group.participantNames.count) 位成员")
        .accessibilityAddTraits(
            destination == .groupChatPreview(group.id) ? .isSelected : []
        )
    }

    private var contactsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("功能")

            MacWeChatFeatureRow(
                title: "新的朋友",
                subtitle: "添加角色并发送好友申请",
                systemImage: "person.badge.plus",
                tint: MacWeChatStyle.featureOrange,
                isSelected: destination == .newFriends,
                status: nil
            ) {
                destination = .newFriends
            }

            MacWeChatFeatureRow(
                title: "群聊",
                subtitle: "查看已创建群聊并创建新群",
                systemImage: "person.3.fill",
                tint: MacWeChatStyle.selectedGreen,
                isSelected: destination == .groupChat,
                status: nil
            ) {
                destination = .groupChat
            }

            sectionLabel("联系人")
            if matchingCompanions.isEmpty {
                emptySearchResult
            } else {
                ForEach(matchingCompanions) { companion in
                    Button {
                        do {
                            try appModel.selectCompanion(id: companion.id)
                            destination = .companionContact
                        } catch {
                            appModel.errorMessage = error.localizedDescription
                        }
                    } label: {
                        MacWeChatContactRow(
                            name: companion.name,
                            avatarImageData: companion.avatarImageData,
                            subtitle: companion.relationshipState.canChat
                                ? "长期记忆独立保存"
                                : companion.relationshipState.title,
                            isSelected: destination == .companionContact
                                && companion.id == appModel.currentRoleID
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(companion.name)
                    .accessibilityValue(
                        companion.relationshipState.canChat
                            ? "长期记忆独立保存"
                            : companion.relationshipState.title
                    )
                    .accessibilityAddTraits(
                        destination == .companionContact
                            && companion.id == appModel.currentRoleID ? .isSelected : []
                    )
                }
            }
        }
    }

    private var discoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("发现")

            MacWeChatFeatureRow(
                title: "朋友圈",
                subtitle: "发布动态、查看互动与通知",
                systemImage: "camera.fill",
                tint: MacWeChatStyle.featureBlue,
                isSelected: destination == .moments,
                status: appModel.momentsUnreadCount > 0
                    ? "\(appModel.momentsUnreadCount) 条未读"
                    : nil
            ) {
                destination = .moments
            }
        }
    }

    private var meContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if matchesMe {
                Button {
                    destination = .meHome
                } label: {
                    MacWeChatProfileRow(
                        name: appModel.userProfile.displayName,
                        subtitle: "仅本机个人使用",
                        isSelected: destination == .meHome
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我，\(appModel.userProfile.displayName)")
                .accessibilityAddTraits(destination == .meHome ? .isSelected : [])
            }

            sectionLabel("本机内容")

            MacWeChatFeatureRow(
                title: "定时任务",
                subtitle: "安排朋友圈、生日与执行时间",
                systemImage: "calendar.badge.clock",
                tint: MacWeChatStyle.featureTeal,
                isSelected: destination == .scheduledTasks
            ) {
                destination = .scheduledTasks
            }

            MacWeChatFeatureRow(
                title: "长期记忆",
                subtitle: "查看证据、冲突与遗忘记录",
                systemImage: "books.vertical.fill",
                tint: MacWeChatStyle.featureBrown,
                isSelected: destination == .memory
            ) {
                destination = .memory
            }

            MacWeChatFeatureRow(
                title: "角色与对话方式",
                subtitle: "人格提示、称呼与亲密表达",
                systemImage: "person.text.rectangle.fill",
                tint: MacWeChatStyle.featurePurple,
                isSelected: destination == .persona
            ) {
                destination = .persona
            }

            MacWeChatFeatureRow(
                title: "API 与模型",
                subtitle: "提供商、地址、模型与连接测试",
                systemImage: "key.fill",
                tint: MacWeChatStyle.featureOrange,
                isSelected: destination == .settingsAPI
            ) {
                destination = .settingsAPI
            }

            MacWeChatFeatureRow(
                title: "聊天显示",
                subtitle: "流式回复、输入状态与发送节奏",
                systemImage: "bubble.left.and.bubble.right.fill",
                tint: MacWeChatStyle.featureBlue,
                isSelected: destination == .settingsChat
            ) {
                destination = .settingsChat
            }

            MacWeChatFeatureRow(
                title: "主动消息",
                subtitle: "角色主动联系与静默时段",
                systemImage: "bell.badge.fill",
                tint: MacWeChatStyle.featurePurple,
                isSelected: destination == .settingsProactive
            ) {
                destination = .settingsProactive
            }

            MacWeChatFeatureRow(
                title: "世界观库",
                subtitle: "角色独立绑定，新增好友可自动匹配",
                systemImage: "globe.asia.australia.fill",
                tint: MacWeChatStyle.featureTeal,
                isSelected: destination == .worldProfile
            ) {
                destination = .worldProfile
            }

            MacWeChatFeatureRow(
                title: "设置与数据",
                subtitle: "同步、隐私、导入导出与清除",
                systemImage: "gearshape.fill",
                tint: MacWeChatStyle.secondaryText,
                isSelected: destination == .settings || destination == .settingsData
            ) {
                destination = .settingsData
            }
        }
    }

    private var chatHeaderActions: [MacWeChatMenuAction] {
        [
            MacWeChatMenuAction(
                title: "发起聊天",
                systemImage: "bubble.left",
                action: { destination = .startChat }
            ),
            MacWeChatMenuAction(
                title: "添加角色",
                systemImage: "person.badge.plus",
                action: { destination = .newFriends }
            ),
            MacWeChatMenuAction(
                title: "创建群聊",
                systemImage: "person.3",
                action: { destination = .groupChatCreate }
            )
        ]
    }

    private var contactsHeaderActions: [MacWeChatMenuAction] {
        [
            MacWeChatMenuAction(
                title: "添加角色",
                systemImage: "person.badge.plus",
                action: { destination = .newFriends }
            ),
            MacWeChatMenuAction(
                title: "创建群聊",
                systemImage: "person.3",
                action: { destination = .groupChatCreate }
            )
        ]
    }

    private var emptySearchResult: some View {
        Text("没有找到匹配内容")
            .font(.system(size: 12))
            .foregroundStyle(MacWeChatStyle.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
            .padding(.horizontal, 16)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MacWeChatStyle.secondaryText)
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 6)
    }

    private var matchingCompanions: [CompanionProfileSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.companions }
        return appModel.companions.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.userName.localizedCaseInsensitiveContains(query)
                || latestPreview(for: $0).localizedCaseInsensitiveContains(query)
        }
    }

    private var matchingGroups: [GroupConversationSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.groupConversations }
        return appModel.groupConversations.filter { group in
            group.name.localizedCaseInsensitiveContains(query)
                || group.participantNames.contains {
                    $0.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private var matchesMe: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || appModel.userProfile.displayName.localizedCaseInsensitiveContains(query)
            || "本机个人使用".localizedCaseInsensitiveContains(query)
    }

    private func latestPreview(for companion: CompanionProfileSummary) -> String {
        let preview = appModel.directConversationActivity(roleID: companion.id)?.preview ?? ""
        return preview.isEmpty ? "点击进入对话" : preview.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct MacWeChatMenuAction {
    let title: String
    let systemImage: String
    let action: () -> Void
}

private struct MacWeChatTitleHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MacWeChatStyle.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(MacWeChatStyle.sessionBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacWeChatStyle.separator.opacity(0.8))
                .frame(height: 0.5)
        }
    }
}

private struct MacWeChatSearchHeader: View {
    @Binding var text: String
    let prompt: String
    var title: String? = nil
    let actions: [MacWeChatMenuAction]
    var directAction: (() -> Void)? = nil
    var directActionAccessibilityLabel: String? = nil
    var directActionIdentifier: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MacWeChatStyle.primaryText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(height: 36)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MacWeChatStyle.secondaryText)

                    TextField(prompt, text: $text)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .foregroundStyle(MacWeChatStyle.primaryText)
                        .accessibilityIdentifier(
                            title == "通讯录"
                                ? "wechat.mac.contacts.search"
                                : "wechat.mac.chats.search"
                        )

                    if !text.isEmpty {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(MacWeChatStyle.secondaryText.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除搜索")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    AppTheme.searchBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(MacWeChatStyle.separator.opacity(0.72), lineWidth: 0.5)
                }

                if let directAction {
                    Button(action: directAction) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(MacWeChatStyle.primaryText.opacity(0.72))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(directActionAccessibilityLabel ?? "添加")
                    .accessibilityIdentifier(directActionIdentifier ?? "wechat.mac.header.add")
                    .help(directActionAccessibilityLabel ?? "添加")
                } else {
                    Menu {
                        ForEach(actions.indices, id: \.self) { index in
                            let action = actions[index]
                            Button(action: action.action) {
                                Label(action.title, systemImage: action.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(MacWeChatStyle.primaryText.opacity(0.68))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel(title == "通讯录" ? "添加角色与群聊" : "更多操作")
                    .accessibilityIdentifier(title == "通讯录" ? "wechat.mac.contacts.menu" : "wechat.mac.chats.menu")
                    .help(title == "通讯录" ? "添加角色" : "更多操作")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
        }
        .frame(height: title == nil ? 60 : 84)
        .background(MacWeChatStyle.sessionBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MacWeChatStyle.separator.opacity(0.8))
                .frame(height: 0.5)
        }
    }
}

private struct MacWeChatConversationRow: View {
    let name: String
    let avatarImageData: Data?
    let preview: String
    let date: Date?
    let isSelected: Bool
    let isWorking: Bool
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 10) {
            CompanionAvatar(size: 44, name: name, imageData: avatarImageData)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let date {
                        Text(date, style: .time)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 5) {
                    Text(preview)
                        .font(.system(size: 12))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacWeChatStyle.iconOnAccent)
                            .padding(.horizontal, unreadCount > 9 ? 4 : 3)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(MacWeChatStyle.badgeBackground, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? MacWeChatStyle.iconOnAccent : MacWeChatStyle.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(isSelected ? MacWeChatStyle.selectedGreen : Color.clear)
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(MacWeChatStyle.separator.opacity(0.42))
                    .frame(height: 0.5)
                    .padding(.leading, 68)
            }
        }
    }
}

private struct MacWeChatGroupRow: View {
    let group: GroupConversationSummary
    let isSelected: Bool
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 10) {
            MacWeChatGroupAvatarView(group: group, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(group.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(group.updatedAt, style: .time)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text("群聊 · \(group.participantNames.count) 位成员")
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MacWeChatStyle.iconOnAccent)
                            .padding(.horizontal, unreadCount > 9 ? 4 : 3)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(MacWeChatStyle.badgeBackground, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? MacWeChatStyle.iconOnAccent : MacWeChatStyle.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(isSelected ? MacWeChatStyle.selectedGreen : Color.clear)
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(MacWeChatStyle.separator.opacity(0.42))
                    .frame(height: 0.5)
                    .padding(.leading, 68)
            }
        }
    }
}

/// A compact two-by-two group avatar for the macOS message list. The local
/// user is always the first tile, followed by up to three role members, so the
/// avatar column stays the same 44pt width as one-to-one conversation rows.
private struct MacWeChatGroupAvatarView: View {
    @Environment(AppModel.self) private var appModel

    let group: GroupConversationSummary
    let size: CGFloat

    var body: some View {
        avatarContent
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .accessibilityLabel("群聊头像，包含我和角色成员")
    }

    @ViewBuilder
    private var avatarContent: some View {
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
                ForEach(members) { member in
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
            .background(MacWeChatStyle.secondarySurface)
        }
    }

    private var members: [MacWeChatGroupAvatarMember] {
        let user = MacWeChatGroupAvatarMember(
            id: appModel.userProfile.id,
            name: appModel.userProfile.displayName,
            imageData: appModel.userProfile.avatarImageData,
            isUser: true
        )
        let roles = group.participantRoleIDs.prefix(3).compactMap { roleID in
            appModel.companions.first { $0.id == roleID }
        }.map { companion in
            MacWeChatGroupAvatarMember(
                id: companion.id,
                name: companion.name,
                imageData: companion.avatarImageData,
                isUser: false
            )
        }
        return [user] + roles
    }
}

private struct MacWeChatGroupAvatarMember: Identifiable {
    let id: UUID
    let name: String
    let imageData: Data?
    let isUser: Bool
}

private struct MacWeChatContactRow: View {
    let name: String
    let avatarImageData: Data?
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CompanionAvatar(size: 44, name: name, imageData: avatarImageData)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? MacWeChatStyle.iconOnAccent : MacWeChatStyle.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(isSelected ? MacWeChatStyle.selectedGreen : Color.clear)
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(MacWeChatStyle.separator.opacity(0.42))
                    .frame(height: 0.5)
                    .padding(.leading, 68)
            }
        }
    }
}

private struct MacWeChatProfileRow: View {
    let name: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            CompanionAvatar(size: 44, name: name)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(isSelected ? MacWeChatStyle.iconOnAccent : MacWeChatStyle.primaryText)
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(isSelected ? MacWeChatStyle.selectedGreen : Color.clear)
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(MacWeChatStyle.separator.opacity(0.42))
                    .frame(height: 0.5)
                    .padding(.leading, 68)
            }
        }
    }
}

private struct MacWeChatFeatureRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    var status: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(MacWeChatStyle.iconOnAccent)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let status {
                    Text(status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? MacWeChatStyle.iconOnAccent.opacity(0.9)
                                : MacWeChatStyle.secondaryText
                        )
                }
            }
            .foregroundStyle(isSelected ? MacWeChatStyle.iconOnAccent : MacWeChatStyle.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 64)
            .background(isSelected ? MacWeChatStyle.selectedGreen : Color.clear)
            .overlay(alignment: .bottom) {
                if !isSelected {
                    Rectangle()
                        .fill(MacWeChatStyle.separator.opacity(0.42))
                        .frame(height: 0.5)
                        .padding(.leading, 68)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MacWeChatDetailColumn: View {
    @Environment(AppModel.self) private var appModel

    let destination: MacWeChatDestination
    let openChat: () -> Void
    let openSettings: () -> Void

    var body: some View {
        detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MacWeChatStyle.detailBackground)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch destination {
        case .chat:
            ChatView(onOpenSettings: openSettings)

        case .companionContact:
            NavigationStack {
                CompanionContactView(
                    roleID: appModel.currentRoleID,
                    openChat: openChat
                )
            }

        case .newFriends:
            NavigationStack {
                NewFriendsMigrationView(onCreated: openChat)
            }

        case .groupChat:
            NavigationStack {
                GroupChatHubView()
            }

        case .groupChatCreate:
            NavigationStack {
                GroupChatCreateView()
            }

        case .groupChatPreview(let groupID):
            if let group = appModel.groupConversations.first(where: { $0.id == groupID }) {
                NavigationStack {
                    GroupChatPreviewView(group: group)
                }
            } else {
                ContentUnavailableView {
                    Label("群聊不可用", systemImage: "person.3")
                } description: {
                    Text("这个群聊已不在当前本机数据中。")
                }
            }

        case .startChat:
            NavigationStack {
                WeChatStartChatView(openSettings: openSettings)
            }

        case .discoverHome:
            NavigationStack {
                DiscoverView()
            }

        case .moments:
            NavigationStack {
                MomentsMigrationView()
            }

        case .meHome:
            NavigationStack {
                MeView()
            }

        case .scheduledTasks:
            NavigationStack {
                ScheduledTasksHomeView()
            }

        case .memory:
            NavigationStack {
                MemoryView()
            }

        case .persona:
            NavigationStack {
                PersonaView()
            }

        case .settingsAPI:
            NavigationStack {
                SettingsView(mode: .service)
            }

        case .settings, .settingsChat, .settingsProactive, .settingsData:
            NavigationStack {
                SettingsView(mode: .personal)
            }

        case .worldProfile:
            NavigationStack {
                WorldProfileView()
            }
        }
    }
}

#endif
