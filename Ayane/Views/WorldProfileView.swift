import Foundation
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

private enum WorldProfileSemantic {
    #if os(macOS)
    static let page = Color(nsColor: .windowBackgroundColor)
    #else
    static let page = AppTheme.rootBackground
    #endif
}

struct WorldProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedWorldProfiles: [WorldProfileRecord]

    @State private var selectedWorldID = WorldProfileRecord.realityID
    @State private var draft = WorldProfileDraft()
    @State private var previousWorldID = WorldProfileRecord.realityID
    @State private var statusText: String?
    @State private var hasLoaded = false
    @State private var isNewDraft = false

    var body: some View {
        Form {
            worldLibrarySection
            worldEditorSection
            commonFactsSection

            Section {
                Button(isNewDraft ? "创建并保存" : "保存世界观", action: save)
                    .buttonStyle(.borderedProminent)

                if isNewDraft {
                    Button("取消新建", action: cancelCreating)
                }

                if let statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusText.hasPrefix("保存失败") ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                }
            } footer: {
                Text("角色与世界观独立保存；每个角色可以单独绑定一个世界观。世界观库不会删除任何记录，同一 ID 的同步副本只展示 revision、更新时间和设备 ID 决定的最新版本。")
            }
        }
        .formStyle(.grouped)
#if os(macOS)
        .scrollContentBackground(.hidden)
        .background(WorldProfileSemantic.page)
        .frame(maxWidth: 760, alignment: .topLeading)
#endif
#if os(iOS)
        .wechatDetailShell(title: "世界观库")
#else
        .navigationTitle("世界观库")
