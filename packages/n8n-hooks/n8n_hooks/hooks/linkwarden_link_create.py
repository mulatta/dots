"""linkwarden-link-create hook — confirmed Linkwarden link creation via n8n."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import NoReturn

from n8n_hooks.config import HookConfig
from n8n_hooks.webhook import post

HOOK_NAME = "linkwarden-link-create"
ALLOWED_COLLECTIONS = {
    "Inbox",
    "Research",
    "Academic",
    "Engineering",
    "Operations",
    "Personal",
    "Library",
}


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        HOOK_NAME,
        help="Create a confirmed Linkwarden link via n8n",
        description="Submit a validated Linkwarden create request after user confirmation.",
    )
    p.add_argument("--url", required=True, help="HTTP(S) URL to save")
    p.add_argument("--name", help="Link title/name")
    p.add_argument(
        "--description",
        help="Short why/provenance description. Use --description-file for multiline text.",
    )
    p.add_argument("--description-file", help="File containing description text")
    p.add_argument(
        "--collection",
        required=True,
        choices=sorted(ALLOWED_COLLECTIONS),
        help="Top-level Linkwarden collection",
    )
    p.add_argument(
        "--tag",
        dest="tags",
        action="append",
        default=[],
        help="Tag to attach. Repeat for multiple tags.",
    )
    p.set_defaults(func=run)


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    description = _description(args.description, args.description_file)
    tags = [_validate_tag(tag) for tag in args.tags]
    return {
        "operation": "create-link",
        "url": _required_text("url", args.url),
        "name": str(args.name).strip() if args.name else "",
        "description": description,
        "collection": args.collection,
        "tags": tags,
    }


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


def _description(inline: str | None, file_path: str | None) -> str:
    if inline and file_path:
        _die("use either --description or --description-file, not both")
    if file_path:
        try:
            text = Path(file_path).read_text()
        except OSError as exc:
            _die(f"could not read description file: {exc}")
    else:
        text = inline or ""
    text = text.strip()
    if len(text) > 2048:
        _die("description must be at most 2048 characters")
    return text


def _validate_tag(value: str) -> str:
    tag = value.strip()
    if not tag:
        _die("tag must not be empty")
    if len(tag) > 50:
        _die("tag must be at most 50 characters")
    if tag.lower().startswith("status:"):
        _die("status:* tags are not used for Linkwarden workflow state")
    return tag


def _required_text(name: str, value: str) -> str:
    text = value.strip()
    if not text:
        _die(f"{name} must not be empty")
    return text


def _die(message: str) -> NoReturn:
    print(f"n8n-hooks: {message}", file=sys.stderr)
    sys.exit(1)
