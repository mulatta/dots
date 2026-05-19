"""linkwarden hook — read-only Linkwarden context via n8n.

The n8n workflow holds the Linkwarden token. This CLI only exposes a fixed set
of read operations so agents can inspect saved links without holding Linkwarden
credentials or mutating bookmark state.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from n8n_hooks.config import HookConfig
from n8n_hooks.webhook import post

HOOK_NAME = "linkwarden"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        HOOK_NAME,
        help="Read Linkwarden context via n8n (read-only)",
        description="List/search Linkwarden collections, tags, and links.",
    )
    sub = p.add_subparsers(dest="op", required=True)

    sub.add_parser("list-collections", help="List collections")

    tags = sub.add_parser("list-tags", help="List tags")
    tags.add_argument("--search", help="Filter tags by name")

    search = sub.add_parser("search-links", help="Search links")
    search.add_argument("--query", required=True, help="Linkwarden search query")

    get = sub.add_parser("get-link", help="Show one link")
    get.add_argument("link_id", help="Link id")

    p.set_defaults(func=run)


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    payload: dict[str, object] = {"operation": args.op}

    if args.op == "list-tags" and getattr(args, "search", None):
        payload["search"] = str(args.search)
        return payload

    if args.op == "search-links":
        query = _required_text("query", args.query)
        payload["query"] = query
        return payload

    if args.op == "get-link":
        payload["link_id"] = _positive_int("link id", args.link_id)
        return payload

    return payload


def run(args: argparse.Namespace, config: dict[str, HookConfig]) -> None:
    if HOOK_NAME not in config:
        print(f"n8n-hooks: no '{HOOK_NAME}' section in config", file=sys.stderr)
        sys.exit(1)

    result = post(config[HOOK_NAME], build_payload(args))
    status = result.get("status")
    body = result.get("body", result)
    print(json.dumps(body, indent=2, ensure_ascii=False))
    if isinstance(status, int) and status >= 400:
        sys.exit(1)


def _positive_int(name: str, value: Any) -> int:
    try:
        number = int(str(value))
    except ValueError:
        print(f"n8n-hooks: invalid {name}: {value}", file=sys.stderr)
        sys.exit(1)
    if number < 1:
        print(f"n8n-hooks: invalid {name}: {value}", file=sys.stderr)
        sys.exit(1)
    return number


def _required_text(name: str, value: str) -> str:
    text = value.strip()
    if not text:
        print(f"n8n-hooks: {name} must not be empty", file=sys.stderr)
        sys.exit(1)
    return text
