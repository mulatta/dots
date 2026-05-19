"""CLI entry point."""

import argparse
import difflib
import json
import sys
from pathlib import Path
from typing import Any

from slack_manifest_cli.client import Client
from slack_manifest_cli.config import default_config_file, list_targets, resolve_credentials
from slack_manifest_cli.errors import CLIError, ConfigError
from slack_manifest_cli.manifest import dump_manifest, load_manifest
from slack_manifest_cli.state import app_id_for_manifest, find_state_file, save_app_id_for_manifest


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="slack-manifest",
        description="Manage Slack app manifests from YAML or JSON files",
    )
    p.add_argument("-j", "--json", action="store_true", dest="use_json", help="Output JSON")
    p.add_argument("--config", help=f"Config path (default: {default_config_file()})")
    p.add_argument("--target", help="Config target name")
    p.add_argument("--token", help="Slack app config token")
    p.add_argument("--app-id", help="Slack app ID")
    p.add_argument("--api-base", help="Slack API base URL")
    p.add_argument("--state", help="Path to local app-id state file")

    sub = p.add_subparsers(dest="command")

    s = sub.add_parser("targets", help="List configured targets")
    s.set_defaults(handler=cmd_targets, needs_client=False)

    s = sub.add_parser("validate", help="Validate manifest with Slack API")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.set_defaults(handler=cmd_validate, needs_client=True, needs_app_id=False)

    s = sub.add_parser("create", help="Create Slack app from manifest")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.add_argument("--save", action="store_true", help="Save created app_id to local state")
    s.set_defaults(handler=cmd_create, needs_client=True, needs_app_id=False)

    s = sub.add_parser("update", help="Update Slack app from manifest")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.set_defaults(handler=cmd_update, needs_client=True, needs_app_id=False)

    s = sub.add_parser("apply", help="Update app from state/config; create only with --create")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.add_argument("--create", action="store_true", help="Create app when no app_id is known")
    s.set_defaults(handler=cmd_apply, needs_client=True, needs_app_id=False)

    s = sub.add_parser("adopt", help="Record existing Slack app_id for a local manifest")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.add_argument("app_id", help="Existing Slack app ID")
    s.set_defaults(handler=cmd_adopt, needs_client=False)

    s = sub.add_parser("export", help="Export Slack app manifest")
    s.add_argument("-o", "--output", help="Write manifest to file")
    s.add_argument("--format", choices=["json", "yaml"], default="yaml", help="Output format")
    s.add_argument("--save", action="store_true", help="Save app_id for --output path")
    s.set_defaults(handler=cmd_export, needs_client=True, needs_app_id=False)

    s = sub.add_parser("diff", help="Diff local manifest against exported Slack app manifest")
    s.add_argument("file", help="Manifest YAML/JSON file")
    s.add_argument("--format", choices=["json", "yaml"], default="yaml", help="Diff format")
    s.set_defaults(handler=cmd_diff, needs_client=True, needs_app_id=False)

    return p


def _make_client(ns: argparse.Namespace) -> tuple[Client, str | None]:
    token, app_id, api_base, timeout = resolve_credentials(
        config_path=ns.config,
        target_name=ns.target,
        token=ns.token,
        app_id=ns.app_id,
        api_base=ns.api_base,
    )
    if not token:
        raise ConfigError(
            "SLACK_MANIFEST_TOKEN not set. Set env var, --token, or config token_command"
        )
    return Client(token, api_base, timeout), app_id


def _require_app_id(app_id: str | None) -> str:
    if not app_id:
        raise ConfigError("app_id not found. Use --app-id, target app_id, adopt, or create --save")
    return app_id


def _app_id_for_file(configured_app_id: str | None, ns: argparse.Namespace) -> str | None:
    if configured_app_id:
        return configured_app_id
    state_file = find_state_file(ns.file, ns.state)
    return app_id_for_manifest(ns.file, state_file)


def _save_app_id(file: str, app_id: str, ns: argparse.Namespace) -> str:
    state_file = find_state_file(file, ns.state)
    save_app_id_for_manifest(file, app_id, state_file)
    return str(state_file)


def _print(ns: argparse.Namespace, data: dict[str, Any], text: str) -> None:
    if ns.use_json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        print(text)


