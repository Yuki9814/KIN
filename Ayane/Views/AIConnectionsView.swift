import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum AIConnectionsSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    #else
    static let page = AppTheme.rootBackground
    #endif
}

struct AIConnectionsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var connections: [AIConnectionProfile] = []
    @State private var defaultConnectionID = AIConnectionStore.legacyConnectionID
    @State private var credentialStatus: [UUID: String] = [:]
    @State private var testStatus: [UUID: ConnectionTestState] = [:]
    @State private var testTasks: [UUID: Task<Void, Never>] = [:]
    @State private var isPresentingAddConnection = false
    @State private var pendingDeleteConnection: AIConnectionProfile?
    @State private var pageMessage: String?
    @State private var pageMessageIsError = false
    @State private var imageAPIKey = ""
    @State private var loadedImageAPIKey = ""
    @State private var imageBaseURL = ""
    @State private var loadedImageBaseURL = ""
    @State private var imageModel = ""
    @State private var loadedImageModel = ""
    @State private var imageAPIStyle = ImageGenerationAPIStyle.imagesAPI
    @State private var loadedImageAPIStyle = ImageGenerationAPIStyle.imagesAPI
    @State private var imageAPIKeyStatus: String?
    @State private var showDeleteImageAPIKeyConfirmation = false

    var body: some View {
        Form {
            Section {
                ForEach(connections) { connection in
                    AIConnectionRow(
                        connection: connection,
                        isDefault: connection.id == defaultConnectionID,
                        credentialStatus: credentialStatus[connection.id] ?? "未检查",
                        testStatus: testStatus[connection.id],
                        onSetDefault: { setDefault(connection) },
                        onTest: { test(connection) },
                        onDelete: connection.id == AIConnectionStore.legacyConnectionID
                            ? nil
                            : { pendingDeleteConnection = connection }
                    )
                }
            } header: {
                Text("本机连接")
            } footer: {
                Text("默认连接会用于没有单独绑定连接的角色。角色卡可以覆盖这里的默认项。")
            }

            Section {
                Picker("请求方式", selection: $imageAPIStyle) {
                    ForEach(ImageGenerationAPIStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                #endif
                .accessibilityIdentifier("aiConnections.imageAPIStyle")
                .onChange(of: imageAPIStyle) { _, _ in
                    updateImageAPIKeyStatus()
                }

                TextField("API 根地址或完整 endpoint", text: $imageBaseURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("aiConnections.imageBaseURL")
                    .onChange(of: imageBaseURL) { _, _ in
                        updateImageAPIKeyStatus()
                    }

                TextField("图片模型 ID", text: $imageModel)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityIdentifier("aiConnections.imageModel")
                    .onChange(of: imageModel) { _, _ in
                        updateImageAPIKeyStatus()
                    }

                SecureField("图片生成 API Key", text: $imageAPIKey)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .privacySensitive()
                    .accessibilityIdentifier("aiConnections.imageAPIKey.field")
                    .onChange(of: imageAPIKey) { _, _ in
                        updateImageAPIKeyStatus()
                    }

                HStack(spacing: 10) {
                    Button("保存生图配置") {
                        saveImageConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!imageConfigurationCanSave)
                    .accessibilityIdentifier("aiConnections.imageAPIKey.save")

                    if !loadedImageAPIKey.isEmpty {
                        Button("删除", role: .destructive) {
                            showDeleteImageAPIKeyConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("aiConnections.imageAPIKey.delete")
                    }

                    Spacer(minLength: 0)

                    if let imageAPIKeyStatus {
                        Text(imageAPIKeyStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("图片生成 API")
            } footer: {
                Text("\(imageAPIStyle.detail)。在单聊的“更多－生成图片”中输入提示词后，KIN 会真实调用该接口，并把返回图片保存为本地聊天消息。密钥仅保存在本机钥匙串。")
            }

            Section {
                if let pageMessage {
                    StatusBanner(
                        text: pageMessage,
                        style: pageMessageIsError ? .error : .information
                    ) {
                        self.pageMessage = nil
                    }
                }
                Text("令牌仅保存在本机钥匙串；连接和角色绑定不进入 KIN 数据导出或 CloudKit。OpenAI 是 Codex/ChatGPT 登录兼容通道，可能受账号权限或上游变化影响；xAI 使用订阅 OAuth。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("隐私与兼容性")
            }
        }
        .formStyle(.grouped)
        .tint(AppTheme.accent)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(AIConnectionsSemantic.page)
        .frame(maxWidth: 820, alignment: .topLeading)
        .navigationTitle("AI 连接与订阅")
        #else
        .wechatDetailShell(title: "AI 连接与订阅")
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("新增", systemImage: "plus") {
                    isPresentingAddConnection = true
                }
                .accessibilityIdentifier("aiConnections.add")
            }
        }
        .sheet(isPresented: $isPresentingAddConnection) {
            AddAIConnectionSheet {
                reload()
                pageMessage = "登录凭据已保存，请点“测试连接”确认模型可用。"
                pageMessageIsError = false
            }
        }
        .confirmationDialog(
            "删除 \(pendingDeleteConnection?.displayName ?? "这个连接")？",
            isPresented: Binding(
                get: { pendingDeleteConnection != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteConnection = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除连接", role: .destructive) {
                deletePendingConnection()
            }
            Button("取消", role: .cancel) {
                pendingDeleteConnection = nil
            }
        } message: {
            Text("对应的订阅令牌也会从本机钥匙串删除，已绑定角色会恢复跟随默认连接。")
        }
        .confirmationDialog(
            "删除图片生成 API Key？",
            isPresented: $showDeleteImageAPIKeyConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除 API Key", role: .destructive) {
                deleteImageAPIKey()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会删除本机钥匙串中的图片生成密钥，不影响现有文字聊天连接。")
        }
        .onAppear {
            reload()
        }
        .onDisappear {
            testTasks.values.forEach { $0.cancel() }
            testTasks.removeAll()
        }
    }

    private func reload() {
        let loadedConnections = AIConnectionStore.connections()
        connections = loadedConnections
        defaultConnectionID = AIConnectionStore.defaultConnectionID()
        credentialStatus = Dictionary(uniqueKeysWithValues: loadedConnections.map { connection in
            (connection.id, credentialDescription(for: connection))
        })
        loadImageAPIKey()
    }

    private var imageAPIKeyIsDirty: Bool {
        imageAPIKey != loadedImageAPIKey
            || imageBaseURL != loadedImageBaseURL
            || imageModel != loadedImageModel
            || imageAPIStyle != loadedImageAPIStyle
    }

    private var imageConfigurationCanSave: Bool {
        imageAPIKeyIsDirty
            && !imageAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !imageBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !imageModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadImageAPIKey() {
        do {
            let configuration = SettingsStore.imageGenerationConfiguration()
            let value = try SettingsStore.imageGenerationAPIKey() ?? ""
            loadedImageBaseURL = configuration.baseURL
            imageBaseURL = configuration.baseURL
            loadedImageModel = configuration.model
            imageModel = configuration.model
            loadedImageAPIStyle = configuration.apiStyle
            imageAPIStyle = configuration.apiStyle
            loadedImageAPIKey = value
            imageAPIKey = value
            imageAPIKeyStatus = value.isEmpty ? "尚未填写 Key" : "配置已保存"
        } catch {
            imageAPIKeyStatus = error.localizedDescription
        }
    }

    private func updateImageAPIKeyStatus() {
        if imageAPIKeyIsDirty {
            imageAPIKeyStatus = "有未保存更改"
        } else {
            imageAPIKeyStatus = loadedImageAPIKey.isEmpty ? "尚未填写 Key" : "配置已保存"
        }
    }

    private func saveImageConfiguration() {
        do {
            let trimmed = imageAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let configuration = ImageGenerationConfiguration(
                baseURL: imageBaseURL,
                model: imageModel,
                apiStyle: imageAPIStyle
            )
            _ = try OpenAICompatibleImageGenerationClient.endpoint(for: configuration)
            try SettingsStore.saveImageGenerationAPIKey(trimmed)
            SettingsStore.saveImageGenerationConfiguration(configuration)
            let savedConfiguration = SettingsStore.imageGenerationConfiguration()
            imageAPIKey = trimmed
            loadedImageAPIKey = trimmed
            imageBaseURL = savedConfiguration.baseURL
            loadedImageBaseURL = savedConfiguration.baseURL
            imageModel = savedConfiguration.model
            loadedImageModel = savedConfiguration.model
            imageAPIStyle = savedConfiguration.apiStyle
            loadedImageAPIStyle = savedConfiguration.apiStyle
            imageAPIKeyStatus = "配置已保存，接口将在实际生成时验证"
        } catch {
            imageAPIKeyStatus = error.localizedDescription
        }
    }

    private func deleteImageAPIKey() {
        do {
            try SettingsStore.deleteImageGenerationAPIKey()
            imageAPIKey = ""
            loadedImageAPIKey = ""
            imageAPIKeyStatus = "已删除"
        } catch {
            imageAPIKeyStatus = error.localizedDescription
        }
    }

    private func setDefault(_ connection: AIConnectionProfile) {
        do {
            try AIConnectionStore.setDefaultConnectionID(connection.id)
            defaultConnectionID = connection.id
            pageMessage = "默认连接已切换为“\(connection.displayName)”。"
            pageMessageIsError = false
        } catch {
            pageMessage = error.localizedDescription
            pageMessageIsError = true
        }
    }

    private func deletePendingConnection() {
        guard let connection = pendingDeleteConnection else { return }
        pendingDeleteConnection = nil
        do {
            try AIConnectionStore.delete(id: connection.id)
            reload()
            pageMessage = "已删除“\(connection.displayName)”。"
            pageMessageIsError = false
        } catch {
            reload()
            pageMessage = error.localizedDescription
            pageMessageIsError = true
        }
    }

    private func test(_ connection: AIConnectionProfile) {
        guard testTasks[connection.id] == nil else { return }
        let connectionID = connection.id
        testStatus[connectionID] = .testing
        pageMessage = nil

        let task = Task { @MainActor in
            do {
                let resolved = try resolvedConnectionForTesting(connection)
                let result = try await OpenAICompatibleClient().testConnection(
                    configuration: resolved.configuration,
                    apiKey: resolved.credential
                )
                try Task.checkCancellation()
                testStatus[connectionID] = .success(result)
            } catch is CancellationError {
                testStatus[connectionID] = nil
            } catch {
                testStatus[connectionID] = .failure(error.localizedDescription)
            }
            testTasks[connectionID] = nil
        }
        testTasks[connectionID] = task
    }

    /// Resolve a specific row without changing the user's live default or any
    /// role binding. A short-lived UserDefaults suite lets the shared resolver
    /// exercise the same Keychain path that chat uses for that exact profile.
    private func resolvedConnectionForTesting(
        _ connection: AIConnectionProfile
    ) throws -> ResolvedAIConnection {
        let suiteName = "com.example.kin.connection-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw AIConnectionStoreError.invalidConnection
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(connection.providerID, forKey: SettingsKeys.providerID)
        defaults.set(connection.baseURL, forKey: SettingsKeys.baseURL)
        defaults.set(connection.model, forKey: SettingsKeys.model)
        defaults.set(connection.embeddingModel, forKey: SettingsKeys.embeddingModel)
        defaults.set(connection.temperature, forKey: SettingsKeys.temperature)
        defaults.set(connection.streamsResponses, forKey: SettingsKeys.streamResponses)

        if connection.id != AIConnectionStore.legacyConnectionID {
            try AIConnectionStore.save(connection, defaults: defaults)
        }
        try AIConnectionStore.setDefaultConnectionID(connection.id, defaults: defaults)
        return try AIConnectionStore.resolvedConnection(
            for: UUID(),
            defaults: defaults,
            legacyKeyLoader: {
                try SettingsStore.currentAPIKey(defaults: defaults)
            }
        )
    }

    private func credentialDescription(for connection: AIConnectionProfile) -> String {
        if connection.id == AIConnectionStore.legacyConnectionID {
            do {
                let key = try SettingsStore.currentAPIKey()?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return key?.isEmpty == false ? "API Key 已配置" : "未配置 API Key"
            } catch {
                return "无法读取 API Key"
            }
        }

        do {
            guard let data = try KeychainStore.loadConnectionCredential(
                connectionID: connection.id
            ), !data.isEmpty else {
                return "尚未完成登录"
            }
            if connection.kind == .chatGPTSubscription
                || connection.kind == .grokSubscription {
                guard (try? JSONDecoder().decode(
                    SubscriptionOAuthCredential.self,
                    from: data
                )) != nil else {
                    return "凭据格式异常"
                }
                return "登录凭据已保存 · 尚未测试"
            }
            return "凭据已配置"
        } catch {
            return "无法读取本机凭据"
        }
    }
}

private enum ConnectionTestState: Equatable {
    case testing
    case success(ConnectionTestResult)
    case failure(String)
}

private struct AIConnectionRow: View {
    let connection: AIConnectionProfile
    let isDefault: Bool
    let credentialStatus: String
    let testStatus: ConnectionTestState?
    let onSetDefault: () -> Void
    let onTest: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(connection.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        if isDefault {
                            Text("默认")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(providerLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("模型：\(connection.model.isEmpty ? "未配置" : connection.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(credentialStatus)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Button(testButtonTitle, action: onTest)
                    .buttonStyle(.bordered)
                    .disabled(testStatus == .testing)
                    .accessibilityIdentifier("aiConnections.test.\(connection.id.uuidString)")

                if !isDefault {
                    Button("设为默认", action: onSetDefault)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("aiConnections.default.\(connection.id.uuidString)")
                }

                if let onDelete {
                    Button("删除", role: .destructive, action: onDelete)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("aiConnections.delete.\(connection.id.uuidString)")
                }

                Spacer(minLength: 0)
            }

            if case .success(let result) = testStatus {
                Text("测试成功 · \(formattedLatency(result.latency)) · 回复：\(result.reply)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
                    .textSelection(.enabled)
            } else if case .failure(let message) = testStatus {
                Text("测试失败：\(message)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 5)
    }

    private var iconName: String {
        switch connection.kind {
        case .apiKey:
            "key.fill"
        case .chatGPTSubscription:
            "person.crop.circle.badge.checkmark"
        case .grokSubscription:
            "sparkles"
        }
    }

    private var providerLine: String {
        let provider = connection.kind == .apiKey
            ? ProviderPreset.resolve(connection.providerID).title
            : connection.kind.providerTitle
        return "\(provider) · \(connection.kind.title)"
    }

    private var statusColor: Color {
        if case .success = testStatus { return AppTheme.accent }
        if case .failure = testStatus { return .red }
        return .secondary
    }

    private var testButtonTitle: String {
        testStatus == .testing ? "测试中…" : "测试连接"
    }

    private func formattedLatency(_ latency: TimeInterval) -> String {
        latency < 1
            ? String(format: "%.0f ms", latency * 1_000)
            : String(format: "%.1f s", latency)
    }
}

private struct AddAIConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var kind: AIConnectionProfile.Kind = .chatGPTSubscription
    @State private var displayName = "ChatGPT 订阅"
    @State private var model = "gpt-5.5"
    @State private var shouldSetDefault = false
    @State private var authorization: SubscriptionDeviceAuthorization?
    @State private var authorizationTask: Task<Void, Never>?
    @State private var errorText: String?

    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("登录类型") {
                    Picker("订阅服务", selection: $kind) {
                        Text("ChatGPT 登录").tag(AIConnectionProfile.Kind.chatGPTSubscription)
                        Text("Grok 登录").tag(AIConnectionProfile.Kind.grokSubscription)
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                    .disabled(authorizationTask != nil)

                    Text(kind == .chatGPTSubscription
                         ? "使用 OpenAI 的 Codex/ChatGPT 设备登录。"
                         : "使用 xAI 的订阅 OAuth 设备登录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("连接信息") {
                    TextField("显示名称", text: $displayName)
                        .disabled(authorizationTask != nil)
                    TextField("模型 ID", text: $model)
                        .autocorrectionDisabled()
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .disabled(authorizationTask != nil)
                    Toggle("保存后设为默认连接", isOn: $shouldSetDefault)
                        .disabled(authorizationTask != nil)
                }

                if let authorization {
                    Section("完成官方登录") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("请在官方页面输入以下用户代码")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(authorization.userCode)
                                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                                .accessibilityIdentifier("aiConnections.oauth.userCode")
                            Text((authorization.verificationURLComplete
                                  ?? authorization.verificationURL).absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("aiConnections.oauth.verificationURL")
                            Button("打开官方验证页面", systemImage: "safari") {
                                openURL(
                                    authorization.verificationURLComplete
                                        ?? authorization.verificationURL
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("等待登录确认，完成后会自动保存连接…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        StatusBanner(text: errorText, style: .error) {
                            self.errorText = nil
                        }
                    }
                }

                Section {
                    Text("令牌只会写入本机钥匙串，连接描述不会携带访问令牌。登录页面和授权接口均为对应服务官方地址。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tint(AppTheme.accent)
            #if os(macOS)
            .scrollContentBackground(.hidden)
            .background(AIConnectionsSemantic.page)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 520)
            #endif
            .navigationTitle("新增订阅连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        authorizationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(startButtonTitle, systemImage: "arrow.right.circle") {
                        beginAuthorization()
                    }
                    .disabled(
                        authorizationTask != nil
                            || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("aiConnections.oauth.start")
                }
            }
        }
        .onChange(of: kind) { _, newKind in
            guard authorizationTask == nil else { return }
            switch newKind {
            case .chatGPTSubscription:
                displayName = "ChatGPT 订阅"
                model = "gpt-5.5"
            case .grokSubscription:
                displayName = "Grok 订阅"
                model = "grok-build"
            case .apiKey:
                displayName = "AI 连接"
                model = ""
            }
        }
        .onDisappear {
            authorizationTask?.cancel()
            authorizationTask = nil
        }
    }

    private var startButtonTitle: String {
        authorization == nil ? "开始登录" : "登录中…"
    }

    private func beginAuthorization() {
        guard authorizationTask == nil else { return }
        errorText = nil
        let selectedKind = kind
        let task = Task { @MainActor in
            do {
                let service = SubscriptionOAuthService()
                let deviceAuthorization = try await service.requestDeviceAuthorization(
                    kind: selectedKind
                )
                try Task.checkCancellation()
                authorization = deviceAuthorization
                let credential = try await service.completeDeviceAuthorization(
                    deviceAuthorization
                )
                try Task.checkCancellation()
                try save(
                    credential,
                    kind: selectedKind,
                    displayName: displayName,
                    model: model,
                    shouldSetDefault: shouldSetDefault
                )
                onSaved()
                dismiss()
            } catch is CancellationError {
                // Dismissing the sheet is the cancellation UI; do not show a
                // stale error after the user intentionally stopped polling.
            } catch {
                errorText = error.localizedDescription
            }
            authorizationTask = nil
        }
        authorizationTask = task
    }

    private func save(
        _ credential: SubscriptionOAuthCredential,
        kind: AIConnectionProfile.Kind,
        displayName: String,
        model: String,
        shouldSetDefault: Bool
    ) throws {
        let connectionID = UUID()
        let profile = AIConnectionProfile(
            id: connectionID,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            providerID: kind == .chatGPTSubscription
                ? ProviderPreset.openAI.rawValue
                : ProviderPreset.xAI.rawValue,
            baseURL: kind == .chatGPTSubscription
                ? "https://chatgpt.com/backend-api/codex"
                : "https://cli-chat-proxy.grok.com/v1",
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            embeddingModel: "",
            temperature: 0.8,
            streamsResponses: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        let encodedCredential = try JSONEncoder().encode(credential)
        try KeychainStore.saveConnectionCredential(
            encodedCredential,
            connectionID: connectionID
        )
        do {
            try AIConnectionStore.save(profile)
            if shouldSetDefault {
                try AIConnectionStore.setDefaultConnectionID(connectionID)
            }
        } catch {
            try? KeychainStore.deleteConnectionCredential(connectionID: connectionID)
            throw error
        }
    }
}
