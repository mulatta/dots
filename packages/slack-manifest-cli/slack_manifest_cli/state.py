"""Local app identity state for raw Slack manifest files."""

import json
from pathlib import Path
from typing import Any

from slack_manifest_cli.errors import ConfigError

STATE_FILENAME = "slack-manifest-state.json"


def find_state_file(manifest_path: str | None = None, explicit: str | None = None) -> Path:
    """Find state file, preferring explicit path then nearest existing parent state."""
    if explicit:
        return Path(explicit)

    if manifest_path:
        start = Path(manifest_path).resolve().parent
        for directory in (start, *start.parents):
            candidate = directory / STATE_FILENAME
            if candidate.exists():
                return candidate

    return Path.cwd() / STATE_FILENAME


def load_state(path: Path) -> dict[str, Any]:
    """Load state file if present."""
    if not path.exists():
        return {"version": 1, "manifests": {}}
    try:
        loaded = json.loads(path.read_text())
    except json.JSONDecodeError as e:
        raise ConfigError(f"invalid state file {path}: {e}") from e
    if not isinstance(loaded, dict):
        raise ConfigError(f"state file must contain object: {path}")
    manifests = loaded.setdefault("manifests", {})
    if not isinstance(manifests, dict):
        raise ConfigError(f"state file manifests must be object: {path}")
    loaded.setdefault("version", 1)
    return loaded


def state_key(manifest_path: str, state_file: Path) -> str:
    """Return stable state key for manifest path."""
    path = Path(manifest_path).resolve()
    root = state_file.resolve().parent
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def app_id_for_manifest(manifest_path: str, state_file: Path) -> str | None:
    """Return app_id stored for manifest path."""
    state = load_state(state_file)
    entry = state["manifests"].get(state_key(manifest_path, state_file))
    if not isinstance(entry, dict):
        return None
    app_id = entry.get("app_id")
    return app_id if isinstance(app_id, str) and app_id else None


def save_app_id_for_manifest(manifest_path: str, app_id: str, state_file: Path) -> None:
    """Persist app_id for manifest path."""
    state = load_state(state_file)
    key = state_key(manifest_path, state_file)
    state["manifests"][key] = {"app_id": app_id}
    state_file.parent.mkdir(parents=True, exist_ok=True)
    tmp = state_file.with_suffix(state_file.suffix + ".tmp")
    tmp.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    tmp.replace(state_file)
