# Claude Cleaner for macOS

清理当前用户的 Claude Desktop、Claude Code 安装与已知专属残留。支持常见 native、Homebrew、npm 安装、用户配置与历史、缓存、日志、已知 IDE 扩展和浏览器 native host；对共享资料和系统管理项给出明确边界。

这是独立开源工具，不是 Anthropic 官方卸载器。默认只预览。执行会**永久删除**本机配置、登录状态、会话、记忆、技能和插件；不自动备份，也不搬到废纸篓。先阅读计划并自行保存要保留的资料。

当前版本 `0.1.1` 增加显式选择的浏览器专属 IndexedDB 清理；这项新增范围尚未完成真实环境删除与同范围复查。初始 `0.1.0` 的验收基线为隔离夹具破坏性测试和真实环境只读盘点，不能据此声称新增范围或全套实机卸载已验收。

会话清理默认覆盖已知用户数据根内的**所有账户、所有项目和全部日期**，包含会话正文、历史、自动记忆、文件历史、计划、上传附件、内部备份，以及 Desktop/Cowork 数据根内的本机会话和 VM。它不按最近使用日期筛选。外部导出、改名副本和历史备份不能靠标准目录推定已经消失；发现不明确副本时列为人工待处理。

清理本机不会删除服务端已保留的记录，也不能保证平台以后不再标记账号。本工具不修改设备身份或平台风控信息。

## 快速开始

下载或 clone 本仓库后，在仓库目录运行。需要 macOS 的 `/bin/bash` 和 `/usr/bin/ruby`（Ruby 2.6+）；代码只用标准库，不下载第三方运行依赖。不要使用 `sudo`。

```bash
# 默认预览：显示计划，不卸载、不删除
./claude-cleaner

# 执行：先显示计划，再要求输入 DELETE CLAUDE
./claude-cleaner --apply

# 只读复查：有已知残留、人工项或盘点问题时退出 1
./claude-cleaner --verify
```

也可以在 Finder 双击 `Clean Claude.command`：它会打开终端，展示计划并要求输入 `DELETE CLAUDE`。未输入确认短语就取消；结束时显示退出码。应先正常退出 Claude 及相关会话；检测到相关程序运行时工具拒绝清理，不会自动 kill 应用。

明确需要无人值守执行时使用：

```bash
./claude-cleaner --apply --yes
```

`--yes` 只允许与 `--apply` 同用，不会关闭路径保护、进程检查或失败报告。不要把它加入未经核对的自动化。

## 选项与默认保护

| 参数 | 作用 |
| --- | --- |
| `--apply` | 显式执行，默认交互确认。 |
| `--yes` | 与 `--apply` 同用，明确跳过交互确认。 |
| `--verify` | 只读复查；不能与 `--apply` 同用。 |
| `--json` | 将结构化报告写到标准输出；交互执行不能与它同用。 |
| `--config-dir PATH` | 纳入额外的、当前用户 home 内符合规则的 Claude 配置目录，可重复。当前进程的 `CLAUDE_CONFIG_DIR` 也按相同边界核对。 |
| `--project PATH` | 仅纳入指定项目根的 `.claude` 可清项，可重复。 |
| `--include-project-instructions` | 同时纳入已指定项目根的 `CLAUDE.md`、`CLAUDE.local.md`。 |
| `--include-cowork-files` | 同时纳入 `~/Claude`、`~/Documents/Claude` 中的用户产物。 |
| `--include-shared-security` | 同时纳入选定配置目录的 `security` 和支持的临时根中的 `claude-security-guidance-*`，可能影响 Codex 或其他共用工具。 |
| `--include-browser-site-data` | 同时纳入支持的 Chromium 根/profile 下 `https://claude.ai`、`https://console.anthropic.com`、`https://platform.claude.com` 的专属 IndexedDB LevelDB/blob 目录；支持范围内的 Chromium 浏览器及 Helper 必须全部退出。 |
| `--help` / `--version` | 显示帮助或源码版本。 |

默认保留共享安全资料、Git `worktrees`、项目说明和 Cowork 用户文件。`worktrees` 始终保护；共享 `.mcp.json`、`AGENTS.md`、源码、其他 AI 工具和共享依赖不自动删除。路径包含不安全父链接、目标身份变化或归属不明确时拒绝或保留，不靠扩大匹配完成删除。

项目示例只作用于显式目录：

```bash
./claude-cleaner --project /path/to/repository
./claude-cleaner --project /path/to/repository --include-project-instructions --apply
```

预览与执行时使用相同范围参数；没有指定的项目、外置盘、历史自定义目录和其他用户不会被全量扫描。

### 可选的浏览器专属 IndexedDB 清理

默认只将可识别的浏览器站点目录列为人工项。显式 `--include-browser-site-data` 只增加上述三个 HTTPS origin 的 `IndexedDB/https_<host>_0.indexeddb.leveldb` 和 `.indexeddb.blob` 目录；不读取数据库内容。它不是清除所有浏览器会话或全部站点数据的开关。

