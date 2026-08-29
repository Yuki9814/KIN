import SwiftUI

#if os(iOS)
import UIKit
struct WeChatHeaderMenuItem {
    let title: String
    let systemImage: String
    let action: () -> Void
}

struct WeChatRootHeader: View {
    let title: String
    var trailingSystemImage: String? = nil
    var trailingAccessibilityLabel: String = ""
    var trailingAction: (() -> Void)? = nil
    var trailingMenuItems: [WeChatHeaderMenuItem] = []
    var leadingSystemImage: String? = nil
    var leadingAccessibilityLabel: String = ""
    var leadingAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)

            HStack {
                if let leadingSystemImage {
                    if let leadingAction {
                        Button(action: leadingAction) {
                            headerIcon(systemImage: leadingSystemImage)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(leadingAccessibilityLabel)
                    } else {
                        headerIcon(systemImage: leadingSystemImage)
                            .accessibilityLabel(leadingAccessibilityLabel)
                    }
                }

                Spacer()
                if let trailingSystemImage, !trailingMenuItems.isEmpty {
                    Menu {
                        ForEach(trailingMenuItems.indices, id: \.self) { index in
                            let item = trailingMenuItems[index]
                            Button(action: item.action) {
                                Label(item.title, systemImage: item.systemImage)
                            }
                        }
                    } label: {
                        headerIcon(systemImage: trailingSystemImage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trailingAccessibilityLabel)
                    .accessibilityIdentifier("wechat.header.menu")
                } else if let trailingSystemImage, let trailingAction {
                    Button(action: trailingAction) {
                        headerIcon(systemImage: trailingSystemImage)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trailingAccessibilityLabel)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .background(AppTheme.rootBackground.ignoresSafeArea(edges: .top))
    }

    private func headerIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(AppTheme.iconPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct WeChatSearchBar: View {
    @Binding var text: String
    var prompt: String = "搜索"

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppTheme.secondaryText)
                    .opacity(text.isEmpty ? 0 : 1)
                    .accessibilityHidden(true)
                TextField("", text: $text)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.primaryText)
                    .submitLabel(.search)
                    .accessibilityLabel(prompt)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }

            if text.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .regular))
                    Text(prompt)
                        .font(.system(size: 16))
                }
                .foregroundStyle(AppTheme.secondaryText)
                .allowsHitTesting(false)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 10)
        .background(AppTheme.searchBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(AppTheme.rootBackground)
    }
}

struct WeChatTabBar: View {
    @Binding var selection: AppSection
    var fractionalPage: CGFloat = 0
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            tabIcon(for: section)
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: iconSize(for: section), height: iconSize(for: section))
                                .frame(height: 27)

                            if let badgeText = badgeText(for: section) {
                                Text(badgeText)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, badgeText == "99+" ? 4 : 5)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 9, y: -3)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(height: 27)

                        Text(section.title)
                            .font(.system(size: 10.5, weight: .regular))
                    }
                    .foregroundStyle(selection == section ? AppTheme.accent : AppTheme.inactiveTab)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityValue(accessibilityValue(for: section))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
                .accessibilityIdentifier("wechat.tab.\(section.rawValue)")
            }
        }
        .frame(height: 49)
        .padding(.top, 4)
        .background {
            AppTheme.barBackground
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.divider)
                .frame(height: 0.5)
        }
    }

    private var clampedFractionalPage: CGFloat {
        min(
            max(fractionalPage, 0),
            CGFloat(AppSection.allCases.count - 1)
        )
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

    private func badgeText(for section: AppSection) -> String? {
        guard let count = unreadCount(for: section), count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }

    private func accessibilityValue(for section: AppSection) -> Text {
        guard let count = unreadCount(for: section), count > 0 else { return Text("") }
        return Text(count > 99 ? "99 条以上未读" : "\(count) 条未读")
    }

    private func tabIcon(for section: AppSection) -> Image {
        switch section {
        case .chats where selection != .chats:
            // There is only a filled chat asset; use the outline SF Symbol
            // for the inactive state to preserve the WeChat tab convention.
            Image(systemName: "message")
        case .me where selection == .me:
            // The bundled Me asset is the outline state; use the matching
            // filled symbol only while this tab is selected.
            Image(systemName: "person.fill")
        default:
            Image(imageAsset(for: section))
        }
    }

    private func imageAsset(for section: AppSection) -> String {
        switch section {
        case .chats: "WeChatTabChats"
        case .contacts: "WeChatTabContacts"
        case .discover: "WeChatTabDiscover"
        case .me: "WeChatTabMe"
        }
    }

    private func iconSize(for section: AppSection) -> CGFloat {
        switch section {
        case .chats: 25
        case .contacts: 26
        case .discover: 25
        case .me: 25
        }
    }
}

struct WeChatBackHeader: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var trailingSystemImage: String? = nil
    var trailingAccessibilityLabel: String = ""
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(AppTheme.primaryText)
                .padding(.horizontal, 58)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppTheme.iconPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .accessibilityIdentifier("wechat.back")

                Spacer()

                if let trailingSystemImage, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingSystemImage)
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(AppTheme.iconPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trailingAccessibilityLabel)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 2)
    }
}

struct WeChatDetailShellModifier: ViewModifier {
    let title: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(AppTheme.rootBackground.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(false)
                .toolbar(.visible, for: .navigationBar)
        } else {
            content
                .background(AppTheme.rootBackground.ignoresSafeArea())
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(false)
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(AppTheme.barBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

extension View {
    func wechatDetailShell(title: String) -> some View {
        modifier(WeChatDetailShellModifier(title: title))
    }

    func restoresWeChatEdgeBackGesture() -> some View {
        background(WeChatInteractivePopGestureRestorer())
    }

    func wechatEdgeBackFallback() -> some View {
        modifier(WeChatEdgeBackFallbackModifier())
    }
}

private struct WeChatEdgeBackFallbackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    guard value.startLocation.x <= 28,
                          value.translation.width >= 100,
                          abs(value.translation.width) > abs(value.translation.height) * 1.5
                    else { return }
                    dismiss()
                }
        )
    }
}

private struct WeChatInteractivePopGestureRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> RestoringViewController {
        RestoringViewController()
    }

    func updateUIViewController(_ uiViewController: RestoringViewController, context: Context) {
        uiViewController.restoreGestureIfPossible()
    }

    final class RestoringViewController: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            restoreGestureIfPossible()
        }

        func restoreGestureIfPossible() {
            guard let navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.delegate = nil
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}

struct WeChatIconTile: View {
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

struct WeChatDisclosureIndicator: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppTheme.tertiaryText)
            .accessibilityHidden(true)
    }
}

struct WeChatRowDivider: View {
    var leading: CGFloat = 60

    var body: some View {
        Rectangle()
            .fill(AppTheme.divider)
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}
#endif
