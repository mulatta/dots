#!/usr/bin/env python3
"""Export Prime Agent JSONL sessions to ctx-history-jsonl-v1."""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

SOURCE_ID = "default"
PROVIDER_KEY = "prime-agent"
SOURCE_FORMAT = "prime-agent-jsonl-v1"
SESSIONS_DIR = Path.home() / ".prime" / "agent" / "sessions"


def emit(record):
    print(json.dumps(record, ensure_ascii=False, separators=(",", ":")))


def load_cursor():
    text = os.environ.get("CTX_HISTORY_CURSOR")
    cursor_file = os.environ.get("CTX_HISTORY_CURSOR_FILE")
    if not text and cursor_file:
        try:
            text = Path(cursor_file).read_text()
        except OSError:
            pass
    try:
        value = json.loads(text or "{}")
        return value if isinstance(value, dict) else {}
    except json.JSONDecodeError:
        return {}


def text_content(value):
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
    return ""


def event_view(row):
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


def iso_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def main():
    cursor = {} if os.environ.get("CTX_HISTORY_FULL_RESCAN") == "1" else load_cursor()
    old_files = (
        cursor.get("files", {}) if isinstance(cursor.get("files", {}), dict) else {}
    )
    next_files = {}
    output = []

    for path in sorted(SESSIONS_DIR.glob("*.jsonl")) if SESSIONS_DIR.is_dir() else []:
        stat = path.stat()
        key = str(path)
        previous = old_files.get(key, {})
        offset = previous.get("offset", 0)
        line_index = previous.get("lines", 0)
        if (
            not isinstance(offset, int)
            or not isinstance(line_index, int)
            or stat.st_size < offset
        ):
            offset = line_index = 0

        session = None
        rows = []
        with path.open("rb") as handle:
            # Read metadata from the first line even during an incremental append.
            first = handle.readline()
            try:
                candidate = json.loads(first)
                if candidate.get("type") == "session":
                    session = candidate
            except (json.JSONDecodeError, UnicodeDecodeError):
                pass
            handle.seek(offset)
            while True:
                start = handle.tell()
                raw = handle.readline()
                if not raw:
                    break
                # Do not checkpoint an incomplete final line.
                if not raw.endswith(b"\n"):
                    handle.seek(start)
                    break
                try:
                    row = json.loads(raw)
                except (json.JSONDecodeError, UnicodeDecodeError):
                    print(
                        f"prime-agent ctx plugin: skipping malformed line in {path}",
                        file=sys.stderr,
                    )
                    line_index += 1
                    continue
                rows.append((line_index, start, row))
                line_index += 1
            final_offset = handle.tell()

        if session is None:
            next_files[key] = {
                "offset": final_offset,
                "lines": line_index,
                "size": stat.st_size,
            }
            continue

        session_id = str(session.get("id") or path.stem)
        started_at = session.get("timestamp") or iso_now()
        if rows or offset == 0:
            output.append(
                {
                    "record_type": "session",
                    "source_id": SOURCE_ID,
                    "session_id": session_id,
                    "native_session_id": session_id,
                    "cwd": session.get("cwd"),
                    "started_at": started_at,
                    "agent_type": "primary"
                    if session.get("rlmDepth", 0) == 0
                    else "subagent",
                    "role_hint": "developer",
                    "is_primary": session.get("rlmDepth", 0) == 0,
                    "metadata": {
                        "rlm_depth": session.get("rlmDepth"),
                        "git": session.get("git"),
                        "source_file": path.name,
                    },
                }
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
            output.append(
                {
                    "record_type": "event",
                    "source_id": SOURCE_ID,
                    "session_id": session_id,
                    "event_index": index,
                    "event_id": row.get("id"),
                    "native_cursor": f"{path.name}:{byte_offset}",
                    "event_type": "message",
                    "role": role,
                    "metadata": {"prime_event_type": kind},
                    "occurred_at": row.get("timestamp") or started_at,
                    "payload": {"text": preview},
                    "preview": preview,
                }
            )
        next_files[key] = {
            "offset": final_offset,
            "lines": line_index,
            "size": stat.st_size,
        }

    observed_at = iso_now()
    emit(
        {
            "record_type": "manifest",
            "schema_version": "ctx-history-jsonl-v1",
            "metadata": {"exporter": "prime-agent-ctx-plugin"},
        }
    )
    emit(
        {
            "record_type": "source",
            "source_id": SOURCE_ID,
            "provider_key": PROVIDER_KEY,
            "source_format": SOURCE_FORMAT,
            "raw_source_path": str(SESSIONS_DIR),
            "observed_at": observed_at,
            "cursor": {
                "after": {
                    "stream": os.environ.get(
                        "CTX_HISTORY_CURSOR_STREAM", "prime-agent:default"
                    ),
                    "cursor": json.dumps({"files": next_files}, separators=(",", ":")),
                    "observed_at": observed_at,
                }
            },
        }
    )
    for record in output:
        emit(record)


if __name__ == "__main__":
    main()
