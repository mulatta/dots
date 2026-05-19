"""Tests for the Vikunja task-create hook."""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from threading import Thread
from typing import Any

import pytest
import yaml

from n8n_hooks.config import HookConfig
from n8n_hooks.hooks.vikunja_task_create import build_payload, run


def _schema(name: str, *, checklist_min: int = 1) -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": ["summary", "checklist"],
        "properties": {
            "summary": {"type": "string", "minLength": 1},
            "checklist": {
                "type": "array",
                "items": {"type": "string"},
                "minItems": checklist_min,
                "maxItems": 5,
            },
            "notes": {"type": "array", "items": {"type": "string"}, "maxItems": 6},
            "proof": {"type": "array", "items": {"type": "string"}, "maxItems": 3},
            "sources": {
                "type": "array",
                "items": {"$ref": "#/$defs/Source"},
                "maxItems": 5,
            },
        },
        "$defs": {
            "SourceKind": {"type": "string", "enum": ["url", "webmail", "other"]},
            "Source": {
                "type": "object",
                "additionalProperties": False,
                "required": ["kind", "locator"],
                "properties": {
                    "kind": {"$ref": "#/$defs/SourceKind"},
                    "locator": {"type": "string", "minLength": 1},
                    "title": {"type": "string"},
                },
            },
        },
        "x-note_hints": ["recipient"],
    }


def _write_template(
    tmp_path: Path, name: str = "communication", *, checklist_min: int = 1
) -> Path:
    template_dir = tmp_path / "templates"
    template_dir.mkdir(exist_ok=True)
    data = {
        "name": name,
        "description": "Send message/request and track response.",
        "defaults": {"priority": 3, "labels": ["type:communication", "state:next"]},
        "schema": _schema(name, checklist_min=checklist_min),
        "attachment_expectations": [],
    }
    path = template_dir / f"{name}.md"
    path.write_text(
        "---\n" + yaml.safe_dump(data, sort_keys=False) + "---\n\n# template\n"
    )
    return template_dir


def _write_context(tmp_path: Path, data: dict[str, Any]) -> Path:
    path = tmp_path / "context.json"
    path.write_text(json.dumps(data))
    return path


def _make_args(tmp_path: Path, **overrides: Any) -> argparse.Namespace:
    context = overrides.pop("context", None)
    if context is None:
        context = str(
            _write_context(
                tmp_path,
                {
                    "summary": "메일 답장 준비",
                    "checklist": ["요청 확인", "초안 작성"],
                    "sources": [
                        {
                            "kind": "webmail",
                            "locator": "https://mail.mulatta.io/ko?email=boiqaaalse",
                            "title": "원본 메일",
                        }
                    ],
                },
            )
        )
    template_dir = overrides.pop("template_dir", None)
    if template_dir is None:
        template_dir = str(_write_template(tmp_path))
    defaults: dict[str, Any] = {
        "project": "Inbox",
        "title": "메일 답장 준비",
        "template": "communication",
        "template_dir": template_dir,
        "context": context,
        "due": "2026-05-20",
        "start": None,
        "end": None,
        "priority": 3,
        "color": None,
        "reminders": [],
        "relations": ["related:123"],
        "allow_missing": False,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_build_payload_is_template_and_type_aware(tmp_path: Path) -> None:
    payload = build_payload(_make_args(tmp_path))

    assert payload["operation"] == "create_task_from_template"
    assert payload["template"] == "communication"
    assert payload["template_defaults"] == {
        "priority": 3,
        "labels": ["type:communication", "state:next"],
    }
    assert payload["template_schema"]["$defs"]["SourceKind"]["enum"] == [
        "url",
        "webmail",
        "other",
    ]
    assert (
        payload["context"]["sources"][0]["locator"]
        == "https://mail.mulatta.io/ko?email=boiqaaalse"
    )
    assert payload["relations"] == [{"kind": "related", "other": "123"}]


def test_rejects_context_that_violates_template_schema(tmp_path: Path) -> None:
    context = _write_context(
        tmp_path,
        {
            "summary": "bad source",
            "checklist": ["확인"],
            "sources": [{"kind": "email", "locator": "bare-message-id"}],
        },
    )
    template_dir = _write_template(tmp_path)

    with pytest.raises(SystemExit):
        build_payload(
            _make_args(tmp_path, template_dir=str(template_dir), context=str(context))
        )


def test_rejects_missing_required_context(tmp_path: Path) -> None:
    context = _write_context(tmp_path, {"summary": "too short", "checklist": ["one"]})
    template_dir = _write_template(tmp_path, checklist_min=2)

    with pytest.raises(SystemExit):
        build_payload(
            _make_args(tmp_path, template_dir=str(template_dir), context=str(context))
        )


def test_rejects_invalid_relation_kind(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        build_payload(_make_args(tmp_path, relations=["waits:123"]))


class _FakeVikunjaTaskCreateHandler(BaseHTTPRequestHandler):
    last_payload: dict[str, Any] = {}

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        _FakeVikunjaTaskCreateHandler.last_payload = json.loads(body)

        auth = self.headers.get("Authorization", "")
        if auth != "Bearer mutation-secret":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(b'{"error":"unauthorized"}')
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status":200,"body":{"id":987,"title":"made"}}')

    def log_message(self, *_args: Any) -> None:
        pass


def test_end_to_end(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    server = HTTPServer(("127.0.0.1", 0), _FakeVikunjaTaskCreateHandler)
    port = server.server_address[1]
    thread = Thread(target=server.handle_request, daemon=True)
    thread.start()

    config = {
        "vikunja-task-create": HookConfig(
            url=f"http://127.0.0.1:{port}/webhook/vikunja-task-create",
            token="mutation-secret",
        ),
    }
    run(_make_args(tmp_path), config)

    thread.join(timeout=5)
    server.server_close()

    assert _FakeVikunjaTaskCreateHandler.last_payload["template"] == "communication"
    assert _FakeVikunjaTaskCreateHandler.last_payload["template_schema"]["properties"][
        "summary"
    ]

    captured = capsys.readouterr()
    assert '"id": 987' in captured.out
