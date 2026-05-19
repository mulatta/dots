"""Tests for the Vikunja hook."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from typing import Any

import pytest

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks.vikunja import build_payload, run


def _make_args(**overrides: Any) -> argparse.Namespace:
    defaults: dict[str, Any] = {
        "op": "list-tasks",
        "task_id": None,
        "project_id": None,
        "search": None,
        "filter": None,
        "limit": 50,
        "page": 1,
        "sort_by": None,
        "order_by": None,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_list_tasks_payload() -> None:
    payload = build_payload(
        _make_args(
            project_id=42,
            search="paperwork",
            filter="done = false",
            limit=25,
            page=2,
            sort_by="due_date",
            order_by="asc",
        )
    )

    assert payload == {
        "operation": "list-tasks",
        "project_id": 42,
        "search": "paperwork",
        "filter": "done = false",
        "limit": 25,
        "page": 2,
        "sort_by": "due_date",
        "order_by": "asc",
    }


def test_show_task_payload() -> None:
    payload = build_payload(_make_args(op="show-task", task_id="1234"))

    assert payload == {"operation": "show-task", "task_id": 1234}


class _FakeVikunjaWebhookHandler(BaseHTTPRequestHandler):
    """Captures the last POST body and replies with Vikunja-like JSON."""

    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeVikunjaWebhookHandler.last_payload = json.loads(body)

        auth = self.headers.get("Authorization", "")
        if auth != "Bearer test-secret":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":200,"body":{"id":1234,"title":"Submit form"}}')

    def log_message(self, *_args: Any) -> None:
        pass


def test_end_to_end(capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeVikunjaWebhookHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "vikunja": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/context-vikunja",
            token="test-secret",
        ),
    }
    run(_make_args(op="show-task", task_id="1234"), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeVikunjaWebhookHandler.last_payload == {
        "operation": "show-task",
        "task_id": 1234,
    }

    captured = capsys.readouterr()
    assert '"title": "Submit form"' in captured.out


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

    config = {"vikunja": HookConfig(url=f"http://127.0.0.1:{port}/w", token=None)}
    with pytest.raises(SystemExit):
        run(_make_args(op="show-task", task_id="1234"), config)

    thread.join(timeout=5)
    server.server_close()

    captured = capsys.readouterr()
    assert '"message": "Not Found"' in captured.out
