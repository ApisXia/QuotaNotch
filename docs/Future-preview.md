# Future preview · Codex task monitor

This preview is built from the `future` branch. It adds multi-project task monitoring to QuotaNotch 1.02. The stable 1.02 release is unchanged.

## 使用

- 安装 DMG 中的 QuotaNotch，替换原应用并重新打开。
- 本机 Codex 桌面端或 VS Code 的 Codex 扩展开始任务后，刘海下方显示项目与任务数量。
- 点击摘要进入任务页；“全部项目”打开可缩放的任务监控窗口。菜单栏也有直接入口。
- 项目名和归属自动跟随 Codex 的调整；没有明确归属时使用 Git 根目录或工作根目录名。Git worktree 尽量归回主仓库，同名但路径不同的项目保持独立。
- 可以搜索项目、任务名和目录，筛选进行中或未读任务，置顶常用项目，清除已结束任务。
- 点击任务返回其来源应用；任务菜单可指定 Codex 或 VS Code，也可查看工作目录、复制会话 ID。
- 刘海保留原有额度和音乐布局；任务摘要作为附加行显示。

## 状态与连接

“本轮完成”只表示 Codex 结束本轮响应，不保证代码或测试通过。中断单独显示。两分钟没有新活动会显示提示，十二小时没有新活动的未结束记录标为“状态待确认”，不会自动宣告失败或成功。

默认监控不改 Codex 配置。它读取本机任务记录，支持开始、结束、中断和可识别的等待输入状态。要及时显示工具的**等待批准**状态，在设置 → 任务监控安装事件连接，然后在 Codex CLI 的 `/hooks` 中审阅并信任 QuotaNotch 的连接，再重新打开任务。这是 Codex 的信任要求；预览版不会绕过它。未信任时基础监控正常工作。

事件连接保留已有 hooks，提供移除操作。它只记录会话 ID、轮次 ID、事件类型和时间，不批准或阻止任何 agent 操作。原配置备份保存在本机 QuotaNotch 的 Application Support 目录。

远程 SSH、容器或纯云端任务只有在本机存在对应活动记录时才能显示。目录可在设置中指定。默认追踪最近七天更新的最多 2000 条记录，任务窗口保留活跃任务与最近一天的结果；归档任务和内部子代理不会挤占列表。

系统通知可单独开启；按项目归组，密集完成时限制提示音频率，首次启动不重播历史完成通知。所有状态在本机处理，不上传对话、项目或路径。

## Validation

The cloud workflow runs core fixture tests, builds a universal arm64/x86_64 application, tests the native event adapter, verifies translations and signing, packages the installer, and separately renders the actual task/settings interfaces in Chinese and English at narrow/wide widths and in light/dark appearances. Preview code is excluded from the installer.

New fixtures cover concurrent projects, same-name roots, project renaming and reassignment, linked worktrees, archived tasks, resumed/duplicated rollouts, partial and oversized JSONL writes, file replacement, long-conversation recovery, interruption, stale events, approval hooks, and configuration preservation. No real user credentials are used in CI.

The Codex local metadata/transcript formats and VS Code deep-link route are compatibility adapters, not a promise that every future client version will preserve them. When data cannot be read, the app reports degraded monitoring instead of fabricating completion.
