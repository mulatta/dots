import json
import urllib.parse
from typing import Any

import pytest
from pytest import MonkeyPatch

from slack_manifest_cli.client import Client
from slack_manifest_cli.errors import SlackAPIError


class FakeResponse:
    def __init__(self, body: dict[str, Any]):
        self.body = json.dumps(body).encode()

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None

    def read(self) -> bytes:
        return self.body


def test_update_sends_manifest_and_app_id(monkeypatch: MonkeyPatch) -> None:
    captured: dict[str, Any] = {}

    def fake_urlopen(request: Any, timeout: int) -> FakeResponse:
        captured["url"] = request.full_url
        captured["headers"] = dict(request.header_items())
        captured["timeout"] = timeout
        captured["body"] = urllib.parse.parse_qs(request.data.decode())
        return FakeResponse({"ok": True, "app_id": "A123"})

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)
    data = Client("token", "https://slack.test/api", 9).update(
        "A123",
        {"display_information": {"name": "Test"}},
    )

    assert data["app_id"] == "A123"
    assert captured["url"] == "https://slack.test/api/apps.manifest.update"
    assert captured["headers"]["Authorization"] == "Bearer token"
    assert captured["timeout"] == 9
    assert captured["body"]["app_id"] == ["A123"]
    manifest = json.loads(captured["body"]["manifest"][0])
    assert manifest["display_information"]["name"] == "Test"


def test_export_normalizes_manifest(monkeypatch: MonkeyPatch) -> None:
    def fake_urlopen(request: Any, timeout: int) -> FakeResponse:
        return FakeResponse(
            {
                "ok": True,
                "manifest": {"display_information": {"name": "Test"}},
            }
        )

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    assert Client("token").export("A123")["manifest"]["display_information"]["name"] == "Test"


def test_slack_error_raises(monkeypatch: MonkeyPatch) -> None:
    def fake_urlopen(request: Any, timeout: int) -> FakeResponse:
        return FakeResponse({"ok": False, "error": "invalid_auth"})

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    with pytest.raises(SlackAPIError, match="invalid_auth"):
        Client("bad").validate({"display_information": {"name": "Test"}})
