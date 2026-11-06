# 0.1.1 浏览器站点数据验证

日期：2026-11-06。用户明确授权新增删除能力并清理上轮专属 IndexedDB 残留，随后说明当前暂不能退出 Chrome。真实删除因此保持待执行，不将授权本身视为浏览器已退出。

## 实现与隔离测试

新选项 `--include-browser-site-data` 仅规划三个明确网站 origin 的六种 legacy IndexedDB LevelDB/blob 专属目录。默认行为保留；共享浏览器库和其他网站不在删除范围。规划使用现有 Target/Remover，浏览器及 Helper 进程在多阶段重验。

系统 Ruby 2.6.10 运行 `bash scripts/check.sh`：151 个测试、695 条断言，0 失败、0 错误、0 跳过，公开内容检查与 diff 检查通过。新增行为均先观察失败后实现；浏览器根/profile/IndexedDB 的其他 UID 边界经独立审查发现并修复，已加入反例和普通祖先 UID 的正例。最终独立复审无未解决 P1/P2。

## 本机阻断验证

18:24:49（Asia/Singapore），对经审查的 0.1.1 工作树运行同一 scope 的 preview、apply 和 verify：

| 阶段 | 参数 | 退出码 | 结果 |
| --- | --- | ---: | --- |
| preview | `--include-browser-site-data --json` | 0 | 正确发现 1 个专属目录、27 个浏览器及 Helper 进程，盘点无问题 |
| apply | `--include-browser-site-data --apply --yes --json` | 1 | `blocked`，执行结果列表为空，零删除 |
| verify | `--include-browser-site-data --verify --json` | 1 | `remaining`，保持待清状态 |

目标目录及直接子项的设备号/inode/类型/大小元数据在阻断前后完全一致，目标仍在。仅读取元数据，没有读取数据库或用户会话正文，没有退出或结束浏览器。私有 JSON 报告保存于本机，不提交公开仓库。

## 未验收事项

真实专属目录删除及删除后的同范围复查尚未执行；必须等支持的 Chromium 浏览器与 Helper 退出后进行。隔离测试、真实阻断与真实删除是三层证据，不能互相替代。此选项也不代表共享 Cookies/Local Storage、所有浏览器会话或云端记录已清理。远端 CI 以对应提交的 GitHub 检查为准。