def _result_text(data: dict[str, Any]) -> str:
    app_id = data.get("app_id") or data.get("id")
    if isinstance(app_id, str) and app_id:
        return f"ok app_id={app_id}"
    return "ok"


def cmd_targets(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    del client, app_id
    targets = list_targets(ns.config)
    if ns.use_json:
        print(json.dumps({"targets": targets}, indent=2, sort_keys=True))
    else:
        for target in targets:
            print(target)


def cmd_validate(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    del app_id
    assert client is not None
    data = client.validate(load_manifest(ns.file))
    _print(ns, data, _result_text(data))


def cmd_create(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    del app_id
    assert client is not None
    data = client.create(load_manifest(ns.file))
    created_app_id = data.get("app_id")
    if ns.save and isinstance(created_app_id, str) and created_app_id:
        state_file = _save_app_id(ns.file, created_app_id, ns)
        _print(ns, data, f"ok app_id={created_app_id} saved={state_file}")
        return
    _print(ns, data, _result_text(data))


def cmd_update(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    assert client is not None
    resolved_app_id = _require_app_id(_app_id_for_file(app_id, ns))
    data = client.update(resolved_app_id, load_manifest(ns.file))
    _print(ns, data, _result_text(data))


def cmd_apply(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    assert client is not None
    manifest = load_manifest(ns.file)
    resolved_app_id = _app_id_for_file(app_id, ns)
    if resolved_app_id:
        data = client.update(resolved_app_id, manifest)
        _print(ns, data, _result_text(data))
        return
    if not ns.create:
        raise ConfigError("app_id not found. Use adopt first, or pass apply --create")
    data = client.create(manifest)
    created_app_id = data.get("app_id")
    if isinstance(created_app_id, str) and created_app_id:
        state_file = _save_app_id(ns.file, created_app_id, ns)
        _print(ns, data, f"ok app_id={created_app_id} saved={state_file}")
        return
    _print(ns, data, _result_text(data))


def cmd_adopt(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    del client, app_id
    state_file = _save_app_id(ns.file, ns.app_id, ns)
    if ns.use_json:
        print(json.dumps({"app_id": ns.app_id, "state": state_file}, indent=2, sort_keys=True))
    else:
        print(f"saved app_id={ns.app_id} state={state_file}")


def cmd_export(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    assert client is not None
    resolved_app_id = _require_app_id(app_id)
    data = client.export(resolved_app_id)
    rendered = dump_manifest(data["manifest"], ns.format)
    if ns.output:
        Path(ns.output).write_text(rendered)
        if ns.save:
            state_file = _save_app_id(ns.output, resolved_app_id, ns)
            _print(ns, data, f"wrote {ns.output} saved={state_file}")
        else:
            _print(ns, data, f"wrote {ns.output}")
    elif ns.use_json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        print(rendered, end="")


def cmd_diff(client: Client | None, app_id: str | None, ns: argparse.Namespace) -> None:
    assert client is not None
    resolved_app_id = _require_app_id(_app_id_for_file(app_id, ns))
    local = dump_manifest(load_manifest(ns.file), ns.format)
    remote = dump_manifest(client.export(resolved_app_id)["manifest"], ns.format)
    diff = "".join(
        difflib.unified_diff(
            remote.splitlines(keepends=True),
            local.splitlines(keepends=True),
            fromfile="slack",
            tofile=ns.file,
        )
    )
    if ns.use_json:
        print(json.dumps({"diff": diff, "different": bool(diff)}, indent=2, sort_keys=True))
    else:
        print(diff, end="")
    if diff:
        raise SystemExit(1)


def main() -> None:
    parser = _build_parser()
    ns = parser.parse_args()
    if not ns.command:
        parser.print_help()
        raise SystemExit(0)

    try:
        client: Client | None = None
        app_id: str | None = None
        if ns.needs_client:
            client, app_id = _make_client(ns)
            if ns.needs_app_id:
                _require_app_id(app_id)
        ns.handler(client, app_id, ns)
    except CLIError as e:
        print(f"Error: {e}", file=sys.stderr)
        raise SystemExit(1) from e


if __name__ == "__main__":
    main()
