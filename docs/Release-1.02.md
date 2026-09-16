# QuotaNotch 1.02

改善 Claude 额度读取的恢复能力，统一系统控制提示，并整理设置界面的逻辑与中英文排版。

- **Claude 连接恢复：** 增加登录状态更新、凭据重新读取和有时限的 Claude Code 用量恢复路径，减少登录状态变化后额度无法继续读取的情况。
- **一致的系统提示：** 调节音量、屏幕亮度等控制时，保留当前刘海内容，在下方显示控制条；音乐、混合和纯额度模式遵循相同规则。
- **更简洁的设置：** 移除空闲表情、手动刘海尺寸、悬停延迟和零散的装饰样式选项。刘海高度自动适配屏幕，视觉效果采用统一默认值。
- **中英文布局：** 重新归类设置项，统一标签与控件的对齐，修正英文长文本拥挤、侧栏截断及部分中文标题未翻译的问题。设置窗口支持拉伸并记住尺寸。
- **清晰的权限与状态：** 区分日历权限未申请、被拒绝和受限制等情况；暂停监控或服务时保留配置，并清楚显示额度自动选择与手动备用项的关系。
- **音乐控制修复：** 点击和拖动采用一致的去重规则，位置已满时需要明确选择替换位置；音乐来源回退时，设置与实际使用的来源保持一致。

**安装：** 先退出 QuotaNotch，下载 `QuotaNotch-1.02.dmg`，将应用拖入「应用程序」替换。支持 Apple Silicon 与 Intel，要求 macOS 15 或更新版本。应用版本为 **1.02（279）**。

现有 CLI 登录、服务选择与额度配置会保留；旧的手动尺寸和已移除的装饰选项不再生效。安装包沿用临时签名，尚未进行 Apple 公证。

---

## English

QuotaNotch 1.02 improves Claude usage recovery, makes system indicators consistent, and simplifies settings with clearer English and Chinese layouts.

- **Claude recovery:** Refreshes and reloads credentials when needed, with a time-limited Claude Code usage fallback to recover from authentication changes.
- **Consistent system indicators:** Volume, brightness and related controls appear below the current notch content across music, combined and quota-only modes.
- **Simpler preferences:** Removes the idle face, manual notch sizing, hover-delay adjustment and small decorative options. Notch height adapts to the display, with consistent visual defaults.
- **Settings layout:** Regroups related options, aligns labels and controls, fixes crowded English text and clipped sidebar labels, and completes missing Chinese labels. The settings window resizes and remembers its dimensions.
- **Permissions and saved choices:** Distinguishes calendar permission states, preserves configuration while monitoring or providers are paused, and explains automatic quota selection and its manual fallback.
- **Music controls:** Click and drag now share duplicate-handling rules. A full layout requires an explicit replacement choice, and source settings reflect the active fallback.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.02.dmg`, and replace the app in Applications. macOS 15+, Apple Silicon and Intel. App version: **1.02 (279)**.

Existing CLI logins, provider choices and quota preferences are retained. Retired manual sizing and decorative preferences no longer apply. The app remains ad-hoc signed and is not Apple-notarized.
