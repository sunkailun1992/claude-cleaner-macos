# 清理覆盖范围与验收边界

核对日期：2026-11-06。来源及采用理由见 [sources.md](sources.md)。

本工具面向 macOS 当前用户，先生成有限范围的清理计划，再按显式执行请求处理并重新盘点。它不扫描整块磁盘，不使用 `sudo`，拒绝作为 root 运行。检测到相关程序仍在运行时拒绝清理，请先自行正常退出；工具不通过 kill Claude、IDE 或浏览器来换取成功结果。

“深度清理”表示在选定范围内覆盖安装渠道、用户数据、已知系统缓存位置与集成残留，并逐项复查。它不表示全盘已擦除，也不表示外部备份、云端、其他用户、未知第三方路径或可恢复数据块已经清除。

执行采用永久删除，不自动备份，也不把目标搬到废纸篓。确需保留的会话、技能、插件、账号快照或用户产物，应在执行前自行导出并检查；保留副本不属于本工具已经清除的范围。实际 JSON 报告可能含本机路径，公开分享前应先脱敏。

## 计划、执行与验证是三个阶段

| 阶段 | 能说明什么 | 不能据此推定什么 |
| --- | --- | --- |
| 计划 | 本次参数下发现了哪些现存候选、保留项、系统动作和盘点问题；只列元数据，不读取会话正文或凭据值。 | 候选已经删除、所有安装都已发现、权限一定足够。默认预览不是执行成功。 |
| 执行 | 对计划中的路径、软件包、已知用户服务和精确 Keychain 项执行操作，分别保存结果。路径身份改变、权限失败或安全边界触发时应拒绝该操作。 | 一条命令退出 0 等于其他候选也已处理，或包卸载等于用户数据删除。 |
| 验证 | 重新盘点本工具的已知范围，区分残留、保留、人工事项和无法检查项。 | 未发现已知候选等于全盘不存在 Claude 资料，或普通删除达到取证级擦除。 |

不能把无法扫描、命令超时、Keychain 锁定、安装器失败、路径竞态或程序运行中写成“没有残留”。测试夹具通过、macOS 实际卸载、重新登录后的检查、用户确认资料范围也分别属于不同证据，发布说明应独立报告。

## 默认纳入的用户范围

下表描述本项目的有限规则。只处理本次计划实际列出的候选；版本布局、自定义路径和权限可能导致候选没有被发现。没有被列出的条目不能自行算作执行或验证成功。

| 类别 | 候选或动作 | 重要边界 |
| --- | --- | --- |
| Desktop 应用 | 已知应用根中的 `Claude.app`、`Claude-3p.app` 和已知切换器应用候选。 | 需要匹配已核 bundle 身份；未知第三方 bundle、应用叶链接和权限问题保留并报告，不仅凭显示名删除。第三方 fork 不是官方产品。 |
| Desktop 专属资料 | `~/Library/Application Support/Claude`、`Claude-3p` 及其日志；已知 bundle 的 Caches、ShipIt、HTTPStorages、WebKit、Preferences、ByHost 偏好、savedState、精确诊断报告等。 | App Support 包含登录状态、插件配置、内嵌 Code/Cowork 数据和 VM，删除会失去这些本机资料。诊断/辅助路径是有限补充，不能扩大成整个 Library 目录。 |
| Code 用户配置与历史 | `~/.claude`、`~/.config/claude` 中所有账户、所有项目、全部日期的会话、记忆、历史、附件、设置、插件、技能、日志；`~/.claude.json` 受限文件备份，以及 home 一级严格日期命名的 `.claude.bak-*`、`.claude.backup-*`、`.claude.backup.*`、`.claude-backup-*` 目录备份。 | 默认保留 `security` 和 `worktrees`；目录备份同样保护。日期需合法、名称需匹配；未知名字、文件或备份链接转人工。不递归找全盘改名副本。 |
| native 安装及用户缓存 | `~/.local/bin/claude`、`~/.local/share/claude`、`~/.local/state/claude`、`.cache/claude`、`.config/claude` 等明确候选。 | 旧的 `~/.claude/local` 随该用户目录规则覆盖；只处理计划中已识别的安装与缓存路径。 |
| Homebrew | 实际盘点到的 `claude`、`claude-code`、`claude-code@latest` cask。 | 不执行全局 cleanup/autoremove，不卸 Homebrew 或共享依赖。cask 卸载和用户资料清理分别报告。 |
| npm | 在支持的 npm 安装位置实际盘点到的 `@anthropic-ai/claude-code` 全局包，查询并固定其 global prefix 后执行。 | 多个 Node 版本分别盘点；仅确认官方包存在时才扩展动态 prefix。npx、项目依赖、无法发现的自定义安装和未知版本管理器不因当前全局卸载成功而算作已清除。 |
| IDE 专属目录 | 已知 VS Code、Insiders、Cursor、VSCodium 默认扩展根中 `anthropic.claude-code-<version>`，以及专属 `globalStorage/anthropic.claude-code`；JetBrains 标准产品插件根中的严格版本化 `claude-code-jetbrains-plugin-<version>.jar` 普通文件。 | 不清空 IDE、其他扩展、全部 globalStorage、workspaceStorage、settings 或共享数据库。不将任意同名目录、链接或无版本 JAR 当官方插件。自定义根、profile、其他 fork、远端需独立核对。 |
| 浏览器桥接 | 支持的 Chromium 配置根中两个精确名称：`com.anthropic.claude_browser_extension.json` 和 `com.anthropic.claude_code_browser_extension.json`。 | 仅删除 native manifest，不删除浏览器扩展本体、网站登录态或整个 profile。系统级 host 注册不在用户删除范围内。 |
| 钥匙串 | 已知 Desktop Safe Storage、历史 Code 名称、`Claude Code-credentials` 及受限哈希后缀项。 | 仅盘点服务元数据，不输出密码/token。Keychain 无法盘点须报告未知；删除本机项不等于撤销所有云端授权。保留的快照可能失去解密能力。 |
| 已知用户切换器 | 有限清单中的切换器用户资料与已确认的用户级 launchd label。 | 系统 daemon 不自动卸载；其他切换器、外部 profile、副本和服务不能凭相似名字推定覆盖。 |
| 当前用户临时与系统缓存 | 由当前用户运行时根导出的、名称受限的 Claude 候选，例如 `claude-<uid>`、已知 `claude-code-*` 及 Desktop bundle 缓存。 | 不清空 `/tmp`、`/private/tmp`、`/private/var/folders` 或 Darwin 用户缓存根。仅匹配到名称不能证明覆盖所有历史位置。 |

