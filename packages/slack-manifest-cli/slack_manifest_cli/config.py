"""Configuration loading and credential resolution."""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

from slack_manifest_cli.errors import ConfigError

APP_NAME = "slack-manifest"


def default_config_file() -> Path:
    """Return XDG config path for CLI config."""
    base = os.environ.get("XDG_CONFIG_HOME")
    config_home = Path(base) if base else Path.home() / ".config"
    return config_home / APP_NAME / "config.json"


def load_config(config_path: str | None = None) -> dict[str, Any]:
    """Load JSON config file."""
    path = Path(config_path) if config_path else default_config_file()
    if not path.exists():
        return {}
    try:
        with path.open() as f:
            loaded = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Warning: invalid JSON in config file {path}: {e}", file=sys.stderr)
        return {}
    if not isinstance(loaded, dict):
        raise ConfigError(f"config file must contain JSON object: {path}")
    return loaded


def run_secret_command(command: str | list[str]) -> str | None:
    """Execute local trusted command to retrieve config value."""
    try:
        if isinstance(command, list):
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True,
                timeout=30,
            )
        else:
            result = subprocess.run(
                shlex.split(command),
                capture_output=True,
                text=True,
                check=True,
                timeout=30,
            )
        return result.stdout.strip() or None
    except subprocess.TimeoutExpired:
        print(f"Warning: command timed out after 30s: {command}", file=sys.stderr)
        return None
    except subprocess.CalledProcessError as e:
        print(f"Warning: command failed: {command}: {e}", file=sys.stderr)
        if e.stderr:
            print(f"  stderr: {e.stderr.strip()}", file=sys.stderr)
        return None


def _as_mapping(value: Any, label: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ConfigError(f"{label} must be object")
    return value


def target_config(cfg: dict[str, Any], target: str | None) -> dict[str, Any]:
    """Return selected target config."""
    selected = target or cfg.get("default_target")
    if not selected:
        return {}
    if not isinstance(selected, str):
        raise ConfigError("default_target must be string")
    targets = _as_mapping(cfg.get("targets"), "targets")
    if selected not in targets:
        raise ConfigError(f"target not found: {selected}")
    return _as_mapping(targets[selected], f"targets.{selected}")


def _resolve_value(
    *,
    explicit: str | None,
    env_var: str,
    root: dict[str, Any],
    target: dict[str, Any],
    direct_key: str,
    command_key: str,
) -> str | None:
    if explicit:
        return explicit

    value = os.environ.get(env_var)
    if value:
        return value

    for source in (target, root):
        command = source.get(command_key)
        if isinstance(command, str | list) and command:
            resolved = run_secret_command(command)
            if resolved:
                return resolved

    for source in (target, root):
        direct = source.get(direct_key)
        if isinstance(direct, str) and direct:
            return direct

    return None


def _resolve_timeout(root: dict[str, Any], target: dict[str, Any]) -> int:
    value: Any = os.environ.get("SLACK_MANIFEST_TIMEOUT")
    if value is None:
        value = target.get("timeout", root.get("timeout", 30))
    try:
        return int(value)
    except (TypeError, ValueError):
        print(f"Warning: invalid timeout {value!r}, using default", file=sys.stderr)
        return 30


def resolve_credentials(
    *,
    config_path: str | None = None,
    target_name: str | None = None,
    token: str | None = None,
    app_id: str | None = None,
    api_base: str | None = None,
) -> tuple[str | None, str | None, str, int]:
    """Resolve token, app id, API base, and timeout."""
    cfg = load_config(config_path)
    target = target_config(cfg, target_name)
    resolved_token = _resolve_value(
        explicit=token,
        env_var="SLACK_MANIFEST_TOKEN",
        root=cfg,
        target=target,
        direct_key="token",
        command_key="token_command",
    )
    resolved_app_id = _resolve_value(
        explicit=app_id,
        env_var="SLACK_MANIFEST_APP_ID",
        root=cfg,
        target=target,
        direct_key="app_id",
        command_key="app_id_command",
    )
    resolved_api_base = (
        _resolve_value(
            explicit=api_base,
            env_var="SLACK_MANIFEST_API_BASE",
            root=cfg,
            target=target,
            direct_key="api_base",
            command_key="api_base_command",
        )
        or "https://slack.com/api"
    )
    timeout = _resolve_timeout(cfg, target)
    return resolved_token, resolved_app_id, resolved_api_base.rstrip("/"), timeout


def list_targets(config_path: str | None = None) -> list[str]:
    """List target names from config."""
    cfg = load_config(config_path)
    targets = _as_mapping(cfg.get("targets"), "targets")
    return sorted(targets)
