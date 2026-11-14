# Agent 接管说明

1. 先读取目标项目的 `AGENTS.md`，不要根据聊天主题改变项目绑定目录。
2. 每次任务开始运行 `scripts/run-codex-archive-base.ps1`。
3. 每轮结束把用户消息、最终答复、关键执行结果和路径追加到当前项目的 `会话记录.md`。
4. Obsidian 项目摘要由 `sync-obsidian-project-notes.ps1` 维护；它不替代项目本地会话归档。
5. 用户要求归档某个具体会话时，使用 `skills/obsidianto-codex-conversation-archive`，按 thread ID 更新同一笔记。
6. Context Infrastructure 的 Observer 只采集观察；Reflector 默认只提议。没有人工批准，不执行 `--apply`。
7. 遇到 OpenCode/模型超时，保留日志并报告未完成，不得把“已启动”写成 PASS。

## 上游接入

```powershell
git submodule update --init --recursive
git -C vendor/context-infrastructure apply ..\..\patches\context-infrastructure-windows-deepseek.patch
```

补丁只包含本项目对 Observer、Reflector 和 OpenCode 客户端的适配。上游更新后应先检查补丁是否仍能干净应用。
