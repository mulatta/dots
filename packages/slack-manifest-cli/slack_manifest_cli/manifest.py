"""Slack manifest file parsing and formatting."""

import json
from pathlib import Path
from typing import Any, Literal

import yaml

from slack_manifest_cli.errors import ManifestError

Format = Literal["json", "yaml"]


def load_manifest(path: str) -> dict[str, Any]:
    """Load manifest from YAML or JSON."""
    manifest_path = Path(path)
    try:
        text = manifest_path.read_text()
    except OSError as e:
        raise ManifestError(f"failed to read manifest {path}: {e}") from e
    return parse_manifest(text, path=path)


def parse_manifest(text: str, *, path: str = "<input>") -> dict[str, Any]:
    """Parse manifest text as JSON first for .json-like input, YAML otherwise."""
    stripped = text.lstrip()
    try:
        if stripped.startswith("{"):
            loaded = json.loads(text)
        else:
            loaded = yaml.safe_load(text)
    except (json.JSONDecodeError, yaml.YAMLError) as e:
        raise ManifestError(f"invalid manifest {path}: {e}") from e

    if not isinstance(loaded, dict):
        raise ManifestError(f"manifest must contain object: {path}")
    return loaded


def dump_manifest(manifest: dict[str, Any], output_format: Format) -> str:
    """Dump manifest as stable JSON or readable YAML."""
    if output_format == "json":
        return json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    return yaml.safe_dump(manifest, sort_keys=False, allow_unicode=True)


def manifest_api_value(manifest: dict[str, Any]) -> str:
    """Return JSON string expected by Slack manifest API."""
    return json.dumps(manifest, separators=(",", ":"), sort_keys=True)


def manifest_from_api(value: Any) -> dict[str, Any]:
    """Normalize Slack export response value into manifest object."""
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        return parse_manifest(value, path="Slack API response")
    raise ManifestError("Slack API response does not contain manifest object")
