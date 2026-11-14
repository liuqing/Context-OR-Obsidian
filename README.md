# Codex Conversation Archive Pipeline

一套可复用的 Windows/Codex 会话归档与上下文维护链路。目标是先把会话可靠归档到各项目，再生成 Obsidian 项目摘要，并按需把指定会话整理到 Obsidian 对话库。

## 执行顺序

```text
run-codex-archive-base.ps1
  -> sync-codex-projects.ps1
  -> export-codex-history.ps1
  -> 项目目录/会话记录.md
  -> 无法归属的会话进入 E:\临时会话记录.md

sync-obsidian-project-notes.ps1
  -> Obsidian/05-Codex归档/项目

obsidianto-codex-conversation-archive
  -> 仅按需整理指定 thread
  -> Obsidian/05-Codex归档/对话
```

grapeot 的 [Context Infrastructure](https://github.com/grapeot/context-infrastructure) 以固定提交 `3c25337` 的 Git 子模块接入。`patches/` 中保存 Windows、OpenCode 与 DeepSeek 的本机适配，不重新声称拥有上游源码。

## 快速开始

```powershell
git clone --recurse-submodules https://github.com/liuqing/Context-OR-Obsidian.git E:\workspace\Context-OR-Obsidian
cd E:\workspace\Context-OR-Obsidian
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

安装前请检查脚本中的本机路径、Codex SQLite 文件名和 Obsidian Vault 路径。本模板默认使用 `E:\workspace`、`E:\obsidian\QingObs`。API Key 只能通过用户环境变量提供，不得提交到仓库。

## 推荐调度

- Observer：每天 08:00，仅更新 `OBSERVATIONS.md`。
- Reflector：每周日 09:30，只生成待批准候选。
- Obsidian 项目摘要：每周日 20:00。
- 单会话 Obsidian Skill：用户明确要求时触发，不做全量定时扫描。

## 安全边界

- `run-codex-archive-base.ps1` 是基础归档的唯一入口，并用互斥锁阻止并发重复执行。
- Reflector 提议阶段不得修改 `rules/`。
- 同一 Obsidian 对话以 `codex_thread_id` 更新，不重复建笔记。
- 不提交 API Key、Token、密码、Cookie、私钥、Codex 数据库或真实会话正文。

## 当前验证状态

- 基础项目同步与历史导出：已在 Windows 实机验证，退出码 0。
- Obsidian 项目摘要：已生成并更新项目笔记。
- Observer/Reflector：包装链路、OpenCode 启停和日志已接入；一次人工演练中模型调用未在限定时间完成，因此接管者仍需复测端到端模型响应。

详见 [HANDOFF.md](HANDOFF.md)。
