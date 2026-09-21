# QuotaNotch 1.04

新增可选像素猫猫，统一任务状态图标，并修复右侧增加 minimal 时左侧音频跟着外移的问题。

- **猫猫默认关闭。** 在设置中手动开启后，可在刘海左右边缘来回摩擦鼠标唤出。猫猫会从对应一侧出现；空间不足时只探头轻顶，并自动收回。支持可选的任务提示动作。
- **统一任务状态。** widget、minimal 和列表图标使用同一母版等比缩放。运行中为翻动纸张，等待处理为有节奏跳动的气泡，完成为绿色收尾，中断为紫色双竖线，出错为带呼吸光晕的红叉。遵循系统“减少动态效果”。
- **更明确的任务管理。** 新增一键已读；任务窗口可按当前项目处理。保留运行和等待状态、有限历史，以及后续新事件的未读提醒。主状态优先级为未读失败、等待处理、进行中、其他最新状态，角标只统计当前主状态。
- **独立的左右布局。** 右侧增加 minimal 只向右扩展，音频和物理刘海保持原位。任务单独显示、模块切换和不同显示密度也使用一致的定位规则。
- **猫猫交互修复。** 改善左右边缘触发、拥挤时同侧探头、重复手势、自动退出和中途收回的连续性。

**安装：** 退出 QuotaNotch，下载 `QuotaNotch-1.04.dmg`，拖入「应用程序」替换。版本 **1.04（307）**，支持 **macOS 15+、Apple Silicon 和 Intel**。默认关闭猫猫；已手动保存的开关选择会保留。

云端验证覆盖核心逻辑、中英文布局、模块组合、播放切换、刘海定位和模拟鼠标交互。安装包沿用临时签名，尚未 Apple 公证；更新仍需手动安装。任务监控范围与 1.03 一致，依赖本机活动记录。

---

## English

QuotaNotch 1.04 adds an optional pixel cat, unifies task status artwork, and fixes music shifting when a minimal module appears on the right.

- **Cat off by default.** Enable it in settings, then rub either outer notch edge to summon it on that side. Crowded wings show a small peek and nudge before retreating. Optional task reactions are available.
- **Consistent task icons.** Widgets, minimal slots and list marks scale the same artwork. Running pages, a bouncing waiting bubble, a green completion mark, purple interruption bars and a breathing red error halo distinguish states. Reduce Motion is respected.
- **Read all.** Mark current unread tasks across projects or within the selected project, preserving history, active/waiting states and later unread events. The status badge counts only the displayed primary state.
- **Independent wings.** Adding a right-side minimal module keeps music and the physical notch anchored. Task-only layouts, module swaps and display density changes follow the same positioning rules.
- **Cat interaction fixes.** More reliable edge gestures, same-side crowded peeks, repeated-gesture handling and continuous automatic/interrupted retreat.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.04.dmg`, and replace the app in Applications. Version **1.04 (307)**; **macOS 15+**, Apple Silicon and Intel. The cat starts disabled; explicitly saved preferences are retained.

Cloud validation covers core logic, English/Chinese layouts, module combinations, playback transitions, notch anchoring and simulated pointer input. The app remains ad-hoc signed and not Apple-notarized; updates install manually. Task monitoring retains the local-record scope of 1.03.
