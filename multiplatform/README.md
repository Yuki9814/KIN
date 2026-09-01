# KIN 有灵：Android / Windows 核心版

版本：`0.1.5`（Windows jpackage 原生安装器字段规范化为 `1.1.5`，因为 jpackage 禁止主版本号为 0；应用显示版本仍为 `0.1.5`）

这是与 Apple 工程并列的 Kotlin Multiplatform 工程，固定目录为：

- `sharedLogic`：领域模型、SQLite 仓储、关系状态机、角色隔离记忆、SSE 生命周期、附件与备份协议。
- `sharedUI`：Compose Multiplatform 的消息、通讯录/角色、记忆、附件、设置、备份页面。
- `androidApp`：Android 入口，`minSdk 29`、`compileSdk/targetSdk 36`，Android Keystore。
- `desktopApp`：Compose Desktop JVM 入口，Windows `Exe` 与 `Msi` 原生发行物，Windows DPAPI。

固定工具链为 Kotlin `2.4.10`、Compose Multiplatform `1.11.1`、AGP `9.3.0`、Gradle `9.5.0`、JDK `21`；shared modules 保持 JVM 17 字节码目标以覆盖 Windows 10。Compose 选用与 Android API 36 AAR 要求兼容的稳定版本（1.12.0 的 Android AAR 要求 compileSdk 37），直接依赖版本集中在 `gradle/libs.versions.toml`。CI 应使用 `./gradlew`（脚本会校验 Gradle 分发 SHA-256）并在具备 JDK 21、Android SDK 36 的 runner 上执行。

## 安全与可移植备份边界

`SecretStore` 不把 API key 放进 `AppSettings` 或 `KINPortableArchiveV1`：Android 实现使用 Android Keystore；Windows/JVM 实现仅在 Windows 上调用 JNA 的 DPAPI `CryptProtectData/CryptUnprotectData`。非 Windows 主机没有明文回退。

`KINPortableArchiveV1` 的二进制头包含 magic、版本、16-byte salt、12-byte nonce，密文使用 PBKDF2-HMAC-SHA256（600000 次、256-bit key）与 AES-256-GCM；头部作为 AAD。payload 只包含角色、关系、聊天事件、长期记忆、应用显示设置和附件元数据/内容，不包含 API key、OAuth、device ID 或派生索引。解密、校验和 SQLite 导入均在写入前验证；重复 `exportId`、错误密码、篡改、记录冲突都会失败，导入使用 SQLite transaction，附件失败会清理本次写入。

兼容边界是显式单向的：ArchivePayloadCodec.decodePortableOrApple 可读取 Apple AyaneDataExport schema v4–v18 的脱敏 JSON，并把 profiles、relationships、events、memories、tombstones 与事件内嵌附件转换为 KMP core；Apple 专属 evidence、summaries、Moments、群聊、主动任务、OAuth、用户资料和 world profile 会被忽略。v18 的 `relationships.manual_affinity_score` 与 `manual_affinity_updated_at` 是可选字段，但 KMP 当前的 RelationshipState 没有手动好感度流，因此安全读入时会忽略它们，只使用 `affinity_score`（或旧版 tier），不宣称该状态可在 Apple round-trip 中保留。v17 的 `moment_interactions.deleted_at` 是 Apple 侧黏性删除墓碑；KMP 当前没有 Moments DTO，因此安全读入时不会把任何 Moments 互动（包括已删除互动）伪装成聊天或记忆记录，避免删除状态被复活，也不宣称 Moments 双向 round-trip。KMP 导出的 canonical KINPortableArchivePayloadV1 不是 Apple AyaneDataExport JSON，KMP→Swift 的同构转换需由 Swift 侧按本节 schema/fixture 实现，当前不宣称双向无损互导。

## 首版边界

已实现的核心是唯一稳定内置角色“绫音” (`8D5DFB45-198D-4B74-B1F1-4C9C7A8248A1`)、自建角色、好感度关系状态机、append-only 聊天事件、OpenAI-compatible SSE（先落盘 request/pending，增量落盘，取消/失败保留，支持 retry）、角色隔离长期记忆与 prompt 组装、私有附件 SHA-256、SQLite 抽象和加密备份导入导出。

朋友圈、群聊、主动任务、OAuth 首版明确不实现；UI 设置页会显示此边界。Android 由宿主 Activity 在创建期注册 `OpenDocument`/`CreateDocument`，再通过 `PlatformFilePicker` 挂起桥接完成选择和保存；Windows Desktop 使用可复用的 Swing `JFileChooser` picker。

## 验证命令

```sh
./gradlew test
./gradlew :androidApp:assembleDebug
./gradlew :desktopApp:packageExe :desktopApp:packageMsi
```

`sharedLogic` 的测试包含固定跨语言 golden vector、错误密码/篡改拒绝、关系状态机、prompt 角色隔离和 Desktop SQLite 重复导入原子性测试。

Android Debug 产物位于 `androidApp/build/outputs/apk/debug/androidApp-debug.apk`，使用本机/CI 的 debug 签名，仅用于安装验证。Release 构建只接受 `kinReleaseStoreFile`、`kinReleaseStorePassword`、`kinReleaseKeyAlias`、`kinReleaseKeyPassword` Gradle properties，或对应的 `KIN_RELEASE_*` 环境变量；`.p12`/`.pfx` 会自动按 PKCS12 读取，也可用可选的 `kinReleaseStoreType`/`KIN_RELEASE_STORE_TYPE` 显式指定。缺少任一项会阻止 release 打包，仓库不含 keystore、默认密码或真实密钥。Windows MSI/EXE 任务已在 `desktopApp` 配置，需在 Windows x64 runner 执行生成。
