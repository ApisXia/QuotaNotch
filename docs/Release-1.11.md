# QuotaNotch 1.11

可以查看 Gemini 额度了（通过 Google Antigravity）；音量和亮度按键更可靠。

- **Gemini 额度：** 新增 Gemini 标签页，显示 Antigravity 账号的 5 小时和 7 天额度，以及其中 Claude 和 GPT 模型共用的额度。需要本机已安装并登录 Antigravity CLI（`agy` 1.1.11 或更高）；QuotaNotch 只运行它自带的用量报告，不向模型发送任何内容，也不读取令牌。约每 10 分钟更新一次，可在 设置 → AI 额度 中关闭。
- **音量和亮度按键：** 系统暂停按键监听后会自动恢复，刘海里的音量、亮度提示不会再悄悄失效到重开应用为止。
- **更稳：** 播放时长读不到时不再导致应用退出；亮度控制的后台连接重建后不会被旧连接的回调断开。

**安装：** 1.08 及以后版本可以在应用内直接更新。也可以退出 QuotaNotch，下载 `QuotaNotch-1.11.dmg`，将应用拖入「应用程序」替换。支持 Apple Silicon 与 Intel，要求 macOS 15 或更新版本。应用版本为 **1.11（325）**。安装包沿用临时签名，尚未进行 Apple 公证。

---

## English

Gemini quota (through Google Antigravity), and more dependable volume and brightness keys.

- **Gemini quota:** A new Gemini tab shows the 5-hour and 7-day quota of your Antigravity account, and the quota its Claude and GPT models share. It needs the Antigravity CLI (`agy` 1.1.11 or later) installed and signed in on this Mac; QuotaNotch only runs its built-in usage report, sends nothing to a model and reads no token. It updates about every 10 minutes and can be turned off in Settings → AI Usage.
- **Volume and brightness keys:** When macOS pauses the key listener, it now resumes on its own, so the notch's volume and brightness display no longer stops working until the app is reopened.
- **Steadier:** An unreadable track length no longer quits the app, and the brightness helper's connection is not dropped by a late callback from an earlier one.

**Install:** 1.08 and later can update from inside the app. Or quit QuotaNotch, download `QuotaNotch-1.11.dmg`, and replace the app in Applications. macOS 15+, Apple Silicon and Intel. App version: **1.11 (325)**. The app remains ad-hoc signed and is not Apple-notarized.
