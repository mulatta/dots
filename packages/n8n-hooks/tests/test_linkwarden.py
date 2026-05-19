"""Tests for the Linkwarden hooks."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
from typing import Any

import pytest

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks import linkwarden, linkwarden_link_create


def _read_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "op": "search-links",
        "query": "Nix",
        "link_id": None,
        "search": None,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def _create_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "url": "https://example.com/article",
        "name": "Example Article",
        "description": "Why keep text",
        "description_file": None,
        "collection": "Engineering",
        "tags": ["source:rss", "signal:noa-saved", "kind:article", "Nix"],
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_search_links_payload() -> None:
    payload = linkwarden.build_payload(_read_args(query="Nix source:rss"))

    assert payload == {"operation": "search-links", "query": "Nix source:rss"}


def test_get_link_payload() -> None:
    payload = linkwarden.build_payload(_read_args(op="get-link", link_id="1234"))

    assert payload == {"operation": "get-link", "link_id": 1234}


def test_create_link_payload_from_description_file(tmp_path: Path) -> None:
    description = tmp_path / "description.md"
    description.write_text("Why keep\n")

    payload = linkwarden_link_create.build_payload(
        _create_args(description=None, description_file=str(description))
    )

    assert payload == {
        "operation": "create-link",
        "url": "https://example.com/article",
        "name": "Example Article",
        "description": "Why keep",
        "collection": "Engineering",
        "tags": ["source:rss", "signal:noa-saved", "kind:article", "Nix"],
    }


def test_create_link_rejects_status_tags() -> None:
    with pytest.raises(SystemExit):
        linkwarden_link_create.build_payload(_create_args(tags=["status:inbox"]))


class _FakeWebhookHandler(BaseHTTPRequestHandler):
    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeWebhookHandler.last_payload = json.loads(body)

        auth = self.headers.get("Authorization", "")
        if auth != "Bearer test-secret":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(
            b'{"status":200,"body":{"id":1234,"url":"https://example.com/article"}}'
        )

    def log_message(self, *_args: Any) -> None:
        pass


def test_read_hook_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "linkwarden": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/context-linkwarden",
            token="test-secret",
        ),
    }
    linkwarden.run(_read_args(op="get-link", link_id="1234"), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeWebhookHandler.last_payload == {
        "operation": "get-link",
        "link_id": 1234,
    }

    captured = capsys.readouterr()
    assert '"id": 1234' in captured.out


def test_create_hook_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "linkwarden-link-create": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/linkwarden-link-create",
            token="test-secret",
        ),
    }
    linkwarden_link_create.run(_create_args(), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeWebhookHandler.last_payload["operation"] == "create-link"
    assert _FakeWebhookHandler.last_payload["collection"] == "Engineering"

    captured = capsys.readouterr()
    assert '"url": "https://example.com/article"' in captured.out
