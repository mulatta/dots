"""Tests for the github hook."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from typing import Any

import pytest

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks.github import build_payload, run


def _make_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "path": "/repos/owner/repo/pulls/42/files",
        "term": "",
        "query": [],
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_build_payload_without_query() -> None:
    payload = build_payload(_make_args())

    assert payload == {"path": "/repos/owner/repo/pulls/42/files"}


def test_build_payload_with_repeated_query() -> None:
    payload = build_payload(_make_args(query=["per_page=100", "page=2"]))

    assert payload == {
        "path": "/repos/owner/repo/pulls/42/files",
        "query": {"per_page": "100", "page": "2"},
    }


class _FakeGitHubWebhookHandler(BaseHTTPRequestHandler):
    """Captures the last POST body and replies with wrapped API result."""

    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeGitHubWebhookHandler.last_payload = json.loads(body)

        auth = self.headers.get("Authorization", "")
        if auth != "Bearer test-secret":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":200,"body":[{"filename":"flake.nix"}]}')

    def log_message(self, *_args: Any) -> None:
        pass


def test_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeGitHubWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "github": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/context-github",
            token="test-secret",
        ),
    }
    run(_make_args(query=["per_page=1"]), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeGitHubWebhookHandler.last_payload == {
        "path": "/repos/owner/repo/pulls/42/files",
        "query": {"per_page": "1"},
    }

    captured = capsys.readouterr()
    assert '"filename": "flake.nix"' in captured.out


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

    config = {"github": HookConfig(url=f"http://127.0.0.1:{port}/w", token=None)}
    with pytest.raises(SystemExit):
        run(_make_args(), config)

    thread.join(timeout=5)
    server.server_close()

    captured = capsys.readouterr()
    assert '"message": "Not Found"' in captured.out