### 临时目录与 `CLAUDE_CODE_TMPDIR`

官方资料将临时根与用户配置根分开：`CLAUDE_CODE_TMPDIR` 可以改变 scratchpad 和图片等临时文件的位置。macOS 示例是 `/private/tmp/claude-<uid>/...`，而 `/tmp` 通常映射到系统的物理临时位置。若使用 `CLAUDE_CODE_TMPDIR=/tmp`，应把它当作发现精确 Claude 子目录的动态根，不能将 `/tmp` 本身当作删除目标。

工具只检查它已经支持、已经解析并安全限定的运行时根。调用者自行设置的其他临时根、另一终端的环境值、历史配置和外置盘副本不会因此被全量发现。环境变量值为空、根目录、共享父目录、含路径穿越或经过符号链接父目录时，不能放宽成递归删除。`claude-security-guidance-*` 默认保留。

## 需要单独选择的范围

这些选项扩大的是本次明确指定的范围，不解除 root、符号链接、路径身份及程序运行检查。

| 选项 | 纳入什么 | 仍保留什么 |
| --- | --- | --- |
| `--config-dir /path/to/.claude-profile` | 明确指定、位于当前用户 home 内、名字符合 Claude 配置规则的额外配置目录。 | 不接受 `/`、home 本身、任意共享父目录或不安全父路径；`security` 与 `worktrees` 保护仍适用。不能推定找到了所有历史 `CLAUDE_CONFIG_DIR`。 |
| `--project /path/to/repository` | 只在该现存项目根下纳入 `.claude` 的可清项。 | 不递归寻找所有项目；不删除源码、`.git`、共享 `.mcp.json`、`AGENTS.md` 或 Git worktree；根部说明文件需要下一项选项。 |
| `--include-project-instructions` | 与选定项目配合，将该根部的 `CLAUDE.md`、`CLAUDE.local.md` 纳入。 | 不自动删除 `AGENTS.md` 或其他工具共享说明；Git 跟踪文件的删除是项目改动，用户应自行评估和提交。 |
| `--include-cowork-files` | 将有限清单中的 `~/Claude` 与 `~/Documents/Claude` 用户文件目录纳入。 | 不搜索其他工作目录、下载目录、云盘或项目产物；这两个目录可能含用户自己的重要成果，名称并不代表可以恢复的缓存。 |
| `--include-shared-security` | 将选定 Claude 配置目录下的 `security` 和支持的临时根中 `claude-security-guidance-*` 候选纳入。 | 这些资料可能被 Codex 或其他工具共用。选项不是卸载其他 AI 工具的授权，也不解除 `worktrees` 保护。 |

仅列出上述参数不表示当前运行已经使用它们。计划与报告必须反映实际参数和现存目标。

## 人工处理和保留边界

