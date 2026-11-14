# ObsidianTo 对话归档格式

## 目录

- 对话：`E:\obsidian\QingObs\05-Codex归档\对话`
- 项目索引：`E:\obsidian\QingObs\05-Codex归档\项目`
- 主题索引：`E:\obsidian\QingObs\05-Codex归档\主题`
- 总索引：`E:\obsidian\QingObs\05-Codex归档\Codex总索引.md`

## Frontmatter

```yaml
---
type: Codex对话
title: "对话标题"
codex_thread_id: "完整 UUID"
created: "YYYY-MM-DD HH:mm"
updated: "YYYY-MM-DD HH:mm"
project: "项目名称"
cwd: "E:/workspace/项目目录"
status: 开发中
tags:
  - Codex归档
  - Codex对话
---
```

## 正文模板

```markdown
# Codex对话 - YYYY-MM-DD - 标题 - thread前8位

上级索引：[[Codex总索引]]  
关联项目：[[Codex项目 - 项目名称]]  
关联主题：[[主题 - 主题名称]]

<!-- ObsidianTo:start -->
> [!abstract] 对话主线
> 一句话说明对话从什么问题走到什么结果。

## 归档摘要

## 用户需求演进

## 已确认规则

## 交付结果

## 重要问题与修复

## 验证状态

## 当前待办

## 关键路径

## 原始记录

- Rollout：`只读原始 JSONL 路径`
- 本笔记是精简归档，不保存工具噪音、密钥或完整逐字聊天内容。
<!-- ObsidianTo:end -->
```

## 质量规则

- 归档必须能让另一个 Codex 在不重读完整对话的情况下继续工作。
- “已完成”必须有实际文件、测试、部署或工具结果支撑。
- 使用 Obsidian wikilink 链接 Vault 内笔记。
- 使用 Windows 绝对路径记录本地文件，frontmatter 中路径统一使用 `/`。
- 保存为 UTF-8 无 BOM，换行使用 LF。
- 同一 thread 只能有一个主归档。
- 不更新总索引计数，除非确实新建了对话文件。
- 不自动修改业务项目笔记；用户明确要求时另行处理。

## 敏感信息

以下内容必须删除或替换为 `[已脱敏]`：

- AppSecret、API key、access token、refresh token。
- `Authorization: Bearer ...`。
- 密码、Cookie、会话凭据。
- `auth.json`、SQLite 认证字段或环境变量中的密钥值。

可以保留风险说明，例如：“对话中曾暴露 AppSecret，本归档未保存明文，建议立即轮换。”
