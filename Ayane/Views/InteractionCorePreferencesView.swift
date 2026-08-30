import SwiftUI

/// Reusable settings surface for the interaction-core preferences. It is kept
/// separate from the chat transcript so low-frequency controls do not crowd the
/// primary messaging UI. Group details and the service settings page can both
/// navigate to this screen without duplicating persistence logic.
struct InteractionCorePreferencesView: View {
    @Environment(AppModel.self) private var appModel

    let conversationID: UUID?
    let imageConnectionID: UUID?

    @State private var groupPreferences = GroupInteractionPreferences.defaultValue
    @State private var imagePreferences = ImageInteractionPreferences.defaultValue
    @State private var hasLoaded = false
    @State private var statusText: String?
    @State private var errorText: String?

    init(
        conversationID: UUID? = nil,
        imageConnectionID: UUID? = nil
    ) {
        self.conversationID = conversationID
        self.imageConnectionID = imageConnectionID
    }

    var body: some View {
        Form {
            if conversationID != nil {
                groupSection
            }
            imageSection

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

            Section {
                Button(action: save) {
                    Label("保存交互设置", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!hasLoaded)

                Button("恢复安全默认值", role: .destructive, action: reset)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(!hasLoaded)
            } footer: {
                Text("这些设置只影响未来的回复规划和生图请求，不会改写已有消息、记忆、关系事件或图片。")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("交互与生图")
        .kinInlineNavigationTitle()
        .onAppear(perform: load)
        .accessibilityIdentifier("interaction-core.preferences")
    }

    @ViewBuilder
    private var groupSection: some View {
        Section {
            Picker("回复模式", selection: $groupPreferences.strategyRaw) {
                Text("自然选择").tag("natural")
                Text("手动指定").tag("manual")
                Text("成员轮询").tag("listOrder")
                Text("公平抢答").tag("pooled")
            }

            Picker("角色卡组装", selection: $groupPreferences.promptAssemblyModeRaw) {
                Text("仅当前角色（推荐）").tag("swapActiveCharacter")
                Text("合并全部角色卡").tag("joinCharacterCards")
            }

            Stepper(
                "自动回复上限：\(groupPreferences.maximumAutomaticResponders) 人",
                value: $groupPreferences.maximumAutomaticResponders,
                in: 1...4
            )

            Toggle(
                "允许本群使用敏感记忆",
                isOn: $groupPreferences.allowSensitiveMemory
            )
            .tint(AppTheme.accent)
        } header: {
            Text("群聊轮次")
        } footer: {
            Text(groupPreferences.allowSensitiveMemory
                ? "本群已允许敏感记忆。发送前仍应经过角色与会话范围校验。"
                : "默认关闭。单聊中的私密事实不会进入群聊提示词。")
        }
    }

    private var imageSection: some View {
        Section {
            Stepper(
                "每次生成：\(imagePreferences.imageCount) 张",
                value: $imagePreferences.imageCount,
                in: 1...4
            )

            Picker("画面比例", selection: $imagePreferences.aspectRatioRaw) {
                Text("1:1 方形").tag("square")
                Text("3:4 竖图").tag("portrait")
                Text("9:16 长竖图").tag("tallPortrait")
                Text("4:3 横图").tag("landscape")
                Text("16:9 宽横图").tag("wideLandscape")
            }

            Picker("质量意图", selection: $imagePreferences.qualityRaw) {
                Text("草稿").tag("draft")
                Text("标准").tag("standard")
                Text("高质量").tag("high")
            }

            Picker("风格", selection: $imagePreferences.styleRaw) {
                Text("跟随提示词").tag("inherit")
                Text("摄影写实").tag("photographic")
                Text("电影感").tag("cinematic")
                Text("插画").tag("illustration")
                Text("2.5D 动漫 CG").tag("animeCG")
            }

            Toggle(
                "保持角色身份特征",
                isOn: $imagePreferences.preserveCharacterIdentity
            )
            .tint(AppTheme.accent)

            Stepper(
                "瞬时失败重试：\(imagePreferences.maximumRetries) 次",
                value: $imagePreferences.maximumRetries,
                in: 0...3
            )

            TextField(
                "负面提示词（可选）",
                text: $imagePreferences.negativePrompt,
                axis: .vertical
            )
            .lineLimit(2...6)
        } header: {
            Text("生图默认值")
        } footer: {
            Text("供应商能力适配器会在发送前过滤不支持的参数；保存高质量意图不代表每个 API 都支持同名字段。")
        }
    }

    private func load() {
        guard !hasLoaded else { return }
        if let conversationID {
            groupPreferences = appModel.groupInteractionPreferences(
                conversationID: conversationID
            )
        }
        imagePreferences = appModel.imageInteractionPreferences(
            connectionID: imageConnectionID
        )
        hasLoaded = true
    }

    private func save() {
        do {
            if let conversationID {
                try appModel.saveGroupInteractionPreferences(
                    groupPreferences.normalized,
                    conversationID: conversationID
                )
                groupPreferences = appModel.groupInteractionPreferences(
                    conversationID: conversationID
                )
            }
            try appModel.saveImageInteractionPreferences(
                imagePreferences.normalized,
                connectionID: imageConnectionID
            )
            imagePreferences = appModel.imageInteractionPreferences(
                connectionID: imageConnectionID
            )
            statusText = "交互设置已保存。"
            errorText = nil
        } catch {
            errorText = "保存交互设置失败：\(error.localizedDescription)"
            statusText = nil
        }
    }

    private func reset() {
        if let conversationID {
            appModel.resetGroupInteractionPreferences(
                conversationID: conversationID
            )
            groupPreferences = appModel.groupInteractionPreferences(
                conversationID: conversationID
            )
        }
        appModel.resetImageInteractionPreferences(
            connectionID: imageConnectionID
        )
        imagePreferences = appModel.imageInteractionPreferences(
            connectionID: imageConnectionID
        )
        statusText = "已恢复安全默认值。"
        errorText = nil
    }
}
