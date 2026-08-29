# KIN 安全与隐私审计说明

这份说明描述公开仓库的防外发门禁、发布边界和已知剩余风险。文档只使用占位符，不包含 Team、Bundle、CloudKit 容器、设备标识、真实 provider 内容、个人路径或秘密值。

## 安全承诺

- Git 中只保留源代码、测试、必要资源、配置模板、脚本、文档和 CI；构建产物、数据库、日志、录屏、签名文件、密钥和本机状态拒绝进入外发包。GIF 直接禁止进入源码导出和 Release 归档。
- API Key、OAuth token 和 provider 响应不进入 Git、备份、CloudKit 或 CI 日志。公开 CI 只使用合成 fixture，不做真实 provider 验证。
- Apple Personal Team 只允许个人设备上的短期 Debug；公开构建无签名，公开 Release 不携带个人 Team 或本地签名材料。
- Release 页面只发布经过门禁的 macOS DMG、iOS unsigned IPA、iOS Simulator ZIP、Android APK、Windows MSI/EXE 和 `SHA256SUMS`。macOS 镜像未公证，iOS 真机包需自行重签，Windows 安装包未使用个人证书，Android 包不等同于商店签名。

## 门禁矩阵

| 检查 | 命令/入口 | 失败条件 |
| --- | --- | --- |
| 暂存区 | `scripts/kin-privacy-gate.sh --staged --source-only` | 秘密、个人标识、私有路径、Apple/设备值或非白名单路径 |
| 工作树 | `scripts/kin-privacy-gate.sh --tree --source-only` | 同上，另加 xattr、媒体分类、OCR 和内置角色断言 |
| 全部 refs | `scripts/kin-privacy-gate.sh --all-refs --source-only` | 任一历史对象包含敏感内容、旧角色策略违规或被拒绝路径 |
| 发布门禁 | `scripts/kin-privacy-gate.sh --tree --source-only --release` | gitleaks 或 OCR 工具不可用、扫描失败或任一发现 |
| Release 文件 | `scripts/kin-release-asset-gate.sh --require-ocr KIN-macos.dmg KIN-ios-unsigned.ipa KIN-ios-simulator.zip KIN-android.apk KIN-windows.msi KIN-windows.exe SHA256SUMS` | metadata/秘密/隐私/OCR、非中性应用标识、缺少包或 SHA-256 不匹配 |
| Hook | `scripts/kin-install-hooks.sh` | pre-push 对待推送 ref range 的隐私扫描、测试前置或输入校验失败 |

gitleaks 可用时会使用 `--redact` 并删除临时报告；不可用时仍执行内置 pattern fallback。`--release` 明确要求 gitleaks 与 OCR，避免发布流水线静默跳过工具。门禁输出只报告类别和文件路径，不打印匹配值、OCR 文本、环境变量或命令响应。

## 源码外发白名单

`scripts/kin-export-source.sh` 每次创建一个新的目标目录，候选只来自 `git ls-files --cached --others --exclude-standard`，再经过显式 allowlist 与 denylist；它不会盲遍历 allowlisted 目录。`.env`、`.npmrc`、`*.jks`、`*.keystore`、证书、`GoogleService-Info.plist`、GIF、构建/输出/视频/设计捕获、数据库、日志、应用包、签名材料和压缩归档均不会复制。导出完成后，脚本在目标目录创建一次性临时 index 运行 privacy gate，并删除该 `.git`，因此外发树不含旧历史或临时 Git 元数据。

图片在允许复制前会剥离 JPEG/PNG EXIF、XMP、ICC、C2PA 和文本块；工作树门禁会解析图片 metadata，并逐张执行 OCR。macOS 使用 Vision，Linux/Windows 使用 tesseract；`--release` 缺少 OCR 引擎直接失败。OCR 结果只用于匹配本地隐私词表、绝对路径和旧角色文本，永远不打印原文。当前设备、实际日历、家庭、实体设备和原始屏幕录制类媒体按路径直接拒绝。

