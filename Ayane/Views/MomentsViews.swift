import Foundation
import PhotosUI
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum MomentsSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let groupedSurface = Color(nsColor: .underPageBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let accent = Color(nsColor: .linkColor)
    #else
    static let page = AppTheme.rowBackground
    static let surface = AppTheme.rowBackground
    static let groupedSurface = AppTheme.secondarySurface
    static let separator = AppTheme.divider
    static let accent = AppTheme.momentsAccent
    #endif
}

struct MomentsMigrationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var actionMenuPresented = false
    @State private var showsPublisher = false
    @State private var showsScheduler = false
    @State private var showsProfileEditor = false
    @State private var selectedAuthor: MomentAuthorSelection?
    @State private var selectedComment: MomentCommentTarget?
    @State private var commentDrafts: [UUID: String] = [:]
    @FocusState private var commentInputFocused: Bool
    @State private var localStatus: String?
    @State private var showsNotifications = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        MomentsUserCover(
                            profile: appModel.userProfile,
                            height: coverHeight,
                            width: geometry.size.width,
                            edit: { showsProfileEditor = true }
                        )

                        if appModel.momentFeed.isEmpty {
                            VStack(spacing: 9) {
                                Image(systemName: "camera")
                                    .font(.system(size: 30, weight: .light))
                                Text("还没有朋友圈")
                                    .font(.system(size: 14))
                                Text("你和已成为好友的角色发布后，都会出现在这里")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 58)
                        } else {
                            ForEach(appModel.momentFeed) { post in
                                MomentsFeedPostRow(
                                    post: post,
                                    onVisible: {
                                        appModel.markMomentRead(postID: post.id)
                                    },
                                    openAuthor: {
                                        selectedAuthor = MomentAuthorSelection(
                                            kind: post.authorKind,
                                            roleID: post.authorRoleID,
                                            name: post.authorName,
                                            avatarImageData: post.authorAvatarImageData
                                        )
                                    },
                                    toggleLike: {
                                        perform {
                                            try appModel.toggleUserMomentLike(postID: post.id)
                                        }
                                    },
                                    comment: { parent in
                                        beginComment(
                                            postID: post.id,
                                            parent: parent,
                                            authorName: post.authorName
                                        )
                                    },
                                    delete: post.isUserAuthored ? {
                                        perform { try appModel.deleteUserMoment(id: post.id) }
                                    } : nil,
                                    deleteComment: { interaction in
                                        guard interaction.actorKind == .user else { return }
                                        perform {
                                            try appModel.deleteUserMomentComment(
                                                id: interaction.id,
                                                postID: post.id
                                            )
                                        }
                                    }
                                )
                                MomentsRowDivider(leading: 70)
                            }
                        }
                    }
                    .frame(width: geometry.size.width)
                }
                .background(MomentsSemantic.surface)
                .ignoresSafeArea(edges: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let target = selectedComment {
                        MomentCommentInputBar(
                            title: target.title,
                            text: Binding(
                                get: { commentDrafts[target.postID] ?? "" },
                                set: { commentDrafts[target.postID] = $0 }
                            ),
                            status: $localStatus,
                            send: { _ = submitComment() },
                            cancel: clearComment,
                            focused: $commentInputFocused
                        )
                    }
                }
            }
        }
        .background(MomentsSemantic.page.ignoresSafeArea())
        #if os(iOS)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .tint(.white)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsNotifications = true
                } label: {
                    MomentsNotificationToolbarLabel(count: appModel.momentsUnreadCount)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("朋友圈消息")
                .accessibilityValue(
                    appModel.momentsUnreadCount > 0
                        ? "\(appModel.momentsUnreadCount)条未读"
                        : "无未读消息"
                )
                .accessibilityIdentifier("wechat.moments.notifications")

                Button {
                    actionMenuPresented = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("朋友圈操作")
                .accessibilityIdentifier("wechat.moments.actions")
            }
        }
        #else
        .navigationTitle("朋友圈")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsPublisher = true
                } label: {
                    Label("发布", systemImage: "square.and.pencil")
                }
                .accessibilityLabel("发布朋友圈")
                .accessibilityIdentifier("wechat.moments.publish")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNotifications = true
                } label: {
                    MomentsNotificationToolbarLabel(count: appModel.momentsUnreadCount)
                }
                .accessibilityLabel("朋友圈消息")
                .accessibilityValue(
                    appModel.momentsUnreadCount > 0
                        ? "\(appModel.momentsUnreadCount)条未读"
                        : "无未读消息"
                )
                .accessibilityIdentifier("wechat.moments.notifications")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("发布朋友圈", systemImage: "square.and.pencil") {
                        showsPublisher = true
                    }
                    Button("定时任务", systemImage: "calendar.badge.clock") {
                        showsScheduler = true
                    }
                    Button("编辑个人资料与封面", systemImage: "person.crop.square") {
                        showsProfileEditor = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .accessibilityLabel("朋友圈更多操作")
                .accessibilityIdentifier("wechat.moments.more")
            }
        }
        #endif
        .confirmationDialog("朋友圈", isPresented: $actionMenuPresented, titleVisibility: .hidden) {
            Button("发布朋友圈") { showsPublisher = true }
            Button("定时任务") { showsScheduler = true }
            Button("编辑个人资料与封面") { showsProfileEditor = true }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showsPublisher) {
            UserMomentComposer(status: $localStatus)
        }
        .sheet(isPresented: $showsScheduler) {
            NavigationStack {
                ScheduledTasksHomeView()
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 680)
            #endif
        }
        .sheet(isPresented: $showsProfileEditor) {
            UserMomentsProfileEditor(status: $localStatus)
        }
        .sheet(isPresented: $showsNotifications) {
            MomentsNotificationsView()
        }
        .sheet(item: $selectedAuthor) { author in
            if author.kind == .companion, let roleID = author.roleID {
                #if os(macOS)
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                .frame(minWidth: 450, minHeight: 560)
                #else
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                #endif
            } else {
                MomentAuthorTimeline(author: author)
            }
        }
        .onAppear {
            appModel.refreshFromStore()
            appModel.markMomentsRead()
        }
        .onChange(of: selectedComment?.id) { _, newID in
            if newID == nil {
                commentInputFocused = false
            } else {
                DispatchQueue.main.async {
                    commentInputFocused = true
                }
            }
        }
    }

    private var coverHeight: CGFloat {
        #if os(iOS)
        350
        #else
        250
        #endif
    }

    private func beginComment(
        postID: UUID,
        parent: MomentInteractionSummary?,
        authorName: String
    ) {
        selectedComment = MomentCommentTarget(
            postID: postID,
            parentInteractionID: parent?.id,
            title: parent.map { "回复\($0.actorName)" } ?? "回复\(authorName)"
        )
        localStatus = nil
        commentInputFocused = true
    }

    private func clearComment() {
        selectedComment = nil
        commentInputFocused = false
        localStatus = nil
    }

    @discardableResult
    private func submitComment() -> Bool {
        guard let target = selectedComment,
              let draft = commentDrafts[target.postID],
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            try appModel.addComment(
                postID: target.postID,
                text: draft,
                parentInteractionID: target.parentInteractionID
            )
            commentDrafts.removeValue(forKey: target.postID)
            localStatus = nil
            selectedComment = nil
            commentInputFocused = false
            return true
        } catch {
            localStatus = "发送失败：\(error.localizedDescription)"
            commentInputFocused = true
            return false
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            localStatus = nil
        } catch {
            localStatus = error.localizedDescription
        }
    }
}

