import json
from pathlib import Path

import pytest

from slack_manifest_cli.config import default_config_file, list_targets, resolve_credentials


def test_default_config_file_uses_xdg(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))

    assert default_config_file() == tmp_path / "slack-manifest" / "config.json"


def test_resolve_target_values(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.delenv("SLACK_MANIFEST_TOKEN", raising=False)
    monkeypatch.delenv("SLACK_MANIFEST_APP_ID", raising=False)
    config = tmp_path / "config.json"
    config.write_text(
        json.dumps(
            {
                "targets": {
                    "read": {
                        "app_id": "A123",
                        "token": "xoxe-token",
                        "api_base": "https://example.test/api/",
                        "timeout": 7,
                    }
                }
            }
        )
    )

    token, app_id, api_base, timeout = resolve_credentials(
        config_path=str(config),
        target_name="read",
    )

    assert token == "xoxe-token"
    assert app_id == "A123"
    assert api_base == "https://example.test/api"
    assert timeout == 7


def test_env_overrides_config(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv("SLACK_MANIFEST_TOKEN", "env-token")
    monkeypatch.setenv("SLACK_MANIFEST_APP_ID", "AENV")
    config = tmp_path / "config.json"
    config.write_text(json.dumps({"token": "config-token", "app_id": "ACONFIG"}))

    token, app_id, _, _ = resolve_credentials(config_path=str(config))

    assert token == "env-token"
    assert app_id == "AENV"


def test_list_targets(tmp_path: Path) -> None:
    config = tmp_path / "config.json"
    config.write_text(json.dumps({"targets": {"b": {}, "a": {}}}))

    assert list_targets(str(config)) == ["a", "b"]


def test_command_list_resolves_value(tmp_path: Path) -> None:
    config = tmp_path / "config.json"
    config.write_text(
        json.dumps(
            {
                "targets": {
                    "read": {
                        "token_command": ["/bin/sh", "-c", "printf token-from-command"],
                    }
                }
            }
        )
    )

    token, _, _, _ = resolve_credentials(config_path=str(config), target_name="read")

    assert token == "token-from-command"
