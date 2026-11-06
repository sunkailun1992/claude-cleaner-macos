# Claude 专属浏览器站点数据清理

## 用户授权与目标

用户明确要求删除上轮残留的 Claude 浏览器数据，并把删除能力加入本脚本。用户随后说明暂时不能退出 Chrome，因此本轮先实现、测试、推送和验证阻断行为；真实删除必须等相关浏览器完全退出后进行，不能以开发任务或授权本身代替这个运行前提。

## 方案与取舍

新增显式 `--include-browser-site-data`，默认行为不变。方案只删除支持的 Chromium 默认配置根/profile 下三个明确 origin 的专属 IndexedDB legacy 目录及 blob 伴随目录：`claude.ai`、`console.anthropic.com`、`platform.claude.com`。它们具有明确文件边界；共享 Cookies/History/Local Storage、第三方 bucket 和未知格式仍保留人工/UI处理。直接修改共享浏览器数据库会扩大影响；在浏览器运行时删除目录存在锁和写回问题，因此选择退出浏览器后处理受限目录。

## 实现边界

- `BrowserData` 只读元数据，输出现有 `Target` 的路径、原因和 lstat 身份；不按 Claude 字符串泛搜，不读会话或数据库。
- 父链接、目标链接、非目录、其他 UID、枚举或身份问题均阻断。现有 Remover 继续检查根、身份、链接和跨文件系统边界。
- `MacSystem.browser_processes` 识别支持的 Chromium App 与 helper。启用选项时预览列进程；apply 和 verify 在浏览器仍运行时不能成功；执行前及每个浏览器目标前重新检查。绝不自动关闭或 kill 浏览器。
- CLI 将仅成功纳入计划的精确站点目录从人工项转为删除项，不移除其他人工发现；删除后继续独立盘点。不能用隐藏报告制造“清洁”。
- 浏览器重新启动与文件 syscall 无法在可移植 Ruby 中原子互斥，用户在本次执行期间须保持退出状态。该功能不承诺清理所有浏览器存储或服务端资料。

## 验收

临时目录验证显式选项与默认差异、精确 origin/相似 host 反例、blob、路径/UID保护、进程与 helper 阻断、盘点失败、预览无写入、删除/复查/幂等，以及删除前浏览器重启保护。运行完整本地检查和两个 CI；真实运行只在退出条件满足时执行，当前应记录 Chrome 运行阻断、目标仍在与零删除。
