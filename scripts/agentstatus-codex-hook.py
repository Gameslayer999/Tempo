#!/usr/bin/env python3
"""Write Codex CLI hook events in AgentStatus's session-file shape.

Codex command hooks receive one JSON object on stdin. This hook maps the
official Codex lifecycle events to the same minimal status JSON Tempo already
reads for Claude Code:

  ~/.codex/status/sessions/<session_id>.json

Set AGENTSTATUS_DIR to write somewhere else, for example ~/.claude/status if
you want one shared AgentStatus directory.
"""

import json
import os
import shutil
import sys
import time
from pathlib import Path


def clean(text):
    return " ".join(str(text or "").split())


def trunc(text, limit):
    text = clean(text)
    if len(text) <= limit:
        return text
    return text[:limit]


def basename(path):
    return Path(path or "").name


def status_root():
    configured = os.environ.get("AGENTSTATUS_DIR") or os.environ.get("CLAUDESTATUS_DIR")
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".codex" / "status"


def state_for(event, payload):
    if event in ("UserPromptSubmit", "PreToolUse", "PostToolUse", "SubagentStart", "SubagentStop"):
        return "running"
    if event == "PermissionRequest":
        return "blocked"
    if event in ("SessionStart", "Stop", "Interrupt"):
        return "idle"
    return None


def detail_for(event, payload, old):
    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
    if event == "PreToolUse":
        if tool == "Bash":
            return "$ " + trunc(tool_input.get("command"), 90)
        if tool == "apply_patch":
            return "Editing files"
        return ("Running " + tool).strip()
    if event == "PermissionRequest":
        return ("waiting - approve " + tool).strip()
    if event == "Stop":
        return trunc(payload.get("last_assistant_message"), 160)
    if event == "Interrupt":
        return ""
    if event == "SessionStart":
        return ""
    return old.get("detail", "")


def read_old(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def write_status(sessions, sid, payload, state, old):
    cwd = payload.get("cwd") or old.get("cwd") or os.getcwd()
    task = old.get("task", "")
    if payload.get("hook_event_name") == "UserPromptSubmit":
        task = trunc(payload.get("prompt"), 160)

    status = {
        "state": state,
        "cwd": cwd,
        "ide": "codex-cli",
        "pid": os.getppid(),
        "label": basename(cwd),
        "updated_at": int(time.time()),
        "task": task,
        "detail": detail_for(payload.get("hook_event_name"), payload, old),
    }
    sessions.mkdir(parents=True, exist_ok=True)
    tmp = sessions / f".{sid}.{os.getpid()}.tmp"
    target = sessions / f"{sid}.json"
    tmp.write_text(json.dumps(status, separators=(",", ":")) + "\n")
    tmp.replace(target)


def main():
    if os.environ.get("AGENTSTATUS_IGNORE") or os.environ.get("CLAUDESTATUS_IGNORE"):
        return
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return

    event = payload.get("hook_event_name") or (sys.argv[1] if len(sys.argv) > 1 else "")
    sid = payload.get("session_id") or payload.get("thread_id") or payload.get("turn_id")
    if not sid:
        return

    root = status_root()
    sessions = root / "sessions"
    session_file = sessions / f"{sid}.json"

    if event == "SessionEnd":
        try:
            session_file.unlink()
        except FileNotFoundError:
            pass
        except Exception:
            pass
        shutil.rmtree(sessions / f"{sid}.subagents", ignore_errors=True)
        return

    old = read_old(session_file)
    payload["hook_event_name"] = event
    state = state_for(event, payload)
    if state:
        write_status(sessions, sid, payload, state, old)


if __name__ == "__main__":
    main()