## 本地隐私词表

可以把组织或个人需要额外检测的词放在仓库之外，并通过 `KIN_PRIVACY_IGNORE_FILE` 或 `--ignore-file` 指定。词表最多 256 行、每行最多 256 个字符；文件不能位于仓库内。任一源码、路径或 OCR 文本命中词表都会失败，但门禁输出只报告 `local-privacy-word` 类别和文件路径，不打印词值。词表值不会出现在导出清单、CI artifact 或 Git 历史中；不要把词表文件作为 issue、PR 或构建附件上传。

## 角色与数据边界

门禁断言内置角色构造恰好一个且名称为绫音；其他角色文字只能出现在明确的迁移摘要常量中，不能出现在 catalog、fixture 或公开文档。对话、长期记忆和附件默认只在本机；跨设备同步需要使用者自己的 Apple 私有 CloudKit 环境。平台密钥分别由系统安全存储托管，便携备份只保存经校验的非秘密数据。

## CI 与发布控制

GitHub Actions 分离隐私、Apple、Android、Windows 和 Release 工作流：

- 隐私工作流运行 staged/tree/all-refs 门禁，并在 Linux 安装 tesseract；不上传日志、录屏或工作树。Release workflow 的 source-gate 强制 all-refs + OCR + gitleaks，且使用固定 release checksums。
- Apple 使用 macOS 26 与 Xcode 26.6 的无签名 build/test；不读取个人登录状态。
- Android 在 Linux 使用 JDK 21、Android SDK 36 构建 APK；Windows 在 Windows 2025 runner 使用 JDK 21 构建 MSI/EXE。
- tag/release 流程将 Apple 无签名构建、Android unsigned 构建、受保护 `release-signing` Android 签名、Windows 包构建和独立资产门禁分离；签名 job 不 checkout 或运行仓库代码，只使用官方 build-tools 对 artifact 执行 `zipalign`/`apksigner`。发布 job 不 checkout 或执行仓库代码，只上传已验证 artifact；所有 checkout 均关闭持久凭据。
- 资产门禁限制归档条目总数、解压总大小和单条目大小；IPA 必须恰好包含 `Payload/*.app` 且为中性 iOS Bundle ID，Simulator ZIP 必须只有顶层 `KIN.app`，DMG 必须经 `hdiutil verify` 与只读挂载并只有一个中性 macOS `KIN.app`，APK 必须由 `aapt`/`apksigner` 校验，Windows MSI/EXE 必须各恰好一个、非空并通过 magic/x64/版本检查。二进制不会写回 Git。
- workflow artifact 名称和 Release asset 名称不含用户名、机器名、设备名、路径或凭据。失败时只保留通用错误类别。

## 剩余风险

1. 公开无签名包不能证明发布者身份；使用者应核对 Release 来源和 `SHA256SUMS`，并理解 macOS 未公证、Windows 未证书签名和 Android 非商店分发提示。
2. OCR 和 metadata 解析是启发式门禁，无法证明任意图像中的隐写或新型格式绝对无隐私；人工审核仍是高风险媒体发布前的必要步骤。
3. 历史 refs 中已经存在的敏感对象需要由仓库管理员按 Git 历史清理流程处理；门禁不会擅自重写历史。
4. CloudKit schema、真实签名、公证、商店审核和真实设备双向同步必须在使用者自己的环境单独验收；CI 的无签名测试不替代这些步骤。
5. 尚未指定项目开源许可证；在明确许可证前，公开可见不等于允许任意再分发。

## 报告问题

请通过公开 issue 提交不含秘密的最小复现，或先在本地使用门禁确认附件已脱敏。不要在 issue、PR、CI 日志、截图或压缩包中提交聊天记录、Keychain 内容、provider 响应、设备标识、签名文件或本机路径。若怀疑真实秘密已进入历史，请只描述受影响的提交范围和文件类别，不要重复粘贴秘密值。