private struct MomentsFloatingHeader: View {
    let topInset: CGFloat
    let back: () -> Void
    let camera: () -> Void

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Spacer()

            Button(action: camera) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发布朋友圈")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
        .padding(.horizontal, 2)
        .padding(.top, topInset)
    }
}

private struct MomentsRowDivider: View {
    let leading: CGFloat

    var body: some View {
        Rectangle()
            .fill(MomentsSemantic.separator)
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

private struct MomentsUserCover: View {
    let profile: UserProfileSummary
    let height: CGFloat
    let width: CGFloat
    let edit: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = PlatformRoleImage.image(from: profile.momentsCoverImageData) {
                    image.resizable().scaledToFill()
                } else {
                    Image("MomentsCover").resizable().scaledToFill()
                }
            }
            .frame(width: width, height: height)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: width, height: height)

            Button(action: edit) {
                HStack(alignment: .bottom, spacing: 12) {
                    Spacer(minLength: 0)

                    Text(profile.displayName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                        .padding(.bottom, 34)

                    UserAvatar(
                        size: 72,
                        name: profile.displayName,
                        imageData: profile.avatarImageData
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(.white.opacity(0.78), lineWidth: 1)
                    }
                    .offset(y: 28)
                }
                .padding(.trailing, 20)
                .frame(width: width, height: height, alignment: .bottomTrailing)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width, height: height, alignment: .bottomTrailing)
        // Keep the overlapping avatar inside this view's layout bounds so a
        // later lazy row can never cover its lower edge.
        .padding(.bottom, 42)
    }
}

