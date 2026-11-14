import argparse
import json
import re
import shutil
import tempfile
from datetime import datetime
from pathlib import Path


DEFAULT_VAULT = Path(r"E:\obsidian\QingObs")
DEFAULT_CONVERSATIONS = DEFAULT_VAULT / "05-Codex归档" / "对话"
DEFAULT_BACKUPS = Path(r"E:\workspace\codex-obsidian-export\backups")
CODEX_HOME = Path(r"C:\Users\liuqi\.codex")

REQUIRED_HEADINGS = [
    "## 归档摘要",
    "## 用户需求演进",
    "## 当前待办",
    "## 关键路径",
    "## 原始记录",
]

SECRET_PATTERNS = [
    ("OpenAI-style key", re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b")),
    ("Bearer token", re.compile(r"Authorization\s*:\s*Bearer\s+\S+", re.I)),
    ("AppSecret value", re.compile(r"AppSecret\s*[:：=]\s*[A-Za-z0-9_-]{16,}", re.I)),
    ("generic secret", re.compile(r"(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret)\s*[:=]\s*[^\s`]+", re.I)),
]


def read_utf8(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        raise ValueError("utf8_bom_detected")
    return data.decode("utf-8")


def frontmatter_value(text: str, key: str) -> str:
    if not text.startswith("---\n"):
        return ""
    end = text.find("\n---\n", 4)
    if end < 0:
        return ""
    match = re.search(rf"(?m)^{re.escape(key)}:\s*[\"']?([^\n\"']+)", text[4:end])
    return match.group(1).strip() if match else ""


def find_notes(thread_id: str, conversations: Path) -> list[Path]:
    matches = []
    if not conversations.exists():
        return matches
    for note in conversations.glob("*.md"):
        try:
            if frontmatter_value(read_utf8(note), "codex_thread_id") == thread_id:
                matches.append(note)
        except (OSError, UnicodeError, ValueError):
            continue
    return sorted(matches)


def find_rollouts(thread_id: str) -> list[Path]:
    matches = []
    for root in (CODEX_HOME / "sessions", CODEX_HOME / "archived_sessions"):
        if root.exists():
            matches.extend(root.rglob(f"*{thread_id}*.jsonl"))
    return sorted(set(matches), key=lambda item: item.stat().st_mtime, reverse=True)


def resolve_wikilink(target: str, vault: Path) -> bool:
    clean = target.split("#", 1)[0].split("|", 1)[0].strip()
    if not clean:
        return True
    direct = vault / f"{clean}.md"
    if direct.exists():
        return True
    return any(path.stem == Path(clean).name for path in vault.rglob("*.md"))


def validate_note(note: Path, vault: Path, thread_id: str = "") -> dict:
    errors = []
    warnings = []
    try:
        text = read_utf8(note)
    except Exception as error:
        return {"ok": False, "note": str(note), "errors": [str(error)], "warnings": []}

    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        errors.append("frontmatter_missing_or_invalid")
    for key in ("type", "title", "codex_thread_id", "created", "updated", "project", "cwd", "tags"):
        if key == "tags":
            if not re.search(r"(?m)^tags:\s*$", text):
                errors.append("frontmatter_missing:tags")
        elif not frontmatter_value(text, key):
            errors.append(f"frontmatter_missing:{key}")

    actual_thread = frontmatter_value(text, "codex_thread_id")
    if thread_id and actual_thread != thread_id:
        errors.append(f"thread_id_mismatch:{actual_thread}")
    for heading in REQUIRED_HEADINGS:
        if heading not in text:
            errors.append(f"heading_missing:{heading}")

    for label, pattern in SECRET_PATTERNS:
        if pattern.search(text):
            errors.append(f"secret_detected:{label}")

    links = sorted(set(re.findall(r"\[\[([^\]]+)\]\]", text)))
    unresolved = [link for link in links if not resolve_wikilink(link, vault)]
    if unresolved:
        warnings.append({"unresolved_wikilinks": unresolved})
    duplicates = find_notes(actual_thread, vault / "05-Codex归档" / "对话") if actual_thread else []
    if len(duplicates) > 1:
        errors.append("duplicate_thread_notes:" + "|".join(str(item) for item in duplicates))

    return {
        "ok": not errors,
        "note": str(note),
        "bytes": note.stat().st_size,
        "lines": len(text.splitlines()),
        "thread_id": actual_thread,
        "wikilinks": len(links),
        "errors": errors,
        "warnings": warnings,
    }


def command_inspect(args) -> int:
    conversations = Path(args.conversations)
    result = {
        "thread_id": args.thread_id,
        "conversation_dir": str(conversations),
        "existing_notes": [str(path) for path in find_notes(args.thread_id, conversations)],
        "rollouts": [str(path) for path in find_rollouts(args.thread_id)],
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def command_backup(args) -> int:
    note = Path(args.note)
    if not note.is_file():
        raise FileNotFoundError(note)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    destination = Path(args.backup_root) / f"ObsidianTo-{timestamp}"
    destination.mkdir(parents=True, exist_ok=False)
    copied = destination / note.name
    shutil.copy2(note, copied)
    print(json.dumps({"backup": str(copied), "bytes": copied.stat().st_size}, ensure_ascii=False, indent=2))
    return 0


def command_validate(args) -> int:
    result = validate_note(Path(args.note), Path(args.vault), args.thread_id)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


def command_self_test(_args) -> int:
    with tempfile.TemporaryDirectory(prefix="obsidianto-") as temp:
        root = Path(temp)
        vault = root / "vault"
        conversations = vault / "05-Codex归档" / "对话"
        conversations.mkdir(parents=True)
        for name in ("Codex总索引", "Codex项目 - 测试项目", "主题 - 测试"):
            target = vault / f"{name}.md"
            target.write_text(f"# {name}\n", encoding="utf-8", newline="\n")
        note = conversations / "Codex对话 - 2026-08-05 - 测试 - 12345678.md"
        body = """---
type: Codex对话
title: "测试"
codex_thread_id: "12345678-1234-1234-1234-123456789012"
created: "2026-08-05 10:00"
updated: "2026-08-05 10:10"
project: "测试项目"
cwd: "E:/workspace/test"
tags:
  - Codex归档
---

# 测试
[[Codex总索引]] [[Codex项目 - 测试项目]] [[主题 - 测试]]
## 归档摘要
## 用户需求演进
## 当前待办
## 关键路径
## 原始记录
"""
        note.write_text(body, encoding="utf-8", newline="\n")
        valid = validate_note(note, vault, "12345678-1234-1234-1234-123456789012")
        if not valid["ok"]:
            raise AssertionError(valid)
        note.write_text(body + "\nAppSecret: abcdef1234567890abcdef1234567890\n", encoding="utf-8", newline="\n")
        invalid = validate_note(note, vault, "12345678-1234-1234-1234-123456789012")
        if invalid["ok"] or not any("secret_detected" in error for error in invalid["errors"]):
            raise AssertionError(invalid)
    print(json.dumps({"ok": True, "tests": ["valid_note", "secret_rejection"]}, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Guard one Codex conversation archive without rebuilding the vault.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect")
    inspect.add_argument("--thread-id", required=True)
    inspect.add_argument("--conversations", default=str(DEFAULT_CONVERSATIONS))
    inspect.set_defaults(handler=command_inspect)

    backup = subparsers.add_parser("backup")
    backup.add_argument("--note", required=True)
    backup.add_argument("--backup-root", default=str(DEFAULT_BACKUPS))
    backup.set_defaults(handler=command_backup)

    validate = subparsers.add_parser("validate")
    validate.add_argument("--note", required=True)
    validate.add_argument("--vault", default=str(DEFAULT_VAULT))
    validate.add_argument("--thread-id", default="")
    validate.set_defaults(handler=command_validate)

    self_test = subparsers.add_parser("self-test")
    self_test.set_defaults(handler=command_self_test)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.handler(args)


if __name__ == "__main__":
    raise SystemExit(main())
