"""vikunja hook — read-only task context via n8n/Vikunja.

The n8n workflow holds the Vikunja API token. This CLI exposes fixed read
operations so agents can inspect project/task state without holding Vikunja
credentials.
"""

from __future__ import annotations

import argparse
import json
import sys

from n8n_hooks.config import HookConfig
from n8n_hooks.webhook import post

HOOK_NAME = "vikunja"


def register(subparsers: argparse._SubParsersAction[argparse.ArgumentParser]) -> None:
    p = subparsers.add_parser(
        "vikunja",
        help="Read Vikunja task context via n8n (read-only)",
        description="List/read Vikunja projects, labels, and tasks.",
    )
    sub = p.add_subparsers(dest="op", required=True)

    projects = sub.add_parser("list-projects", help="List projects")
    projects.add_argument("--search", help="Search text")
    projects.add_argument("--limit", type=int, default=50)
    projects.add_argument("--page", type=int, default=1)

    labels = sub.add_parser("list-labels", help="List labels")
    labels.add_argument("--search", help="Search text")
    labels.add_argument("--limit", type=int, default=50)
    labels.add_argument("--page", type=int, default=1)

    tasks = sub.add_parser("list-tasks", help="List tasks")
    tasks.add_argument("--project-id", type=int, help="Restrict to one project")
    tasks.add_argument("--search", help="Search text")
    tasks.add_argument("--filter", help="Vikunja filter expression")
    tasks.add_argument("--limit", type=int, default=50)
    tasks.add_argument("--page", type=int, default=1)
    tasks.add_argument("--sort-by", help="Sort field, e.g. due_date")
    tasks.add_argument("--order-by", choices=["asc", "desc"], help="Sort order")

    show = sub.add_parser("show-task", help="Show one task")
    show.add_argument("task_id", help="Vikunja task id")

    p.set_defaults(func=run)


def _task_id(value: object) -> int:
    try:
        task_id = int(str(value))
    except ValueError:
        print(f"n8n-hooks: invalid task id: {value}", file=sys.stderr)
        sys.exit(1)
    if task_id < 1:
        print(f"n8n-hooks: invalid task id: {value}", file=sys.stderr)
        sys.exit(1)
    return task_id


def build_payload(args: argparse.Namespace) -> dict[str, object]:
    payload: dict[str, object] = {"operation": args.op}

    if args.op == "show-task":
        payload["task_id"] = _task_id(args.task_id)
        return payload

    for key in (
        "project_id",
        "search",
        "filter",
        "limit",
        "page",
        "sort_by",
        "order_by",
    ):
        value = getattr(args, key, None)
        if value is not None:
            payload[key] = value

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
