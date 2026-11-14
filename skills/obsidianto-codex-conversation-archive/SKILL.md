---
name: obsidianto-codex-conversation-archive
description: Archive the current or a specified Codex conversation into E:\obsidian\QingObs\05-Codex归档\对话 as a concise Obsidian Markdown note. Use when the user asks to write, update, summarize, or archive Codex/chat/task/conversation history into Obsidian according to prior rules, especially when an existing note must be matched by codex_thread_id, backed up, updated without duplicate notes, linked to project/topic indexes, stripped of tool noise and secrets, and verified as UTF-8 without BOM.
---

# ObsidianTo Codex 对话归档

把 Codex 对话整理成可检索、可继续开发的 Obsidian 精简归档。默认只维护用户指定的 `05-Codex归档/对话` 笔记，不改业务项目笔记、成本流水或用户手写正文。

## 固定边界

- 默认 Vault：`E:\obsidian\QingObs`。
- 默认对话目录：`E:\obsidian\QingObs\05-Codex归档\对话`。
- 默认备份根目录：`E:\workspace\codex-obsidian-export\backups`。
- 所有临时文件、报告和备份都放在 `E:\workspace`。
- 不运行会删除或重建整个 `05-Codex归档` 的全量导出脚本。
- 不把 AppSecret、API key、token、密码、Cookie、Authorization 或认证文件内容写入归档。

## 工作流

1. 用 UTF-8 读取 `E:\workspace\规矩文档.txt` 和 `E:\workspace\踩坑日志.txt`。读取失败时停止并报告。
2. 向用户简短说明将读取当前对话/原始记录、写入目标对话目录，并且不会修改其他 Obsidian 笔记。
3. 确定 `codex_thread_id`、对话标题、创建时间、更新时间、项目名称和真实代码目录。优先使用当前任务上下文；信息不足时读取只读 rollout。
4. 运行 `archive_guard.py inspect`，按 `codex_thread_id` 查找已有归档和原始 rollout。
5. 已有归档时保持原文件名和双链，先运行 `archive_guard.py backup`。不得为同一 thread 新建重复笔记。
6. 从用户请求、助手最终结果和已验证工具结果提炼内容。忽略系统提示、developer 指令、AGENTS、环境块、工具噪音、重复进度播报和失败命令全文。
7. 按 `references/archive-format.md` 写入 Obsidian Markdown。内容应包含需求演进、确认规则、交付结果、问题修复、验证状态、当前待办、关键路径和原始记录。
8. 对所有敏感值做脱敏。可以记录“曾出现 AppSecret，未归档明文并建议轮换”，不能保留原值。
9. 更新既有笔记时优先替换 `<!-- ObsidianTo:start -->` 与 `<!-- ObsidianTo:end -->` 之间的自动块；旧笔记无标记时，仅在用户明确要求更新该对话后，备份并进行一次迁移式重写。
10. 运行 `archive_guard.py validate`。只有编码、frontmatter、thread ID、必需章节、敏感信息和双链检查通过后才能报告完成。
11. 将本轮错误、用户修改要求、路径/编码/权限问题追加到 `E:\workspace\踩坑日志.txt`，使用 UTF-8 无 BOM并回读。

## 信息取舍

保留：

- 用户目标与需求变化。
- 已确认的业务规则和人工确认边界。
- 实际创建、修改、部署、上传或验证的结果。
- 真实文件路径、版本号、云环境和测试结论。
- 失败原因、修复方式、残余风险和下一步。

省略：

- 每条工具调用和长日志原文。
- 重复的“正在读取/继续等待”进度。
- 没有验证的推测性完成结论。
- 系统提示、权限模板、完整 AGENTS 内容。
- 密钥、token、Cookie、登录信息和认证数据库内容。

## 更新策略

- 同一 `codex_thread_id`：更新原笔记，不创建重复文件。
- 找不到旧笔记：使用 `Codex对话 - YYYY-MM-DD - 标题 - thread前8位.md`。
- 旧笔记包含用户手写区：保留自动块之外的内容。
- 标题变化但 thread 相同：保持原文件名，更新 frontmatter `title`。
- cwd 已迁移：更新为当前真实路径，并在正文说明历史路径变更（有业务价值时）。
- 原始记录很大：只记录 rollout 路径，不复制完整 JSONL 到 Vault。

## 校验命令

```powershell
python scripts/archive_guard.py inspect --thread-id <thread-id>
python scripts/archive_guard.py backup --note <note-path>
python scripts/archive_guard.py validate --note <note-path> --thread-id <thread-id>
python scripts/archive_guard.py self-test
```

最终回复必须给出：归档文件路径、备份路径、编码/双链/敏感信息检查结果，以及任何未完成或需要用户处理的事项。
