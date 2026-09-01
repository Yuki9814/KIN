import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum PersonaSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    #else
    static let page = AppTheme.rootBackground
    #endif
}

struct PersonaView: View {
    @Environment(AppModel.self) private var appModel
    @Query private var storedWorldProfiles: [WorldProfileRecord]
    @State private var name = ""
    @State private var userName = ""
    @State private var prompt = ""
    @State private var avatarImageData: Data?
    @State private var chatBackgroundImageData: Data?
    @State private var birthdayMonth = 0
    @State private var birthdayDay = 0
    @State private var affinityDraft = 0.0
    @State private var savedManualAffinityScore: Double?
    @State private var selectedWorldProfileID = WorldProfileRecord.realityID
    @State private var availableConnections: [AIConnectionProfile] = []
    @State private var selectedConnectionID: UUID?
    @State private var isDirty = false
    @State private var hasLoadedDraft = false
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var showReset = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    CompanionAvatar(
                        size: 68,
                        name: displayedName,
                        imageData: avatarImageData
                    )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(displayedName)
                            .font(.title2.weight(.semibold))
                        Text("平等、坦诚、有连续记忆的 AI 伴侣")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("头像与聊天背景") {
                RoleMediaPicker(
                    avatarImageData: $avatarImageData,
                    chatBackgroundImageData: $chatBackgroundImageData,
                    name: displayedName,
                    onChange: markDirty
                )
                .padding(.vertical, 6)
            }

