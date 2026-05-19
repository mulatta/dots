"""Tests for n8n-hooks config loading."""

from __future__ import annotations

import json
from pathlib import Path

from n8n_hooks.config import load_config


def test_hook_token_overrides_top_level_token(tmp_path: Path) -> None:
    config_path = tmp_path / "config.json"
    config_path.write_text(
        json.dumps(
            {
                "token": "context-token",
                "hooks": {
                    "github": {"url": "https://n8n.example.test/context-github"},
                    "store-draft": {
                        "url": "https://n8n.example.test/mail-draft-store",
                        "token": "mutation-token",
                    },
                },
            }
        )
    )

    config = load_config(str(config_path))

    assert config["github"].token == "context-token"
    assert config["store-draft"].token == "mutation-token"
