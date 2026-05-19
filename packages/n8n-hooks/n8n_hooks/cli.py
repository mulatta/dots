"""Extensible CLI entry point.

Each subcommand is a module in n8n_hooks.hooks that exposes:
  - register(subparsers)   — adds its argparse subcommand
  - run(args, config)      — executes the hook
"""

from __future__ import annotations

import argparse
import sys

from n8n_hooks.config import load_config
from n8n_hooks.hooks import (
    github,
    linkwarden,
    linkwarden_link_create,
    rss,
    slack,
    store_draft,
    vikunja,
    vikunja_task_create,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="n8n-hooks",
        description="Invoke n8n webhooks from the command line.",
    )
    parser.add_argument(
        "--config",
        metavar="FILE",
        help="Path to JSON config file (default: $XDG_CONFIG_HOME/n8n-hooks/config.json)",
    )
    sub = parser.add_subparsers(dest="command")
    store_draft.register(sub)
    github.register(sub)
    rss.register(sub)
    slack.register(sub)
    vikunja.register(sub)
    vikunja_task_create.register(sub)
    linkwarden.register(sub)
    linkwarden_link_create.register(sub)
    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    config = load_config(args.config)
    args.func(args, config)
