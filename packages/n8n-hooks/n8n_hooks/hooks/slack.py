"""slack hook — read-only Slack context via n8n.

The n8n workflow holds the Slack token. This CLI forwards one of a fixed
set of operations to the webhook so the agent can search messages, list
channels/users, read channel history/thread replies, read small text files, and
download document attachments without holding credentials.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import sys
from pathlib import Path

from n8n_hooks.config import HookConfig
from n8n_hooks.webhook import post

HOOK_NAME = "slack"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        "slack",
        help="Query Slack via n8n (read-only)",
        description="Search / list / read Slack messages, channels and users.",
    )
    sub = p.add_subparsers(dest="op", required=True)

    s = sub.add_parser("search", help="Search messages")
    s.add_argument("query", help="Slack search query, e.g. 'in:#dev foo'")
    s.add_argument("-n", "--limit", type=int, default=20)

    h = sub.add_parser("history", help="Channel history")
    h.add_argument("channel", help="Channel ID, e.g. C0123456789")
    h.add_argument("-n", "--limit", type=int, default=50)

    r = sub.add_parser("replies", help="Thread replies")
    r.add_argument("channel", help="Channel ID")
    r.add_argument("thread_ts", help="Parent message ts, e.g. 1712345678.123456")
    r.add_argument("-n", "--limit", type=int, default=50)

    fi = sub.add_parser("file-info", help="Show Slack file metadata")
    fi.add_argument("file", help="Slack file ID, e.g. F0123456789")

    fc = sub.add_parser("file-content", help="Read small text Slack files")
    fc.add_argument("file", help="Slack file ID, e.g. F0123456789")
    fc.add_argument("--max-bytes", type=int, default=1_048_576)

    fd = sub.add_parser("file-download", help="Download allowed Slack documents")
    fd.add_argument("file", help="Slack file ID, e.g. F0123456789")
    fd.add_argument("-o", "--output", required=True, help="Output file or directory")
    fd.add_argument("--max-bytes", type=int, default=5_242_880)

    sub.add_parser("list-channels", help="List all non-archived channels")
    sub.add_parser("list-users", help="List all users")

    p.set_defaults(func=run)


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    payload: dict[str, object] = {"operation": args.op}
    for k in (
        "query",
        "channel",
        "thread_ts",
        "limit",
        "file",
        "max_bytes",
    ):
        v = getattr(args, k, None)
        if v is not None:
            payload[k] = v
    return payload


def _safe_filename(raw: str) -> str:
    name = raw.strip() or "slack-file"
    name = re.sub(r"[/\\\x00-\x1f\x7f]+", "_", name)
    return name or "slack-file"


def _write_download(result: dict[str, object], output: str) -> dict[str, object]:
    if result.get("ok") is not True:
        return result

    content = result.get("content_base64")
    if not isinstance(content, str):
        return {"ok": False, "error": "missing_content_base64", "response": result}

    file_info = result.get("file")
    if not isinstance(file_info, dict):
        file_info = {}

    filename = _safe_filename(
        str(
            file_info.get("fileName")
            or file_info.get("name")
            or file_info.get("title")
            or file_info.get("id")
            or "slack-file"
        )
    )
    output_path = Path(output)
    if output_path.exists() and output_path.is_dir():
        output_path = output_path / filename
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(base64.b64decode(content))

    return {
        "ok": True,
        "path": str(output_path),
        "file": file_info,
        "bytes": output_path.stat().st_size,
    }


def run(args: argparse.Namespace, config: dict[str, HookConfig]) -> None:
    if HOOK_NAME not in config:
        print(f"n8n-hooks: no '{HOOK_NAME}' section in config", file=sys.stderr)
        sys.exit(1)

    result = post(config[HOOK_NAME], build_payload(args))
    if args.op == "file-download":
        result = _write_download(result, args.output)
    print(json.dumps(result, indent=2))
