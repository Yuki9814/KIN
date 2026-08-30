import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

private enum SettingsSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    #else
    static let page = AppTheme.rootBackground
    static let surface = AppTheme.rowBackground
    #endif
}

struct SettingsView: View {
    /// Settings can be presented as a focused service page on iOS while the
    /// macOS Settings scene keeps the historical complete form by using the
    /// default `.all` mode.
    enum Mode: Equatable {
        case all
        case service
        case personal

        fileprivate var includesService: Bool {
            self == .all || self == .service
        }

        fileprivate var includesPersonal: Bool {
            self == .all || self == .personal
        }
    }

    private let mode: Mode

    init(mode: Mode = .all) {
        self.mode = mode
    }

    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingsKeys.providerID) private var providerID = ProviderPreset.deepSeek.rawValue
    @AppStorage(SettingsKeys.baseURL) private var baseURL = ""
    @AppStorage(SettingsKeys.model) private var model = ""
    @AppStorage(SettingsKeys.embeddingModel) private var embeddingModel = ""
    @AppStorage(SettingsKeys.temperature) private var temperature = 0.8
    @AppStorage(SettingsKeys.streamResponses) private var streamResponses = true
    @AppStorage(SettingsKeys.typingIndicatorEnabled) private var typingIndicatorEnabled = true
    @AppStorage(SettingsKeys.humanizedReplyDelayEnabled) private var humanizedReplyDelayEnabled = true
    @AppStorage(SettingsKeys.timeInjectionEnabled) private var timeInjectionEnabled = true
    @AppStorage(SettingsKeys.autoExtractMemory) private var autoExtractMemory = true
    @AppStorage(SettingsKeys.memoryTokenBudget) private var memoryTokenBudget = 2_400
    @AppStorage(SettingsKeys.recentMessageLimit) private var recentMessageLimit = 24
    @AppStorage(SettingsKeys.rawHistoryRecallEnabled) private var rawHistoryRecallEnabled = true
    @AppStorage(SettingsKeys.rawHistoryTokenBudget) private var rawHistoryTokenBudget = 1_000
    @AppStorage(SettingsKeys.proactiveMessagesEnabled) private var proactiveMessagesEnabled = true
    @AppStorage(SettingsKeys.conversationCareEnabled) private var conversationCareEnabled = true
    @AppStorage(SettingsKeys.conversationCareFirstReminderMinutes)
    private var conversationCareFirstReminderMinutes =
        SettingsStore.defaultConversationCareFirstReminderMinutes
    @AppStorage(SettingsKeys.proactiveFollowUpEnabled) private var proactiveFollowUpEnabled = true
    @AppStorage(SettingsKeys.proactiveFollowUpMinDays) private var proactiveFollowUpMinDays = ProactiveMessagePolicy.defaultFollowUpMinDays
    @AppStorage(SettingsKeys.proactiveFollowUpMaxDays) private var proactiveFollowUpMaxDays = ProactiveMessagePolicy.defaultFollowUpMaxDays
    @AppStorage(SettingsKeys.proactiveQuietStartHour) private var proactiveQuietStartHour = 23
    @AppStorage(SettingsKeys.proactiveQuietEndHour) private var proactiveQuietEndHour = 8
    @AppStorage(SettingsKeys.cloudSyncEnabled) private var cloudSyncEnabled = false
    @AppStorage(SettingsKeys.worldviewAutoMatchEnabled) private var worldviewAutoMatchEnabled = true

    @State private var apiKey = ""
    @State private var loadedAPIKey = ""
    @State private var loadedCredentialID = ""
    @State private var keyStatus: String?
    @State private var availableModels: [String] = []
    @State private var isDiscoveringModels = false
    @State private var modelDiscoveryMessage: String?
    @State private var modelDiscoveryTask: Task<Void, Never>?
    @State private var activeModelDiscoveryID: UUID?
    @State private var showDeleteKeyConfirmation = false
    @State private var showClearDataConfirmation = false
    @State private var pendingCloudSyncValue: Bool?
    @State private var showCloudSwitchConfirmation = false
    @State private var showStopCloudDrainConfirmation = false
    @State private var exportDocument: AyaneDataExportDocument?
    @State private var isExporting = false
    @State private var dataManagementMessage: String?
    @State private var dataManagementIsError = false
    @State private var isClearingData = false
    @State private var isSelectingRestoreFile = false
    @State private var isReadingRestoreFile = false
    @State private var isRestoringData = false
    @State private var pendingRestoreData: Data?
    @State private var pendingRestoreSummary: DataImportSummary?
    @State private var showRestoreConfirmation = false
    @State private var showsAPIUsageInfo = false
    #if os(iOS)
    @State private var proactiveNotificationStatus:
        ProactiveNotificationAuthorizationStatus = .notDetermined
    @State private var proactiveNotificationMessage: String?
    @State private var isSchedulingNotificationTest = false
    #endif

    var body: some View {
        documentPresentationView
    }

    private var coreForm: some View {
        Form {
            if mode.includesService {
                Section("API") {
                NavigationLink {
                    AIConnectionsView()
                } label: {
                    LabeledContent(
                        "AI 连接与订阅",
                        value: "\(AIConnectionStore.connections().count) 个"
                    )
                }

                Text("可同时保留现有 DeepSeek API Key，并添加多个 ChatGPT 或 Grok 登录连接；每个角色可在角色卡中单独选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("API 提供商", selection: $providerID) {
                    ForEach(ProviderPreset.allCases) { provider in
                        Text("\(provider.regionTitle) · \(provider.title)")
                            .tag(provider.rawValue)
                    }
                }
#if os(macOS)
                .pickerStyle(.menu)
#endif

                TextField("API 地址，例如 https://host.example/v1", text: $baseURL)
                    .textContentType(.URL)
                HStack(spacing: 8) {
                    SecureField("API Key（本机钥匙串）", text: $apiKey)
                    Button {
                        showsAPIUsageInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看 API 调用与费用说明")
                }

                HStack {
                    Button(isDiscoveringModels ? "正在获取模型…" : "保存并尝试获取模型") {
                        saveKeyAndDiscoverModels()
                    }
                    .disabled(
                        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isDiscoveringModels
                    )
                    Button(appModel.isTestingConnection ? "正在测试…" : "测试连接") {
                        appModel.testConnection()
                    }
                    .disabled(
                        baseURL.isEmpty
                            || model.isEmpty
                            || keyIsDirty
                            || loadedAPIKey.isEmpty
                            || isDiscoveringModels
                            || appModel.isTestingConnection
                    )
                    Spacer()
                    if let keyStatus {
                        Text(keyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !availableModels.isEmpty {
                    Picker("可用聊天模型", selection: $model) {
                        if model.isEmpty {
                            Text("请选择模型").tag("")
                        }
                        ForEach(modelChoices, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                    }
#if os(macOS)
                    .pickerStyle(.menu)
#endif
                }

                TextField("聊天模型 ID（也可手动填写）", text: $model)

                if let modelDiscoveryMessage {
                    Text(modelDiscoveryMessage)
                        .font(.caption)
                        .foregroundStyle(availableModels.isEmpty ? Color.secondary : AppTheme.accent)
                        .textSelection(.enabled)
                }

                Text("保存后会尝试读取提供商公开的模型列表；若区域或工作空间不支持，可直接手填模型 ID。仅预设官方 OpenAI 兼容接口，Claude 等原生协议不会被伪装成兼容提供商。连接测试会发送一次很短的请求，可能产生少量费用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let connection = appModel.connectionTestText {
                    Text(connection)
                        .font(.caption)
                        .foregroundStyle(connection.hasPrefix("连接成功") ? AppTheme.accent : Color.secondary)
                        .textSelection(.enabled)
                }

                    Toggle("流式显示回复", isOn: $streamResponses)
                    LabeledContent("温度") {
                        Slider(value: $temperature, in: 0...1.5, step: 0.1)
                            .frame(maxWidth: 220)
                        Text(temperature, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                    }
                }
            }

            if mode.includesPersonal {
                Section("聊天显示") {
                Toggle("正在输入状态", isOn: $typingIndicatorEnabled)
                Text("角色生成回复时，在聊天导航栏显示“正在输入中…”。关闭后仍会正常生成回复，只隐藏这个状态提示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("真人发送节奏", isOn: $humanizedReplyDelayEnabled)
                Text("开启时，API 完成后随机等待 3–5 秒再显示第一条；后续每段按字数等待 1.5–4 秒。关闭后第一条立即显示，后续每段固定等待 1.2 秒。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("注入时间上下文", isOn: $timeInjectionEnabled)
                Text("开启后，普通聊天和群聊都会把当前日期、时间、时区与上次有效消息间隔交给角色；关闭后不注入这些时间信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("时间观念与主动消息") {
                Toggle("允许角色主动联系", isOn: $proactiveMessagesEnabled)
                Toggle("当前角色主动联系", isOn: proactiveRoleBinding)
                    .disabled(!proactiveMessagesEnabled)
                Toggle("连续聊天关怀", isOn: $conversationCareEnabled)
                    .disabled(!proactiveMessagesEnabled)
                if conversationCareEnabled {
                    Stepper(
                        "首次关怀：\(conversationCareFirstReminderMinutes) 分钟",
                        value: $conversationCareFirstReminderMinutes,
                        in: SettingsStore.minimumConversationCareFirstReminderMinutes...SettingsStore.maximumConversationCareFirstReminderMinutes,
                        step: 30
                    )
                    .disabled(!proactiveMessagesEnabled)
                }
                Toggle("未回复跟进", isOn: $proactiveFollowUpEnabled)
                    .disabled(!proactiveMessagesEnabled)
                if proactiveFollowUpEnabled {
                    Stepper(
                        "跟进最短：\(proactiveFollowUpMinDays) 天",
                        value: $proactiveFollowUpMinDays,
                        in: ProactiveMessagePolicy.minimumFollowUpDays...ProactiveMessagePolicy.maximumFollowUpDays
                    )
                    Stepper(
                        "跟进最长：\(proactiveFollowUpMaxDays) 天",
                        value: $proactiveFollowUpMaxDays,
                        in: proactiveFollowUpMinDays...ProactiveMessagePolicy.maximumFollowUpDays
                    )
                }
                Stepper(
                    "静默开始：\(String(format: "%02d:00", proactiveQuietStartHour))",
                    value: $proactiveQuietStartHour,
                    in: 0...23
                )
                Stepper(
                    "静默结束：\(String(format: "%02d:00", proactiveQuietEndHour))",
                    value: $proactiveQuietEndHour,
                    in: 0...23
                )
                Text(proactiveExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #if os(iOS)
                Divider()
                LabeledContent("系统通知", value: proactiveNotificationStatusText)
                HStack {
                    if proactiveNotificationStatus == .notDetermined {
                        Button("允许通知") {
                            requestProactiveNotificationAuthorization()
                        }
                    } else if proactiveNotificationStatus == .denied {
                        Button("打开系统通知设置") {
                            openSystemNotificationSettings()
                        }
                    }
                    Button(
                        isSchedulingNotificationTest
                            ? "正在排定…"
                            : "1 分钟后测试通知"
                    ) {
                        scheduleProactiveNotificationTest()
                    }
                    .disabled(
                        isSchedulingNotificationTest
                            || proactiveNotificationStatus == .denied
                    )
                }
                if let proactiveNotificationMessage {
                    Text(proactiveNotificationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                #endif
            }

                Section("世界观") {
                NavigationLink("世界观库与角色匹配") {
                    WorldProfileView()
                }
                Toggle("新增好友时自动匹配世界观", isOn: $worldviewAutoMatchEnabled)
                Text("角色与世界观独立保存；每个角色都可以单独绑定世界观。开启后，新增好友时会依据角色信息匹配世界观，之后仍可在角色页面手动改选。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("长期记忆") {
                Toggle("启用长期记忆", isOn: $autoExtractMemory)
                TextField("向量模型（可选）", text: $embeddingModel)
                Stepper("记忆注入预算：\(memoryTokenBudget) tokens", value: $memoryTokenBudget, in: 400...8_000, step: 200)
                Stepper("最近对话：\(recentMessageLimit) 条", value: $recentMessageLimit, in: 4...80, step: 4)
                Toggle("从历史原文补充召回", isOn: $rawHistoryRecallEnabled)
                if rawHistoryRecallEnabled {
                    Stepper(
                        "历史原文预算：\(rawHistoryTokenBudget) tokens",
                        value: $rawHistoryTokenBudget,
                        in: 200...1_000,
                        step: 200
                    )
                }
                Text(memoryExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("Mac 与 iPhone 同步") {
                Toggle("使用 iCloud 私有数据库", isOn: cloudSyncBinding)
                LabeledContent("当前实际存储") {
                    Text(appModel.isUsingCloud ? "iCloud 私有数据库" : "仅本机")
                        .foregroundStyle(appModel.isUsingCloud ? AppTheme.accent : Color.secondary)
                }
                if let target = appModel.pendingStorageTarget {
                    LabeledContent("下次启动目标") {
                        Text(target.title)
                            .foregroundStyle(.orange)
                    }
                }
                if appModel.isCloudSourceDrainActive {
                    LabeledContent("云端延迟补收") {
                        Text(appModel.cloudSourceDrainStatusText ?? "持续补收中")
                            .foregroundStyle(.orange)
                    }
                    Button("确认云端已稳定并停止补收", role: .destructive) {
                        showStopCloudDrainConfirmation = true
                    }
                }
                Text("切换会在下次启动时同时读取原存储与目标存储，按稳定 ID 非破坏性合并角色、会话和长期记忆；原数据库不会删除。从 iCloud 切回本机后会继续补收延迟导入，直到你确认云端已稳定。真实双设备同步仍需要两个 target 使用同一个 CloudKit container、有效签名和同一 Apple 账户；API Key 与模型连接设置不自动同步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

                Section("隐私") {
                LabeledContent("API Key") { Text("本机 Keychain") }
                LabeledContent("对话与记忆") {
                    Text(appModel.isUsingCloud ? "iCloud 私有数据库" : "应用沙盒数据库")
                }
                LabeledContent("角色身份") {
                    Text(appModel.isUsingCloud ? "随私有数据库同步" : "应用沙盒数据库")
                }
                Button("删除本机 API Key", role: .destructive) {
                    showDeleteKeyConfirmation = true
                }
            }

                Section("数据管理") {
                Button("导出本地数据", systemImage: "square.and.arrow.up") {
                    prepareDataExport()
                }
                .disabled(isRestoringData || isReadingRestoreFile || isClearingData)

                Button(
                    isReadingRestoreFile ? "正在检查备份…" : "从 JSON 备份恢复",
                    systemImage: "square.and.arrow.down"
                ) {
                    isSelectingRestoreFile = true
                }
                .disabled(isRestoringData || isReadingRestoreFile || isClearingData)

                NavigationLink {
                    KINPortableArchiveSettingsView()
                } label: {
                    Label("加密便携备份", systemImage: "lock.doc")
                }

                Text("导出包含全部会话、原始事件、记忆断言、证据、摘要、遗忘墓碑，以及人格和非敏感设置。恢复前会校验 ID、引用、原文哈希和证据范围；API Key 永远留在本机钥匙串，iCloud 开关也不会被备份静默改变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isClearingData ? "正在清除…" : "清除全部对话与记忆", role: .destructive) {
                    showClearDataConfirmation = true
                }
                .disabled(isClearingData || isRestoringData || isReadingRestoreFile)

                Text(appModel.isUsingCloud
                     ? "当前已启用 iCloud 私有数据库。清除会提交云端删除，但尚无全局清除屏障；请先让其他设备完成同步并保持在线，避免离线旧记录稍后重新出现。"
                     : "当前数据仅保存在本机应用沙盒中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let dataManagementMessage {
                    StatusBanner(
                        text: dataManagementMessage,
                        style: dataManagementIsError ? .error : .information
                    ) {
                        self.dataManagementMessage = nil
                    }
                }
                }
            }
        }
        .formStyle(.grouped)
        // Keep every native Form control on the WeChat green accent. This is
        // deliberately local to the settings form so a detail-shell tint
        // cannot silently turn toggles, sliders, or links into system blue.
        .tint(AppTheme.accent)
#if os(macOS)
        .scrollContentBackground(.hidden)
        .background(SettingsSemantic.page)
#endif
#if os(iOS)
        .wechatDetailShell(title: settingsTitle)
#else
        .navigationTitle(settingsTitle)
#endif
    }

    private var lifecycleForm: some View {
        coreForm
        .task {
            normalizeFollowUpRange()
            normalizeConversationCareTiming()
            #if os(iOS)
            await refreshProactiveNotificationStatus()
            #endif
            if mode.includesService {
                normalizeProviderSelection()
                loadKeyState()
            }
        }
        .onDisappear {
            cancelModelDiscovery(clearResults: false)
        }
        .onChange(of: providerID) {
            guard mode.includesService else { return }
            applySelectedProvider()
        }
        .onChange(of: apiKey) {
            handleAPIKeyChange()
        }
        .onChange(of: baseURL) {
            handleBaseURLChange()
        }
        .onChange(of: model) {
            appModel.resetConnectionTest()
        }
        .onChange(of: autoExtractMemory) {
            appModel.memorySettingDidChange(enabled: autoExtractMemory)
        }
        .onChange(of: proactiveMessagesEnabled) {
            appModel.proactiveMessagingSettingDidChange(enabled: proactiveMessagesEnabled)
        }
        .onChange(of: conversationCareEnabled) {
            appModel.conversationCareSettingDidChange(enabled: conversationCareEnabled)
        }
        .onChange(of: conversationCareFirstReminderMinutes) {
            normalizeConversationCareTiming()
            appModel.conversationCareTimingSettingDidChange()
        }
        .onChange(of: proactiveFollowUpEnabled) {
            appModel.proactiveFollowUpSettingDidChange(enabled: proactiveFollowUpEnabled)
        }
        .onChange(of: proactiveFollowUpMinDays) {
            normalizeFollowUpRange()
        }
        .onChange(of: proactiveFollowUpMaxDays) {
            normalizeFollowUpRange()
        }
    }

    private var dialogPresentationView: some View {
        lifecycleForm
        .sheet(isPresented: $showsAPIUsageInfo) {
            APIUsageInfoView()
        }
        .confirmationDialog("删除本机 API Key？", isPresented: $showDeleteKeyConfirmation) {
            Button("删除", role: .destructive) { deleteKey() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            pendingCloudSyncValue == true ? "切换到 iCloud 存储？" : "切换到仅本机存储？",
            isPresented: $showCloudSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button(pendingCloudSyncValue == true ? "准备合并并切换到 iCloud" : "准备合并并切换到本机") {
                confirmCloudSwitch()
            }
            Button("先导出额外备份") {
                pendingCloudSyncValue = nil
                prepareDataExport()
            }
            Button("取消", role: .cancel) {
                pendingCloudSyncValue = nil
            }
        } message: {
            Text("确认后请关闭并重新打开 KIN。下次启动会把两边已有的会话、原始事件、记忆、证据、摘要与遗忘标记增量合并；不会清空目标，也不会删除源数据库。合并失败会保留重试记录。")
        }
        .confirmationDialog(
            "停止 CloudKit 延迟补收？",
            isPresented: $showStopCloudDrainConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认稳定并停止补收", role: .destructive) {
                cloudSyncEnabled = false
                dataManagementIsError = false
                dataManagementMessage = appModel.confirmCloudSourceDrainStop()
            }
            Button("继续安全补收", role: .cancel) {}
        } message: {
            Text("仅当其他设备已经完成同步、云端不再有待导入记录时再停止。停止后，本机数据库不会删除；但之后才到达 iCloud 源的记录不会自动进入本机，除非重新启用 iCloud。")
        }
        .confirmationDialog(
            "清除全部本地对话与记忆？",
            isPresented: $showClearDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除对话与记忆", role: .destructive) {
                clearAllLocalData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(appModel.isUsingCloud
                 ? "这会删除当前 iCloud 存储中可见的全部会话、原始事件、记忆、证据、摘要和遗忘标记，再新建一个默认会话。请先让其他设备同步并保持在线；离线设备中尚未上传的旧记录仍可能稍后重新出现。角色身份与 API Key 都会保留。"
                 : "这会删除应用沙盒中的全部会话、原始事件、记忆、证据、摘要和遗忘标记，并新建一个默认会话。角色身份与 API Key 都会保留。")
        }
        .confirmationDialog(
            "用这份备份替换当前数据？",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复并替换当前数据", role: .destructive) {
                restorePendingBackup()
            }
            Button("取消", role: .cancel) {
                pendingRestoreData = nil
                pendingRestoreSummary = nil
            }
        } message: {
            if let summary = pendingRestoreSummary {
                Text(restoreConfirmationText(summary))
            }
        }
    }

    private var documentPresentationView: some View {
        dialogPresentationView
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentTypes: AyaneDataExportDocument.readableContentTypes,
            defaultFilename: DataExportService.defaultFilename()
        ) { handleExportResult($0) }
        .fileImporter(
            isPresented: $isSelectingRestoreFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { handleImportResult($0) }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 660, maxWidth: 820, minHeight: 540, alignment: .topLeading)
        .background(SettingsSemantic.page.ignoresSafeArea())
        #endif
    }

    private var memoryExplanation: String {
        autoExtractMemory
            ? "每个完成的对话轮次都会排队；回复完成后闲置 2 秒或累计 4 轮时批量整理，启动时补处理积压。明确说“记住……”会立即在本机写入；忘记、编辑与确认请在记忆库操作。约 20 轮后自动维护滚动摘要。"
            : "关闭后不会自动创建或整理长期记忆；原始对话仍完整保留，也可以手动整理积压。"
    }

    private var settingsTitle: String {
        mode == .service ? "服务" : "设置"
    }

    private var proactiveExplanation: String {
        let followUpText = proactiveFollowUpEnabled
            ? "未回复时会在 \(proactiveFollowUpMinDays)–\(proactiveFollowUpMaxDays) 天后再跟进一次"
            : "未回复跟进已关闭"
        let careText = conversationCareEnabled
            ? "同一段对话连续活动满 \(conversationCareFirstReminderMinutes) 分钟时，角色会在到点后结合真实已聊时长主动关怀；若仍连续到 180 分钟，会再关怀一次"
            : "连续聊天关怀已关闭"
        return "\(careText)。连续 20 分钟没有有效互动就视为本轮结束，这类关怀只在应用处于前台时触发，并不依赖上方的提示词时间注入。角色也会依据好感度在 3–14 天后自然联系；\(followUpText)。静默时段只延后离线主动消息。"
    }

    #if os(iOS)
    private var proactiveNotificationStatusText: String {
        switch proactiveNotificationStatus {
        case .notDetermined: "尚未询问"
        case .denied: "已关闭"
        case .authorized: "已允许"
        case .provisional: "临时允许"
        case .ephemeral: "本次允许"
        }
    }

    private func refreshProactiveNotificationStatus() async {
        proactiveNotificationStatus = await ProactiveNotificationService.shared
            .authorizationStatus()
    }

    private func requestProactiveNotificationAuthorization() {
        Task {
            proactiveNotificationStatus = await ProactiveNotificationService.shared
                .requestAuthorization()
            proactiveNotificationMessage = proactiveNotificationStatus == .denied
                ? "系统通知未开启；可以随时前往系统设置修改。"
                : "系统通知已开启。"
            if proactiveNotificationStatus != .denied {
                appModel.processDueProactiveTasks()
            }
        }
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    private func scheduleProactiveNotificationTest() {
        isSchedulingNotificationTest = true
        proactiveNotificationMessage = nil
        let route = ProactiveNotificationRoute(
            taskID: UUID(),
            roleID: appModel.currentRoleID,
            conversationID: appModel.currentConversation.id,
            stage: .test
        )
        Task {
            let didSchedule = await ProactiveNotificationService.shared.schedule(
                route: route,
                title: appModel.persona.name,
                body: "测试通知：即使 KIN 被划掉，我也还能来找你。",
                at: Date().addingTimeInterval(60)
            )
            await refreshProactiveNotificationStatus()
            isSchedulingNotificationTest = false
            proactiveNotificationMessage = didSchedule
                ? "已排定 1 分钟后的测试通知。现在可以划掉 KIN。"
                : "测试通知未能排定，请检查系统通知权限。"
        }
    }
    #endif

    private func normalizeConversationCareTiming() {
        let normalized = min(
            SettingsStore.maximumConversationCareFirstReminderMinutes,
            max(
                SettingsStore.minimumConversationCareFirstReminderMinutes,
                conversationCareFirstReminderMinutes
            )
        )
        if conversationCareFirstReminderMinutes != normalized {
            conversationCareFirstReminderMinutes = normalized
        }
    }

    private func normalizeFollowUpRange() {
        let lowerBound = ProactiveMessagePolicy.minimumFollowUpDays
        let upperBound = ProactiveMessagePolicy.maximumFollowUpDays
        let normalizedMin = min(upperBound, max(lowerBound, proactiveFollowUpMinDays))
        let normalizedMax = min(upperBound, max(normalizedMin, proactiveFollowUpMaxDays))
        if proactiveFollowUpMinDays != normalizedMin {
            proactiveFollowUpMinDays = normalizedMin
        }
        if proactiveFollowUpMaxDays != normalizedMax {
            proactiveFollowUpMaxDays = normalizedMax
        }
    }

    private var proactiveRoleBinding: Binding<Bool> {
        Binding(
            get: {
                SettingsStore.proactiveMessagesEnabled(
                    roleID: appModel.currentRoleID
                )
            },
            set: { enabled in
                SettingsStore.setProactiveMessagesEnabled(
                    enabled,
                    roleID: appModel.currentRoleID
                )
                appModel.proactiveMessagingSettingDidChange(
                    enabled: enabled,
                    roleID: appModel.currentRoleID
                )
            }
        )
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        isExporting = false
        switch result {
        case .success:
            dataManagementIsError = false
            dataManagementMessage = "本地数据已导出。"
        case .failure(let error):
            dataManagementIsError = true
            dataManagementMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            inspectRestoreFile(at: url)
        case .failure(let error):
            dataManagementIsError = true
            dataManagementMessage = "读取备份失败：\(error.localizedDescription)"
        }
    }

    private var cloudSyncBinding: Binding<Bool> {
        Binding(
            get: {
                appModel.pendingStorageTarget?.usesCloud ?? appModel.isUsingCloud
            },
            set: { requestedValue in
                let currentValue = appModel.pendingStorageTarget?.usesCloud
                    ?? appModel.isUsingCloud
                guard requestedValue != currentValue else { return }
                pendingCloudSyncValue = requestedValue
                showCloudSwitchConfirmation = true
            }
        )
    }

    private var selectedProvider: ProviderPreset {
        ProviderPreset.resolve(providerID)
    }

    private var modelChoices: [String] {
        guard !model.isEmpty, !availableModels.contains(model) else {
            return availableModels
        }
        return [model] + availableModels
    }

    private var keyIsDirty: Bool {
        apiKey != loadedAPIKey || loadedCredentialID != credentialID
    }

    private var credentialID: String {
        selectedProvider.credentialID(for: baseURL)
    }

    private func handleAPIKeyChange() {
        cancelModelDiscovery(clearResults: true)
        appModel.resetConnectionTest()
        if keyIsDirty {
            keyStatus = "有未保存更改"
        } else if loadedAPIKey.isEmpty {
            keyStatus = "尚未保存"
        } else {
            keyStatus = "已安全保存"
        }
    }

    private func handleBaseURLChange() {
        cancelModelDiscovery(clearResults: true)
        appModel.resetConnectionTest()
        if selectedProvider != .custom,
           ProviderPreset.matching(baseURL: baseURL) != selectedProvider {
            providerID = ProviderPreset.custom.rawValue
            return
        }
        guard selectedProvider == .custom,
              loadedCredentialID != credentialID else { return }
        loadedAPIKey = ""
        apiKey = ""
        loadedCredentialID = credentialID
        keyStatus = "地址已变更，请重新输入密钥"
    }

    private func normalizeProviderSelection() {
        let selected = ProviderPreset.resolve(providerID)
        if selected != .custom,
           !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           ProviderPreset.matching(baseURL: baseURL) != selected {
            providerID = ProviderPreset.matching(baseURL: baseURL)?.rawValue
                ?? ProviderPreset.custom.rawValue
        }
    }

    private func applySelectedProvider() {
        guard mode.includesService else { return }
        cancelModelDiscovery(clearResults: true)
        appModel.resetConnectionTest()

        let provider = selectedProvider
        if provider != .custom {
            baseURL = provider.defaultBaseURL
            model = provider.initialModel
        }
        loadKeyState()
    }

    private func loadKeyState() {
        do {
            let currentCredentialID = credentialID
            let value = try KeychainStore.loadAPIKey(providerID: currentCredentialID)
            loadedAPIKey = value ?? ""
            apiKey = loadedAPIKey
            loadedCredentialID = currentCredentialID
            keyStatus = value == nil ? "尚未保存" : "已安全保存"
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    @discardableResult
    private func saveKey() -> Bool {
        do {
            let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentCredentialID = credentialID
            try KeychainStore.saveAPIKey(trimmedKey, providerID: currentCredentialID)
            // Keep the current field value so this synchronous save does not
            // look like a user edit and cancel the discovery started next.
            // Both the persisted value and outgoing model-list request are
            // trimmed at their security boundaries.
            loadedAPIKey = apiKey
            loadedCredentialID = currentCredentialID
            keyStatus = "已安全保存"
            return true
        } catch {
            keyStatus = error.localizedDescription
            return false
        }
    }

    private func saveKeyAndDiscoverModels() {
        guard saveKey() else { return }
        discoverModels()
    }

    private func discoverModels() {
        cancelModelDiscovery(clearResults: true)
        let provider = selectedProvider
        let requestedBaseURL = baseURL
        let key = loadedAPIKey
        let discoveryID = UUID()
        activeModelDiscoveryID = discoveryID
        isDiscoveringModels = true
        modelDiscoveryMessage = "正在向 \(provider.title) 获取模型列表…"
        appModel.resetConnectionTest()

        modelDiscoveryTask = Task {
            do {
                let models = try await ProviderModelCatalogClient().listChatModels(
                    provider: provider,
                    baseURL: requestedBaseURL,
                    apiKey: key
                )
                try Task.checkCancellation()
                guard activeModelDiscoveryID == discoveryID,
                      provider == selectedProvider,
                      requestedBaseURL == baseURL,
                      key == loadedAPIKey else { return }
                availableModels = models
                if model.isEmpty, models.count == 1 {
                    model = models[0]
                }
                modelDiscoveryMessage = "已获取 \(models.count) 个可选聊天模型。"
            } catch is CancellationError {
                return
            } catch {
                guard activeModelDiscoveryID == discoveryID,
                      provider == selectedProvider,
                      requestedBaseURL == baseURL,
                      key == loadedAPIKey else { return }
                availableModels = []
                modelDiscoveryMessage = error.localizedDescription
            }
            guard activeModelDiscoveryID == discoveryID else { return }
            isDiscoveringModels = false
            modelDiscoveryTask = nil
            activeModelDiscoveryID = nil
        }
    }

    private func cancelModelDiscovery(clearResults: Bool) {
        modelDiscoveryTask?.cancel()
        modelDiscoveryTask = nil
        activeModelDiscoveryID = nil
        isDiscoveringModels = false
        if clearResults {
            availableModels = []
            modelDiscoveryMessage = nil
        }
    }

    private func deleteKey() {
        do {
            try KeychainStore.deleteAPIKey(providerID: credentialID)
            loadedAPIKey = ""
            apiKey = ""
            loadedCredentialID = credentialID
            keyStatus = "已删除"
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func prepareDataExport() {
        do {
            exportDocument = try appModel.makeDataExportDocument()
            isExporting = true
            dataManagementMessage = nil
            dataManagementIsError = false
        } catch {
            dataManagementIsError = true
            dataManagementMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func confirmCloudSwitch() {
        guard let requested = pendingCloudSyncValue else { return }
        do {
            let message = try appModel.prepareStorageSwitch(toCloud: requested)
            cloudSyncEnabled = requested
            dataManagementIsError = false
            dataManagementMessage = message
        } catch {
            cloudSyncEnabled = appModel.isUsingCloud
            dataManagementIsError = true
            dataManagementMessage = "无法准备存储切换：\(error.localizedDescription)"
        }
        pendingCloudSyncValue = nil
    }

    private func clearAllLocalData() {
        isClearingData = true
        Task {
            defer { isClearingData = false }
            do {
                try await appModel.clearAllLocalData()
                dataManagementIsError = false
                dataManagementMessage = appModel.isUsingCloud
                    ? "已清除当前存储中可见的对话与记忆，并提交云端删除；尚未同步的离线旧记录仍可能重新出现。角色身份已保留，AI 凭据仍在本机钥匙串中。"
                    : "已清除全部本地对话与记忆，并新建默认会话。角色身份已保留，AI 凭据仍在本机钥匙串中。"
            } catch {
                dataManagementIsError = true
                dataManagementMessage = "清除失败：\(error.localizedDescription)"
            }
        }
    }

    private func inspectRestoreFile(at url: URL) {
        isReadingRestoreFile = true
        dataManagementMessage = nil
        dataManagementIsError = false
        let hasSecurityScope = url.startAccessingSecurityScopedResource()

        Task {
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                isReadingRestoreFile = false
            }
            do {
                let (data, summary) = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return (data, try DataImportService.inspect(data))
                }.value
                pendingRestoreData = data
                pendingRestoreSummary = summary
                showRestoreConfirmation = true
            } catch {
                pendingRestoreData = nil
                pendingRestoreSummary = nil
                dataManagementIsError = true
                dataManagementMessage = "备份检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func restorePendingBackup() {
        guard let data = pendingRestoreData else { return }
        isRestoringData = true
        Task {
            defer {
                isRestoringData = false
                pendingRestoreData = nil
                pendingRestoreSummary = nil
            }
            do {
                let summary = try await appModel.restoreData(from: data)
                dataManagementIsError = false
                dataManagementMessage = "备份恢复完成：\(summary.profiles) 份角色、\(summary.events) 条原始事件、\(summary.memories) 条记忆。AI 凭据、角色连接绑定和本机 iCloud 开关未改变。"
            } catch {
                dataManagementIsError = true
                dataManagementMessage = "恢复失败：\(error.localizedDescription)"
            }
        }
    }

    private func restoreConfirmationText(_ summary: DataImportSummary) -> String {
        let cloudNotice = appModel.isUsingCloud
            ? "当前使用 iCloud 私有数据库，替换结果会通过 CloudKit 传播到其他设备。"
            : "当前使用本机数据库。"
        return "备份日期：\(summary.exportedAt.formatted(date: .abbreviated, time: .shortened))；包含 \(summary.profiles) 份角色、\(summary.events) 条原始事件、\(summary.memories) 条记忆和 \(summary.totalRecords) 条总记录。恢复会完整替换现有角色、对话与记忆。\(cloudNotice) AI 凭据和本机角色连接绑定不会改变。"
    }
}

private struct APIUsageInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                usageRow(
                    title: "聊天与连接测试",
                    detail: "每次聊天会调用一次聊天模型；连接测试会发送一次很短的请求，均可能产生少量费用。"
                )
                usageRow(
                    title: "朋友圈",
                    detail: "角色定时发布会调用一次聊天模型。用户发布后，仅由好感度、角色性格和内容相关性选中的角色生成点赞或评论；回复角色评论时还可能调用一次模型继续互动。"
                )
                usageRow(
                    title: "长期记忆",
                    detail: "自动记忆会在回复完成后闲置 2 秒、累计 4 轮或启动补积压时调用聊天模型；约 20 轮时维护滚动摘要。配置向量模型后还可能产生向量请求。“记住……”指令优先在本机立即写入；忘记和修改在记忆库操作。"
                )
                usageRow(
                    title: "凭据与备份",
                    detail: "API Key、访问令牌和刷新令牌仅保存在本机钥匙串，不写入普通设置，也不进入 KIN 数据导出或 CloudKit。实际用量规则由所选提供商和订阅决定。"
                )
            }
            .navigationTitle("API 调用与费用")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 360)
    }

    private func usageRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
