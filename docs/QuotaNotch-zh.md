# QuotaNotch：Claude / Codex 刘海用量监控

这是 Boring Notch 的衍生版本，应用名称为 **QuotaNotch**，bundle ID 为
`com.apisxia.quotanotch`，内嵌 XPC 服务也使用独立标识。保留原项目窗口、刘海形状、
Home/Shelf、动画与交互，新增 AI 标签。不是独立菜单栏额度面板。

## 安装与使用

1. GitHub 仓库 Actions → **QuotaNotch macOS app** → 成功的运行 → 下载 artifact。
   解压后打开 `QuotaNotch.dmg`，把 QuotaNotch 拖入 Applications；也可使用 app.zip。
2. 退出正在运行的 Boring Notch，再启动 QuotaNotch。两者能分别安装，但不要同时
   占用同一刘海。设置和系统授权独立；如需音乐、相机或辅助功能，需要另行授权。
3. 未经 Apple 公证的构建首次打开可能被 Gatekeeper 拦截，可在系统设置 →
   隐私与安全性检查并允许打开该应用。CI 的 ad-hoc 签名不等于 Apple 开发者签名。
4. 鼠标移到刘海展开，选择柱状图图标（AI 用量），点击「启用本机用量监控」。
5. 切换 Claude / Codex，查看剩余百分比、重置日期时间、上次更新及下次可查询时间。
   重置时间使用 Mac 当前时区。关闭状态保持原版行为；第一版不在刘海两侧常驻额度。

## 本机登录要求

- Claude：需要 Claude Code 的订阅登录；在 CLI 中运行 `/login`。优先读取
  `~/.claude/.credentials.json`，不存在时读取钥匙串服务 `Claude Code-credentials`。
  自定义绝对路径 `CLAUDE_CONFIG_DIR` 仅在传入 App 进程环境时有效。
- Codex：需要 `codex login` 建立的 `~/.codex/auth.json` OAuth 凭据；支持 App 进程
  环境中的绝对路径 `CODEX_HOME`。本版暂不支持只存于 Codex 钥匙串的登录配置。
  可以在本机 Codex 配置中选择文件凭据存储后重新登录；请勿将 auth.json 发给任何人。
- 只有网页 / ChatGPT 登录、API key，或 Claude inference-only token 不保证能读取
  这些订阅额度。本版不包含完整浏览器 OAuth 登录流程，不读取浏览器 cookie。
- 过期或 401/403 会清除显示的旧额度并提示重新登录；不自动轮换 refresh token，
  不修改 CLI 凭据，避免与 CLI 同时刷新造成冲突。

凭据只在运行 App 的 Mac 内存中读取并通过 HTTPS 发给对应服务；不写日志、
不写 App 设置、不上传 workspace/GitHub、不扫描钥匙串。数据请求使用无持久缓存、
无 cookie 的短期 URLSession，并拒绝重定向。首次钥匙串访问可能需要本机允许。

## 读取与错误行为

- Claude：`https://api.anthropic.com/api/oauth/usage`，通常含 5 小时、7 天及模型窗口。
- Codex：`https://chatgpt.com/backend-api/wham/usage`，读取返回的主/次窗口及实际时长。
- 显示服务端百分比的补数（剩余 = 100 − 已用），没有返回的窗口不显示。
  缺少重置时间就标记未知。绝不将额度百分比换算为 token、费用或虚构 credits 总额。
- Claude 成功查询缓存 15 分钟，Codex 5 分钟；每分钟检查一次是否到期。
  点击刷新和多显示器共享限流，不绕过冷却。429 遵守 Retry-After，缺失时退避 15 分钟；
  其他失败冷却 60 秒。网络/服务失败时显示明确标记的旧数据。
- 启用后首次打开 AI 页启动后台轮询；重启 App 后再打开 AI 页恢复。
  暂停会停止后续轮询并清空界面；已经发出的请求可能完成。
- 这些是订阅/CLI 使用的接口，并非稳定的公开额度 API，结构、权限、限流可能变化。

## 云端构建

无需在自己的 Mac 管理源码。工作流使用 macOS 15 runner、Xcode 26.0：
先执行 `swift test --parallel`（纯 fixtures），再编译完整 universal App，ad-hoc 签名，
打包 DMG / ZIP，附同一提交的完整源码和 SHA-256 校验值。它不需要 Apple 证书 secrets，
不推送上游，不发布 Release，不改变仓库权限。GitHub runner 配额/Actions 权限仍需可用。

工作流已写入，但是否成功以实际 Actions 结果为准；本次 Linux 开发环境没有
Xcode/Swift，尚未运行 Swift 测试、macOS 编译、签名验证或真实刘海交互验证。
DMG 只有工作流通过后才会产生，源码压缩包不是安装程序。

如当前连接器无法创建 fork：在 GitHub 网页 fork Boring Notch 到自己的账户，名称可填
QuotaNotch，向 ChatGPT GitHub 连接授权该仓库，并提供链接。随后可在云端继续推送功能分支。
首次 fork 的 GitHub Actions 可能需要在 Actions 页手动启用。

## 验收清单（需 Mac）

- 应用显示 QuotaNotch，原版安装未覆盖；自动更新不指向原版。
- 刘海展开后 Home/Shelf/AI 均可访问，关闭 Shelf 设置也不隐藏 AI；多屏及全屏模式正常。
- 真实 Claude/Codex 登录、未登录、过期及钥匙串拒绝均有明确状态；额度与官方页面一致。
- 断网显示旧数据及失败说明，刷新不突破冷却；暂停后无周期请求。
- 动画、滚动、点击、屏幕缩放和 VoiceOver；不得把纯源码检查当作这些验证已通过。

## 源码与归属

基于 Boring Notch 提交 `85af174f3b3894996152c5402f6569a987d86694`（GPL-3.0）。
参考 ClaudeBar 提交 `b4077683c95b2863d65da6d8b8bd6788a5a77736` 中的数据接口行为；
其 README 标注 MIT，但该快照没有独立完整许可证文件。本实现没有复制 ClaudeBar 的
源文件、测试、图标或 UI，QuotaNotch 数据层和测试为独立编写，并保留参考归属。
因此不需要擅自替 ClaudeBar 作者补写版权持有人或许可证文本。

新增代码按 GPL-3.0-only 提供，保留原项目 LICENSE 和 THIRD_PARTY_LICENSES。
发布 App 时提供与该构建对应的完整源码及构建说明；CI 已将源码放入 artifact 与 DMG。
上游和本分支均不代表 Anthropic、OpenAI 的官方产品。
