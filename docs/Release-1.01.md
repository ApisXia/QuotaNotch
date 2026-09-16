# QuotaNotch 1.01

在保留原有紧凑布局的基础上，改善额度显示与状态反馈。

- 修正圆环与图标的视觉尺寸差异，轻微提高数字可读性，保持原版面板尺寸与单排工具栏。
- 显示额度重置倒计时；悬停可查看完整时间。
- 增加刷新冷却提示、按更新时间识别旧数据，以及电脑唤醒后的额度检查。
- 在「设置 → AI 额度」中增加可选的低额度/恢复通知、自动关注所选额度窗口，以及不含凭据的诊断信息复制。
- 调整悬停收起延迟，保护菜单操作，并统一遵循系统「减少动态效果」设置。
- 使用过放大版开发包的用户，首次启动本版本会恢复紧凑显示；后续仍可自行选择大字模式。

**安装：** 先退出 QuotaNotch，下载 `QuotaNotch-1.01.dmg` 并将应用拖入「应用程序」替换。支持 Apple Silicon 与 Intel，要求 macOS 15 或更新版本。

此安装包沿用临时签名，尚未进行 Apple 公证。系统可能要求在「隐私与安全性」中允许打开。现有 CLI 登录与固定额度设置会保留。

---

## English

QuotaNotch 1.01 refines quota readability and status feedback while retaining the original compact layout.

- Corrected ring alignment and slightly clearer digits, with the original panel dimensions and single-row toolbar.
- Reset countdowns with complete timestamps on hover.
- Refresh cooldown feedback, age-based stale readings and a usage check after wake.
- Optional low-quota/recovery alerts, automatic selection among chosen quota windows, and credential-free diagnostics under Settings → AI Usage.
- More forgiving hover dismissal, menu protection and consistent support for Reduce Motion.
- Users of the enlarged development build return to compact display once on upgrade; larger display remains optional.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.01.dmg`, and replace the application in Applications. macOS 15+, Apple Silicon and Intel.

The app remains ad-hoc signed and is not Apple-notarized. macOS may require allowing it in Privacy & Security. Existing CLI logins and pinned quota settings are retained.
