# QuotaNotch 1.06

Claude 额度改为从 Claude Code 的状态栏读取，不再弹出钥匙串授权；设置重新整理，新增「连接」页；去掉了不常用的功能。

- **不再读取钥匙串：** 在「设置 → 连接」或首次启动时点击「连接 Claude Code」。QuotaNotch 只记录 Claude Code 状态栏中的 5 小时和 7 天用量，不读取也不刷新登录令牌。原有状态栏命令会保留并照常显示，断开后 `settings.json` 逐字节恢复。需要 Claude Pro 或 Max 订阅。注意：设置状态栏后，Claude Code 底部的部分快捷键提示（如 esc to interrupt）不再显示。
- **新的「连接」页：** Claude Code 与 Codex 的额度、可选的任务事件和数据目录集中在一处，每项都显示当前状态。
- **额度面板：** Claude 与 Codex 同屏显示；没有数据时直接给出连接或登录方法。进度条平时为中性色，额度偏低时才变黄、变红。「收起时显示」合并为一个选项，默认自动显示剩余最少的额度。
- **任务：** 按 Esc 中断或执行 `/model` 等命令后不再一直显示「进行中」；通知只显示项目和状态，不再包含对话内容。
- **配置文件：** 安装或移除事件连接时保留 `settings.json` 的原有顺序、格式和权限。
- **性能：** 空闲时刘海不再每 2 秒重绘，减少后台耗电。
- **移除：** 电池指示、YouTube Music、Gemini、首次启动动画和锁屏显示。触觉反馈、播放提示（sneak peek）、音量/亮度提示和 1.05 的滑动切换修复均保留。

**安装：** 先退出 QuotaNotch，下载 `QuotaNotch-1.06.dmg`，将应用拖入「应用程序」替换。支持 Apple Silicon 与 Intel，要求 macOS 15 或更新版本。应用版本为 **1.06（309）**。升级后请在「设置 → 连接」中连接 Claude Code。安装包沿用临时签名，尚未进行 Apple 公证；更新后可能需要重新授予辅助功能权限。

---

## English

QuotaNotch 1.06 reads Claude quota from Claude Code's own status line, so Keychain prompts are gone. Settings are reorganized around a new Connections page, and rarely used features were removed.

- **No more Keychain access:** Click **Connect Claude Code** in Settings → Connections or during first launch. QuotaNotch records only the 5-hour and 7-day usage from Claude Code's status line and never reads or refreshes login tokens. An existing status line command is kept and still shown; disconnecting restores `settings.json` byte for byte. Requires Claude Pro or Max. Note: with a status line, Claude Code hides some footer hints such as "esc to interrupt".
- **New Connections page:** Quota, optional task events and data folders for Claude Code and Codex in one place, each with its current state.
- **Quota panel:** Claude and Codex side by side; a service without data shows how to connect or sign in. Bars stay neutral until quota runs low. One "Closed notch shows" choice, defaulting to the lowest remaining quota.
- **Tasks:** Esc interrupts and commands like `/model` no longer leave a task stuck on "Working". Notifications show only the project and status.
- **Configuration files:** Installing or removing task events preserves `settings.json` key order, formatting and permissions.
- **Performance:** The notch no longer redraws every 2 seconds while idle.
- **Removed:** Battery indicator, YouTube Music, Gemini, the first-launch animation and the lock-screen notch. Haptics, playback sneak peek, the volume/brightness HUD and the 1.05 swipe fix are kept.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.06.dmg`, and replace the app in Applications. macOS 15+, Apple Silicon and Intel. App version: **1.06 (309)**. After upgrading, connect Claude Code in Settings → Connections. The app remains ad-hoc signed and is not Apple-notarized; you may need to grant Accessibility again after updating.
