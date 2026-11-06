# 变更记录

本文件记录源码版本与用户可见行为。发布标签、CI、本地检查和真实设备验收分别取证；版本条目本身不证明已经发布。

## 0.1.1 — 2026-11-06

- 新增显式 `--include-browser-site-data`：默认浏览器项仍为人工；开启后只将支持的 Chromium 默认根/profile 中 `https://claude.ai`、`https://console.anthropic.com`、`https://platform.claude.com` 的专属 legacy IndexedDB `.indexeddb.leveldb` 与 `.indexeddb.blob` 目录纳入计划与现有 Remover。
- 浏览器开启时可以只读预览目标和阻断信息；选项开启时，支持范围内任一 Chromium 浏览器主进程或 Helper 仍运行，执行被阻断且 `--verify` 不能成功，即使没有当前目录候选。执行前重新核对进程，不自动关闭或 kill 浏览器。
- 浏览器目标拒绝父路径链接、叶子链接、其他 UID 和非目录，继续执行目录身份与竞态检查。报告保持本机私密，不能原样提交或公开。
- 保留共享 Cookies、History、Local Storage、Service Worker、CacheStorage 和官方扩展；未知 origin、自定义位置、分区/bucket/新版布局继续人工核对。选项不表示已清除全部浏览器会话，浏览器 UI 仍是共享站点存储的推荐入口。
- 同步精确覆盖范围、Chromium 官方来源与安全/测试规范，执行和复查示例使用相同范围参数。

新增浏览器范围的真实验收状态：当前尚未执行并完成真实删除与同范围复查；浏览器暂不能退出时保持阻断。源码、隔离测试、真实只读预览、真实删除、用户验收和 CI 分别记录，不从本条目推定后续阶段已完成。

## 0.1.0 — 2026-11-06

初始源码版本，提供 macOS Bash 启动器与 Ruby 2.6+ 标准库实现。

- 默认预览，显式 `--apply` 展示计划并要求输入 `DELETE CLAUDE`，`--apply --yes` 提供明确无人值守入口，`--verify` 只读复查，`--json` 输出本机报告。
- 提供 `Clean Claude.command` 双击入口，仍要求阅读计划与确认。
- 覆盖常见 Claude Desktop / Code 安装、用户配置与历史、有限专属缓存、日志、IDE 扩展、浏览器 native host、已知 Keychain 服务与用户切换器残留。
- 提供项目、自定义配置、项目说明、Cowork 用户文件和共享安全资料的单独范围选项；保护 Git worktrees 和默认共享安全资料。
- 检查不安全路径、符号链接父目录、目标身份变化和相关运行进程；不 root、不 sudo、不 kill 应用。
- 区分规划、执行和复查，保留浏览器数据、MDM、系统服务、共享状态等人工事项；人工残留或盘点问题不报告完全成功。
- 建立来源/覆盖说明、AGENTS 单入口、四份 AI 编码规范及贡献、维护和安全政策。

验收基线：隔离夹具的破坏性测试与真实环境只读盘点通过；尚未对真实已安装的全套 Claude 环境执行破坏性清理。没有完整实机卸载验收、全盘擦除或云端删除的结论。
