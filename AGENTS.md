# AI 协作入口

本文件是仓库内所有 AI 编码代理的统一入口。先读本文件，再按任务读取下面的规范；`CLAUDE.md` 只保留指针，不维护第二套规则。

## 项目目标

本项目是 macOS 当前用户的 Claude Desktop / Claude Code 卸载与已知残留清理工具。默认预览；只有显式执行才永久删除。它不提供全盘、云端或取证级擦除保证。

- 入口：`./claude-cleaner`；双击入口：`Clean Claude.command`。
- 运行时：macOS `/bin/bash` 和 `/usr/bin/ruby`，Ruby 2.6+，使用标准库。
- 主代码：`lib/claude_cleaner/`；隔离测试：`test/`。
- 完整本地检查：`bash scripts/check.sh`。
- 覆盖范围与来源：[coverage.md](docs/coverage.md)、[sources.md](docs/sources.md)。

## 规范导航

| 文档 | 什么时候读 |
| --- | --- |
| [AI_CODING_GUIDE](docs/ai-coding/AI_CODING_GUIDE.md) | 每次开始实现、排错、审查或发布工作时。 |
| [ENGINEERING_GUARDRAILS](docs/ai-coding/ENGINEERING_GUARDRAILS.md) | 修改路径枚举、删除、系统命令、报告或 CLI 时。 |
| [SECURITY_CODING_SPEC](docs/ai-coding/SECURITY_CODING_SPEC.md) | 修改任何可能影响数据、凭据、进程、权限或共享资料的行为时。 |
| [TESTING_SPEC](docs/ai-coding/TESTING_SPEC.md) | 设计验证、运行测试、声明完成或发布前。 |
| [MAINTAINERS](MAINTAINERS.md) | 推送、审查、合并、发版或处理仓库权限时。 |
| [CONTRIBUTING](CONTRIBUTING.md) | 准备外部贡献或帮助贡献者提交改动时。 |
| [SECURITY](SECURITY.md) | 发现潜在误删、越界、凭据泄露或其他安全问题时。 |

## 不可绕过的工程边界

1. 默认 preview；`--apply` 必须展示计划并要求输入 `DELETE CLAUDE`；`--apply --yes` 是明确的无人值守入口。`--verify` 只读。不要降低确认或扩大参数默认值。
2. 不以 root 运行，不调用 `sudo`。检测到相关程序运行时拒绝清理，不 kill 应用、IDE、浏览器或其他工具。
3. 只处理有限白名单和明确选项；拒绝根目录、home 本身、路径穿越和不安全符号链接父路径。执行前重新验证目标身份；不能跟随链接删除外部内容。
4. 默认保留 `security`、`claude-security-guidance-*` 和 Git `worktrees`；共享安全资料只有 `--include-shared-security` 才纳入，`worktrees` 始终保护。项目与 Cowork 用户文件按独立选项处理。
5. 不读取或输出密码/token、会话正文、完整私有配置、共享浏览器数据库。不把真实扫描报告、机器路径、账号或私人资料提交到 Git。使用合成夹具。
6. 浏览器站点数据默认只报人工；只有 `--include-browser-site-data` 才纳入已支持 Chromium 根/profile 下三个明确 HTTPS origin 的专属 IndexedDB LevelDB/blob 目录。选项开启时，支持范围内的 Chromium 浏览器及 Helper 须全部退出，否则阻断执行与成功复查，执行前重验；不关闭或 kill 浏览器。共享 Cookies、History、Local Storage、Service Worker、CacheStorage、官方扩展、未知 origin/布局，以及系统服务、MDM、未知安装与共享状态保留人工边界。人工残留、盘点错误或执行失败不能报成完全成功。
7. 规划通过、删除完成、已知范围复查、人工事项关闭、真实设备验收分别记录。`known_scope_clean` 不表示全盘或全部浏览器资料已擦除。
8. 编码任务不自动授权对开发者真实安装环境运行清理。默认验证使用临时夹具与命令替身；真实破坏性试验须有该次明确授权及限定环境。

## 协作与 Git

保留与任务无关的改动；多人/多代理并行时只改分配的文件，不覆盖他人中间状态。不要通过 `--no-verify`、删测试、吞异常或改退出码掩盖失败。

维护者本人及获授权 AI 可使用同一管理员账号直推 `main`；外部贡献使用 fork PR，经维护者或获授权 AI 审核后 squash 合并。管理员可以按既定规则绕过 PR/checks 要求，但必须完成本地检查并跟进推后 CI。禁止 force push 或删除 `main`。

同一 GitHub 账号不能批准自己的 PR。AI 审查必须保留针对具体提交的证据，使用管理员合并记录，不伪造独立审批。初始化之后，没有新的明确授权，不修改 ruleset、权限、管理员绕过范围或可见性。完整流程见 [MAINTAINERS.md](MAINTAINERS.md)。