```bash
# 浏览器运行时仍可预览目标与阻断信息，不执行删除
./claude-cleaner --include-browser-site-data

# 自行正常退出支持范围内的 Chromium 浏览器及其 Helper 后执行
./claude-cleaner --include-browser-site-data --apply --yes

# 使用同样范围只读复查
./claude-cleaner --include-browser-site-data --verify
```

选项开启时，支持范围内任一 Chromium 浏览器进程（包括 Helper）仍运行，执行就被阻断，复查也不能报告成功；即使本次没发现目录，进程检查仍适用。工具在执行前重新检查，不会替用户退出或 kill 浏览器。候选必须是当前用户所有的真实目录；父路径链接、叶子链接、其他 UID 或非目录均拒绝。支持的默认根/profile 与六个精确目录名见 [覆盖范围](docs/coverage.md#浏览器专属-indexeddb-的精确范围)。

共享 Cookies、History、Local Storage、Service Worker、CacheStorage 和官方 Claude 扩展继续保留；其他 origin、自定义位置、分区/新版存储布局仍需人工核对。建议通过每个浏览器 profile 的站点数据界面清理共享存储，并在扩展管理界面卸载扩展。当前这项新增范围未完成真实删除验收；浏览器暂不能退出时应保留预览和待执行状态。

## 报告如何理解

计划、执行和验证分别记录。报告发现浏览器扩展、可识别的站点存储、系统服务、MDM 或其他人工事项时，不会擅自破坏共享数据。自动删除成功但人工残留仍在，执行仍为 `incomplete`、退出 `1`；请按 [人工处理边界](docs/coverage.md) 继续核对。

| 状态/退出码 | 含义 |
| --- | --- |
| `preview` | 已生成预览，尚未执行。退出 `0` 也不表示资料已经清除。 |
| `known_scope_clean` / `0` | 本版本选定的已知清单通过复查，未发现阻断项；不代表全盘或全部浏览器资料已经擦除。 |
| `remaining` / `1` | 只读复查仍有已知目标、进程、人工项或盘点问题。 |
| `blocked`、`changed_since_preview`、`incomplete` / `1` | 执行被阻断、计划变化或结果未完整通过，需阅读具体条目。 |
| `2` | 参数错误或用户取消等未按请求执行的情况。 |

`--json` 输出可能包含真实用户路径与应用位置。可保存在本机审阅，**不要原样提交到 Git 或公开 Issue**：

```bash
./claude-cleaner --json > "$HOME/claude-cleaner-preview.json"
```

浏览器扩展、cookies 和共享数据库通过浏览器 UI 单独处理；系统 daemon、MDM 和权限由用户/管理员核对。默认纳入 home 一级已识别的严格日期命名 Claude 配置备份，同样保留共享安全资料和 `worktrees`；未知副本转人工。工具不清空系统日志、TCC、共享浏览器 profile、外部备份、Time Machine 或 APFS 快照，不取消订阅、不删除云端账号。“深度清理”是对选定范围的更完整检查，不是取证级擦除。

## 覆盖依据与开发

- [覆盖范围与验收边界](docs/coverage.md)：默认、单独选项、人工事项和验证语义。
- [来源与取舍](docs/sources.md)：官方文档、Homebrew 清单、公开问题及第三方工具的采用/拒绝理由。
- [贡献指南](CONTRIBUTING.md)、[维护规则](MAINTAINERS.md)、[安全政策](SECURITY.md)。
- [AGENTS.md](AGENTS.md)：所有 AI 编码代理的统一入口，链接四份精简工程规范。
- [CHANGELOG.md](CHANGELOG.md)：源码版本变化与验收状态。

本地完整检查：

```bash
bash scripts/check.sh
```

测试使用临时目录和系统命令替身，不对开发者真实环境执行卸载。维护者及获授权 AI 可依既定管理员权限直推 `main`；外部贡献走 fork PR，审查后 squash 合并。两条路径都需要本地验证和推后 CI，禁止 force push 或删除 `main`。

## English summary

Claude Cleaner is an independent macOS tool for removing known Claude Desktop and Claude Code installations and local data for the current user. It previews by default. `--apply` requires `DELETE CLAUDE`; `--apply --yes` explicitly selects unattended permanent deletion. It never uses sudo or kills running applications.

Shared security data, Git worktrees, project files and Cowork outputs have separate protection rules. Browser site data is manual by default. `--include-browser-site-data` opts into only the dedicated legacy IndexedDB LevelDB/blob directories for three explicit HTTPS origins: `claude.ai`, `console.anthropic.com`, and `platform.claude.com`. All supported Chromium browser families and helpers must be stopped before apply or successful verification. The tool never closes them. Shared cookies, history, Local Storage, Service Worker, CacheStorage, official extensions, unknown layouts and other origins remain outside automatic deletion. Use each browser profile's UI for shared site data and extensions. JSON reports can contain private paths and must not be committed as-is.

Version 0.1.1 adds this explicit browser scope; real deletion and matching-scope verification of that new scope have not been accepted. Version 0.1.0's original baseline was sandbox destructive tests and real read-only inventory validation. A clean known-scope report is not a guarantee of forensic erasure, cloud deletion, removal of every trace, or clearing all browser sessions.
