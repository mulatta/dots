"""Tests for the slack hook."""

from __future__ import annotations

import argparse
import base64
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
from typing import Any

import pytest

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks.slack import _write_download, build_payload, run


def _make_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "op": "search",
        "query": "in:#ops deploy",
        "channel": None,
        "thread_ts": None,
        "limit": 20,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_search_payload() -> None:
    payload = build_payload(_make_args(limit=5))

    assert payload == {
        "operation": "search",
        "query": "in:#ops deploy",
        "limit": 5,
    }


def test_replies_payload() -> None:
    payload = build_payload(
        _make_args(
            op="replies",
            query=None,
            channel="C0123",
            thread_ts="1712345678.123456",
            limit=50,
        )
    )

    assert payload == {
        "operation": "replies",
        "channel": "C0123",
        "thread_ts": "1712345678.123456",
        "limit": 50,
    }


def test_file_content_payload() -> None:
    payload = build_payload(
        _make_args(
            op="file-content",
            query=None,
            file="F0123",
            max_bytes=1024,
            limit=None,
        )
    )

    assert payload == {
        "operation": "file-content",
        "file": "F0123",
        "max_bytes": 1024,
    }


def test_file_download_payload() -> None:
    payload = build_payload(
        _make_args(
            op="file-download",
            query=None,
            file="F0123",
            output="/tmp/out.pptx",
            max_bytes=2048,
            limit=None,
        )
    )

    assert payload == {
        "operation": "file-download",
        "file": "F0123",
        "max_bytes": 2048,
    }


def test_write_download(tmp_path: Path) -> None:
    result = _write_download(
        {
            "ok": True,
            "content_base64": base64.b64encode(b"hello").decode(),
            "file": {"name": "../hello.txt", "mimetype": "text/plain"},
        },
        str(tmp_path),
    )

    assert result["ok"] is True
    assert Path(str(result["path"])).read_bytes() == b"hello"


class _FakeSlackWebhookHandler(BaseHTTPRequestHandler):
    """Captures the last POST body and replies with Slack-like result."""

    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeSlackWebhookHandler.last_payload = json.loads(body)

        auth = self.headers.get("Authorization", "")
        if auth != "Bearer test-secret":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true,"messages":[{"text":"deploy done"}]}')

    def log_message(self, *_args: Any) -> None:
        pass


def test_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeSlackWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "slack": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/context-slack",
            token="test-secret",
        ),
    }
    run(_make_args(), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeSlackWebhookHandler.last_payload == {
        "operation": "search",
        "query": "in:#ops deploy",
        "limit": 20,
    }

    captured = capsys.readouterr()
    assert '"text": "deploy done"' in captured.out