            Section("生日") {
                HStack(spacing: 10) {
                    Picker("月份", selection: $birthdayMonth) {
                        Text("未设置").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("角色生日月份")
                    .accessibilityIdentifier("persona.birthday.month")

                    Picker("日期", selection: $birthdayDay) {
                        Text("未设置").tag(0)
                        ForEach(birthdayDayOptions, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("角色生日日期")
                    .accessibilityIdentifier("persona.birthday.day")

                    Spacer(minLength: 0)

                    Button("保存") { saveBirthday() }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accent)
                        .frame(minHeight: 44)
                        .disabled(!birthdayIsDirty)
                        .accessibilityLabel("保存角色生日")
                        .accessibilityIdentifier("persona.birthday.save")
                }
                .onChange(of: birthdayMonth) { _, newMonth in
                    if newMonth == 0 {
                        birthdayDay = 0
                    } else if birthdayDay > birthdayMaximumDay(for: newMonth) {
                        birthdayDay = birthdayMaximumDay(for: newMonth)
                    }
                }

                Text(birthdaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("只保存月和日，不记录出生年份。生日资料独立保存，不会改变人格设定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Section("称呼") {
                TextField("角色名", text: $name)
                    .onChange(of: name) { markDirty() }
                TextField("她如何称呼你", text: $userName)
                    .onChange(of: userName) { markDirty() }
            }

            Section("好感度") {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(affinityControlTitle)
                            .font(.body.weight(.medium))
                        Text(affinityParameters.band.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(affinityValueText)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                Slider(value: $affinityDraft, in: 0...100, step: 1) {
                    Text("好感度")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                .onChange(of: affinityDraft) { _, _ in
                    statusText = nil
                    errorText = nil
                }
                .accessibilityValue("\(Int(affinityDraft.rounded())) / 100，\(affinityParameters.band.title)")
                .accessibilityIdentifier("persona.affinity.slider")

                HStack(spacing: 12) {
                    Button(savedManualAffinityScore == nil ? "启用手动控制" : "保存手动值") {
                        saveAffinity()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(!affinityDraftIsDirty)
                    .accessibilityIdentifier("persona.affinity.save")

                    if savedManualAffinityScore != nil {
                        Button(affinityRestoreTitle) {
                            restoreAutomaticAffinity()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("persona.affinity.restore")
                    }
                }

                Text("保存后，这个数值会直接进入实际提示词，控制角色的亲密语气、称呼、主动性、自我披露、关系延续倾向和角色层服从边界；手动值会保持不变，直到你恢复默认或自动变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("人格与角色设定") {
                TextEditor(text: $prompt)
                    .frame(minHeight: 220)
                    .onChange(of: prompt) { markDirty() }
                Text("这里只定义角色身份、经历与说话方式，不再承载世界观。好感度由上方独立控制，并在每次生成时进入角色行为提示词。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("角色卡与世界书") {
                NavigationLink {
                    CharacterCardImportView()
                } label: {
                    Label(
                        "导入 Character Card",
                        systemImage: "person.crop.rectangle.badge.plus"
                    )
                    .frame(minHeight: 36)
                }

                Text("支持 Character Card V1/V2 JSON。导入前会检查永久上下文、首条消息与内嵌世界书；创建者备注只在预览中显示，不会发送给模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("独立世界观") {
                Picker("绑定世界观", selection: $selectedWorldProfileID) {
                    ForEach(availableWorldProfiles, id: \.id) { world in
                        Text(world.displayName).tag(world.id)
                    }
                }
                .onChange(of: selectedWorldProfileID) { markDirty() }
                Text("世界观与角色卡分开保存。你可以任意改选，也可以让多个角色复用同一个世界观。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI 连接") {
                Picker("这个角色使用", selection: $selectedConnectionID) {
                    Text("跟随默认连接").tag(UUID?.none)
                    ForEach(availableConnections) { connection in
                        Text(connection.displayName).tag(Optional(connection.id))
                    }
                }
                .onChange(of: selectedConnectionID) { markDirty() }
                Text("选择后，单聊、群聊回复、朋友圈和记忆整理都会使用这个角色自己的连接。选择“跟随默认连接”时，会自动使用服务页中设置的默认项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: save) {
                    Label("保存角色设置", systemImage: "checkmark")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                    .disabled(!isDirty || !draftIsValid)

                Button(role: .destructive) {
                    showReset = true
                } label: {
                    Text("恢复默认人格")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.plain)
            } footer: {
                Text("角色资料保存在 KIN 数据中；登录凭据只保存在本机钥匙串。")
            }
        }
        .formStyle(.grouped)
#if os(macOS)
        .scrollContentBackground(.hidden)
        .background(PersonaSemantic.page)
        .frame(maxWidth: 760, alignment: .topLeading)
#endif
#if os(iOS)
        .wechatDetailShell(title: "角色")
#else
        .navigationTitle("角色")
#endif
        .onAppear(perform: loadInitialDraft)
        .onChange(of: appModel.persona) { _, updated in
            guard !isDirty else { return }
            loadDraft(from: updated)
        }
        .confirmationDialog("恢复默认人格？", isPresented: $showReset) {
            Button("恢复", role: .destructive, action: reset)
            Button("取消", role: .cancel) {}
        }
    }

    private var displayedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appModel.persona.name : trimmed
    }

    private var draftIsValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && availableWorldProfiles.contains { $0.id == selectedWorldProfileID }
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

    private func loadInitialDraft() {
        guard !hasLoadedDraft else { return }
        loadDraft(from: appModel.persona)
        hasLoadedDraft = true
    }

    private func loadDraft(from persona: PersonaConfiguration) {
        name = persona.name
        userName = persona.userName
        prompt = persona.prompt
        birthdayMonth = persona.birthdayMonth ?? 0
        birthdayDay = persona.birthdayDay ?? 0
        avatarImageData = persona.avatarImageData
        chatBackgroundImageData = persona.chatBackgroundImageData
        selectedWorldProfileID = appModel.worldProfileID(for: appModel.currentRoleID)
        availableConnections = AIConnectionStore.connections()
        selectedConnectionID = AIConnectionStore.explicitConnectionID(
            for: appModel.currentRoleID
        )
        loadAffinityDraft()
        isDirty = false
    }

    private func markDirty() {
        guard hasLoadedDraft else { return }
        isDirty = personalityDraft != storedPersonality
            || selectedWorldProfileID != appModel.worldProfileID(for: appModel.currentRoleID)
            || selectedConnectionID != AIConnectionStore.explicitConnectionID(
                for: appModel.currentRoleID
            )
        statusText = nil
        errorText = nil
    }

    private var personalityDraft: PersonaConfiguration {
        PersonaConfiguration(
            name: name,
            userName: userName,
            prompt: prompt,
            birthdayMonth: nil,
            birthdayDay: nil,
            avatarImageData: avatarImageData,
            chatBackgroundImageData: chatBackgroundImageData
        )
    }

    private var storedPersonality: PersonaConfiguration {
        PersonaConfiguration(
            name: appModel.persona.name,
            userName: appModel.persona.userName,
            prompt: appModel.persona.prompt,
            birthdayMonth: nil,
            birthdayDay: nil,
            avatarImageData: appModel.persona.avatarImageData,
            chatBackgroundImageData: appModel.persona.chatBackgroundImageData
        )
    }

    private func save() {
        let previousConnectionID = AIConnectionStore.explicitConnectionID(
            for: appModel.currentRoleID
        )
        do {
            try AIConnectionStore.setConnectionID(
                selectedConnectionID,
                for: appModel.currentRoleID
            )
            try appModel.savePersona(
                name: name,
                userName: userName,
                prompt: prompt,
                avatarImageData: avatarImageData,
                chatBackgroundImageData: chatBackgroundImageData,
                worldProfileID: selectedWorldProfileID
            )
            loadDraft(from: appModel.persona)
            statusText = appModel.isUsingCloud
                ? "角色已保存，将通过你的私有 iCloud 同步。"
                : "角色已保存到当前本机数据库。启用 iCloud 后会随数据一起迁移。"
            errorText = nil
        } catch {
            try? AIConnectionStore.setConnectionID(
                previousConnectionID,
                for: appModel.currentRoleID
            )
            errorText = error.localizedDescription
        }
    }

    private var birthdayIsDirty: Bool {
        let persistedMonth = appModel.companionSummary(for: appModel.currentRoleID)?.birthdayMonth ?? appModel.persona.birthdayMonth ?? 0
        let persistedDay = appModel.companionSummary(for: appModel.currentRoleID)?.birthdayDay ?? appModel.persona.birthdayDay ?? 0
        return birthdayMonth != persistedMonth || birthdayDay != persistedDay
    }

    private var birthdaySummary: String {
        guard birthdayMonth > 0, birthdayDay > 0 else { return "尚未设置角色生日" }
        return "每年\(birthdayMonth)月\(birthdayDay)日"
    }

    private var birthdayDayOptions: ClosedRange<Int> {
        1...birthdayMaximumDay(for: birthdayMonth)
    }

    private func birthdayMaximumDay(for month: Int) -> Int {
        guard (1...12).contains(month) else { return 31 }
        return [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    private func saveBirthday() {
        do {
            try appModel.saveCompanionBirthday(
                roleID: appModel.currentRoleID,
                month: birthdayMonth == 0 ? nil : birthdayMonth,
                day: birthdayDay == 0 ? nil : birthdayDay
            )
            statusText = "角色生日已独立保存。"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private var affinityParameters: AffinityPolicy.Parameters {
        AffinityPolicy.parameters(for: affinityDraft)
    }

    private var affinityControlTitle: String {
        if savedManualAffinityScore != nil { return "手动控制中" }
        return appModel.isCurrentRoleAffinityInfinite ? "默认无限好感" : "自动变化中"
    }

    private var affinityValueText: String {
        if savedManualAffinityScore == nil && appModel.isCurrentRoleAffinityInfinite {
            return "∞ / 100"
        }
        return "\(Int(affinityDraft.rounded())) / 100"
    }

    private var affinityRestoreTitle: String {
        BuiltInCompanionCatalog.contains(roleID: appModel.currentRoleID)
            ? "恢复默认 ∞"
            : "恢复自动变化"
    }

    private var affinityDraftIsDirty: Bool {
        guard let savedManualAffinityScore else { return true }
        return Int(affinityDraft.rounded()) != Int(savedManualAffinityScore.rounded())
    }

    private func loadAffinityDraft() {
        let manualScore = appModel.manualAffinityScore(for: appModel.currentRoleID)
        savedManualAffinityScore = manualScore
        let effectiveScore = manualScore ?? appModel.effectiveAffinityScore(for: appModel.currentRoleID)
        affinityDraft = effectiveScore.isFinite ? min(100, max(0, effectiveScore)) : 100
    }

    private func saveAffinity() {
        do {
            try appModel.setManualAffinityScore(affinityDraft, for: appModel.currentRoleID)
            loadAffinityDraft()
            statusText = "好感度已设为 \(Int(affinityDraft.rounded())) / 100，并会从下一次回复开始控制角色行为。"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func restoreAutomaticAffinity() {
        do {
            try appModel.clearManualAffinityScore(for: appModel.currentRoleID)
            loadAffinityDraft()
            statusText = appModel.isCurrentRoleAffinityInfinite
                ? "已恢复内置好友的默认无限好感度。"
                : "已恢复好感度自动变化。"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func reset() {
        do {
            try appModel.resetPersona()
            loadDraft(from: appModel.persona)
            statusText = "已恢复并保存默认人格。"
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
