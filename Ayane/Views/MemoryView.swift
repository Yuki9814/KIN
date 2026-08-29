import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum MemorySemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondarySurface = Color(nsColor: .underPageBackgroundColor)
    #else
    static let page = AppTheme.rootBackground
    static let surface = AppTheme.rowBackground
    static let secondarySurface = AppTheme.secondarySurface
    #endif
}

private struct MemoryEditTarget: Identifiable {
    let id: UUID
    let initialValue: String
}

private struct MemoryDotWave: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 5
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 6, height: 6)
                        .offset(y: sin(phase + Double(index) * 1.5) * 3)
                }
            }
        }
        .accessibilityLabel("正在整理长期记忆")
    }
}

struct MemoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKeys.autoExtractMemory) private var memoryEnabled = true

    @State private var query = ""
    @State private var stateFilter: MemoryState?
    @State private var memories: [MemoryLibraryItem] = []
    @State private var nextCursor: MemoryLibraryCursor?
    @State private var hasMoreMemories = false
    @State private var isLoadingPage = false
    @State private var loadGeneration = 0
    @State private var loadedStoreRevision: Int?
    @State private var editTarget: MemoryEditTarget?
    @State private var detailMemory: MemoryLibraryItem?
    @State private var pendingForget: MemoryLibraryItem?
    @State private var localError: String?

    var body: some View {
        memoryContent
        .searchable(text: $query, prompt: "搜索内容、主体或类型")
#if os(iOS)
        .wechatDetailShell(title: "记忆")
#else
        .navigationTitle("记忆")
#endif
        .task(id: libraryReloadToken) {
            await reloadLibrary(debounceSearch: true)
        }
        .refreshable {
            await reloadLibrary(debounceSearch: false)
        }
        .sheet(item: $editTarget) { target in
            MemoryEditSheet(initialValue: target.initialValue) { newValue in
                mutateMemory(id: target.id) { current in
                    try MemoryRepository.userEdited(current, value: newValue, context: modelContext)
                }
            }
        }
        .sheet(item: $detailMemory) { memory in
            MemoryEvidenceSheet(
                memoryID: memory.id,
                roleID: appModel.currentRoleID,
                roleName: currentMemoryRoleName
            )
        }
        .confirmationDialog(
            "忘记这条记忆？",
            isPresented: Binding(
                get: { pendingForget != nil },
                set: { if !$0 { pendingForget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("忘记并移除派生内容", role: .destructive) {
                guard let memory = pendingForget else { return }
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.forget(
                        current,
                        context: modelContext,
                        deviceID: "local-user-action"
                    )
                }
                pendingForget = nil
            }
            Button("取消", role: .cancel) { pendingForget = nil }
        } message: {
            Text("会清空这条派生记忆并创建跨设备删除标记。旧对话和推断不会让它复活；只有你在遗忘之后再次明确说出，才会重新记住。原始对话仍会保留。")
        }
    }

    private var memoryRoles: [CompanionProfileSummary] {
        let activeRoles = appModel.companions
        guard !activeRoles.contains(where: { $0.id == appModel.currentRoleID }),
              let current = appModel.companionSummary(for: appModel.currentRoleID) else {
            return activeRoles
        }
        return [current] + activeRoles
    }

    private var currentMemoryRoleName: String {
        appModel.companionSummary(for: appModel.currentRoleID)?.name
            ?? appModel.persona.name
    }

    @ViewBuilder
    private var memoryRoleSelector: some View {
        if memoryRoles.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("切换角色记忆")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(memoryRoles) { role in
                            let isSelected = role.id == appModel.currentRoleID
                            Button {
                                selectMemoryRole(role.id)
                            } label: {
                                Text(role.name)
                                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    #if os(iOS)
                                    .frame(minHeight: 44)
                                    #endif
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.primaryText)
                            .background(
                                isSelected ? AppTheme.accent.opacity(0.15) : MemorySemantic.secondarySurface,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        isSelected
                                            ? AppTheme.accent.opacity(0.35)
                                            : AppTheme.subtleBorder,
                                        lineWidth: 1
                                    )
                            }
                            .accessibilityLabel("查看\(role.name)的长期记忆")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func selectMemoryRole(_ roleID: UUID) {
        guard roleID != appModel.currentRoleID else { return }
        do {
            try appModel.selectCompanion(id: roleID)
            loadGeneration &+= 1
            memories = []
            nextCursor = nil
            hasMoreMemories = false
            loadedStoreRevision = nil
            editTarget = nil
            detailMemory = nil
            pendingForget = nil
            localError = nil
        } catch {
            localError = "无法切换角色记忆：\(error.localizedDescription)"
        }
    }

    private func memoryEmptyState(minHeight: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(query.isEmpty ? "还没有长期记忆" : "没有匹配的记忆")
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Text(query.isEmpty
                 ? "与\(currentMemoryRoleName)对话后，带原文证据的长期信息会出现在这里。"
                 : "试试更短的关键词或切换状态筛选。")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var memoryContent: some View {
#if os(iOS)
        iOSMemoryScrollView
#else
        macOSMemoryList
#endif
    }

#if os(iOS)
    private var iOSMemoryScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                iOSOverviewCard

                if !appModel.lastUsedMemories.isEmpty {
                    iOSUsedMemorySection
                }

                if let localError {
                    StatusBanner(text: localError, style: .error) {
                        self.localError = nil
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                iOSFilterBar
                iOSMemoryLibrary
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MemorySemantic.page.ignoresSafeArea())
    }

    private var iOSOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(currentMemoryRoleName)的长期记忆")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text("当前只显示并调用这个角色自己的记忆；不同角色互不混用。")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(hasMoreMemories ? "\(memories.count)+" : "\(memories.count)")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("已载入")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            memoryRoleSelector

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    if appModel.isOrganizingMemory {
                        MemoryDotWave()
                            .frame(width: 34, height: 20)
                    }
                    Text(memoryEnabled ? appModel.memoryActivityText : "自动记忆已关闭，可手动整理")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    appModel.retryPendingMemory()
                } label: {
                    Label(
                        appModel.isOrganizingMemory ? "正在整理" : "整理记忆",
                        systemImage: appModel.isOrganizingMemory ? "hourglass" : "arrow.triangle.2.circlepath"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
                .disabled(appModel.isGenerating || appModel.isOrganizingMemory)
                .accessibilityHint("整理尚未处理的原始对话，会调用你配置的 API")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private var iOSUsedMemorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            iOSSectionHeader("本轮使用的记忆", count: appModel.lastUsedMemories.count)

            Text("这里只显示最近一次请求实际送入 API 的私人记忆；可以直接核对、编辑、置顶或忘记。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            ForEach(appModel.lastUsedMemories) { memory in
                iOSUsedMemoryCard(memory)
            }
        }
    }

    private func iOSUsedMemoryCard(_ memory: UsedMemorySummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if memory.isPinned {
                Image(systemName: "pin.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(memory.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text("相关度 \(Int(memory.score * 100))% · 可信 \(Int(memory.confidence * 100))%")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            iOSUsedMemoryActionsMenu(for: memory)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private var iOSFilterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            iOSSectionHeader("筛选工具")

            Text("按状态查看可核对的长期记忆")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    iOSFilterButton(title: "全部", state: nil)
                    ForEach([MemoryState.active, .candidate, .contested, .superseded], id: \.rawValue) { state in
                        iOSFilterButton(title: state.title, state: state)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private func iOSSectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 8)
            if let count {
                Text("\(count) 条")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }

    private func iOSFilterButton(title: String, state: MemoryState?) -> some View {
        Button {
            stateFilter = state
        } label: {
            Text(title)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .background(
            stateFilter == state ? AppTheme.accent.opacity(0.16) : MemorySemantic.surface,
            in: Capsule()
        )
        .foregroundStyle(stateFilter == state ? AppTheme.accent : AppTheme.primaryText)
        .overlay {
            Capsule()
                .stroke(
                    stateFilter == state ? AppTheme.accent.opacity(0.35) : AppTheme.subtleBorder,
                    lineWidth: 1
                )
        }
        .accessibilityAddTraits(stateFilter == state ? .isSelected : [])
    }

    private var iOSMemoryLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            iOSSectionHeader("长期记忆", count: memories.count)

            if isLoadingPage && memories.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("正在读取长期记忆…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if memories.isEmpty {
                memoryEmptyState(minHeight: 170)
                .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(memories) { memory in
                    iOSMemoryCard(memory)
                }

                if hasMoreMemories {
                    Button {
                        Task { await loadNextPage() }
                    } label: {
                        Group {
                            if isLoadingPage {
                                ProgressView()
                            } else {
                                Label("载入更多记忆", systemImage: "arrow.down.circle")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                    .disabled(isLoadingPage)
                }
            }
        }
    }

    private func iOSMemoryCard(_ memory: MemoryLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(memory.kind.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                        MemoryStateBadge(state: memory.state)
                    }

                    if memory.userVerified {
                        Label("已确认", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if memory.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: true, vertical: false)
                }

                iOSMemoryActionsMenu(for: memory)
            }

            Text(memory.value)
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .contentShape(Rectangle())
                .onTapGesture {
                    detailMemory = memory
                }
                .accessibilityHint("轻点查看原文证据")

            VStack(alignment: .leading, spacing: 4) {
                Text("\(memory.subject).\(memory.predicate)")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("可信 \(Int(memory.confidence * 100))% · 更新于 \(memory.updatedAt, format: .dateTime.year().month().day())")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private func iOSMemoryActionsMenu(for memory: MemoryLibraryItem) -> some View {
        Menu {
            Button(memory.isPinned ? "取消置顶" : "置顶") {
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.setPinned(
                        current,
                        pinned: !current.isPinned,
                        context: modelContext
                    )
                }
            }
            Button("编辑并确认") {
                editTarget = MemoryEditTarget(id: memory.id, initialValue: memory.value)
            }
            Button("查看原文来源") {
                detailMemory = memory
            }
            Button("确认当前内容") {
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.userEdited(
                        current,
                        value: current.value,
                        context: modelContext
                    )
                }
            }
            Divider()
            Button("忘记", role: .destructive) {
                pendingForget = memory
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.iconPrimary)
        .accessibilityLabel("更多记忆操作")
    }

    private func iOSUsedMemoryActionsMenu(for memory: UsedMemorySummary) -> some View {
        Menu {
            Button(memory.isPinned ? "取消置顶" : "置顶") {
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.setPinned(
                        current,
                        pinned: !current.isPinned,
                        context: modelContext
                    )
                }
            }
            Button("编辑并确认") {
                editTarget = MemoryEditTarget(id: memory.id, initialValue: memory.text)
            }
            Button("查看原文来源") {
                detailMemory = iOSUsedMemoryItem(for: memory)
            }
            Divider()
            Button("忘记", role: .destructive) {
                pendingForget = iOSUsedMemoryItem(for: memory)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.iconPrimary)
        .accessibilityLabel("本轮记忆操作")
    }

    private func iOSUsedMemoryItem(for memory: UsedMemorySummary) -> MemoryLibraryItem {
        memories.first(where: { $0.id == memory.id }) ?? MemoryLibraryItem(
            id: memory.id,
            kind: .episode,
            subject: "本轮使用",
            predicate: "相关记忆",
            value: memory.text,
            state: .active,
            confidence: Double(memory.confidence),
            updatedAt: .distantPast,
            isPinned: memory.isPinned,
            userVerified: false
        )
    }
#endif

#if os(macOS)
    private var macOSMemoryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                memoryOverview

                if !appModel.lastUsedMemories.isEmpty {
                    macOSSectionHeader("本轮使用的记忆", count: appModel.lastUsedMemories.count)

                    Text("这里只显示最近一次请求实际送入 API 的私人记忆；可以直接核对、编辑、置顶或忘记。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)

                    ForEach(appModel.lastUsedMemories) { memory in
                        usedMemoryRow(memory)
                    }
                }

                if let localError {
                    StatusBanner(text: localError, style: .error) {
                        self.localError = nil
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppTheme.subtleBorder, lineWidth: 1)
                    }
                }

                filterBar
                macOSMemoryCollection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(MemorySemantic.page.ignoresSafeArea())
    }

    private var macOSMemoryCollection: some View {
        Group {
            if isLoadingPage && memories.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取长期记忆…")
                        .font(.callout)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleBorder, lineWidth: 1)
                }
            } else if memories.isEmpty {
                memoryEmptyState(minHeight: 142)
                .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleBorder, lineWidth: 1)
                }
            } else {
                ForEach(memories) { memory in
                    memoryRow(memory)
                }

                if hasMoreMemories {
                    Button {
                        Task { await loadNextPage() }
                    } label: {
                        Group {
                            if isLoadingPage {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("载入更多记忆", systemImage: "arrow.down.circle")
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accent)
                    .disabled(isLoadingPage)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macOSSectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.primaryText)
            Spacer(minLength: 8)
            if let count {
                Text("\(count) 条")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.horizontal, 2)
    }
#endif

    private var libraryReloadToken: String {
        "\(appModel.currentRoleID.uuidString)|\(appModel.memoryStoreRevision)|\(stateFilter?.rawValue ?? "all")|\(query)"
    }

    @MainActor
    private func reloadLibrary(debounceSearch: Bool) async {
        let requestedQuery = query
        let requestedState = stateFilter
        let requestedRoleID = appModel.currentRoleID
        let requestedRevision = appModel.memoryStoreRevision
        let requestedFingerprint = MemoryLibrary.filterFingerprint(
            query: requestedQuery,
            state: requestedState,
            roleID: requestedRoleID
        )

        if debounceSearch,
           !requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
        }
        guard !Task.isCancelled,
              requestedRevision == appModel.memoryStoreRevision,
              requestedRoleID == appModel.currentRoleID,
              requestedFingerprint == MemoryLibrary.filterFingerprint(
                query: query,
                state: stateFilter,
                roleID: appModel.currentRoleID
              ) else { return }

        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingPage = true
        defer {
            if generation == loadGeneration {
                isLoadingPage = false
            }
        }

        do {
            let page = try MemoryLibrary.fetchPage(
                context: modelContext,
                query: requestedQuery,
                state: requestedState,
                roleID: requestedRoleID,
                after: nil,
                storeRevision: requestedRevision
            )
            guard !Task.isCancelled,
                  generation == loadGeneration,
                  requestedRevision == appModel.memoryStoreRevision,
                  requestedRoleID == appModel.currentRoleID,
                  requestedFingerprint == MemoryLibrary.filterFingerprint(
                    query: query,
                    state: stateFilter,
                    roleID: appModel.currentRoleID
                  ) else { return }

            if let loadedStoreRevision, loadedStoreRevision != requestedRevision {
                editTarget = nil
                detailMemory = nil
                pendingForget = nil
            }
            loadedStoreRevision = requestedRevision
            memories = page.items
            nextCursor = page.nextCursor
            hasMoreMemories = page.hasMore
            localError = nil
        } catch {
            if generation == loadGeneration {
                memories = []
                nextCursor = nil
                hasMoreMemories = false
                localError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadNextPage() async {
        guard !isLoadingPage,
              hasMoreMemories,
              let cursor = nextCursor else { return }

        let requestedQuery = query
        let requestedState = stateFilter
        let requestedRoleID = appModel.currentRoleID
        let requestedRevision = appModel.memoryStoreRevision
        let requestedFingerprint = MemoryLibrary.filterFingerprint(
            query: requestedQuery,
            state: requestedState,
            roleID: requestedRoleID
        )
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingPage = true
        defer {
            if generation == loadGeneration {
                isLoadingPage = false
            }
        }

        do {
            let page = try MemoryLibrary.fetchPage(
                context: modelContext,
                query: requestedQuery,
                state: requestedState,
                roleID: requestedRoleID,
                after: cursor,
                storeRevision: requestedRevision
            )
            guard !Task.isCancelled,
                  generation == loadGeneration,
                  requestedRevision == appModel.memoryStoreRevision,
                  requestedRoleID == appModel.currentRoleID,
                  requestedFingerprint == MemoryLibrary.filterFingerprint(
                    query: query,
                    state: stateFilter,
                    roleID: appModel.currentRoleID
                  ) else { return }

            var seen = Set(memories.map(\.id))
            memories.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
            nextCursor = page.nextCursor
            hasMoreMemories = page.hasMore
            localError = nil
        } catch MemoryLibraryError.staleCursor {
            await reloadLibrary(debounceSearch: false)
        } catch {
            if generation == loadGeneration {
                localError = error.localizedDescription
            }
        }
    }

    private func mutateMemory(
        id: UUID,
        operation: (MemoryAssertionRecord) throws -> Void
    ) {
        do {
            let current = try MemoryLibrary.fetchLatestVisibleRecord(
                id: id,
                roleID: appModel.currentRoleID,
                context: modelContext
            )
            try operation(current)
            appModel.refreshFromStore(force: true)
        } catch {
            localError = error.localizedDescription
            appModel.refreshFromStore(force: true)
        }
    }

#if os(macOS)
    private var memoryOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(currentMemoryRoleName)的长期记忆")
                        .font(.headline)
                        .foregroundStyle(AppTheme.primaryText)
                    Text("当前只显示并调用这个角色自己的记忆；不同角色互不混用。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(hasMoreMemories ? "\(memories.count)+" : "\(memories.count)")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.primaryText)
                    Text("已载入")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            memoryRoleSelector

            HStack(alignment: .center, spacing: 10) {
                if appModel.isOrganizingMemory {
                    MemoryDotWave()
                        .frame(width: 34, height: 16)
                }
                Text(memoryEnabled ? appModel.memoryActivityText : "自动记忆已关闭，可手动整理")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(appModel.isOrganizingMemory ? "正在整理" : "整理记忆") {
                    appModel.retryPendingMemory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(AppTheme.accent)
                .disabled(appModel.isGenerating || appModel.isOrganizingMemory)
                .help("整理尚未处理的原始对话，会调用你配置的 API")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("长期记忆")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primaryText)
                Text(hasMoreMemories ? "\(memories.count)+ 条" : "\(memories.count) 条")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                Spacer(minLength: 8)
                if isLoadingPage && !memories.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    filterButton(title: "全部", state: nil)
                    ForEach([MemoryState.active, .candidate, .contested, .superseded], id: \.rawValue) { state in
                        filterButton(title: state.title, state: state)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.secondarySurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private func filterButton(title: String, state: MemoryState?) -> some View {
        Button(title) { stateFilter = state }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .frame(minHeight: 27)
            .background(
                stateFilter == state ? AppTheme.accent.opacity(0.16) : MemorySemantic.surface,
                in: Capsule()
            )
            .foregroundStyle(stateFilter == state ? AppTheme.accent : AppTheme.secondaryText)
            .overlay {
                Capsule()
                    .stroke(
                        stateFilter == state ? AppTheme.accent.opacity(0.28) : AppTheme.subtleBorder,
                        lineWidth: 1
                    )
            }
            .accessibilityAddTraits(stateFilter == state ? .isSelected : [])
    }

    private func memoryRow(_ memory: MemoryLibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 8) {
                    Text(memory.kind.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    MemoryStateBadge(state: memory.state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if memory.userVerified {
                    Label("已确认", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if memory.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: true, vertical: false)
                }
                memoryActionsMenu(for: memory)
            }

            Text(memory.value)
                .font(.body)
                .foregroundStyle(AppTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .contentShape(Rectangle())
                .onTapGesture {
                    detailMemory = memory
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(memory.subject).\(memory.predicate)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Text("可信 \(Int(memory.confidence * 100))%")
                    Text("更新于 \(memory.updatedAt, format: .dateTime.year().month().day())")
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }

    private func memoryActionsMenu(for memory: MemoryLibraryItem) -> some View {
        Menu {
            Button(memory.isPinned ? "取消置顶" : "置顶") {
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.setPinned(
                        current,
                        pinned: !current.isPinned,
                        context: modelContext
                    )
                }
            }
            Button("编辑并确认") {
                editTarget = MemoryEditTarget(id: memory.id, initialValue: memory.value)
            }
            Button("查看原文来源") {
                detailMemory = memory
            }
            Button("确认当前内容") {
                mutateMemory(id: memory.id) { current in
                    try MemoryRepository.userEdited(
                        current,
                        value: current.value,
                        context: modelContext
                    )
                }
            }
            Divider()
            Button("忘记", role: .destructive) {
                pendingForget = memory
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.primaryText)
        .accessibilityLabel("更多记忆操作")
    }

    private func usedMemoryRow(_ memory: UsedMemorySummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if memory.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(memory.text)
                    .font(.body)
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("相关度 \(Int(memory.score * 100))% · 可信 \(Int(memory.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                Button(memory.isPinned ? "取消置顶" : "置顶") {
                    mutateMemory(id: memory.id) { current in
                        try MemoryRepository.setPinned(
                            current,
                            pinned: !current.isPinned,
                            context: modelContext
                        )
                    }
                }
                Button("编辑并确认") {
                    editTarget = MemoryEditTarget(id: memory.id, initialValue: memory.text)
                }
                Button("查看原文来源") {
                    if let item = memories.first(where: { $0.id == memory.id }) {
                        detailMemory = item
                    } else {
                        detailMemory = MemoryLibraryItem(
                            id: memory.id,
                            kind: .episode,
                            subject: "本轮使用",
                            predicate: "相关记忆",
                            value: memory.text,
                            state: .active,
                            confidence: Double(memory.confidence),
                            updatedAt: Date.distantPast,
                            isPinned: memory.isPinned,
                            userVerified: false
                        )
                    }
                }
                Divider()
                Button("忘记", role: .destructive) {
                    if let item = memories.first(where: { $0.id == memory.id }) {
                        pendingForget = item
                    } else {
                        pendingForget = MemoryLibraryItem(
                            id: memory.id,
                            kind: .episode,
                            subject: "本轮使用",
                            predicate: "相关记忆",
                            value: memory.text,
                            state: .active,
                            confidence: Double(memory.confidence),
                            updatedAt: Date.distantPast,
                            isPinned: memory.isPinned,
                            userVerified: false
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primaryText)
            .accessibilityLabel("本轮记忆操作")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MemorySemantic.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AppTheme.subtleBorder, lineWidth: 1)
        }
    }
#endif
}

private struct MemoryEvidenceDisplay: Identifiable {
    let id: UUID
    let eventID: UUID
    let role: EventRole
    let occurredAt: Date
    let quote: String
    let relation: EvidenceRelation
    let confidence: Double
}

private struct MemoryEvidenceCursor: Equatable {
    let createdAt: Date
    let id: UUID
}

private struct MemoryEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let memoryID: UUID
    let roleID: UUID
    let roleName: String
    @State private var memory: MemoryLibraryItem?
    @State private var evidence: [MemoryEvidenceDisplay] = []
    @State private var nextCursor: MemoryEvidenceCursor?
    @State private var hasMoreEvidence = false
    @State private var isLoadingEvidence = false
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if let memory {
                    Section("记忆结论") {
                        Text(memory.value)
                            .font(.body)
                            .textSelection(.enabled)
                        LabeledContent("结构") {
                            Text("\(memory.subject).\(memory.predicate)")
                                .textSelection(.enabled)
                        }
                        LabeledContent("状态", value: memory.state.title)
                        LabeledContent("可信度", value: "\(Int(memory.confidence * 100))%")
                        if memory.userVerified {
                            Label("这条内容已由你亲自确认", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    Section("原文证据") {
                        if let loadError {
                            Text(loadError)
                                .foregroundStyle(.red)
                        } else if evidence.isEmpty, isLoadingEvidence {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else if evidence.isEmpty {
                            ContentUnavailableView(
                                "没有可显示的原文",
                                systemImage: "quote.bubble",
                                description: Text("手动确认的记忆或已删除来源的记忆可能没有原文证据。")
                            )
                        } else {
                            ForEach(evidence) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("“\(item.quote)”")
                                        .font(.body)
                                        .textSelection(.enabled)
                                    HStack {
                                        Text(item.role == .user ? "你" : roleName)
                                        Text(item.occurredAt, format: .dateTime.year().month().day().hour().minute())
                                        Spacer()
                                        Text(relationTitle(item.relation))
                                        Text("\(Int(item.confidence * 100))%")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                            if hasMoreEvidence {
                                HStack {
                                    Spacer()
                                    Button("载入更多原文") { loadEvidence(reset: false) }
                                        .buttonStyle(.bordered)
                                        .disabled(isLoadingEvidence)
                                    Spacer()
                                }
                            }
                        }
                    }
                } else if let loadError {
                    ContentUnavailableView(
                        "记忆已不可用",
                        systemImage: "eye.slash",
                        description: Text(loadError)
                    )
                } else {
                    HStack {
                        Spacer()
                        ProgressView("正在读取原文证据…")
                        Spacer()
                    }
                    .padding(.vertical, 28)
                }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(MemorySemantic.page)
            .navigationTitle("\(roleName)的记忆来源")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { loadEvidence(reset: true) }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 480)
        #endif
    }

    private func loadEvidence(reset: Bool) {
        guard !isLoadingEvidence else { return }
        isLoadingEvidence = true
        defer { isLoadingEvidence = false }
        do {
            let current = try MemoryLibrary.fetchLatestVisibleRecord(
                id: memoryID,
                roleID: roleID,
                context: modelContext
            )
            memory = MemoryLibraryItem(
                id: current.id,
                kind: current.kind,
                subject: current.subject,
                predicate: current.predicate,
                value: current.value,
                state: current.state,
                confidence: current.confidence,
                updatedAt: current.updatedAt,
                isPinned: current.isPinned,
                userVerified: current.userVerified
            )
            if reset {
                evidence = []
                nextCursor = nil
                hasMoreEvidence = false
            }

            let afterDate = nextCursor?.createdAt ?? .distantPast
            let afterID = nextCursor?.id
                ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            let includesLegacyNilRows = roleID == RoleScope.legacyRoleID
            var descriptor = FetchDescriptor<MemoryEvidenceRecord>(
                predicate: #Predicate {
                    $0.memoryID == memoryID
                        && ($0.roleID == roleID
                            || (includesLegacyNilRows && $0.roleID == nil))
                        && ($0.createdAt > afterDate
                            || ($0.createdAt == afterDate && $0.id > afterID))
                },
                sortBy: [
                    SortDescriptor(\.createdAt, order: .forward),
                    SortDescriptor(\.id, order: .forward)
                ]
            )
            descriptor.fetchLimit = 61
            descriptor.propertiesToFetch = [
                \MemoryEvidenceRecord.id,
                \MemoryEvidenceRecord.roleID,
                \MemoryEvidenceRecord.eventID,
                \MemoryEvidenceRecord.startUTF16,
                \MemoryEvidenceRecord.endUTF16,
                \MemoryEvidenceRecord.relationRaw,
                \MemoryEvidenceRecord.confidence,
                \MemoryEvidenceRecord.createdAt
            ]
            let records = try modelContext.fetch(descriptor)
            let pageRecords = Array(records.prefix(60))
            let eventIDs = Array(Set(pageRecords.map(\.eventID)))
            let events: [ConversationEvent]
            if eventIDs.isEmpty {
                events = []
            } else {
                var eventDescriptor = FetchDescriptor<ConversationEvent>(
                    predicate: #Predicate {
                        eventIDs.contains($0.id)
                            && ($0.roleID == roleID
                                || (includesLegacyNilRows && $0.roleID == nil))
                            && !$0.redacted
                    }
                )
                eventDescriptor.propertiesToFetch = [
                    \ConversationEvent.id,
                    \ConversationEvent.roleID,
                    \ConversationEvent.roleRaw,
                    \ConversationEvent.content,
                    \ConversationEvent.occurredAt,
                    \ConversationEvent.redacted
                ]
                events = try modelContext.fetch(eventDescriptor)
            }
            let eventsByID = Dictionary(
                events.map { ($0.id, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            let page = pageRecords.compactMap { record -> MemoryEvidenceDisplay? in
                guard let event = eventsByID[record.eventID],
                      let quote = quote(
                        in: event.content,
                        startUTF16: record.startUTF16,
                        endUTF16: record.endUTF16
                      ) else {
                    return nil
                }
                return MemoryEvidenceDisplay(
                    id: record.id,
                    eventID: record.eventID,
                    role: event.role,
                    occurredAt: event.occurredAt,
                    quote: quote,
                    relation: EvidenceRelation(rawValue: record.relationRaw) ?? .supports,
                    confidence: record.confidence
                )
            }
            var seen = Set(evidence.map(\.id))
            evidence.append(contentsOf: page.filter { seen.insert($0.id).inserted })
            hasMoreEvidence = records.count > 60
            if hasMoreEvidence, let last = pageRecords.last {
                nextCursor = MemoryEvidenceCursor(createdAt: last.createdAt, id: last.id)
            } else {
                nextCursor = nil
            }
            loadError = nil
        } catch {
            loadError = "读取原文证据失败：\(error.localizedDescription)"
        }
    }

    private func quote(in content: String, startUTF16: Int, endUTF16: Int) -> String? {
        let utf16 = content.utf16
        guard startUTF16 >= 0,
              endUTF16 >= startUTF16,
              endUTF16 <= utf16.count,
              let start = utf16.index(utf16.startIndex, offsetBy: startUTF16).samePosition(in: content),
              let end = utf16.index(utf16.startIndex, offsetBy: endUTF16).samePosition(in: content) else {
            return nil
        }
        return String(content[start..<end])
    }

    private func relationTitle(_ relation: EvidenceRelation) -> String {
        switch relation {
        case .supports: "支持"
        case .contradicts: "反证"
        case .updates: "更新"
        }
    }
}

private struct MemoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let save: (String) -> Void
    @State private var value: String

    init(initialValue: String, save: @escaping (String) -> Void) {
        self.save = save
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记忆内容") {
                    TextEditor(text: $value)
                        .frame(minHeight: 140)
                }
                Section("说明") {
                    Text("保存后会标记为你亲自确认，后续模型提炼不能自动覆盖它。")
                        .foregroundStyle(.secondary)
                }
            }
            #if os(macOS)
            .scrollContentBackground(.hidden)
            #endif
            .background(MemorySemantic.page)
            .navigationTitle("编辑记忆")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save(value)
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 300)
    }
}
