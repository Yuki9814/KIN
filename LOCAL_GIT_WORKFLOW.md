# KIN 本地 Git 多任务工作流

这个仓库可以推送到公开远端。安装 hooks 后，`pre-push` 会读取 Git 提供的待推送 ref 更新，逐个扫描 `remote-old..local-new`（新分支扫描 local-new）中的对象；隐私门禁失败或 ref 输入不明确时拒绝推送。

## 每个 Codex 任务

1. 新建任务时选择 **Worktree**，不要让多个写入任务共用主目录。
2. 在任务 worktree 中创建唯一分支：`git switch -c task/<任务名>`。
3. 完成后先测试并提交，然后向集成任务报告 worktree 路径、分支名和固定提交 SHA；推送前确保本地 privacy gate 与测试 hook 通过。
4. 报告 SHA 后冻结该任务分支；后续修改使用新提交并重新报告。

## 合并到 main

只有一个集成任务可以写主目录。它应依次执行：

```sh
git status --short --branch
git merge-tree --write-tree --messages "$(git rev-parse main)" <任务提交SHA>
git merge --no-ff <任务提交SHA>
./scripts/kin-verify-main.sh
./scripts/kin-local-git-status.sh <任务提交SHA>
```

`git merge-tree` 非零退出时不要合并；回到任务 worktree 处理冲突并重新测试。合并后验收失败时，状态会保持 `MERGED_BUT_UNVERIFIED`，不能当作可用版本。

## 状态含义

- `NOT_MERGED`：指定任务提交尚未进入 main。
- `MERGED_BUT_UNVERIFIED`：已合并，但当前 main 尚未通过完整验收或工作区不干净。
- `SAFE_TO_USE`：指定任务提交已在 main 中，main 工作区干净，且完整 macOS 测试与 iOS 编译对应当前 main。

持续观察：

```sh
./scripts/kin-local-git-status.sh --watch <任务提交SHA>
```

停止观察按 `Control-C`。每个 worktree 都应使用独立 DerivedData；不要同时在两个任务中操作同一个 worktree，也不要让两个任务同时合并、回滚或重写 main。公开发布还会在 GitHub Actions 中对全部可达 refs 执行 source-only privacy gate；本地 hook 的范围扫描不能替代该历史门禁。

如果确实需要检查本地全部 refs，可手动运行：

```sh
scripts/kin-privacy-gate.sh --all-refs --source-only
```
