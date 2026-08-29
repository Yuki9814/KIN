import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppSection = .chats
    @State private var fractionalPage: CGFloat = 0

    var body: some View {
        Group {
            #if os(macOS)
            MacWeChatShellView(selection: $selection)
            #else
            NavigationStack {
                VStack(spacing: 0) {
                    WeChatRootPager(
                        selection: $selection,
                        fractionalPage: $fractionalPage,
                        content: sectionView
                    )
                    WeChatTabBar(
                        selection: $selection,
                        fractionalPage: fractionalPage
                    )
                }
                .background(AppTheme.rootBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
            }
            #endif
        }
        .onChange(of: scenePhase) {
            appModel.conversationCareAppActivityDidChange(
                isActive: scenePhase == .active
            )
            if scenePhase == .active {
                appModel.refreshFromStore(
                    force: true,
                    migrateImportedIdentity: true
                )
                appModel.processDueMomentTasks()
                appModel.processDueMemoryMaintenance()
                appModel.processDueProactiveTasks()
            }
        }
        .task(id: scenePhase) {
            appModel.conversationCareAppActivityDidChange(
                isActive: scenePhase == .active
            )
            guard scenePhase == .active else { return }
            appModel.processDueMomentTasks()
            appModel.processDueMemoryMaintenance()
            appModel.processDueProactiveTasks()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                appModel.refreshFromStore(migrateImportedIdentity: true)
                appModel.processDueMomentTasks()
                appModel.processDueMemoryMaintenance()
                appModel.processDueProactiveTasks()
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .chats:
            #if os(iOS)
            WeChatConversationListView(
                openSettings: { selection = .me }
            )
            #else
            ConversationListView(
                openSettings: { selection = .me }
            )
            #endif
        case .contacts:
            #if os(iOS)
            WeChatContactsView(openSettings: { selection = .me })
            #else
            ContactsView(openChat: { selection = .chats })
            #endif
        case .discover:
            #if os(iOS)
            WeChatDiscoverView()
            #else
            DiscoverView()
            #endif
        case .me:
            #if os(iOS)
            WeChatMeView()
            #else
            MeView()
            #endif
        }
    }
}

#if os(iOS)
private struct WeChatRootPager<Content: View>: View {
    @Binding var selection: AppSection
    @Binding var fractionalPage: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: (AppSection) -> Content

    @State private var dragAxis: PagerDragAxis = .idle
    @State private var dragTranslation: CGFloat = 0

    private let edgeGuard: CGFloat = 28
    private let axisLockDistance: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let pageCount = AppSection.allCases.count
            let pageIndex = selectedIndex

            HStack(spacing: 0) {
                ForEach(AppSection.allCases) { section in
                    content(section)
                        .frame(width: width, height: height)
                        .allowsHitTesting(section == selection)
                        .accessibilityHidden(section != selection)
                }
            }
            .frame(width: width * CGFloat(pageCount), height: height, alignment: .leading)
            .offset(x: -CGFloat(pageIndex) * width + dragTranslation)
            .contentShape(Rectangle())
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: selection)
            // Chat and contact rows own horizontal drags for their native
            // swipe actions. Those two tabs remain reachable from the tab bar.
            .simultaneousGesture(
                pagerGesture(width: width),
                including: pagerGestureMask
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("主栏目")
            .accessibilityValue(selection.title)
            .accessibilityHint("调整以切换栏目")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    moveSelection(by: 1)
                case .decrement:
                    moveSelection(by: -1)
                @unknown default:
                    break
                }
            }
            .onChange(of: selection) { _, newSelection in
                fractionalPage = CGFloat(index(of: newSelection))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedIndex: Int {
        index(of: selection)
    }

    private var pagerGestureMask: GestureMask {
        selection == .chats || selection == .contacts ? .none : .all
    }

    private func index(of section: AppSection) -> Int {
        AppSection.allCases.firstIndex(of: section) ?? 0
    }

    private func pagerGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                if dragAxis == .idle {
                    guard value.startLocation.x > edgeGuard else {
                        dragAxis = .ignored
                        return
                    }

                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    guard max(horizontal, vertical) >= axisLockDistance else {
                        return
                    }

                    dragAxis = horizontal > vertical ? .horizontal : .vertical
                }

                guard dragAxis == .horizontal else { return }

                dragTranslation = rubberBandedTranslation(
                    value.translation.width,
                    width: width
                )
                fractionalPage = fractionalPage(for: dragTranslation, width: width)
            }
            .onEnded { value in
                finishDrag(value, width: width)
            }
    }

    private func rubberBandedTranslation(_ translation: CGFloat, width: CGFloat) -> CGFloat {
        let lowerBound = selectedIndex < AppSection.allCases.count - 1 ? -width : 0
        let upperBound = selectedIndex > 0 ? width : 0

        if translation > upperBound {
            return upperBound + (translation - upperBound) * 0.22
        }
        if translation < lowerBound {
            return lowerBound + (translation - lowerBound) * 0.22
        }
        return translation
    }

    private func fractionalPage(for translation: CGFloat, width: CGFloat) -> CGFloat {
        let rawPage = CGFloat(selectedIndex) - translation / width
        return min(max(rawPage, 0), CGFloat(AppSection.allCases.count - 1))
    }

    private func finishDrag(_ value: DragGesture.Value, width: CGFloat) {
        guard dragAxis == .horizontal else {
            let animation = reduceMotion ? nil : Animation.easeOut(duration: 0.24)
            withAnimation(animation) {
                dragTranslation = 0
                fractionalPage = CGFloat(selectedIndex)
            }
            dragAxis = .idle
            return
        }

        let predictedTranslation = value.predictedEndTranslation.width
        let effectiveTranslation = abs(predictedTranslation) > abs(value.translation.width)
            ? predictedTranslation
            : value.translation.width
        let threshold = width * 0.22
        var targetIndex = selectedIndex

        if effectiveTranslation < -threshold {
            targetIndex += 1
        } else if effectiveTranslation > threshold {
            targetIndex -= 1
        }

        targetIndex = min(max(targetIndex, 0), AppSection.allCases.count - 1)
        let target = AppSection.allCases[targetIndex]
        let animation = reduceMotion ? nil : Animation.easeOut(duration: 0.24)

        withAnimation(animation) {
            dragTranslation = 0
            selection = target
            fractionalPage = CGFloat(targetIndex)
        }
        dragAxis = .idle
    }

    private func moveSelection(by offset: Int) {
        let targetIndex = min(
            max(selectedIndex + offset, 0),
            AppSection.allCases.count - 1
        )
        guard targetIndex != selectedIndex else { return }

        let animation = reduceMotion ? nil : Animation.easeOut(duration: 0.24)
        withAnimation(animation) {
            selection = AppSection.allCases[targetIndex]
            fractionalPage = CGFloat(targetIndex)
        }
    }
}

private enum PagerDragAxis {
    case idle
    case horizontal
    case vertical
    case ignored
}
#endif
