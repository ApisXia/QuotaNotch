<p align="center"><img src="docs/assets/quotanotch-icon-source.png" width="144" alt="QuotaNotch 蜷睡猫额度环图标"></p>

# QuotaNotch

在 MacBook 刘海中查看 AI 剩余额度、控制音乐和查看日历。基于 [Boring Notch](https://github.com/TheBoredTeam/boring.notch) 精简开发。

[English](README.md) · [云端构建](https://github.com/ApisXia/QuotaNotch/actions/workflows/quotanotch.yml) · [Release 页面](https://github.com/ApisXia/QuotaNotch/releases)

## 保留的功能

- Claude、Codex，以及可选的 Gemini CLI / Code Assist 额度；使用这台 Mac 上已登录的 CLI 账户。Gemini 接入不代表支持消费版网页订阅额度。
- 固定一个额度窗口：小圆环显示剩余量，可开启环内数字。音乐与额度共存时，左边封面叠加音频动效，右边显示额度。
- 顶部切换 AI 来源，中间展示具体额度，底部工具栏固定；更多窗口翻页查看。暂停来源后，从界面和固定选项中隐藏。
- 音乐控制、日历事件与提醒事项。在「设置 → 日历」启用日历。
- 「设置 → 通用 → 语言」支持简体中文、English、跟随系统，重启后应用。
- 可选的音量、亮度、电池提示；通过悬停、点击和快捷键操作刘海。

已移除文件架、AirDrop、文件共享、相机镜像、歌词抓取、实验性双指开合、展开状态 HUD 和自定义 Lottie 动画编辑器。全屏隐藏统一对所有应用生效，也可以关闭。

## 安装与使用

需要 **macOS 15 或更新版本**，支持 Apple Silicon 和 Intel。下载可用 Release 或成功构建附件内的 QuotaNotch DMG。构建附件是 ZIP，需先解压，再打开 DMG，将 **QuotaNotch.app** 拖到「应用程序」。更新前退出 QuotaNotch。

应用标识独立为 `com.apisxia.quotanotch`，不会替换原版 Boring Notch；使用时请退出原版，避免同时占用刘海。当前采用临时签名，尚未 Apple 公证；原版自动更新已关闭。

先在本机登录相应 CLI，再在 AI 额度设置启用监控。凭据保留在本机。缺失或过期的数据明确标记，不推算不存在的 token 总数、费用或模型额度。只查询已启用的来源。

## 构建与验证

使用 Xcode 26 打开 `boringNotch.xcodeproj`，选择 `boringNotch` scheme，产物名为 **QuotaNotch.app**。`swift test --parallel` 运行不需要真实账户的核心测试。云端工作流编译双架构 App，校验中英文资源、生成原生界面测试图、检查签名并打包 DMG，同时附上对应源码和许可证。

真实刘海定位、播放、日历权限和账户响应仍需在 Mac 上确认。预览图使用测试数据。

## 许可证与致谢

保留上游 **GPL-3.0** 许可证及原作者版权声明，见 [LICENSE](LICENSE) 和 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)。蜷睡猫额度环为本项目选定的原创图标，正式源图保存在 `docs/assets`；AI 品牌图形用于标识对应服务。

当前通过 GitHub Releases 手动更新。发布 Release 不会自动启用 Sparkle；还需配置本项目的更新订阅地址、公钥和安装包签名，并启用更新器。
