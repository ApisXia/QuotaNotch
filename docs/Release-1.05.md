# QuotaNotch 1.05

改善 Claude 登录凭据的读取方式，减少反复出现的钥匙串授权提示，并修复额度与任务的滑动切换。

- **Claude 登录：** 优先使用有效的本地登录凭据，减少重复读取钥匙串；认证失败时不再反复启动备用检测，避免连续触发授权提示。
- **滑动切换：** 轻滑也能切换额度与任务的紧凑显示，同一次滑动不会重复切换。修正刘海中央的悬停区域遮挡两侧操作的问题。

**安装：** 先退出 QuotaNotch，下载 `QuotaNotch-1.05.dmg`，将应用拖入「应用程序」替换。支持 Apple Silicon 与 Intel，要求 macOS 15 或更新版本。应用版本为 **1.05（308）**。

现有登录和设置会保留。本版不包含试验中的收纳功能。安装包沿用临时签名，尚未进行 Apple 公证。

---

## English

QuotaNotch 1.05 improves Claude credential handling to reduce repeated Keychain permission prompts and fixes compact quota/task switching.

- **Claude sign-in:** Uses valid local credentials first and reduces repeated Keychain reads. Authentication failures no longer trigger fallback detection that could cause additional permission prompts.
- **Swipe switching:** Gentle swipes now switch between compact quota and task displays reliably, with one switch per gesture. The central notch hover region no longer overlaps the wing controls.

**Install:** Quit QuotaNotch, download `QuotaNotch-1.05.dmg`, and replace the app in Applications. macOS 15+, Apple Silicon and Intel. App version: **1.05 (308)**.

Existing logins and preferences are retained. This release does not include the experimental Shelf feature. The app remains ad-hoc signed and is not Apple-notarized.
