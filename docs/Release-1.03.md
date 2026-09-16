# QuotaNotch 1.03

将已确认的 Future 290 功能纳入正式版：新增多项目 AI 编程任务监控，并整理任务、额度与音乐共存时的显示和操作。

- **多项目任务监控：** 显示项目／根目录、Codex 或 Claude Code 来源、任务名和当前状态，支持快速筛选。覆盖本机 Codex 桌面端、VS Code 扩展、CLI，以及具备本地记录的 Claude Code 会话。
- **紧凑的刘海布局：** 音乐保持左侧；额度与任务使用固定尺寸的 widget／minimal。只有任务时，左侧图标按出错、进行中、最新其他状态展示，右侧列出最近两个任务名及小状态符号。
- **清晰的任务阅读：** 任务名突出，项目与来源作为副行；详情在原 panel 内展开并与标题对齐，固定高度、内容可滚动。移除重复的空泛提示。
- **有限历史：** 已读结束记录保留在列表中，亮度略低并显示相对时间。可选保留 1 小时、5 小时（默认）或 1 天，进行中和等待处理不受时限影响；同一会话只显示最新状态。
- **整行滑动切页：** 鼠标位于展开 panel 的顶部一行时，可左右滑动切换音乐、额度和任务；一次一页，两端停止，正文滚动与按钮点击保持正常。
- **状态与等待提示：** 小符号结合状态色，进行中保留轻微动效并尊重系统“减少动态效果”。可选事件连接改善等待批准的识别，只观察状态，不会批准操作。

**安装：** 退出 QuotaNotch，下载 `QuotaNotch-1.03.dmg`，拖入「应用程序」替换。应用版本 **1.03（291）**，要求 **macOS 15+**，支持 Apple Silicon 和 Intel。现有设置和历史保留偏好继续使用。

任务监控依赖本地活动记录；不覆盖 Claude Chat／Cowork 或无本地记录的远程任务。安装事件连接后，需在相应应用中审阅并信任 hooks。安装包沿用临时签名，尚未 Apple 公证；更新仍需手动安装。

---

## English

QuotaNotch 1.03 promotes the approved Future 290 features to stable, adding multi-project coding task monitoring alongside quota and music.

- **Task monitoring:** Follow local Codex desktop, VS Code extension and CLI sessions, plus Claude Code sessions with local transcripts. See project/root folder, source, task name and current state, with quick filters.
- **Compact layouts:** Music stays left. Quota and tasks share fixed widget/minimal footprints. Task-only mode shows a priority state symbol on the left and two recent task names with small state marks on the right.
- **Readable details:** Task names lead each row; project and source appear below. Details expand inline within the fixed-height, scrollable panel, aligned with task titles. Redundant prompts are removed.
- **Bounded history:** Read results remain visible, slightly subdued with relative timestamps. Keep 1 hour, 5 hours by default, or 1 day; working and waiting tasks are exempt. Each conversation has one current record.
- **Header swiping:** Swipe anywhere across the open header row to move between Music, Quota and Tasks, one page per gesture, without wrapping or interfering with body scrolling and button clicks.
- **State awareness:** Small shapes supplement state colors, with subtle running motion that respects Reduce Motion. Optional hooks improve approval-wait detection without approving operations.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.03.dmg`, and replace the app in Applications. Version **1.03 (291)**; **macOS 15+**, Apple Silicon and Intel. Existing preferences are retained.

Monitoring requires local activity records. Claude Chat/Cowork and remote sessions without local records are not covered. Review and trust optional hooks in the relevant app after installation. The app remains ad-hoc signed and not Apple-notarized; updates install manually.