| 范围 | 为什么不自动破坏 | 建议核对方式 |
| --- | --- | --- |
| 浏览器扩展与站点数据 | Cookies、History、Local Storage、IndexedDB 和 profile 共享数据库同时保存其他网站的数据；Chrome 同步还可能把删除传播到其他设备。 | 在每个浏览器 profile 的扩展管理界面移除官方 Claude 扩展；在站点数据界面按 Claude/Anthropic 站点单独核对并清除。manifest 消失不代表这些步骤已完成。 |
| JetBrains 未识别布局与自定义 IDE 位置 | 官方插件 ID 是 `com.anthropic.code.plugin`，标准根为 `~/Library/Application Support/JetBrains/<product><version>/plugins/`；设置可自定义，remote host 也独立。 | 对严格版本化 JAR 规则未覆盖的安装，经 IDE 的 Plugins 界面卸载 Claude Code [Beta]，关闭 IDE 后复查。不要删除整个 plugins、options、IDE cache 或日志。 |
| 系统切换器 daemon | `/Library/LaunchDaemons/` 的第三方服务可能以管理员身份运行，删除用户目录不等于卸载这些服务。 | 本工具发现已知 system label 时报告人工。由用户/管理员核对原工具与所属文件，采用该工具正常卸载流程；本工具不 sudo，不替它修复系统设置。 |
| MDM 与组织策略 | `/Library/Application Support/ClaudeCode/`、managed settings、managed MCP 和 MDM policy 归设备管理流程。 | 联系设备管理员；本工具不删系统策略，不把“用户数据已清除”说成“组织管理已撤销”。 |
| TCC、系统权限与安全策略 | TCC 涉及辅助功能、录屏、自动化等系统授权，数据库为系统共享状态。直接改库、重置全部应用权限或绕过保护会影响其他软件。 | 在系统设置的隐私与安全性入口检查 Claude 相关授权。不要删除 TCC 数据库、关闭 SIP 或修改系统信任。 |
| Unified Log、系统审计与共享缓存 | 它们记录多个进程；按文字搜索 Claude 后删除整份记录会破坏其他诊断资料，也不能证明没有历史。 | 保留系统正常轮转。工具只按有限专属文件规则处理用户报告，不能清空整个系统日志或 `/private/var/folders`。 |
| shell 设置、环境变量与凭据脚本 | `.zshrc`、`.zprofile`、`.bashrc`、`.profile`、外部 API helper 可能被多个工具共用，任意改行可能破坏 shell 或其他服务。 | 人工检查 Claude alias/function、自定义 PATH、`CLAUDE_CONFIG_DIR`、`CLAUDE_CODE_TMPDIR`、Anthropic 相关变量及辅助脚本；不要公开其真实值。 |
| 未识别安装、下载和共享依赖 | 自定义 npm prefix、npx cache、其他包管理器、手工复制程序、安装包、外置盘及自定义 profile 不保证落在白名单中。 | 结合安装记录和各自卸载入口单独核对；不删除 Node、Python、uv、Docker、整个 npm/Homebrew cache、其他 AI 工具或共享技能目录。 |
| 备份与恢复副本 | Time Machine、APFS 快照、云盘、废纸篓、手工导出、第三方账户快照不随普通文件删除消失。 | 由用户按备份工具自己的恢复/保留规则处理；本工具不删除全盘备份或清空废纸篓。 |
| 云端账号、历史、授权与费用 | 本机卸载不会自动删除云端聊天/记忆、撤销所有令牌、关闭 API key 或取消订阅。 | 在相应账户界面单独处理并核验，不能把这些账号动作计入本机脚本的执行结果。 |

## 深度清理如何验收

发布或执行报告应说明本次软件版本、所选参数、覆盖的安装渠道、实际计划、执行失败、保留项目与人工缺口。至少检查以下相互独立的证据：

1. 默认预览未执行删除或卸载，明确列出候选与保留项；测试使用临时目录和注入系统命令，不接触开发者真实资料。
2. 显式执行只作用于计划内、身份未变化的目标；父路径链接、目录替换、权限失败均不能被忽略。
3. 执行后重新盘点已知路径、包、用户服务、相关运行进程与 Keychain 项；无法检查必须报告，而不是折算为不存在。
4. 选项未开启时，项目说明、Cowork 文件、共享安全资料和 Git worktree 按相应规则保留；开启选项也不能越过其作用范围。
5. 仍需人工处理的浏览器数据、未识别 JetBrains/custom IDE、系统 daemon、MDM、共享设置与历史副本逐项列出。已知残留复查通过和这些人工工作完成分别记录。

合适的结论是“本次选定的已知范围通过复查，并列出保留/人工事项”。不要使用“全盘已擦除”“所有痕迹已消失”“不可恢复”或“云端已注销”来描述普通卸载结果。