private struct MomentsFeedPostRow: View {
    let post: MomentPostSummary
    let onVisible: () -> Void
    let openAuthor: () -> Void
    let toggleLike: (() -> Void)?
    let comment: ((MomentInteractionSummary?) -> Void)?
    let delete: (() -> Void)?
    let deleteComment: ((MomentInteractionSummary) -> Void)?

    @State private var pendingCommentDeletion: MomentInteractionSummary?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: openAuthor) {
                if post.isUserAuthored {
                    UserAvatar(
                        size: 44,
                        name: post.authorName,
                        imageData: post.authorAvatarImageData
                    )
                } else {
                    CompanionAvatar(
                        size: 44,
                        name: post.authorName,
                        imageData: post.authorAvatarImageData
                    )
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                Button(post.authorName, action: openAuthor)
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MomentsSemantic.accent)

                if !post.body.isEmpty {
                    Text(post.body)
                        .font(.system(size: 16))
                        .lineSpacing(3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                MomentPostImage(post: post)

                #if os(macOS)
                macInteractionBar
                #else
                iOSInteractionBar
                #endif

                if !post.interactions.isEmpty {
                    MomentInteractionsPanel(
                        post: post,
                        onReply: { interaction in comment?(interaction) },
                        onDelete: { interaction in requestCommentDeletion(interaction) }
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(MomentsSemantic.surface)
        .accessibilityElement(children: .contain)
        .onAppear(perform: onVisible)
        .confirmationDialog(
            "删除评论？",
            isPresented: Binding(
                get: { pendingCommentDeletion != nil },
                set: { isPresented in
                    if !isPresented { pendingCommentDeletion = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除评论", role: .destructive) {
                guard let pendingCommentDeletion else { return }
                self.pendingCommentDeletion = nil
                deleteComment?(pendingCommentDeletion)
            }
            Button("取消", role: .cancel) {
                pendingCommentDeletion = nil
            }
        } message: {
            Text("仅可删除你自己的评论，删除后不可恢复")
        }
    }

    #if os(macOS)
    private var macInteractionBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(post.publishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)

                Button {
                    toggleLike?()
                } label: {
                    Label(
                        post.userDidLike ? "取消赞" : "赞",
                        systemImage: post.userDidLike ? "heart.fill" : "heart"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 54, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(
                    post.userDidLike
                        ? AppTheme.momentsLikeAccent
                        : AppTheme.secondaryText
                )
                .opacity(toggleLike == nil ? 0.48 : 1)
                .disabled(toggleLike == nil)
                .accessibilityLabel(post.userDidLike ? "取消赞" : "赞")
                .accessibilityValue(post.userDidLike ? "已点赞" : "未点赞")
                .accessibilityIdentifier("wechat.moment.like.\(post.id.uuidString)")

                Button {
                    comment?(nil)
                } label: {
                    Label("评论", systemImage: "bubble.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 60, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(comment == nil ? 0.48 : 1)
                .disabled(comment == nil)
                .accessibilityLabel("评论")
                .accessibilityIdentifier("wechat.moment.comment.\(post.id.uuidString)")

                momentMenu
            }

            Button {
                comment?(nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 12, weight: .medium))
                    Text("回复\(post.authorName)")
                        .font(.system(size: 12))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(MomentsSemantic.groupedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(comment == nil ? 0.48 : 1)
            .disabled(comment == nil)
            .accessibilityLabel("回复\(post.authorName)")
            .accessibilityIdentifier("wechat.moment.reply-author.\(post.id.uuidString)")
        }
    }
    #endif

    #if os(iOS)
    private var iOSInteractionBar: some View {
        HStack {
            Text(post.publishedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiaryText)
            Spacer()
            Button {
                toggleLike?()
            } label: {
                Image(systemName: post.userDidLike ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        post.userDidLike
                            ? AppTheme.momentsLikeAccent
                            : AppTheme.secondaryText
                    )
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(toggleLike == nil ? 0.48 : 1)
            .accessibilityLabel(post.userDidLike ? "取消赞" : "赞")
            .accessibilityValue(post.userDidLike ? "已点赞" : "未点赞")
            .accessibilityIdentifier("wechat.moment.like.\(post.id.uuidString)")

            Button {
                comment?(nil)
            } label: {
                Image(systemName: "bubble.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(comment == nil ? 0.48 : 1)
            .accessibilityLabel("评论")
            .accessibilityIdentifier("wechat.moment.comment.\(post.id.uuidString)")

            momentMenu
        }
    }
    #endif

    private var momentMenu: some View {
        Menu {
            if let toggleLike {
                Button(
                    post.userDidLike ? "取消赞" : "赞",
                    systemImage: post.userDidLike ? "heart.fill" : "heart",
                    action: toggleLike
                )
                .tint(
                    post.userDidLike
                        ? AppTheme.momentsLikeAccent
                        : AppTheme.secondaryText
                )
            }
            if let comment {
                Button("评论", action: { comment(nil) })
            }
            if let delete {
                Button("删除", role: .destructive, action: delete)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MomentsSemantic.accent)
                .frame(width: 38, height: 30)
                .background(MomentsSemantic.groupedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("动态更多操作")
    }

    private func requestCommentDeletion(_ interaction: MomentInteractionSummary) {
        guard interaction.kind == .comment,
              interaction.actorKind == .user,
              deleteComment != nil else { return }
        pendingCommentDeletion = interaction
    }
}

private struct MomentPostImage: View {
    let post: MomentPostSummary
    @State private var showsViewer = false

    var body: some View {
        Group {
            if let image = image {
                Button {
                    showsViewer = true
                } label: {
                    configured(image)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("查看图片")
                .accessibilityIdentifier("wechat.moment.image.\(post.id.uuidString)")
                #if os(macOS)
                .help("查看原图")
                #endif
                #if os(iOS)
                .fullScreenCover(isPresented: $showsViewer) {
                    MomentImageViewer(image: image)
                }
                #else
                .sheet(isPresented: $showsViewer) {
                    MomentImageViewer(image: image)
                }
                #endif
            }
        }
    }

    private var image: Image? {
        if let image = PlatformRoleImage.image(from: post.imageData) {
            return image
        }
        guard !post.bundledImageName.isEmpty else { return nil }
        return Image(post.bundledImageName)
    }

    private func configured(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(maxWidth: 270, maxHeight: 320)
            .aspectRatio(4 / 5, contentMode: .fit)
            .clipped()
    }
}

private struct MomentImageViewer: View {
    let image: Image

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

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
    }
}

private struct MomentInteractionsPanel: View {
    let post: MomentPostSummary
    let onReply: (MomentInteractionSummary) -> Void
    let onDelete: ((MomentInteractionSummary) -> Void)?

    private var commentsByID: [UUID: MomentInteractionSummary] {
        Dictionary(uniqueKeysWithValues: post.comments.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !post.likes.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.momentsLikeAccent)
                    Text(post.likes.map(\.actorName).joined(separator: "，"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MomentsSemantic.accent)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
            }

            if !post.likes.isEmpty && !post.comments.isEmpty {
                Rectangle().fill(MomentsSemantic.separator).frame(height: 0.5)
            }

            ForEach(post.comments) { item in
                HStack(alignment: .top, spacing: 0) {
                    Button {
                        onReply(item)
                    } label: {
                        commentLabel(item)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回复\(item.actorName)：\(item.body)")
                    .accessibilityHint("点击回复这条评论")
                    .accessibilityIdentifier("wechat.moment.reply.\(item.id.uuidString)")

                    if item.actorKind == .user, let onDelete {
                        Button {
                            onDelete(item)
                        } label: {
                            Text("删除")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MomentsSemantic.accent)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除自己的评论")
                        .accessibilityHint("删除后不可恢复")
                        .accessibilityIdentifier("wechat.moment.delete-comment.\(item.id.uuidString)")
                    }
                }
                .padding(.horizontal, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MomentsSemantic.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func commentLabel(_ item: MomentInteractionSummary) -> Text {
        let prefix: String
        if let parentID = item.parentInteractionID,
           let parent = commentsByID[parentID] {
            prefix = "\(item.actorName) 回复 \(parent.actorName)："
        } else {
            prefix = item.actorName + "："
        }
        return Text(prefix)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MomentsSemantic.accent)
            + Text(item.body)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
    }
}

private struct MomentNotificationItem: Identifiable {
    let post: MomentPostSummary
    let interaction: MomentInteractionSummary
    let actorAvatarImageData: Data?

    var id: UUID { interaction.id }

    var title: String {
        switch interaction.kind {
        case .like:
            "\(interaction.actorName)赞了你的朋友圈"
        case .comment:
            interaction.parentInteractionID == nil
                ? "\(interaction.actorName)评论了你的朋友圈"
                : "\(interaction.actorName)回复了你的评论"
        }
    }

    var detail: String {
        interaction.kind == .like
            ? "赞了这条朋友圈"
            : interaction.body
    }
}

private struct MomentsNotificationToolbarLabel: View {
    let count: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bell")
                .font(.system(size: 15, weight: .medium))
                .frame(minWidth: 26, minHeight: 26)

            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, count > 9 ? 3 : 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Color.red, in: Capsule())
                    .offset(x: 7, y: -5)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct MomentsNotificationsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAuthor: MomentAuthorSelection?

    var body: some View {
        NavigationStack {
            Group {
                if notifications.isEmpty {
                    ContentUnavailableView(
                        "还没有朋友圈消息",
                        systemImage: "bell",
                        description: Text("角色对你发布的朋友圈点赞或评论后，会显示在这里。")
                    )
                } else {
                    List(notifications) { item in
                        MomentNotificationRow(item: item) {
                            selectedAuthor = MomentAuthorSelection(
                                kind: .companion,
                                roleID: item.interaction.actorRoleID,
                                name: item.interaction.actorName,
                                avatarImageData: item.actorAvatarImageData
                            )
                        }
                            .listRowBackground(MomentsSemantic.surface)
                    }
                    #if os(macOS)
                    .listStyle(.inset)
                    #else
                    .listStyle(.plain)
                    #endif
                    .scrollContentBackground(.hidden)
                }
            }
            .background(MomentsSemantic.page)
            .navigationTitle("朋友圈消息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 420)
        .sheet(item: $selectedAuthor) { author in
            if author.kind == .companion, let roleID = author.roleID {
                #if os(macOS)
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                .frame(minWidth: 450, minHeight: 560)
                #else
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                #endif
            } else {
                MomentAuthorTimeline(author: author)
            }
        }
        .task {
            appModel.markMomentsRead()
        }
    }

    private var notifications: [MomentNotificationItem] {
        appModel.momentFeed
            .filter(\.isUserAuthored)
            .flatMap { post in
                post.interactions
                    .filter { $0.actorKind == .companion }
                    .map { interaction in
                        MomentNotificationItem(
                            post: post,
                            interaction: interaction,
                            actorAvatarImageData: interaction.actorRoleID.flatMap { roleID in
                                appModel.companions.first { $0.id == RoleScope.resolve(roleID) }?.avatarImageData
                            }
                        )
                    }
            }
            .sorted {
                if $0.interaction.createdAt != $1.interaction.createdAt {
                    return $0.interaction.createdAt > $1.interaction.createdAt
                }
                return $0.interaction.id.uuidString > $1.interaction.id.uuidString
            }
    }
}

private struct MomentNotificationRow: View {
    let item: MomentNotificationItem
    let openAuthor: () -> Void

    var body: some View {
        Button(action: openAuthor) {
            HStack(alignment: .top, spacing: 12) {
                CompanionAvatar(
                    size: 40,
                    name: item.interaction.actorName,
                    imageData: item.actorAvatarImageData
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(item.interaction.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(item.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(item.post.body.isEmpty ? "图片朋友圈" : item.post.body)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let image = postImage {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipped()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel("\(item.interaction.actorName)的朋友圈消息：\(item.detail)")
        .accessibilityHint("打开\(item.interaction.actorName)的资料")
        .accessibilityIdentifier("wechat.moment.notification.\(item.id.uuidString)")
    }

    private var postImage: Image? {
        if let image = PlatformRoleImage.image(from: item.post.imageData) {
            return image
        }
        guard !item.post.bundledImageName.isEmpty else { return nil }
        return Image(item.post.bundledImageName)
    }
}

private struct UserMomentComposer: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Binding var status: String?

    @State private var text = ""
    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("这一刻的想法…", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                    .textFieldStyle(.plain)
                    .font(.body)

                if let image = PlatformRoleImage.image(from: imageData) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                PhotosPicker(selection: $selection, matching: .images) {
                    Label(isLoading ? "正在处理图片" : "选择照片", systemImage: "photo")
                }
                .disabled(isLoading)

                if imageData != nil {
                    Button("移除照片", role: .destructive) { imageData = nil }
                }

                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("发表朋友圈")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发表") {
                        do {
                            try appModel.publishUserMoment(body: text, imageData: imageData)
                            status = nil
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && imageData == nil)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 420)
        .background(MomentsSemantic.page)
        .onChange(of: selection) { _, newValue in
            importPhoto(newValue)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard let source = try await item.loadTransferable(type: Data.self) else {
                    throw RoleImageProcessorError.unreadableImage
                }
                imageData = try RoleImageProcessor.normalizedJPEG(from: source, kind: .chatBackground)
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct MomentCommentTarget: Hashable, Identifiable {
    let postID: UUID
    let parentInteractionID: UUID?
    let title: String

    var id: String {
        postID.uuidString + ":" + (parentInteractionID?.uuidString ?? "root")
    }
}

/// A shared compact composer for both the feed and an author's timeline. It
/// stays in the page safe area so the keyboard resizes the transcript instead
/// of covering the active field.
private struct MomentCommentInputBar: View {
    let title: String
    @Binding var text: String
    @Binding var status: String?
    let send: () -> Void
    let cancel: () -> Void
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let status, !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消评论")
                .accessibilityIdentifier("wechat.moment.comment.cancel")

                TextField(title, text: $text, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(minHeight: 36)
                    .background(
                        MomentsSemantic.groupedSurface,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit {
                        if canSend { send() }
                    }
                    .accessibilityLabel(title)
                    .accessibilityIdentifier("wechat.moment.comment.input")

                Button(action: send) {
                    Text("发送")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 34)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.46)
                .accessibilityLabel("发送评论")
                .accessibilityIdentifier("wechat.moment.comment.send")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MomentsSemantic.separator)
                .frame(height: 0.5)
        }
        .onAppear {
            focused = true
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct UserMomentsProfileEditor: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Binding var status: String?

    @State private var displayName = ""
    @State private var avatarImageData: Data?
    @State private var coverImageData: Data?
    @State private var avatarSelection: PhotosPickerItem?
    @State private var coverSelection: PhotosPickerItem?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("个人资料") {
                    HStack(spacing: 14) {
                        UserAvatar(size: 62, name: displayName, imageData: avatarImageData)
                        PhotosPicker(selection: $avatarSelection, matching: .images) {
                            Text("更换头像")
                        }
                    }
                    TextField("昵称", text: $displayName)
                }

                Section("朋友圈封面") {
                    Group {
                        if let image = PlatformRoleImage.image(from: coverImageData) {
                            image.resizable().scaledToFill()
                        } else {
                            Image("MomentsCover").resizable().scaledToFill()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()

                    PhotosPicker(selection: $coverSelection, matching: .images) {
                        Text("更换朋友圈封面")
                    }
                }

                Section("生日与日期") {
                    NavigationLink {
                        BirthdayManagementView()
                    } label: {
                        Label("管理生日与时区", systemImage: "gift")
                    }
                    .accessibilityLabel("管理生日与时区")
                    .accessibilityIdentifier("wechat.moments.profile.birthday")
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            .navigationTitle("朋友圈资料")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try appModel.saveUserProfile(
                                displayName: displayName,
                                avatarImageData: avatarImageData,
                                momentsCoverImageData: coverImageData
                            )
                            // The editor closes silently, matching WeChat.
                            // Operational confirmation never belongs in the
                            // Moments feed itself.
                            status = nil
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 430)
        #endif
        .frame(minHeight: 520)
        .background(MomentsSemantic.page)
        .onAppear {
            displayName = appModel.userProfile.displayName
            avatarImageData = appModel.userProfile.avatarImageData
            coverImageData = appModel.userProfile.momentsCoverImageData
        }
        .onChange(of: avatarSelection) { _, item in importPhoto(item, avatar: true) }
        .onChange(of: coverSelection) { _, item in importPhoto(item, avatar: false) }
    }

    private func importPhoto(_ item: PhotosPickerItem?, avatar: Bool) {
        guard let item else { return }
        Task {
            do {
                guard let source = try await item.loadTransferable(type: Data.self) else {
                    throw RoleImageProcessorError.unreadableImage
                }
                let processed = try RoleImageProcessor.normalizedJPEG(
                    from: source,
                    kind: avatar ? .avatar : .chatBackground
                )
                if avatar { avatarImageData = processed } else { coverImageData = processed }
                errorText = nil
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct MomentAuthorSelection: Identifiable {
    let kind: MomentAuthorKind
    let roleID: UUID?
    let name: String
    let avatarImageData: Data?

    var id: String {
        kind.rawValue + ":" + (roleID?.uuidString ?? UserProfileRecord.singletonID.uuidString)
    }
}

struct CompanionMomentsTimelineView: View {
    let roleID: UUID
    let name: String
    let avatarImageData: Data?

    var body: some View {
        MomentAuthorTimeline(
            author: MomentAuthorSelection(
                kind: .companion,
                roleID: RoleScope.resolve(roleID),
                name: name,
                avatarImageData: avatarImageData
            ),
            presentation: .navigation
        )
    }
}

struct UserMomentsTimelineView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        MomentAuthorTimeline(
            author: MomentAuthorSelection(
                kind: .user,
                roleID: nil,
                name: appModel.userProfile.displayName,
                avatarImageData: appModel.userProfile.avatarImageData
            ),
            presentation: .navigation
        )
    }
}

private enum MomentTimelinePresentation: Equatable {
    case sheet
    case navigation
}

private struct MomentAuthorTimeline: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let author: MomentAuthorSelection
    var presentation: MomentTimelinePresentation = .sheet

    @State private var selectedComment: MomentCommentTarget?
    @State private var selectedAuthor: MomentAuthorSelection?
    @State private var showsUserProfileEditor = false
    @State private var commentDrafts: [UUID: String] = [:]
    @FocusState private var commentInputFocused: Bool
    @State private var localStatus: String?

    var body: some View {
        Group {
            if presentation == .sheet {
                NavigationStack { timelineContent.toolbar { closeToolbar } }
            } else {
                timelineContent
            }
        }
        #if os(macOS)
        .frame(minWidth: presentation == .sheet ? 450 : nil, minHeight: presentation == .sheet ? 560 : nil)
        #endif
        .background(MomentsSemantic.page)
    }

    private var timelineContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Button(action: openTimelineAuthor) {
                    HStack(spacing: 14) {
                        if author.kind == .user {
                            UserAvatar(size: 62, name: author.name, imageData: author.avatarImageData)
                        } else {
                            CompanionAvatar(size: 62, name: author.name, imageData: author.avatarImageData)
                        }
                        Text(author.name).font(.title3.weight(.semibold))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .padding(18)
                .accessibilityLabel("查看\(author.name)的资料")

                if let localStatus, selectedComment == nil {
                    Text(localStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 8)
                }

                ForEach(posts) { post in
                    MomentsFeedPostRow(
                        post: post,
                        onVisible: { appModel.markMomentRead(postID: post.id) },
                        openAuthor: {
                            if author.kind == .user {
                                showsUserProfileEditor = true
                            } else {
                                selectedAuthor = author
                            }
                        },
                        toggleLike: {
                            perform { try appModel.toggleUserMomentLike(postID: post.id) }
                        },
                        comment: { parent in
                            beginComment(
                                postID: post.id,
                                parent: parent,
                                authorName: post.authorName
                            )
                        },
                        delete: post.isUserAuthored ? {
                            perform { try appModel.deleteUserMoment(id: post.id) }
                        } : nil,
                        deleteComment: { interaction in
                            guard interaction.actorKind == .user else { return }
                            perform {
                                try appModel.deleteUserMomentComment(
                                    id: interaction.id,
                                    postID: post.id
                                )
                            }
                        }
                    )
                    MomentsRowDivider(leading: 70)
                }

                if posts.isEmpty {
                    ContentUnavailableView(
                        "还没有动态",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(
                            author.kind == .user
                                ? "你发布的朋友圈会显示在这里。"
                                : "这个角色发布的朋友圈会显示在这里。"
                        )
                    )
                    .padding(.vertical, 52)
                }
            }
        }
        .background(MomentsSemantic.page)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let target = selectedComment {
                MomentCommentInputBar(
                    title: target.title,
                    text: Binding(
                        get: { commentDrafts[target.postID] ?? "" },
                        set: { commentDrafts[target.postID] = $0 }
                    ),
                    status: $localStatus,
                    send: { _ = submitComment() },
                    cancel: clearComment,
                    focused: $commentInputFocused
                )
            }
        }
        .navigationTitle(author.kind == .user ? "我的朋友圈" : "朋友圈")
        .sheet(item: $selectedAuthor) { selected in
            if selected.kind == .companion, let roleID = selected.roleID {
                #if os(macOS)
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                .frame(minWidth: 450, minHeight: 560)
                #else
                NavigationStack {
                    CompanionContactView(roleID: roleID)
                }
                #endif
            } else {
                UserMomentsProfileEditor(status: $localStatus)
            }
        }
        .sheet(isPresented: $showsUserProfileEditor) {
            UserMomentsProfileEditor(status: $localStatus)
        }
        .onChange(of: selectedComment?.id) { _, newID in
            if newID == nil {
                commentInputFocused = false
            } else {
                DispatchQueue.main.async { commentInputFocused = true }
            }
        }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { dismiss() }
        }
    }

    private var posts: [MomentPostSummary] {
        appModel.momentFeed.filter { post in
            guard post.authorKind == author.kind else { return false }
            if author.kind == .user { return true }
            return post.authorRoleID == author.roleID
        }
    }

    private func openTimelineAuthor() {
        if author.kind == .user {
            showsUserProfileEditor = true
        } else {
            selectedAuthor = author
        }
    }

    private func beginComment(
        postID: UUID,
        parent: MomentInteractionSummary?,
        authorName: String
    ) {
        selectedComment = MomentCommentTarget(
            postID: postID,
            parentInteractionID: parent?.id,
            title: parent.map { "回复\($0.actorName)" } ?? "回复\(authorName)"
        )
        localStatus = nil
        commentInputFocused = true
    }

    private func clearComment() {
        selectedComment = nil
        commentInputFocused = false
        localStatus = nil
    }

    @discardableResult
    private func submitComment() -> Bool {
        guard let target = selectedComment,
              let draft = commentDrafts[target.postID],
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            try appModel.addComment(
                postID: target.postID,
                text: draft,
                parentInteractionID: target.parentInteractionID
            )
            commentDrafts.removeValue(forKey: target.postID)
            selectedComment = nil
            commentInputFocused = false
            localStatus = nil
            return true
        } catch {
            localStatus = "发送失败：\(error.localizedDescription)"
            commentInputFocused = true
            return false
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            localStatus = nil
        } catch {
            localStatus = error.localizedDescription
        }
    }
}
