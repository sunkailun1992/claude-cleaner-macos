# 来源与取舍

最后核对：2026-11-06。以下是公开资料的核对记录，不是任何用户电脑的扫描结果。`~`、`<uid>`、`<product><version>` 和 `/path/to/...` 都是通用占位写法；本页不保存真实账号、用户目录、凭据或会话内容。

本项目独立实现路径规划、执行与验证，不复制第三方清理器代码，也不下载执行这些来源中的安装器、卸载器或技能。上游文档、cask 和第三方布局会变化；增加覆盖项时应同时更新来源、规划器和隔离夹具测试。报告中未列出的目标不能仅凭本页判断已经清理。

## 官方安装与用户数据

| 编号 | 可核来源 | 核对到的事实 | 采用或拒绝的原因 |
| --- | --- | --- | --- |
| S01 | [Anthropic：Advanced setup](https://code.claude.com/docs/en/setup#uninstall-claude-code) | native 安装涉及 `~/.local/bin/claude` 与 `~/.local/share/claude`；Homebrew 的 `claude-code`、`claude-code@latest` 和 npm 全局包有各自卸载入口；用户状态在 `~/.claude`、`~/.claude.json`。Desktop 与 IDE 集成仍在时可能重建用户状态。 | 按检测到的安装渠道分别处理。卸载程序与删除用户数据分别记录，不能互相替代。项目目录不纳入默认用户清理。 |
| S02 | [Anthropic：Troubleshoot installation and login](https://code.claude.com/docs/en/troubleshoot-install#check-for-conflicting-installations) | 可能同时存在多个安装、旧 `~/.claude/local`、shell alias/function；npm 中断安装可能留下 `@anthropic-ai/.claude-code-*`。 | 覆盖已知安装位置并报告盘点失败；不认为当前 PATH 的第一个 `claude` 代表全部安装。拒绝删除整个 Node、npm prefix 或 `@anthropic-ai`。 |
| S03 | [Anthropic：Explore the .claude directory](https://code.claude.com/docs/en/claude-directory) | `CLAUDE_CONFIG_DIR` 改变用户数据与 `.claude.json` 的位置；目录含配置、插件、会话和记忆。临时图片及 scratchpad 可在 `CLAUDE_CODE_TMPDIR` 指定的位置，macOS 示例为 `/private/tmp/claude-<uid>/...`。 | 采用明确的自定义目录选项与有限临时候选；拒绝将任意环境变量值或整个临时根直接递归删除。验证不运行可能重建状态的 `claude auth status`。 |
| S04 | [Anthropic：Credential management](https://code.claude.com/docs/en/authentication#credential-management) | macOS 使用 Keychain；写入失败可回退到 `.credentials.json`。自定义配置目录也改变凭据文件位置及 Keychain 身份。 | 文件与 Keychain 分别盘点。只处理已知服务的元数据与删除结果，不读取 token/password 内容。 |
| S05 | [Homebrew：claude cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/c/claude.rb) | Desktop 身份为 `com.anthropic.claudefordesktop`；`zap` 清单包括 Application Support、近期文档、Caches、ShipIt、HTTPStorages、Logs、Preferences、savedState。 | 作为默认 Desktop 专属路径的主要依据。helper 扩展、ByHost、WebKit、诊断报告等属于本项目有限补充规则，不能声称全由 cask 保证。 |
| S06 | [Homebrew：claude-code cask](https://github.com/Homebrew/homebrew-cask/blob/main/Casks/c/claude-code.rb) | `zap` 包含 `.cache/claude`、`.claude.json*`、`.config/claude`、`.local/{bin,share,state}/claude` 和 `~/Library/Caches/claude-cli-nodejs`。对 `~/.claude` 是 `rmdir`。 | 不把 `brew uninstall --zap` 当作非空用户目录已删除的证据。本项目使用更窄的已知备份命名规则，拒绝把任何 `.claude*` 都当垃圾。 |
| S07 | [Homebrew：Manpage](https://docs.brew.sh/Manpage) | `brew --cache` 可按指定 cask 查询缓存位置；不带目标的清理会影响其他软件。 | 不执行全局 `brew cleanup`、`autoremove` 或删除整个 Homebrew cache。未纳入计划的下载缓存另作人工核对。 |
| S08 | [npm：npx](https://docs.npmjs.com/cli/v11/commands/npx/) 与 [npm-cache](https://docs.npmjs.com/cli/v11/commands/npm-cache/) | npx 可把运行包放进 npm cache，npm cache 同时服务其他包。 | 全局卸载不证明 npx 或所有 Node 版本副本已清除。拒绝清空共享 npm cache；未识别的缓存或项目依赖需人工核对。 |

## IDE 与浏览器

| 编号 | 可核来源 | 核对到的事实 | 采用或拒绝的原因 |
| --- | --- | --- | --- |
| S09 | [Anthropic：VS Code](https://code.claude.com/docs/en/vs-code#uninstall-the-extension) | 官方扩展 ID 为 `anthropic.claude-code`，扩展内有私有 CLI；macOS 专属存储为 `~/Library/Application Support/Code/User/globalStorage/anthropic.claude-code`。 | CLI 与扩展分别覆盖。仅处理已知扩展专属目录，不删除整个 IDE `globalStorage`、`workspaceStorage` 或共享数据库。其他 profile、fork、自定义目录须另外核对。 |
| S10 | [Microsoft：Extension Marketplace](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#command-line-extension-management) | IDE CLI 支持按精确 ID 卸载；扩展根可通过 `--extensions-dir` 改写。 | 默认目录盘点不能证明所有自定义位置、profile 或远端安装已清除。保留 IDE 自身及其他扩展。 |
| S11 | [Anthropic：JetBrains IDEs](https://code.claude.com/docs/en/jetbrains)；[官方 Marketplace 页](https://plugins.jetbrains.com/plugin/27310-claude-code-beta-)；[Marketplace 元数据 API](https://plugins.jetbrains.com/api/plugins/27310) | 官方插件为 Claude Code [Beta]，Marketplace 数字 ID `27310`，`xmlId` 为 `com.anthropic.code.plugin`，vendor 为 Anthropic PBC。当前官方说明插件调用另装的 CLI，不内嵌 CLI。API 于核对日通过只读 HTTPS 请求确认。 | 不把名称带 Claude 的其他 JetBrains 插件一并删除，不误写为所有 JetBrains 插件均内嵌 CLI。插件和 CLI 独立验收。 |
| S12 | [JetBrains：IDE directories](https://www.jetbrains.com/help/idea/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html) 与 [Anthropic issue #15594](https://github.com/anthropics/claude-code/issues/15594) | 标准插件根为 `~/Library/Application Support/JetBrains/<product><version>/plugins/`；可被 `idea.plugins.path` 改写。第一手故障日志出现 `claude-code-jetbrains-plugin-0.1.14-beta.jar` 及上述插件 ID。 | 可据此建立严格的版本化 JAR 候选；不能清空 IDE 共享 plugins、options、缓存或日志。自定义和远端位置保留人工边界，单个版本的文件名不保证所有未来布局。 |
| S13 | [Anthropic：Chrome integration](https://code.claude.com/docs/en/chrome#extension-not-detected) | Code 的 manifest 为 `com.anthropic.claude_code_browser_extension.json`；Chrome、Edge 和其他 Chromium 浏览器各有配置根下的 `NativeMessagingHosts`。 | 仅处理明确文件名；不把整个浏览器配置目录纳入清理。 |
| S14 | [Anthropic issue #21582](https://github.com/anthropics/claude-code/issues/21582) 与 [#46447](https://github.com/anthropics/claude-code/issues/46447) | Desktop 还可注册 `com.anthropic.claude_browser_extension.json`，指向 Desktop 的 `chrome-native-host`；卸载 App 后可能残留 manifest。 | 作为第二个精确 manifest 名称依据。用户报告是布局线索，不是上游对所有版本的兼容性承诺。 |
| S15 | [Chrome：Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging#native-messaging-host-location) | 用户级与系统级 manifest 位置不同；Chrome for Testing 也有独立位置。系统级 Chrome 示例为 `/Library/Google/Chrome/NativeMessagingHosts/`。 | 当前用户范围不提升为系统删除权限。系统级注册和自定义浏览器位置需要人工核对，不能用用户目录通过来覆盖它们。 |
| S16 | [官方 Chrome 扩展](https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn)；[Google：卸载扩展](https://support.google.com/chrome/answer/2664769?hl=en)；[按站点管理数据](https://support.google.com/chrome/answer/95647/clear-enable-and-manage-cookies-in-chrome-computer) | 官方扩展 ID 为 `fcoeoabgfenejglbffodgkkbkcdhcgfn`；扩展卸载和站点 cookie/data 可通过浏览器 UI 单独完成。 | manifest 清理不等于扩展或站点数据已清除。拒绝删除整个 Cookies、Local Storage、IndexedDB、History 或浏览器 profile。 |
| S30 | [Chromium：IndexedDB 路径实现](https://chromium.googlesource.com/chromium/src/+/3d7558df82a016802b43cdfb284a2ae20bde0b10/content/browser/indexed_db/file_path_util.cc)；[origin 标识编码](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/storage/common/database/database_identifier.cc) 与[编码测试](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/storage/common/database/database_identifier_unittest.cc) | first-party 默认 bucket 的 legacy 布局使用序列化 origin 加 `.indexeddb.leveldb` / `.indexeddb.blob`；编码为 scheme、host、port，默认端口编码成 `0`。第三方/非默认 bucket 使用不同布局；源码还存在其他数据库布局。 | 仅支持明确三个 HTTPS origin 在已识别 Chromium 根/profile 下的六种专属 legacy 目录；只有 `--include-browser-site-data` 才自动纳入。不能由这些来源推断整个 IndexedDB、所有分区存储或所有浏览器会话都已覆盖。来源核对仅访问公开源码，不读取用户数据库。 |

## 钥匙串、Cowork 与系统边界

| 编号 | 可核来源 | 核对到的事实 | 采用或拒绝的原因 |
| --- | --- | --- | --- |
| S17 | [Anthropic issue #94491](https://github.com/anthropics/claude-code/issues/94491) 与 [#91158](https://github.com/anthropics/claude-code/issues/91158) | 第一手 macOS 报告给出 `Claude Code-credentials` 和带配置目录哈希后缀的服务项。 | 不只匹配基础名称；仅按严格的已知名称/后缀规则盘点，不按 Claude 子串删除任意钥匙串项。 |
| S18 | [Electron：safeStorage](https://www.electronjs.org/docs/latest/api/safe-storage/) 与 [harryf/claude-switch](https://github.com/harryf/claude-switch) | Electron 在 macOS 使用 Keychain；该切换器公开说明 Desktop 的 `Claude Safe Storage` 是本机加密 key，删除会影响保留的账户快照。其文档也提示 logout 与仅切换本机资料的语义不同。 | 精确 Keychain 删除会使相关加密资料失效；不声称云端 token 全部撤销，不自动执行账号注销、订阅取消或云端删除。 |
| S19 | [Anthropic issue #9403](https://github.com/anthropics/claude-code/issues/9403) | 旧版本日志出现服务名 `Claude Code`，但作者明确修正了最初的“服务名不一致”解释。 | 仅用来补充历史名称的存在性检查，不把已被修正的根因当事实，不保证所有当前版本都有此服务。 |
| S20 | [Anthropic issue #22543](https://github.com/anthropics/claude-code/issues/22543) | macOS Cowork VM 示例为 `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle/rootfs.img`。 | VM 随 Desktop 专属数据处理；不能把 Cowork 工作目录与普通缓存混为一谈。用户另存的产物不从 VM 路径推定归属。 |
| S21 | [Anthropic：Managed settings](https://code.claude.com/docs/en/managed-settings) | `/Library/Application Support/ClaudeCode/` 可含组织设置、分片策略及 managed MCP；也可能由 MDM 或其他管理机制提供。 | 用户清理不修改组织策略或管理配置，不提权，不删 MDM profile。人工处理必须走设备管理员的正常流程。 |
| S22 | [Apple：控制 Mac 上的隐私权限](https://support.apple.com/en-gb/guide/mac-help/mchl2b29231a/mac) 与 [SSD 擦除说明](https://support.apple.com/en-sg/guide/disk-utility/dsku365552c7/mac) | 隐私权限有系统管理入口；Apple 明确 SSD 没有 Disk Utility 的 secure erase 选项。 | 不修改 TCC 数据库、系统安全策略或清空系统日志。普通文件删除与有限残留检查不能称为取证级擦除。 |

## 第三方资料：有限识别与拒绝扩大范围

| 编号 | 可核来源 | 核对结果 | 本项目取舍 |
| --- | --- | --- | --- |
| S23 | [YOURSJEYO/claude-switcher](https://github.com/YOURSJEYO/claude-switcher) 及其 [公开部署说明](https://github.com/YOURSJEYO/claude-switcher/blob/main/AGENTS.md) | 项目可部署 `local.claude-update` 等用户服务，以及 `local.claude-bodyguard`、`local.tz-watchdog` 系统 daemon。 | 仅采纳已知名称的有限识别；系统 daemon 报人工。绝不运行其网络、时区、代理或环境修复操作，也不认为清掉用户文件就卸载了系统 daemon。 |
| S24 | [crazymsn/claude-chinese](https://github.com/crazymsn/claude-chinese) | 公开文档给出 `~/Applications/Claude-3p.app` 作为第三方 fork 示例。 | 将明确的 `Claude-3p` 候选视为第三方覆盖，不能冒称 Anthropic 官方产品，也不能推定所有改包版本都使用这个名字或数据目录。未复制其 patch 代码。 |
| S25 | [kordless：Nuke Claude Desktop](https://gist.github.com/kordless/39db28a3e9d233bf3e8a6547026fe4c8) | 脚本包含 VM 清理思路，也按名称 kill 进程、使用较宽路径并重写 Dock 数组，且混用不同 bundle 名称。 | 不复制实现；拒绝自动 kill、批量改 Dock、忽略失败后宣称完全清除。其引用的 [#25013](https://github.com/anthropics/claude-code/issues/25013) 是 Windows 报告，不能证明 macOS 同样行为。 |
| S26 | [ePlus-DEV/claude-cleaner](https://github.com/ePlus-DEV/claude-cleaner) | 是会话数据清理器，提供 dry-run 和自定义配置目录。 | 参考清理前预览的产品原则，不把其范围当 Desktop/CLI 完整卸载依据；未执行或复制其代码。 |
| S27 | [AgriciDaniel/claude-blog：uninstall.sh](https://github.com/AgriciDaniel/claude-blog/blob/main/uninstall.sh) | 卸载器强调安装清单、文件归属和符号链接边界。 | 参考“未知内容不凭名字猜归属”的安全原则；该工具卸的是自身插件，不能当 Claude 全部路径清单。未复制其代码。 |

## 已知整目录备份惯例

Claude 官方的 `~/.claude/backups/` 随已知数据根清理；用户自行复制的整目录不一定在官方目录中。以下只证明特定命名惯例存在，不证明这些规则能找到任意位置或改名副本。本项目只在 home 一级对合法日期、严格格式的真实目录使用同一 `scan_config` 规则，并继续保护 `security` / `worktrees`；未知名称转人工。

| 编号 | 可核来源 | 采用范围 |
| --- | --- | --- |
| S28 | [dotfiles 的部署脚本](https://github.com/yulonglin/dotfiles/blob/main/deploy.sh) 与 [VisiTrans 安装文档](https://visitrans.github.io/V025-claude-toolkit/getting-started/installation/) | 受限 `.claude.backup.<日期>` / `.claude.backup-<日期>` 格式的证据。 |
| S29 | [安装与认证重置教程](https://mpiv.ai/blog/how-to-install-claude-code-on-macos-linux-and-windows-2026)、[原作者备份操作记录](https://alexkras.com/i-deleted-24-claude-code-skills-and-only-9-came-back/) 与 [LifeOS 源码](https://github.com/danielmiessler/LifeOS) | 受限 `.claude.bak-<日期>` / `.claude-backup-<日期>` 格式的证据；属于第三方惯例，不冒称官方目录契约。 |

## 本项目自己的保留策略

以下为保守的产品决策，不冒称 Anthropic 官方目录契约：默认保留 `~/.claude/security` 和临时根下的 `claude-security-guidance-*`，因为这些安全资料可能由 Codex 或其他工具共用；只有显式选择 `--include-shared-security` 才纳入对应候选。Git `worktrees`、共享 `.mcp.json`、`AGENTS.md`、用户另存产物、系统权限与共享依赖也不因名字含 Claude 而自动删除。

浏览器站点资料默认仍人工处理。`--include-browser-site-data` 的三个 origin 白名单、目录类型/当前 UID 检查、拒绝父/叶链接、以及支持范围内 Chromium 浏览器与 Helper 全部退出的要求，是本项目的保守产品边界；上游路径实现不等于允许在浏览器运行时直接删除目录。共享 Cookies、History、Local Storage、Service Worker、CacheStorage 与官方扩展不读写，继续推荐浏览器 UI。未知 origin、自定义位置和分区/bucket/新版布局不能因有限复查没有目标就当作清除。新增范围尚未完成真实删除与同范围复查。

具体版本已经实现的选项、计划状态及验收边界见 [coverage.md](coverage.md)。本页来源核对不构成真实设备执行或验收证明。