#endif
        .task {
            initializeIfNeeded()
        }
        .onChange(of: storedWorldProfiles.count) { _, _ in
            refreshSelectionIfNeeded()
        }
    }

    private var worldLibrarySection: some View {
        Section("世界观库") {
            if worldProfiles.isEmpty {
                Text("还没有世界观，先创建一个新的世界观。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(worldProfiles) { world in
                    Button {
                        selectWorld(world)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: world.id == WorldProfileRecord.realityID
                                ? "globe.asia.australia.fill"
                                : "sparkles")
                                .foregroundStyle(world.id == WorldProfileRecord.realityID ? AppTheme.accent : .secondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(world.displayName)
                                    .foregroundStyle(.primary)
                                Text(world.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if selectedWorldID == world.id && !isNewDraft {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(world.displayName)
                    .accessibilityValue(world.summary)
                    .accessibilityAddTraits(
                        selectedWorldID == world.id && !isNewDraft ? .isSelected : []
                    )
                }
            }

            Button {
                beginCreating()
            } label: {
                Label("新建世界观", systemImage: "plus.circle.fill")
            }
        }
    }

    private var worldEditorSection: some View {
        Section(isNewDraft ? "新建世界观" : "编辑世界观") {
            TextField("名称", text: $draft.displayName)
                .accessibilityLabel("世界观名称")

            TextField("类型 / 标签", text: $draft.worldKind)
                .accessibilityLabel("世界观类型或标签")

            TextField("地点语境，例如上海", text: $draft.locationContext)
                .accessibilityLabel("地点语境")

            TextField("时区标识，例如 Asia/Shanghai", text: $draft.timezoneIdentifier)
                .autocorrectionDisabled()
#if os(iOS)
                .textInputAutocapitalization(.never)
#endif
                .accessibilityLabel("时区标识")

            Button("使用系统时区") {
                draft.timezoneIdentifier = TimeZone.current.identifier
            }
        }
    }

    private var commonFactsSection: some View {
        Section("共同事实") {
            TextEditor(text: $draft.factsText)
                .frame(minHeight: 180)
                .accessibilityLabel("共同事实，每行一条")

            Text("每行一条，只写你确认过、希望绑定该世界观的角色与群聊共同遵守的事实。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var worldProfiles: [WorldProfileSnapshot] {
        var winners: [UUID: WorldProfileRecord] = [:]
        for record in storedWorldProfiles {
            guard let current = winners[record.id] else {
                winners[record.id] = record
                continue
            }
            if isOlder(current, than: record) {
                winners[record.id] = record
            }
        }

        return winners.values
            .map { WorldProfileSnapshot(record: $0) }
            .sorted { lhs, rhs in
                if (lhs.id == WorldProfileRecord.realityID) != (rhs.id == WorldProfileRecord.realityID) {
                    return lhs.id == WorldProfileRecord.realityID
                }
                let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func initializeIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            let rows = try modelContext.fetch(FetchDescriptor<WorldProfileRecord>())
            if let reality = newestRecord(in: rows.filter { $0.id == WorldProfileRecord.realityID }) {
                loadDraft(from: WorldProfileSnapshot(record: reality))
                return
            }

            // Keep the stable reality identity present even when a migrated
            // store only contains custom worlds. This is additive and never
            // removes physical rows or duplicate sync copies.
            let now = Date()
            let reality = WorldProfileRecord(
                id: WorldProfileRecord.realityID,
                displayName: "现实世界",
                worldKind: "reality",
                timezoneIdentifier: TimeZone.current.identifier,
                createdAt: now,
                updatedAt: now,
                revision: 1,
                deviceID: deviceID
            )
            modelContext.insert(reality)
            try modelContext.save()
            loadDraft(from: WorldProfileSnapshot(record: reality))
        } catch {
            statusText = "保存失败：无法读取世界观库：\(error.localizedDescription)"
            draft = WorldProfileDraft()
        }
    }

    private func refreshSelectionIfNeeded() {
        guard hasLoaded, !isNewDraft else { return }
        guard !worldProfiles.contains(where: { $0.id == selectedWorldID }) else { return }
        guard let fallback = worldProfiles.first else { return }
        selectWorld(fallback)
    }

    private func selectWorld(_ world: WorldProfileSnapshot) {
        selectedWorldID = world.id
        isNewDraft = false
        loadDraft(from: world)
        statusText = nil
    }

    private func beginCreating() {
        previousWorldID = isNewDraft
            ? WorldProfileRecord.realityID
            : selectedWorldID
        selectedWorldID = UUID()
        isNewDraft = true
        draft = WorldProfileDraft(
            id: selectedWorldID,
            displayName: "",
            worldKind: "custom",
            timezoneIdentifier: TimeZone.current.identifier,
            locationContext: "",
            factsText: ""
        )
        statusText = nil
    }

    private func cancelCreating() {
        let targetID = worldProfiles.contains(where: { $0.id == previousWorldID })
            ? previousWorldID
            : (worldProfiles.first?.id ?? WorldProfileRecord.realityID)
        if let target = worldProfiles.first(where: { $0.id == targetID }) {
            selectWorld(target)
        } else {
            isNewDraft = false
            selectedWorldID = WorldProfileRecord.realityID
            draft = WorldProfileDraft()
        }
    }

    private func loadDraft(from world: WorldProfileSnapshot) {
        draft = WorldProfileDraft(
            id: world.id,
            displayName: world.displayName,
            worldKind: world.worldKind,
            timezoneIdentifier: world.timezoneIdentifier,
            locationContext: world.locationContext,
            factsText: world.commonFacts.joined(separator: "\n")
        )
    }

    private func save() {
        let trimmedName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        if trimmedName.isEmpty, draft.id == WorldProfileRecord.realityID {
            name = "现实世界"
        } else if trimmedName.isEmpty {
            statusText = "保存失败：请填写世界观名称。"
            return
        } else {
            name = String(trimmedName.prefix(80))
        }

        let trimmedTimezone = draft.timezoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TimeZone(identifier: trimmedTimezone) != nil else {
            statusText = "保存失败：请输入有效时区，例如 Asia/Shanghai。"
            return
        }

        let trimmedWorldKind = draft.worldKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let worldKind = String(
            (trimmedWorldKind.isEmpty
                ? (draft.id == WorldProfileRecord.realityID ? "reality" : "custom")
                : trimmedWorldKind)
                .prefix(80)
        )
        let location = String(
            draft.locationContext.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        )
        let facts = normalizedFacts(from: draft.factsText)

        do {
            let rows = try modelContext.fetch(FetchDescriptor<WorldProfileRecord>())
            let now = Date()
            let wasNew = isNewDraft
            if let record = newestRecord(in: rows.filter { $0.id == draft.id }) {
                record.displayName = name
                record.worldKind = worldKind
                record.locationContext = location
                record.timezoneIdentifier = trimmedTimezone
                record.commonFacts = facts
                record.updatedAt = now
                record.revision = max(0, record.revision) + 1
                record.deviceID = deviceID
            } else {
                modelContext.insert(WorldProfileRecord(
                    id: draft.id,
                    displayName: name,
                    worldKind: worldKind,
                    timezoneIdentifier: trimmedTimezone,
                    locationContext: location,
                    commonFacts: facts,
                    createdAt: now,
                    updatedAt: now,
                    revision: 1,
                    deviceID: deviceID
                ))
            }

            try modelContext.save()
            draft.displayName = name
            draft.worldKind = worldKind
            draft.locationContext = location
            draft.timezoneIdentifier = trimmedTimezone
            draft.factsText = facts.joined(separator: "\n")
            selectedWorldID = draft.id
            isNewDraft = false
            statusText = wasNew ? "世界观已创建。" : "世界观已保存。"
        } catch {
            statusText = "保存失败：\(error.localizedDescription)"
        }
    }

    private func normalizedFacts(from text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(80)
            .map { String($0.prefix(300)) }
    }

    private func newestRecord(in records: [WorldProfileRecord]) -> WorldProfileRecord? {
        records.max { lhs, rhs in
            isOlder(lhs, than: rhs)
        }
    }

    private func isOlder(_ lhs: WorldProfileRecord, than rhs: WorldProfileRecord) -> Bool {
        if lhs.revision != rhs.revision {
            return lhs.revision < rhs.revision
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.deviceID < rhs.deviceID
    }

    private var deviceID: String {
        ProcessInfo.processInfo.hostName
    }
}

private struct WorldProfileDraft {
    var id: UUID = WorldProfileRecord.realityID
    var displayName = "现实世界"
    var worldKind = "reality"
    var timezoneIdentifier = TimeZone.current.identifier
    var locationContext = ""
    var factsText = ""

    init(
        id: UUID = WorldProfileRecord.realityID,
        displayName: String = "现实世界",
        worldKind: String = "reality",
        timezoneIdentifier: String = TimeZone.current.identifier,
        locationContext: String = "",
        factsText: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.worldKind = worldKind
        self.timezoneIdentifier = timezoneIdentifier
        self.locationContext = locationContext
        self.factsText = factsText
    }
}

private struct WorldProfileSnapshot: Identifiable {
    let id: UUID
    let displayName: String
    let worldKind: String
    let timezoneIdentifier: String
    let locationContext: String
    let commonFacts: [String]
    let revision: Int
    let updatedAt: Date
    let deviceID: String

    init(record: WorldProfileRecord) {
        id = record.id
        displayName = record.displayName.isEmpty
            ? (record.id == WorldProfileRecord.realityID ? "现实世界" : "未命名世界观")
            : record.displayName
        worldKind = record.worldKind
        timezoneIdentifier = record.timezoneIdentifier
        locationContext = record.locationContext
        commonFacts = record.commonFacts
        revision = record.revision
        updatedAt = record.updatedAt
        deviceID = record.deviceID
    }

    var summary: String {
        let kind = worldKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = locationContext.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (kind.isEmpty, location.isEmpty) {
        case (true, true):
            return "未分类 · \(commonFacts.count) 条事实"
        case (false, true):
            return "\(kind) · \(commonFacts.count) 条事实"
        case (true, false):
            return "\(location) · \(commonFacts.count) 条事实"
        case (false, false):
            return "\(kind) · \(location)"
        }
    }
}
