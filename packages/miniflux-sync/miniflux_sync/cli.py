#!/usr/bin/env python3
"""Sync Miniflux assets and feed configuration from a JSON manifest.

Read/star history is preserved by:
  - creating a feed only when its `feed_url` is not already on the server
  - applying setting changes via PUT, which only touches metadata
  - never deleting feeds (drop them from the manifest, then remove via UI)

Manifest layout:

    {
      "base_url": "https://rss.mulatta.io",
      "assets": {
        "css": "~/.config/miniflux/custom.css",
        "js": "~/.config/miniflux/custom.js"
      },
      "feeds": [
        {
          "url": "http://feeds.feedburner.com/geeknews-feed",
          "category": "Notification",
          "crawler": true,
          "scraper_rules": ".topictitle a.bold.ud, #topic_contents",
          "rewrite_rules": "remove(\".view-con, .view-file\")"
        }
      ]
    }

Environment overrides:
    MINIFLUX_URL              base URL
    MINIFLUX_TOKEN            API token (preferred)
    MINIFLUX_TOKEN_COMMAND    fallback shell command, default `rbw get miniflux-api-key`
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

import miniflux

from miniflux_sync.bootstrap import (
    BootstrapRequest,
    ensure_user_and_api_key,
    read_secret_file,
)

DEFAULT_BASE_URL = "https://rss.mulatta.io"
DEFAULT_TOKEN_COMMAND = "rbw get miniflux-api-key"
SETTINGS_KEYS = (
    "site_url",
    "title",
    "description",
    "crawler",
    "scraper_rules",
    "rewrite_rules",
    "urlrewrite_rules",
    "blocklist_rules",
    "keeplist_rules",
    "block_filter_entry_rules",
    "keep_filter_entry_rules",
    "disabled",
    "ignore_entry_updates",
    "ignore_http_cache",
    "allow_self_signed_certificates",
    "fetch_via_proxy",
    "hide_globally",
    "no_media_player",
    "disable_http2",
    "user_agent",
    "cookie",
    "username",
    "password",
    "proxy_url",
)
UPDATE_ONLY_KEYS = (
    "site_url",
    "title",
    "description",
)
SECRET_FILE_KEYS = {
    "cookie_file": "cookie",
    "username_file": "username",
    "password_file": "password",
}


def default_config_path() -> Path:
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "miniflux" / "feeds.json"


def expand_path(value: str, base: Path) -> Path:
    """Expand env vars and `~`, then resolve relative paths against `base`."""
    p = Path(os.path.expandvars(os.path.expanduser(value)))
    if p.is_absolute():
        return p
    return (base / p).resolve()


def resolve_token() -> str:
    token = os.environ.get("MINIFLUX_TOKEN")
    if token:
        return token
    cmd = os.environ.get("MINIFLUX_TOKEN_COMMAND", DEFAULT_TOKEN_COMMAND)
    out = subprocess.check_output(shlex.split(cmd), text=True).strip()
    if not out:
        raise SystemExit("miniflux-sync: token command produced empty output")
    return out


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SystemExit(f"miniflux-sync: manifest not found: {path}")
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def sync_assets(
    client: miniflux.Client,
    assets: dict[str, str],
    *,
    base: Path,
    dry_run: bool,
) -> None:
    if not assets:
        return
    user = client.me()
    diff: dict[str, str] = {}
    if "css" in assets:
        css = expand_path(assets["css"], base).read_text(encoding="utf-8")
        if user.get("stylesheet") != css:
            diff["stylesheet"] = css
    if "js" in assets:
        js = expand_path(assets["js"], base).read_text(encoding="utf-8")
        if user.get("custom_js") != js:
            diff["custom_js"] = js
    if not diff:
        print("[assets] in sync")
        return
    print(f"[assets] update: {', '.join(sorted(diff))}")
    if not dry_run:
        client.update_user(user["id"], **diff)


def ensure_categories(
    client: miniflux.Client,
    names: set[str],
    *,
    dry_run: bool,
) -> dict[str, int]:
    cats = {c["title"]: c["id"] for c in client.get_categories()}
    for name in sorted(names):
        if name in cats:
            continue
        print(f"[category] create: {name}")
        if not dry_run:
            cats[name] = client.create_category(name)["id"]
        else:
            cats[name] = -1
    return cats


def feed_settings(spec: dict[str, Any], *, base: Path) -> dict[str, Any]:
    settings = {k: spec[k] for k in SETTINGS_KEYS if k in spec}
    for file_key, api_key in SECRET_FILE_KEYS.items():
        if file_key not in spec:
            continue
        settings[api_key] = (
            expand_path(spec[file_key], base).read_text(encoding="utf-8").rstrip("\n")
        )
    return settings


def sync_feeds(
    client: miniflux.Client,
    feeds: list[dict[str, Any]],
    *,
    base: Path,
    dry_run: bool,
) -> None:
    existing = {f["feed_url"]: f for f in client.get_feeds()}
    desired = {f["category"] for f in feeds if "category" in f}
    cats = ensure_categories(client, desired, dry_run=dry_run)

    declared_urls: set[str] = set()
    for spec in feeds:
        url = spec["url"]
        declared_urls.add(url)
        wanted_settings = feed_settings(spec, base=base)
        wanted_category = spec.get("category")

        feed = existing.get(url)
        if feed is not None:
            diff = {k: v for k, v in wanted_settings.items() if feed.get(k) != v}
            current_category = (feed.get("category") or {}).get("title")
            if wanted_category and current_category != wanted_category:
                diff["category_id"] = cats[wanted_category]
            if not diff:
                print(f"[feed] skip {url}")
                continue
            print(f"[feed] update {url}: {sorted(diff)}")
            if not dry_run:
                client.update_feed(feed["id"], **diff)
            continue

        if wanted_category and wanted_category in cats:
            cat_id = cats[wanted_category]
        elif cats:
            cat_id = next(iter(cats.values()))
        else:
            raise SystemExit(
                f"miniflux-sync: feed has no category and none exist: {url}"
            )
        print(f"[feed] add {url} -> {wanted_category or '<default>'}")
        if not dry_run:
            create_settings = {
                k: v for k, v in wanted_settings.items() if k not in UPDATE_ONLY_KEYS
            }
            update_after_create = {
                k: v for k, v in wanted_settings.items() if k in UPDATE_ONLY_KEYS
            }
            try:
                feed_id = client.create_feed(url, category_id=cat_id, **create_settings)
            except miniflux.ServerError as exc:
                # Miniflux can answer create_feed with "duplicated feed" while
                # still persisting the feed row. This happens for full-content
                # journal routes (e.g. Cell Press) whose fetched payload trips
                # Miniflux's duplicate detection even though get_feeds() did not
                # report the URL at the start of this run. Treating it as fatal
                # aborts the whole manifest and leaves every later feed unsynced.
                # The feed exists, so the desired state is already met; the next
                # run sees it via get_feeds() and reconciles its settings.
                if "duplicated feed" not in str(exc):
                    raise
                print(
                    f"[feed] exists {url} (server reported duplicate)", file=sys.stderr
                )
                continue
            if update_after_create:
                client.update_feed(feed_id, **update_after_create)

    # Orphan report: feeds present on the server that are absent from the
    # manifest. They are never auto-deleted; this just surfaces drift so the
    # operator can decide whether to add them or remove them via the UI.
    for url, feed in existing.items():
        if url in declared_urls:
            continue
        title = feed.get("title") or "<no title>"
        print(
            "[feed] orphan "
            f"id={feed['id']} {title!r} {url} "
            "(possible URL drift or unmanaged feed; not deleted)",
            file=sys.stderr,
        )


def sync_main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="miniflux-sync sync",
        description="Idempotent Miniflux assets/feeds sync from JSON.",
    )
    parser.add_argument(
        "config",
        nargs="?",
        type=Path,
        default=default_config_path(),
        help=f"path to JSON manifest (default: {default_config_path()})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report planned changes without sending them",
    )
    args = parser.parse_args(argv)

    manifest = load_manifest(args.config)
    base_url = (
        manifest.get("base_url") or os.environ.get("MINIFLUX_URL") or DEFAULT_BASE_URL
    )
    client = miniflux.Client(base_url, api_key=resolve_token())

    base = args.config.resolve().parent
    sync_assets(client, manifest.get("assets", {}), base=base, dry_run=args.dry_run)
    sync_feeds(
        client,
        manifest.get("feeds", []),
        base=base,
        dry_run=args.dry_run,
    )

    if args.dry_run:
        print("\n(dry-run; no changes were sent)")
    return 0


def bootstrap_user_main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="miniflux-sync bootstrap-user",
        description="Ensure a Miniflux user and API key exist in PostgreSQL.",
    )
    parser.add_argument("--database-url", required=True)
    parser.add_argument("--username", required=True)
    parser.add_argument("--api-token-file", type=Path, required=True)
    parser.add_argument("--api-key-description", required=True)
    openid_group = parser.add_mutually_exclusive_group()
    openid_group.add_argument("--openid-connect-id")
    openid_group.add_argument("--openid-connect-id-file", type=Path)
    webhook_group = parser.add_mutually_exclusive_group()
    webhook_group.add_argument(
        "--webhook-enabled", dest="webhook_enabled", action="store_true"
    )
    webhook_group.add_argument(
        "--webhook-disabled", dest="webhook_enabled", action="store_false"
    )
    parser.set_defaults(webhook_enabled=None)
    parser.add_argument("--webhook-url-file", type=Path)
    parser.add_argument("--webhook-secret-file", type=Path)
    args = parser.parse_args(argv)

    openid_connect_id = args.openid_connect_id
    if args.openid_connect_id_file is not None:
        openid_connect_id = read_secret_file(args.openid_connect_id_file)

    webhook_url = None
    if args.webhook_url_file is not None:
        webhook_url = read_secret_file(args.webhook_url_file)
    webhook_secret = None
    if args.webhook_secret_file is not None:
        webhook_secret = read_secret_file(args.webhook_secret_file)

    user_id = ensure_user_and_api_key(
        BootstrapRequest(
            database_url=args.database_url,
            username=args.username,
            api_token=read_secret_file(args.api_token_file),
            api_key_description=args.api_key_description,
            openid_connect_id=openid_connect_id,
            webhook_enabled=args.webhook_enabled,
            webhook_url=webhook_url,
            webhook_secret=webhook_secret,
        )
    )
    print(f"[bootstrap] ensured user id={user_id} username={args.username!r}")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if args and args[0] == "bootstrap-user":
        return bootstrap_user_main(args[1:])
    if args and args[0] == "sync":
        return sync_main(args[1:])
    return sync_main(args)


if __name__ == "__main__":
    sys.exit(main())
