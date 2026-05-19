"""Tests for the RSS hook."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from typing import Any

import pytest

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks.rss import build_payload, run


def _make_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "op": "list-entries",
        "entry_id": None,
        "category_id": 12,
        "starred": True,
        "status": None,
        "limit": 50,
        "offset": 0,
        "order": "changed_at",
        "direction": "desc",
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_list_entries_payload() -> None:
    payload = build_payload(
        _make_args(
            category_id=12,
            starred=True,
            status="unread",
            limit=25,
            offset=50,
        )
    )

    assert payload == {
        "operation": "list-entries",
        "category_id": 12,
        "starred": True,
        "status": "unread",
        "limit": 25,
        "offset": 50,
        "order": "changed_at",
        "direction": "desc",
    }


def test_show_entry_payload() -> None:
    payload = build_payload(
        _make_args(
            op="show-entry",
            entry_id="1234",
            category_id=None,
            starred=False,
        )
    )

    assert payload == {"operation": "show-entry", "entry_id": 1234}


class _FakeRssWebhookHandler(BaseHTTPRequestHandler):
    """Captures the last POST body and replies with RSS-like JSON."""

    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeRssWebhookHandler.last_payload = json.loads(body)

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
            b'{"status":200,"body":{"id":1234,"title":"Scholarship deadline"}}'
        )

    def log_message(self, *_args: Any) -> None:
        pass


def test_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeRssWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "rss": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/context-rss",
            token="test-secret",
        ),
    }
    run(_make_args(op="show-entry", entry_id="1234"), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeRssWebhookHandler.last_payload == {
        "operation": "show-entry",
        "entry_id": 1234,
    }

    captured = capsys.readouterr()
    assert '"title": "Scholarship deadline"' in captured.out


def test_http_error_status_exits(capsys: pytest.CaptureFixture[str]) -> None:
    class _FailingWebhookHandler(BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            body = b'{"status":404,"body":{"message":"Not Found"}}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args: Any) -> None:
            pass

    server = HTTPServer(("127.0.0.1", 0), _FailingWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {"rss": HookConfig(url=f"http://127.0.0.1:{port}/w", token=None)}
    with pytest.raises(SystemExit):
        run(_make_args(op="show-entry", entry_id="1234"), config)

    thread.join(timeout=5)
    server.server_close()

    captured = capsys.readouterr()
    assert '"message": "Not Found"' in captured.out
