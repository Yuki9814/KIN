import SwiftUI

#if os(iOS)
private struct WeChatUnreadBadge: View {
    let count: Int
    let accessibilityText: String

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, count > 99 ? 4 : 2)
                .background(Color.red, in: Capsule())
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

private enum WeChatChatListItem: Identifiable {
    case group(GroupConversationSummary)
    case companion(CompanionProfileSummary, conversationID: UUID)

    var id: UUID { conversationID }

    var conversationID: UUID {
        switch self {
        case .group(let group):
            return group.conversationID
        case .companion(_, let conversationID):
            return conversationID
        }
    }

    var displayName: String {
        switch self {
        case .group(let group):
            return group.name
        case .companion(let companion, _):
            return companion.name
        }
    }
}

struct WeChatConversationListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var showsNewFriend = false
    @State private var showsStartChat = false
    @State private var showsGroupChat = false
    @State private var showsChat = false
    @State private var showsMemory = false
    @State private var selectedGroup: GroupConversationSummary?
    @State private var chatPendingRemoval: WeChatChatListItem?

    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WeChatRootHeader(
                title: "微信",
                trailingSystemImage: "plus.circle",
                trailingAccessibilityLabel: "更多操作",
                trailingMenuItems: [
                    WeChatHeaderMenuItem(
                        title: "发起聊天",
                        systemImage: "bubble.left",
                        action: { showsStartChat = true }
                    ),
                    WeChatHeaderMenuItem(
                        title: "新的朋友",
                        systemImage: "person.badge.plus",
                        action: { showsNewFriend = true }
                    ),
                    WeChatHeaderMenuItem(
                        title: "创建群聊",
                        systemImage: "person.3",
                        action: { showsGroupChat = true }
                    )
                ],
                leadingSystemImage: "star",
                leadingAccessibilityLabel: "长期记忆",
                leadingAction: { showsMemory = true }
            )
            WeChatSearchBar(text: $searchText)

            List {
                deviceStatusRow
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)
                WeChatRowDivider(leading: 0)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)

                if chatListItems.isEmpty {
                    noResults
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(chatListItems) { item in
                        chatListRow(item)
                            .listRowInsets(.init())
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                chatSwipeActions(item)
                            }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(AppTheme.rowBackground)
        }
        .background(AppTheme.rootBackground)
        .navigationDestination(isPresented: $showsNewFriend) {
            NewFriendsMigrationView()
        }
        .navigationDestination(isPresented: $showsStartChat) {
            WeChatStartChatView(openSettings: openSettings)
        }
        .navigationDestination(isPresented: $showsGroupChat) {
            GroupChatCreateView()
        }
        .navigationDestination(item: $selectedGroup) { group in
            GroupChatPreviewView(group: group)
        }
        .navigationDestination(isPresented: $showsChat) {
            ChatView(onOpenSettings: openSettings)
        }
        .navigationDestination(isPresented: $showsMemory) {
            MemoryView()
        }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(
                get: { chatPendingRemoval != nil },
                set: { if !$0 { chatPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(removalButtonTitle, role: .destructive) {
                removePendingChat()
            }
            Button("取消", role: .cancel) {
                chatPendingRemoval = nil
            }
        } message: {
            Text(removalMessage)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .kinProactiveNotificationRouteRequested
            )
        ) { _ in
            openPendingNotificationRoute()
        }
        .task {
            openPendingNotificationRoute()
        }
        .accessibilityIdentifier("wechat.screen.chats")
    }

    private var deviceStatusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: appModel.isUsingCloud ? "laptopcomputer.and.iphone" : "internaldrive")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(AppTheme.secondaryText)
                .frame(width: 34)

            Text(appModel.isUsingCloud ? "Mac 与 iPhone 已启用同步" : "仅保存在这台设备")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(AppTheme.rowBackground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chatListRow(_ item: WeChatChatListItem) -> some View {
        switch item {
        case .group(let group):
            Button {
                selectedGroup = group
            } label: {
                GroupConversationRow(
                    group: group,
                    style: .home,
                    isPinned: appModel.isConversationPinned(group.conversationID)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wechat.group." + group.id.uuidString)

        case .companion(let companion, let conversationID):
            Button {
                openCompanion(companion.id)
            } label: {
                conversationRow(
                    companion,
                    conversationID: conversationID,
                    isPinned: appModel.isConversationPinned(conversationID)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wechat.conversation." + companion.id.uuidString)
        }
    }

    @ViewBuilder
    private func chatSwipeActions(_ item: WeChatChatListItem) -> some View {
        let conversationID = item.conversationID
        let unreadCount = appModel.unreadCount(forConversationID: conversationID)
        let isPinned = appModel.isConversationPinned(conversationID)

        Button(unreadCount > 0 ? "标为已读" : "标为未读") {
            if unreadCount > 0 {
                appModel.markConversationRead(conversationID: conversationID)
            } else {
                appModel.markConversationUnread(conversationID: conversationID)
            }
        }
        .tint(.blue)
        .accessibilityIdentifier("wechat.chat.read-state." + conversationID.uuidString)

        Button(isPinned ? "取消置顶" : "置顶") {
            appModel.setConversationPinned(conversationID, pinned: !isPinned)
        }
        .tint(.orange)
        .accessibilityIdentifier("wechat.chat.pin." + conversationID.uuidString)

        Button(removalActionTitle(for: item), role: .destructive) {
            chatPendingRemoval = item
        }
        .accessibilityIdentifier("wechat.chat.remove." + conversationID.uuidString)
    }

    private func conversationRow(
        _ companion: CompanionProfileSummary,
        conversationID: UUID,
        isPinned: Bool
    ) -> some View {
        let unreadCount = appModel.unreadCount(forConversationID: conversationID)

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                CompanionAvatar(
                    size: 48,
                    name: companion.name,
                    imageData: companion.avatarImageData
                )
                .overlay(alignment: .topTrailing) {
                    WeChatUnreadBadge(
                        count: unreadCount,
                        accessibilityText: "\(unreadCount)条未读消息"
                    )
                    .offset(x: 6, y: -6)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(companion.name)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(AppTheme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let date = appModel.directConversationActivity(roleID: companion.id)?.lastActivityAt {
                            Text(date, style: .time)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(latestPreview(for: companion))
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
            .padding(.horizontal, 12)
            .frame(height: 72)
            .background(isPinned ? AppTheme.secondarySurface : AppTheme.rowBackground)
            .contentShape(Rectangle())

            WeChatRowDivider(leading: 72)
        }
    }

    private var noResults: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
            Text(searchQuery.isEmpty ? "暂无聊天" : "无搜索结果")
                .font(.system(size: 14))
        }
        .foregroundStyle(AppTheme.tertiaryText)
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
    }

    private var chatListItems: [WeChatChatListItem] {
        var items = appModel.groupConversations.compactMap { group -> WeChatChatListItem? in
            let preview = appModel.groupConversationActivity(
                conversationID: group.conversationID
            )?.preview ?? ""
            guard searchQuery.isEmpty
                    || group.name.localizedCaseInsensitiveContains(searchQuery)
                    || preview.localizedCaseInsensitiveContains(searchQuery) else {
                return nil
            }
            return .group(group)
        }
        items.append(contentsOf: appModel.companions.compactMap { companion in
            guard let conversationID = appModel.activeDirectConversationID(roleID: companion.id),
                  searchQuery.isEmpty
                    || companion.name.localizedCaseInsensitiveContains(searchQuery)
                    || companion.userName.localizedCaseInsensitiveContains(searchQuery)
                    || latestPreview(for: companion).localizedCaseInsensitiveContains(searchQuery) else {
                return nil
            }
            return .companion(companion, conversationID: conversationID)
        })
        return items.sorted { lhs, rhs in
            let lhsPinned = appModel.isConversationPinned(lhs.conversationID)
            let rhsPinned = appModel.isConversationPinned(rhs.conversationID)
            if lhsPinned != rhsPinned { return lhsPinned }
            let lhsDate = chatActivityDate(for: lhs)
            let rhsDate = chatActivityDate(for: rhs)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func chatActivityDate(for item: WeChatChatListItem) -> Date {
        switch item {
        case .group(let group):
            return appModel.groupConversationActivity(
                conversationID: group.conversationID
            )?.lastActivityAt ?? group.updatedAt
        case .companion(let companion, _):
            return appModel.directConversationActivity(roleID: companion.id)?.lastActivityAt
                ?? .distantPast
        }
    }

    private func latestPreview(for companion: CompanionProfileSummary) -> String {
        guard companion.relationshipState == .accepted else {
            return relationshipPreview(companion.relationshipState)
        }
        let preview = appModel.directConversationActivity(roleID: companion.id)?.preview ?? ""
        return preview.isEmpty ? "点击进入对话" : preview.replacingOccurrences(of: "\n", with: " ")
    }

    private func relationshipPreview(_ state: CompanionRelationshipState) -> String {
        switch state {
        case .pending: "等待通过好友申请"
        case .accepted: "点击进入对话"
        case .rejected: "好友申请已拒绝"
        case .deleted: "对方已删除你"
        case .recoveryPending: "等待处理道歉申请"
        case .blocked: "对方已将你拉黑"
        }
    }

    private var removalTitle: String {
        guard let chatPendingRemoval else { return "移除聊天" }
        switch chatPendingRemoval {
        case .group:
            return "解散“\(chatPendingRemoval.displayName)”？"
        case .companion:
            return "删除“\(chatPendingRemoval.displayName)”的聊天？"
        }
    }

    private var removalButtonTitle: String {
        guard let chatPendingRemoval else { return "移除" }
        return removalActionTitle(for: chatPendingRemoval)
    }

    private var removalMessage: String {
        guard let chatPendingRemoval else { return "" }
        switch chatPendingRemoval {
        case .group:
            return "你是群主。解散后群聊会从所有聊天入口移除，已有消息和长期记忆仍会保留。"
        case .companion:
            return "聊天会从消息列表移除，联系人仍保留。本机原始消息和长期记忆不会物理清除，之后可从通讯录重新发起聊天。"
        }
    }

    private func removalActionTitle(for item: WeChatChatListItem) -> String {
        switch item {
        case .group: "解散"
        case .companion: "删除"
        }
    }

    private func removePendingChat() {
        guard let chatPendingRemoval else { return }
        do {
            switch chatPendingRemoval {
            case .group(let group):
                try appModel.dissolveGroup(conversationID: group.conversationID)
            case .companion(let companion, _):
                try appModel.removeDirectConversationFromChatList(roleID: companion.id)
            }
            self.chatPendingRemoval = nil
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func openCompanion(_ id: UUID, conversationID: UUID? = nil) {
        do {
            try appModel.selectCompanion(id: id, conversationID: conversationID)
            showsChat = true
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func openPendingNotificationRoute() {
        guard let route = KINNotificationRouter.shared.consume() else { return }
        appModel.processDueProactiveTasks(now: Date())
        openCompanion(route.roleID, conversationID: route.conversationID)
    }
}

struct WeChatContactsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var searchText = ""
    @State private var showsNewFriend = false
    @State private var showsGroupChats = false
    @State private var showsContact = false
    @State private var showsChat = false
    @State private var contactPendingDeletion: CompanionProfileSummary?

    var openSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            WeChatRootHeader(
                title: "通讯录",
                trailingSystemImage: "person.badge.plus",
                trailingAccessibilityLabel: "添加角色",
                trailingAction: { showsNewFriend = true }
            )
            WeChatSearchBar(text: $searchText)

            List {
                Button {
                    showsNewFriend = true
                } label: {
                    featureRow(
                        title: "新的朋友",
                        systemImage: "person.badge.plus",
                        color: .orange,
                        badgeCount: appModel.pendingFriendApplicationCount
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(.init())
                .listRowSeparator(.hidden)

                WeChatRowDivider(leading: 60)
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)

                Button {
                    showsGroupChats = true
                } label: {
                    featureRow(title: "群聊", systemImage: "person.3.fill", color: AppTheme.accent)
                }
                .buttonStyle(.plain)
                .listRowInsets(.init())
                .listRowSeparator(.hidden)

                sectionHeader
                    .listRowInsets(.init())
                    .listRowSeparator(.hidden)

                if matchingContacts.isEmpty {
                    Text("无搜索结果")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72)
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(matchingContacts) { companion in
                        Button {
                            openContact(companion.id)
                        } label: {
                            contactRow(companion)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(.init())
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) {
                                contactPendingDeletion = companion
                            }
                            .accessibilityIdentifier(
                                "wechat.contact.delete." + companion.id.uuidString
                            )
                        }
                        .accessibilityIdentifier("wechat.contact." + companion.id.uuidString)
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(AppTheme.rowBackground)
        }
        .background(AppTheme.rootBackground)
        .navigationDestination(isPresented: $showsNewFriend) {
            NewFriendsMigrationView()
        }
        .navigationDestination(isPresented: $showsGroupChats) {
            GroupChatHubView()
        }
        .navigationDestination(isPresented: $showsContact) {
            CompanionContactView(
                roleID: appModel.currentRoleID,
                openChat: openSelectedChat
            )
        }
        .navigationDestination(isPresented: $showsChat) {
            ChatView(onOpenSettings: openSettings)
        }
        .confirmationDialog(
            contactPendingDeletion.map { "删除联系人“\($0.name)”？" } ?? "删除联系人",
            isPresented: Binding(
                get: { contactPendingDeletion != nil },
                set: { if !$0 { contactPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除联系人", role: .destructive) {
                deletePendingContact()
            }
            Button("取消", role: .cancel) {
                contactPendingDeletion = nil
            }
        } message: {
            Text("联系人会从通讯录移除；已有聊天、长期记忆和群聊成员记录都会保留。")
        }
        .accessibilityIdentifier("wechat.screen.contacts")
    }

    private func featureRow(
        title: String,
        systemImage: String,
        color: Color,
        badgeCount: Int = 0
    ) -> some View {
        HStack(spacing: 12) {
            WeChatIconTile(systemImage: systemImage, color: color, size: 36)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            if badgeCount > 0 {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("\(badgeCount)条新申请")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(AppTheme.rowBackground)
        .contentShape(Rectangle())
    }

    private var sectionHeader: some View {
        HStack {
            Text(contactSectionTitle)
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(AppTheme.rootBackground)
    }

    private func contactRow(_ companion: CompanionProfileSummary) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CompanionAvatar(
                    size: 36,
                    name: companion.name,
                    imageData: companion.avatarImageData
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(companion.name)
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.primaryText)
                    if companion.relationshipState != .accepted {
                        Text(companion.relationshipState == .deleted ? "对方已删除你" : companion.relationshipState.title)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(AppTheme.rowBackground)

            WeChatRowDivider(leading: 60)
        }
        .contentShape(Rectangle())
    }

    private var contactSectionTitle: String {
        "好友"
    }

    private var matchingContacts: [CompanionProfileSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return appModel.companions }
        return appModel.companions.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.userName.localizedCaseInsensitiveContains(query)
        }
    }

    private func openContact(_ id: UUID) {
        do {
            try appModel.selectCompanion(id: id)
            showsContact = true
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func deletePendingContact() {
        guard let contactPendingDeletion else { return }
        do {
            try appModel.archiveCompanion(roleID: contactPendingDeletion.id)
            self.contactPendingDeletion = nil
        } catch {
            appModel.errorMessage = error.localizedDescription
        }
    }

    private func openSelectedChat() {
        showsContact = false
        Task { @MainActor in
            await Task.yield()
            showsChat = true
        }
    }
}

struct WeChatDiscoverView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            WeChatRootHeader(title: "发现")

            ScrollView {
                LazyVStack(spacing: 0) {
                    Color.clear.frame(height: 8)

                    NavigationLink {
                        MomentsMigrationView()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(Color(red: 0.28, green: 0.52, blue: 0.93))
                                .frame(width: 28)
                            Text("朋友圈")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.primaryText)
                            Spacer()
                            WeChatUnreadBadge(
                                count: appModel.momentsUnreadCount,
                                accessibilityText: "\(appModel.momentsUnreadCount)条未读朋友圈"
                            )
                            WeChatDisclosureIndicator()
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 56)
                        .background(AppTheme.rowBackground)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppTheme.rootBackground)
        }
        .background(AppTheme.rootBackground)
        .accessibilityIdentifier("wechat.screen.discover")
    }
}

struct WeChatMeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showsProfileEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: 58)

                Button {
                    showsProfileEditor = true
                } label: {
                    profileRow
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 10)

                NavigationLink {
                    SettingsView(mode: .service)
                } label: {
                    settingsRow(
                        title: "服务",
                        systemImage: "checkmark.message",
                        color: Color(red: 0.02, green: 0.70, blue: 0.48)
                    )
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 10)

                NavigationLink {
                    MemoryView()
                } label: {
                    settingsRow(
                        title: "长期记忆",
                        systemImage: "cube",
                        color: Color(red: 0.19, green: 0.55, blue: 0.90)
                    )
                }
                .buttonStyle(.plain)
                WeChatRowDivider(leading: 56)

                NavigationLink {
                    UserMomentsTimelineView()
                } label: {
                    settingsRow(
                        title: "我的朋友圈",
                        systemImage: "photo",
                        color: Color(red: 0.14, green: 0.55, blue: 0.86)
                    )
                }
                .buttonStyle(.plain)
                WeChatRowDivider(leading: 56)

                NavigationLink {
                    ScheduledTasksHomeView()
                } label: {
                    settingsRow(
                        title: "定时任务",
                        systemImage: "calendar.badge.clock",
                        color: AppTheme.accent
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("定时任务")
                .accessibilityIdentifier("wechat.me.scheduled-tasks")
                WeChatRowDivider(leading: 56)

                NavigationLink {
                    PersonaView()
                } label: {
                    settingsRow(
                        title: "角色与对话方式",
                        systemImage: "person.text.rectangle",
                        color: Color(red: 0.23, green: 0.60, blue: 0.80)
                    )
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: 10)

                NavigationLink {
                    SettingsView(mode: .personal)
                } label: {
                    settingsRow(
                        title: "设置",
                        systemImage: "gearshape",
                        color: Color(red: 0.15, green: 0.55, blue: 0.82)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(AppTheme.rootBackground.ignoresSafeArea(edges: .top))
        .sheet(isPresented: $showsProfileEditor) {
            UserMomentsProfileEditor(status: .constant(nil))
        }
        .accessibilityIdentifier("wechat.screen.me")
    }

    private var profileRow: some View {
        HStack(spacing: 16) {
            UserAvatar(
                size: 68,
                name: appModel.userProfile.displayName,
                imageData: appModel.userProfile.avatarImageData
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(appModel.userProfile.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Text("KIN ID：personal")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.secondaryText)
                Text(appModel.isUsingCloud ? "Mac 与 iPhone 同步已启用" : "仅本机个人使用")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Image(systemName: "qrcode")
                .font(.system(size: 17))
                .foregroundStyle(AppTheme.secondaryText)
            WeChatDisclosureIndicator()
        }
        .padding(.horizontal, 20)
        .frame(height: 120)
        .background(AppTheme.rowBackground.ignoresSafeArea(edges: .top))
    }

    private func settingsRow(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.primaryText)
            Spacer()
            WeChatDisclosureIndicator()
        }
        .padding(.horizontal, 13)
        .frame(height: 56)
        .background(AppTheme.rowBackground)
        .contentShape(Rectangle())
    }
}
#endif
