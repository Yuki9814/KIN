import SwiftUI
import UniformTypeIdentifiers

struct CharacterCardImportView: View {
    @Environment(AppModel.self) private var appModel
    @State private var userName = ""
    @State private var sourceData: Data?
    @State private var sourceFileName = ""
    @State private var preview: CharacterCardImportPreview?
    @State private var isImporterPresented = false
    @State private var statusText: String?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("导入对象") {
                TextField("角色如何称呼你", text: $userName)
                    .onChange(of: userName) { _, _ in
                        refreshPreview()
                    }
                Text("角色卡中的 {{user}} 与 <user> 会替换成这里的称呼；{{char}} 与 <bot> 会替换成卡片角色名。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Character Card JSON") {
                Button {
                    isImporterPresented = true
                } label: {
                    Label(
                        sourceData == nil ? "选择角色卡文件" : "重新选择文件",
                        systemImage: "doc.badge.plus"
                    )
                    .frame(minHeight: 36)
                }

                if !sourceFileName.isEmpty {
                    LabeledContent("当前文件", value: sourceFileName)
                }

                Text("支持 Character Card V1 与 V2 JSON。未知的 namespaced extensions 会在 V2 再导出时原样保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let preview {
                Section("导入预览") {
                    LabeledContent("角色名", value: preview.card.name)
                    LabeledContent(
                        "永久上下文",
                        value: "约 \(preview.qualityReport.estimatedPermanentTokens) token"
                    )
                    LabeledContent(
                        "示例对话",
                        value: "约 \(preview.qualityReport.estimatedExampleTokens) token"
                    )
                    LabeledContent(
                        "内嵌世界书",
                        value: "\(preview.qualityReport.loreEntryCount) 条"
                    )

                    if let greeting = preview.preferredFirstMessage,
                       !greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("首条消息")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(greeting)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if !preview.qualityReport.warnings.isEmpty {
                    Section("质量检查") {
                        ForEach(
                            Array(preview.qualityReport.warnings.enumerated()),
                            id: \.offset
                        ) { _, warning in
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !preview.creatorNotes
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                    Section {
                        DisclosureGroup("查看创建者备注") {
                            Text(preview.creatorNotes)
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                        }
                    } footer: {
                        Text("创建者备注只用于导入预览，不会写入角色提示词，也不会发送给模型。")
                    }
                }

                Section {
                    Button(action: importCard) {
                        Label("创建这个角色", systemImage: "person.crop.circle.badge.plus")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(AppTheme.accent)
                    .disabled(!canImport)
                } footer: {
                    Text("当前版本会立即创建角色，并完整合并卡片中模型可见的角色描述、性格、场景、系统指令、示例对话与后置指令。内嵌世界书已在预览中解析，统一管理入口将在世界书工作台接线时启用。")
                }
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
        }
        .formStyle(.grouped)
#if os(iOS)
        .wechatDetailShell(title: "导入角色卡")
#else
        .navigationTitle("导入角色卡")
#endif
        .onAppear {
            if userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                userName = appModel.persona.userName
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
    }

    private var canImport: Bool {
        sourceData != nil
            && preview != nil
            && !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            sourceData = data
            sourceFileName = url.lastPathComponent
            preview = try appModel.previewCharacterCardImport(
                data: data,
                userName: userName
            )
            statusText = "角色卡已解析，请核对预览后创建角色。"
            errorText = nil
        } catch {
            sourceData = nil
            preview = nil
            statusText = nil
            errorText = error.localizedDescription
        }
    }

    private func refreshPreview() {
        guard let sourceData else { return }
        do {
            preview = try appModel.previewCharacterCardImport(
                data: sourceData,
                userName: userName
            )
            errorText = nil
        } catch {
            preview = nil
            errorText = error.localizedDescription
        }
    }

    private func importCard() {
        guard let sourceData else { return }
        do {
            let result = try appModel.importCharacterCard(
                data: sourceData,
                userName: userName
            )
            statusText = "已创建角色“\(result.preview.card.name)”，角色 ID 为 \(result.roleID.uuidString.prefix(8))。"
            errorText = nil
        } catch {
            statusText = nil
            errorText = error.localizedDescription
        }
    }
}
