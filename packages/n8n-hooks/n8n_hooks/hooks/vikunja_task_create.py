"""vikunja-task-create hook — template-aware Vikunja task creation requests."""

from __future__ import annotations

import argparse
import json
import sys
from enum import StrEnum
from pathlib import Path
from typing import Any, NoReturn, cast

from n8n_hooks.config import HookConfig
from n8n_hooks.templates import (
    TemplateError,
    load_template,
    missing_required,
    validate_context,
)
from n8n_hooks.webhook import post

HOOK_NAME = "vikunja-task-create"


class RelationKind(StrEnum):
    blocked = "blocked"
    blocking = "blocking"
    subtask = "subtask"
    parenttask = "parenttask"
    precedes = "precedes"
    follows = "follows"
    related = "related"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        HOOK_NAME,
        help="Submit template-aware Vikunja task creation requests via n8n",
        description="Validate context against Markdown+YAML template schema and submit a typed create request to n8n.",
    )
    p.add_argument("--project", required=True, help="Target Vikunja project name or id")
    p.add_argument("--title", required=True, help="Task title")
    p.add_argument("--template", required=True, help="Template name")
    p.add_argument(
        "--template-dir",
        help="Template directory (default: $VIKUNJA_TEMPLATE_DIR or XDG data paths)",
    )
    p.add_argument(
        "--context",
        required=True,
        help="JSON description context file, or '-' for stdin",
    )
    p.add_argument("--due", help="Due timestamp/date")
    p.add_argument("--start", help="Start timestamp/date")
    p.add_argument("--end", help="End timestamp/date")
    p.add_argument("--priority", type=int, help="Vikunja priority 0..5")
    p.add_argument("--color", help="Task color as #RRGGBB")
    p.add_argument(
        "--reminder",
        dest="reminders",
        action="append",
        default=[],
        help="Absolute reminder timestamp",
    )
    p.add_argument(
        "--relation",
        dest="relations",
        action="append",
        default=[],
        metavar="KIND:OTHER",
        help="Task relation: blocked|blocking|subtask|parenttask|precedes|follows|related:NUMERIC_TASK_ID",
    )
    p.add_argument(
        "--allow-missing",
        action="store_true",
        help="Allow creation request when required template context fields are missing",
    )
    p.set_defaults(func=run)


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    context = _read_context(args.context)
    template = _load_template(args.template, args.template_dir)
    missing = missing_required(template, context)
    if missing and not args.allow_missing:
        _die("template missing required fields: " + ", ".join(missing))
    if not missing:
        errors = validate_context(template, context)
        if errors:
            _die("template context failed validation: " + "; ".join(errors))

    payload: dict[str, Any] = {
        "operation": "create_task_from_template",
        "project": _required_text("project", args.project),
        "title": _required_text("title", args.title),
        "template": template.name,
        "template_defaults": template.defaults,
        "template_schema": template.schema,
        "attachment_expectations": template.attachment_expectations,
        "context": context,
        "relations": [_parse_relation(value) for value in args.relations],
    }
    for key in ("due", "start", "end", "color"):
        value = getattr(args, key, None)
        if value is not None:
            payload[key] = value
    if args.priority is not None:
        if args.priority < 0 or args.priority > 5:
            _die("priority must be an integer from 0 to 5")
        payload["priority"] = args.priority
    if args.reminders:
        payload["reminders"] = args.reminders
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


def _load_template(name: str, template_dir: str | None) -> Any:
    try:
        return load_template(name, template_dir=template_dir)
    except TemplateError as exc:
        _die(str(exc))


def _read_context(path: str) -> dict[str, Any]:
    try:
        if path == "-":
            data = json.load(sys.stdin)
        else:
            data = json.loads(Path(path).read_text())
    except OSError as exc:
        _die(f"could not read context: {exc}")
    except json.JSONDecodeError as exc:
        _die(f"context is not valid JSON: {exc}")

    if not isinstance(data, dict):
        _die("context must be a JSON object")
    return cast("dict[str, Any]", data)


def _parse_relation(value: str) -> dict[str, str]:
    kind, sep, other = value.partition(":")
    if not sep or not kind or not other:
        _die(f"invalid relation {value!r}; expected KIND:NUMERIC_TASK_ID")
    try:
        relation_kind = RelationKind(kind)
    except ValueError:
        allowed = ", ".join(item.value for item in RelationKind)
        _die(f"invalid relation kind {kind!r}; expected one of: {allowed}")
    if not other.isdigit():
        _die(f"invalid relation target {other!r}; expected numeric task id")
    return {"kind": relation_kind.value, "other": other}


def _required_text(name: str, value: str) -> str:
    text = value.strip()
    if not text:
        _die(f"{name} must not be empty")
    return text


def _die(message: str) -> NoReturn:
    print(f"n8n-hooks: {message}", file=sys.stderr)
    sys.exit(1)
