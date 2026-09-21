<p align="center"><img src="docs/assets/quotanotch-icon-source.png" width="96" alt="QuotaNotch"></p>

# QuotaNotch

在 MacBook 刘海中查看 AI 额度和编程任务状态、控制音乐和查看日历。

[English](README.md) · [下载](https://github.com/ApisXia/QuotaNotch/releases) · [构建附件](https://github.com/ApisXia/QuotaNotch/actions/workflows/quotanotch.yml)

![QuotaNotch](docs/assets/usage-preview.png)

原生界面预览，使用示例数据。

- 可选像素猫猫，默认关闭；在设置中开启后，可在刘海左右边缘来回摩擦鼠标唤出。
- 统一任务状态图标，支持一键已读；左右区域独立定位，新增 minimal 不再带动音频侧。
- 支持 Claude、Codex 和可选的 Gemini CLI / Code Assist 额度。
- 按项目监控本机 Codex 和 Claude Code 任务，显示来源、进行状态与等待处理提醒。
- 固定一个额度，与音乐和任务共存；点击 widget 打开对应页面，在展开后的顶部整行左右滑动切页。
- 已读任务历史可保留 1 小时、5 小时（默认）或 1 天。
- 额度不足时逐渐变黄、变红，并带轻微光晕。
- 保留日历、提醒事项，支持中文与英语。

**macOS 15+，支持 Apple Silicon 和 Intel。** 打开 DMG，拖入「应用程序」。先登录本机 CLI，再在设置中启用 AI 监控。当前手动更新，安装包尚未 Apple 公证。

[使用与构建说明](docs/Guide.zh-CN.md) · [GPL-3.0](LICENSE) · [第三方许可](THIRD_PARTY_LICENSES)

基于 [Boring Notch](https://github.com/TheBoredTeam/boring.notch)。
