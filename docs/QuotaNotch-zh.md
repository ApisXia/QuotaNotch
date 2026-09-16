# QuotaNotch：Claude / Codex 刘海用量监控

这是 Boring Notch 的衍生版本，应用名称为 **QuotaNotch**，bundle ID 为
`com.apisxia.quotanotch`，内嵌 XPC 服务也使用独立标识。保留原项目窗口、刘海形状、
Home/Shelf、动画与交互，新增 AI 标签。不是独立菜单栏额度面板。

## 安装与使用

系统要求：macOS 15 或更新版本（内嵌 MediaRemoteAdapter 二进制要求 macOS 15）。

1. GitHub 仓库 Actions → **QuotaNotch macOS app** → 成功的运行 → 下载 artifact。
   解压后打开 `QuotaNotch.dmg`，把 QuotaNotch 拖入 Applications；也可使用 app.zip。
2. 退出正在运行的 Boring Notch，再启动 QuotaNotch。两者能分别安装，但不要同时
   占用同一刘海。设置和系统授权独立；如需音乐、相机或辅助功能，需要另行授权。
3. 未经 Apple 公证的构建首次打开可能被 Gatekeeper 拦截，可在系统设置 →
   隐私与安全性检查并允许打开该应用。CI 的 ad-hoc 签名不等于 Apple 开发者签名。
4. 鼠标移到刘海展开，选择柱状图图标（AI 用量），点击「启用本机用量监控」。
5. 切换 Claude / Codex，查看剩余百分比、重置日期时间、上次更新及下次可查询时间。
   重置时间使用 Mac 当前时区。底部固定的一行工具栏提供固定选择、更新时间、下次查询、
   显示设置、刷新及暂停。每页并排两项额度，更多项目用底栏箭头翻页，AI 页没有滚动区。
   也可点击窗口旁图钉固定/取消。只固定一个窗口，新选择替换旧选择。
6. 收起时，只有额度则左边是服务图形，右边是细圆环；只有音乐则沿用
   原版左封面、右音频动效。两者同时出现时，左边封面右下角叠加原版音频动效，点击打开
   Home 音乐页；右边显示圆环，其右下角内嵌服务小标记，点击进入该服务的 AI 页。
   收起状态默认不显示数字；底栏齿轮 →「圆环显示数字」可开启并记住选择。环内显示剩余
   百分比数字，省略 % 号；悬停提示完整百分比。开启数字时角标略缩小，不增加两翼宽度。
   圆环、角标均限制在原版音乐图标的尺寸内，
   使用相同中央留空及间距；32pt 刘海高度下图标为 20pt，不再预留 88pt 宽的文字槽。
   音量、亮度、电池、切歌等短暂提示始终优先，提示结束自动恢复，不同时叠画。
   缺失数据使用虚线环及「—」；失败后的旧数据使用灰色圆环及琥珀色状态点，悬停明确标注
   旧数据。左右区域等宽，摄像头区域
   保持居中。隐藏刘海/高度为零时不显示固定额度。
7. AI 页没有滚动操作，滚轮和触控板不触发原版上滑收起或整体缩放；移开鼠标仍按
   原版设置收起。Home/Shelf 的开关手势保持原有设置。

圆环代表服务端剩余额度，不是 token 或费用。Codex 的订阅窗口无法分解到单个模型；
Claude 只有接口实际提供模型窗口时才显示该模型。固定选择保存在本机；旧版两侧选择升级时
优先保留右侧，否则保留左侧。旧版「音乐让位」设置移除，音乐和额度现在可同时显示。

品牌图形为针对小尺寸原创简化的放射星形与六重结形，不是官方品牌资产。云端构建使用
与应用相同的 SwiftUI 图形组件输出 Compact-UX.png，含普通/组合、0%、100%、未知和
过期 fixtures；这是尺寸及静态渲染检查，不代表真实 Mac 刘海或动画验证。

## 本机登录要求

- Claude：需要 Claude Code 的订阅登录；在 CLI 中运行 `/login`。检查
  `~/.claude/.credentials.json` 和钥匙串服务 `Claude Code-credentials`，优先选用
  有效且较新的凭据；损坏或过期的文件不会挡住钥匙串中的有效登录。
  自定义绝对路径 `CLAUDE_CONFIG_DIR` 仅在传入 App 进程环境时有效。
- Codex：需要 `codex login` 建立的 `~/.codex/auth.json` OAuth 凭据；支持 App 进程
  环境中的绝对路径 `CODEX_HOME`。本版暂不支持只存于 Codex 钥匙串的登录配置。
  可以在本机 Codex 配置中选择文件凭据存储后重新登录；请勿将 auth.json 发给任何人。
- 只有网页 / ChatGPT 登录、API key，或 Claude inference-only token 不保证能读取
  这些订阅额度。本版不包含完整浏览器 OAuth 登录流程，不读取浏览器 cookie。
- Claude 在检测时发现凭据距过期不足 5 分钟，会自动续期；认证失败时先重新读取
  本机登录，再有限重试。新的 access/refresh token 写回原来的文件或钥匙串，保留
  scopes 等字段。写入前检查原凭据是否已改变，发现外部更新就使用新凭据。
  这能缩小与 Claude Code 同时续期的竞态窗口，但两者没有共同的跨进程锁。
- Claude API 恢复失败时尝试本机 `claude /usage`，最多等待 20 秒。仅在 App 的专用
  空目录运行内置用量命令，禁用工具、普通 hooks 和外部 MCP 配置；不发送推理提示。
  备用结果支持剩余/已用百分比及相对重置时间，无法可靠解析的重置时间显示未知。
  服务端限流时不会切换通道继续请求。
- Claude 的恢复途径都失败后，才提示重新登录。Codex/Gemini 仍只读取凭据，
  认证失效时清除旧额度并提示重新登录。

凭据在运行 App 的 Mac 上读取，Claude 续期成功后保存回原来的本机存储；
通过 HTTPS 发给对应服务，不写日志、
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
- 启用后自动轮询；重启 App 即恢复监控及固定显示，无需先打开 AI 页。
  暂停会停止后续轮询并清空界面；已经发出的请求可能完成。
- 这些是订阅/CLI 使用的接口，并非稳定的公开额度 API，结构、权限、限流可能变化。

## 云端构建

无需在自己的 Mac 管理源码。工作流使用 macOS 15 runner、Xcode 26.0：
先执行 `swift test --parallel`（纯 fixtures），再编译完整 universal App，ad-hoc 签名，
打包 DMG / ZIP，附同一提交的完整源码和 SHA-256 校验值。它不需要 Apple 证书 secrets，
不推送上游，不发布 Release，不改变仓库权限。GitHub runner 配额/Actions 权限仍需可用。

GitHub macOS CI 已通过全部 14 个 fixtures 测试及 Intel/Apple Silicon 通用 App 编译。
首次运行在打包签名顺序处失败，本版已修复。安装包是否成功以实际 Actions 结果为准。
Linux workspace 本身不运行 Xcode；真实刘海交互和真实账户仍需 Mac 实机验证。
DMG 只有完整工作流通过后才会产生，源码压缩包不是安装程序。

仓库：https://github.com/ApisXia/QuotaNotch
功能分支：`feature/quotanotch-ai-usage`；PR：https://github.com/ApisXia/QuotaNotch/pull/1
GitHub 端仓库安装授权已完成，代码通过云端连接器提交；PR 按原项目规则指向 `dev`。

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
