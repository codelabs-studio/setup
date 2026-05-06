#!/usr/bin/env python3
"""
Anti-sycophancy Stop hook.
Scans the last assistant message in the transcript for forbidden openers.
Logs violations to ~/.claude/logs/sycophancy.log and prints a warning.
Non-blocking: always exits 0.
"""
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

FORBIDDEN_PATTERNS = [
    (r"\byou'?re absolutely right\b", "you're absolutely right"),
    (r"\btienes (toda la )?razón\b", "tienes toda la razón"),
    (r"\b(great|excellent) question\b", "great/excellent question"),
    (r"\bexcelente pregunta\b", "excelente pregunta"),
    (r"\bthat'?s a (really |truly )?(great|interesting|brilliant|fantastic) (idea|point|question)\b", "that's a great idea/point"),
    (r"\bi love how you'?re thinking\b", "i love how you're thinking"),
    (r"\bme encanta cómo estás pensando\b", "me encanta cómo estás pensando"),
    (r"^\s*perfect[!.]", "perfect! opener"),
    (r"^\s*absolutely[!.]", "absolutely! opener"),
    (r"\byou are absolutely correct\b", "you are absolutely correct"),
]

LOG_PATH = Path.home() / ".claude" / "logs" / "sycophancy.log"


def find_last_assistant_text(transcript_path: str) -> str:
    last_text = ""
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if msg.get("type") != "assistant":
                    continue
                content = msg.get("message", {}).get("content", [])
                if isinstance(content, str):
                    last_text = content
                    continue
                if isinstance(content, list):
                    text_parts = [
                        block.get("text", "")
                        for block in content
                        if isinstance(block, dict) and block.get("type") == "text"
                    ]
                    if text_parts:
                        last_text = "\n".join(text_parts)
    except FileNotFoundError:
        return ""
    return last_text


def detect_violations(text: str) -> list[str]:
    found = []
    for pattern, label in FORBIDDEN_PATTERNS:
        if re.search(pattern, text, re.IGNORECASE | re.MULTILINE):
            found.append(label)
    return found


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not os.path.exists(transcript_path):
        sys.exit(0)

    text = find_last_assistant_text(transcript_path)
    if not text:
        sys.exit(0)

    violations = detect_violations(text)
    if not violations:
        sys.exit(0)

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().isoformat(timespec="seconds")
    session_id = (payload.get("session_id") or "?")[:8]
    cwd = payload.get("cwd", "?")
    unique = sorted(set(violations))
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(f"{ts}\tsession={session_id}\tcwd={cwd}\tviolations={'|'.join(unique)}\n")

    print(
        f"⚠️  anti-sycophancy: detected forbidden opener(s): {', '.join(unique)} (logged to {LOG_PATH})",
        file=sys.stderr,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
