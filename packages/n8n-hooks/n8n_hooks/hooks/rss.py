"""rss hook — read-only RSS context via n8n/Miniflux.

The n8n workflow holds the Miniflux token. This CLI only exposes a fixed set
of read operations so agents can inspect RSS entries without holding Miniflux
credentials or mutating read/starred state.
"""

from __future__ import annotations

import argparse
import json
import sys

from n8n_hooks.config import HookConfig
from n8n_hooks.webhook import post

HOOK_NAME = "rss"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        "rss",
        help="Read RSS context via n8n (read-only)",
        description="List/read RSS categories, entries, and enclosures from Miniflux.",
    )
    sub = p.add_subparsers(dest="op", required=True)

    sub.add_parser("list-categories", help="List categories")

    entries = sub.add_parser("list-entries", help="List entries")
    entries.add_argument("--category-id", type=int, help="RSS category id")
    entries.add_argument("--starred", action="store_true", help="Only starred entries")
    entries.add_argument("--status", help="Entry status, e.g. unread/read/removed")
    entries.add_argument("--limit", type=int, default=50)
    entries.add_argument("--offset", type=int, default=0)
    entries.add_argument("--order", default="changed_at")
    entries.add_argument("--direction", choices=["asc", "desc"], default="desc")

    show = sub.add_parser("show-entry", help="Show one entry")
    show.add_argument("entry_id", help="RSS entry id")

    enclosures = sub.add_parser("list-enclosures", help="List entry enclosures")
    enclosures.add_argument("entry_id", help="RSS entry id")

    p.set_defaults(func=run)


def _entry_id(value: object) -> int:
    try:
        return int(str(value))
    except ValueError:
        print(f"n8n-hooks: invalid entry id: {value}", file=sys.stderr)
        sys.exit(1)


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    payload: dict[str, object] = {"operation": args.op}

    if args.op in {"show-entry", "list-enclosures"}:
        payload["entry_id"] = _entry_id(args.entry_id)
        return payload

    if args.op == "list-entries":
        for key in (
            "category_id",
            "status",
            "limit",
            "offset",
            "order",
            "direction",
        ):
            value = getattr(args, key, None)
            if value is not None:
                payload[key] = value
        if getattr(args, "starred", False):
            payload["starred"] = True

    return payload


def run(args: argparse.Namespace, config: dict[str, HookConfig]) -> None:
    if HOOK_NAME not in config:
        print(f"n8n-hooks: no '{HOOK_NAME}' section in config", file=sys.stderr)
        sys.exit(1)

    result = post(config[HOOK_NAME], build_payload(args))
    status = result.get("status")
    body = result.get("body", result)
    print(json.dumps(body, indent=2))
    if isinstance(status, int) and status >= 400:
        sys.exit(1)
