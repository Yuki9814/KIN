# Apple 私有 CloudKit 同步配置

KIN 默认只使用本机 SwiftData。CloudKit 是可选的 Apple 能力，必须由使用者在自己的开发者环境中创建、签名和部署；仓库不提供任何 Team、Bundle、容器、设备或凭据值。公开 CI 不登录 Apple，也不连接任何私有 CloudKit 数据库。

## 先理解验证边界

本地编译、单元测试和模拟器运行不能证明真实设备同步。`scripts/verify-cloudkit-readiness.sh` 只读取你指定的已签名产物，不访问网络、不修改产物：

```sh
scripts/verify-cloudkit-readiness.sh \
  --macos path/to/AyaneMac.app \
  --ios path/to/AyaneiOS.app
```

它检查两端签名有效、Team 非空且一致、CloudKit 容器唯一且一致，以及必要的 iCloud entitlement；iOS 还需远程通知能力。缺少产物返回 `INCONCLUSIVE`，配置不合格返回 `FAIL`，全部对齐返回 `PASS`。`PASS` 只表示产物配置一致，不代表 schema 已部署、权限已批准或设备已完成双向收发。

## 使用自己的开发环境

1. 在 Xcode 打开 `Ayane.xcodeproj`，分别选择 macOS 与 iOS target。
2. 在 Signing & Capabilities 中选择你自己的 Team，并为两个 target 保留各自唯一的 Bundle Identifier。
3. 给两个 target 添加 iCloud capability，只勾选 CloudKit；选择同一个由你管理的私有容器，例如 `iCloud.com.example.project`。该字符串只是格式示例，不是项目配置。
4. 给 iOS target 添加 Background Modes 的 Remote notifications；macOS 保留应用需要的沙盒网络能力。
5. 如果需要手工 entitlement，复制仓库中的示例文件到本机配置后替换占位符。真实 entitlement、provisioning profile、证书和 `Configuration/Local.xcconfig` 必须留在本机，不能提交。
6. 在每台设备登录同一 Apple 账户，安装使用同一 Team/容器签名的构建。API Key 仍需在每台设备单独保存，不会进入 CloudKit。

Personal Team 只能作为个人设备上的短期 Debug 验证边界，不能作为公开 Release、商店分发或公共 CI 的签名身份。公开构建使用中性配置并关闭签名；若要分发，请在自己的受控发布环境完成签名和公证，并重新执行本地门禁。

## 数据与同步边界

- 对话事件、记忆、关系状态、人物设定和可同步的应用数据进入使用者自己的私有 CloudKit 数据库；默认仍只保存在本机。
- API Key、OAuth refresh token、provider 连接测试内容、设备标识和本地路径不进入 CloudKit，也不进入可移植备份。
- API 地址、模型和记忆策略默认保持设备本地；启用原始历史召回时，只有命中的片段才会发送到使用者主动配置的 provider。
- CloudKit 是最终一致同步。网络中断、后台限制、权限变更和延迟导入都可能使两端暂时不一致；应用会保留 journal 并在下次启动/前台时重试。
- 从云端切回本机前应先导出加密/校验后的备份。切换是非破坏性增量合并，目标已有记录不清空，源数据不会在失败时删除。

## Development schema 初始化（仅 DEBUG，人工 opt-in）

项目只在 DEBUG 中提供显式启动参数路径，用临时 Core Data store 调用 Apple 的 schema 初始化 API；Release 不包含这条路径，正常启动也不会触发。它需要你自己的签名、自己的 Development 容器和明确的网络操作许可。

在 Xcode Scheme > Run > Arguments Passed On Launch 中分别加入：

```text
-AyaneInitializeCloudKitSchema
-AyaneCloudKitContainerIdentifier
iCloud.com.example.project
```

第三行只是格式示例，必须替换成你在两个 target 中配置的同一个值。初始化会向 Development 环境写入并删除代表性记录，不是离线检查；完成后立即移除三个参数，避免重复执行。随后在 CloudKit Dashboard 核对 schema，并在公开/商店构建前将已审查的 Development schema 部署到 Production。不要在 Release、TestFlight 或生产环境运行初始化参数。

## 设备验收建议

1. 在设备 A 导出备份并写入一条不会暴露真实隐私的测试消息，等待本地记忆整理完成。
2. 等待 CloudKit 稳定后，在设备 B 观察消息、记忆、关系状态和附件摘要是否到达。
3. 在设备 B 修正一条测试记忆，再回设备 A 检查版本/冲突状态；允许最终一致延迟。
4. 测试网络中断、取消、重复启动、切回本机和备份恢复。确认失败时原记录与 journal 仍在。
5. 通过 readiness 脚本、Dashboard schema 核对和双端读写闭环后，才可声称完成真实同步验收。

不要在 issue、PR、CI 日志或截图中上传真实对话、容器值、Team 值、设备标识、Keychain 内容或 provider 响应。公开仓库的同步说明只能使用占位符和可复现的合成数据。
