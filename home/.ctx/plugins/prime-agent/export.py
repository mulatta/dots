#!/usr/bin/env python3
"""Export Prime Agent sessions to a durable ctx-history-jsonl-v2 file."""

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, TextIO

SOURCE_ID = "default"
PROVIDER_KEY = "prime-agent"
SOURCE_FORMAT = "prime-agent-jsonl-v2"


def emit(output: TextIO, record: dict[str, Any]) -> None:
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")), file=output)


def text_content(value: Any) -> str:
    """Produce searchable text without discarding Prime's structured payload."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(filter(None, (text_content(item) for item in value)))
    if isinstance(value, dict):
        for key in ("text", "content", "message", "summary", "output", "error"):
            if key in value:
                text = text_content(value[key])
                if text:
                    return text
    return ""


def event_view(row: dict[str, Any]) -> tuple[str, str | None, str]:
    kind = row.get("type", "event")
    role = None
    preview = ""
    if kind == "message" and isinstance(row.get("message"), dict):
        message = row["message"]
        native_role = message.get("role")
        role = (
            native_role
            if native_role in {"user", "assistant", "system", "tool"}
            else ("tool" if native_role == "toolResult" else None)
        )
        preview = text_content(message.get("content"))
    elif kind == "compaction":
        role = "assistant"
        preview = text_content(row.get("summary"))
    elif kind == "custom_message" and row.get("display", True):
        preview = text_content(row.get("content"))
    elif kind == "custom":
        preview = text_content(row.get("data"))
    return kind, role, preview[:4096]


def timestamp_from_mtime(path: Path) -> str:
    return (
        datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
        .isoformat()
        .replace("+00:00", "Z")
    )


def export(sessions_dir: Path, output: TextIO) -> None:
    emit(
        output,
        {
            "record_type": "manifest",
            "schema_version": "ctx-history-jsonl-v2",
            "producer": "prime-agent-ctx-plugin",
        },
    )
    emit(
        output,
        {
            "record_type": "source",
            "source_id": SOURCE_ID,
            "provider_key": PROVIDER_KEY,
            "source_format": SOURCE_FORMAT,
            "raw_source_path": str(sessions_dir),
            "trust": "provider_export",
            "fidelity": "partial",
        },
    )

    paths = sorted(sessions_dir.glob("*.jsonl")) if sessions_dir.is_dir() else []
    for path in paths:
        fallback_timestamp = timestamp_from_mtime(path)
        session: dict[str, Any] | None = None
        rows: list[tuple[int, int, dict[str, Any]]] = []

        with path.open("rb") as handle:
            for line_index, raw in enumerate(handle):
                byte_offset = handle.tell() - len(raw)
                try:
                    row = json.loads(raw)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    print(
                        f"prime-agent ctx plugin: skipping malformed line in {path}",
                        file=sys.stderr,
                    )
                    continue
                if line_index == 0 and row.get("type") == "session":
                    session = row
                else:
                    rows.append((line_index, byte_offset, row))

        if session is None:
            continue

        session_id = str(session.get("id") or path.stem)
        started_at = session.get("timestamp") or fallback_timestamp
        is_primary = session.get("rlmDepth", 0) == 0
        emit(
            output,
            {
                "record_type": "session",
                "source_id": SOURCE_ID,
                "provider_session_id": session_id,
                "cwd": session.get("cwd"),
                "started_at": started_at,
                "agent_scope": "primary" if is_primary else "subagent",
                "role_hint": "developer",
                "status": "imported",
                "fidelity": "partial",
                "metadata": {
                    "rlm_depth": session.get("rlmDepth"),
                    "git": session.get("git"),
                    "source_file": path.name,
                },
            },
        )

        searchable_types = {
            "message",
            "custom_message",
            "custom",
            "compaction",
            "git_state",
        }
        for index, byte_offset, row in rows:
            if row.get("type") not in searchable_types:
                continue
            kind, role, preview = event_view(row)
            emit(
                output,
                {
                    "record_type": "event",
                    "source_id": SOURCE_ID,
                    "provider_session_id": session_id,
                    "event_index": index,
                    "event_id": row.get("id"),
                    "native_cursor": f"{path.name}:{byte_offset}",
                    "event_type": "message",
                    "role": role,
                    "fidelity": "partial",
                    "metadata": {"prime_event_type": kind},
                    "occurred_at": row.get("timestamp") or started_at,
                    "payload": {"text": preview},
                    "preview": preview,
                },
            )


def main() -> None:
    home = Path.home()
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=home / ".prime" / "agent" / "sessions",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=home / ".local" / "share" / "prime-agent" / "ctx-history.jsonl",
    )
    args = parser.parse_args()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=args.output.parent, prefix=f".{args.output.name}.", text=True
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            export(args.sessions_dir, output)
        os.replace(temporary_name, args.output)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


if __name__ == "__main__":
    main()
