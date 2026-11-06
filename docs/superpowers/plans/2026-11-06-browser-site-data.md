# 浏览器站点数据实施计划

> **For agentic workers:** 按模块分工实现，先红后绿，主代理整合并进行独立复核。

**Goal:** 让已授权的 Claude 专属 IndexedDB 残留可以通过显式选项安全清理。

**Architecture:** BrowserData 规划精确目录，MacSystem 提供浏览器进程守卫，CLI 统一预览、执行和重新盘点，Remover 保留现有边界。

**Tech Stack:** 系统 Ruby 2.6+、Minitest、现有 Bash 启动器。

**Spec:** `../specs/2026-11-06-browser-site-data-design.md`

## 约束与复核

- 默认不扩大；无 root/sudo/kill，不读共享数据库。
- 当前用户暂不能退出 Chrome，真实删除不得执行；运行状态恢复后另行核验。
- 相似 host、shared store、链接、其他 UID 与未知 bucket 不得纳入。
- 浏览器运行、helper存活、扫描失败或删除前重启不得被报成成功。

## 任务

- [x] 编写 BrowserData 失败测试，再实现元数据清单及保护。
- [x] 编写 Chromium 主进程/helper/扫描失败测试，再实现进程守卫。
- [x] 编写 CLI 显式选项、默认保护、真实夹具删除和重启阻断测试，再整合。
- [x] 更新 0.1.1 帮助、规范、覆盖和来源，运行完整检查及独立审查。
- [x] 真实预览并核验 Chrome 运行时零删除，见本轮验证记录。
- [ ] Chrome 退出后执行真实清理及同范围复查；当前用户暂不能退出，保留待执行状态。

交付门禁：提交推送后确认远端两个 CI；实际状态见 GitHub 对应提交检查与本轮回执。
