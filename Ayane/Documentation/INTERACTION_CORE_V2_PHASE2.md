# Interaction Core V2 — Phase 2 Delivery Plan

本文件记录在领域决策层稳定合并后，完整用户功能仍必须完成的持久化、迁移、主链路与跨端工作。它不是愿望清单；每一项都有可验证的完成标准。

## A. 意图感知记忆主链路

- 将 `MemoryRetrievalPolicy.plan` 接入单聊与群聊的正式召回入口。
- 保留现有 FTS、向量召回、历史原文召回、tombstone 和角色隔离。
- 在 MemoryView 展示召回原因、意图、分数构成、来源消息与最近使用时间。
- 群聊敏感记忆默认拒绝；逐角色、逐群授权后才允许。

完成标准：现有 10k / 50k 规模测试不退化；短指代、身份、偏好、时间线和群聊隔离均有 AppModel 集成测试。

## B. 好感度事件账本

- 新增不可变关系事件表、四维快照与幂等键索引。
- 旧 scalar score 只用于一次性播种；之后由事件重放生成快照。
- 关系事件进入备份、合并、冲突隔离、重复记录清理和跨端协议。
- UI 展示维度趋势与关键事件，不展示可刷的逐消息加分动画。

完成标准：迁移可重复运行；同一事件重放不重复加分；旧备份恢复后数值稳定；Swift 与 KMP 金丝雀数据一致。

## C. Lorebook 持久化与工作台

- 文档、条目、作用域绑定和扩展 JSON 分别持久化。
- 提供条目列表、编辑区、即时激活测试和预算预览。
- 正式 PromptAssembler 按插入位置接收激活结果。
- 导入导出保留未知扩展字段。

完成标准：作用域、递归、正则、概率、预算、互斥组与插入顺序都有持久化往返和提示词边界测试。

## D. Character Card 完整往返

- 保存原始 V1 / V2 文档以及导入来源元数据。
- 允许编辑后再次导出 V2 JSON。
- 将内嵌 character book 与 Lorebook 文档建立可追溯绑定。
- 首句可预览、选择并写入新会话，但不得伪造为历史用户消息。

完成标准：未知 extensions 无损往返；creator notes 永不进入请求；导入事务失败时不留下半成品角色。

## E. 群聊配置与操作逻辑

- 群记录持久化 strategy、prompt assembly mode 与自动回复上限。
- 成员记录持久化 mute、talkativeness 与独立连接绑定。
- 输入框旁直接切换自然 / 手动 / 轮询 / 抢答；手动模式展示成员选择。
- 回复期间显示当前角色和剩余队列；停止只取消未开始的角色。

完成标准：旧群默认 Natural + Swap Card；配置跨重启、备份与跨端恢复不丢失；每个模式有端到端测试。

## F. 生图批量设置与能力探测

- 按连接保存数量、比例、质量、风格、负面提示词与身份保持偏好。
- 探测并缓存供应商能力，不向不支持的接口发送伪参数。
- 聊天附件入口使用批量执行器，逐张展示进行中、成功、重试与失败。
- 部分成功必须保留，取消不得删除已完成图片。

完成标准：Images API、OpenRouter Images 与自定义 Chat 网关均有请求契约测试；429 / 5xx 重试而 400 不重试。

## G. 跨端与迁移闸门

- 为新增枚举、DTO、ID、扩展 JSON 和备份版本建立 Swift / Kotlin 共享样例。
- Android、Windows、macOS 和 iOS 均验证恢复、合并、重复运行迁移和降级行为。
- 任一平台未完成事实表迁移前，不允许另一平台单独写入不可理解的新事实源。

完成标准：四端 CI、privacy gate、固定黄金向量与旧版本备份样例全部通过。

## 推荐拆分

1. Memory mainline + explainability
2. Affinity ledger + schema migration
3. Lorebook persistence + prompt insertion + workbench
4. Character Card durable round-trip
5. Group configuration UX
6. Image generation preferences + batch UI
7. KMP parity + backup version bump

每个 PR 都必须独立可恢复、可回滚，并保持聊天事件与现有记忆事实源不被静默改写。
