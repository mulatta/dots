from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from miniflux_sync.bootstrap import BootstrapError, _ensure_webhook_integration
from miniflux_sync.cli import default_config_path, load_manifest, sync_feeds


def test_load_manifest_reads_json(tmp_path: Path, monkeypatch: Any) -> None:
    manifest_path = tmp_path / "feeds.json"
    manifest_path.write_text(
        '{"base_url":"https://rss.example","feeds":[{"url":"https://example.com/feed.xml","category":"All"}]}',
        encoding="utf-8",
    )

    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))

    assert default_config_path() == tmp_path / "config" / "miniflux" / "feeds.json"
    assert load_manifest(manifest_path) == {
        "base_url": "https://rss.example",
        "feeds": [{"url": "https://example.com/feed.xml", "category": "All"}],
    }


class FakeCursor:
    def __init__(self) -> None:
        self.queries: list[tuple[str, tuple[Any, ...]]] = []

    def execute(self, query: str, params: tuple[Any, ...]) -> None:
        self.queries.append((query, params))


def test_ensure_webhook_integration_updates_declared_fields() -> None:
    cursor = FakeCursor()

    _ensure_webhook_integration(
        cursor,
        7,
        enabled=True,
        url="https://miniflux:secret@n8n.example/webhook/miniflux-save-entry",
        secret=None,
    )

    assert len(cursor.queries) == 1
    query, params = cursor.queries[0]
    assert "webhook_enabled = %s" in query
    assert "webhook_url = %s" in query
    assert "webhook_secret" not in query
    assert params == (
        True,
        "https://miniflux:secret@n8n.example/webhook/miniflux-save-entry",
        7,
    )


def test_ensure_webhook_integration_rejects_enabled_without_url() -> None:
    with pytest.raises(BootstrapError, match="webhook_url is required"):
        _ensure_webhook_integration(
            FakeCursor(),
            7,
            enabled=True,
            url=None,
            secret=None,
        )


class FakeClient:
    def __init__(self, feeds: list[dict[str, Any]] | None = None) -> None:
        self.feeds = feeds or []
        self.categories = [{"id": 1, "title": "All"}]
        self.created_feeds: list[tuple[str, int, dict[str, Any]]] = []
        self.updated_feeds: list[tuple[int, dict[str, Any]]] = []
        self.deleted_feeds: list[int] = []

    def get_feeds(self) -> list[dict[str, Any]]:
        return self.feeds

    def get_categories(self) -> list[dict[str, Any]]:
        return self.categories

    def create_category(self, name: str) -> dict[str, int]:
        category = {"id": len(self.categories) + 1, "title": name}
        self.categories.append(category)
        return {"id": category["id"]}

    def create_feed(self, url: str, *, category_id: int, **kwargs: Any) -> int:
        self.created_feeds.append((url, category_id, kwargs))
        return 42

    def update_feed(self, feed_id: int, **kwargs: Any) -> dict[str, Any]:
        self.updated_feeds.append((feed_id, kwargs))
        return {"id": feed_id, **kwargs}

    def delete_feed(self, feed_id: int) -> None:
        self.deleted_feeds.append(feed_id)


def test_sync_feeds_reads_secret_file_fields(tmp_path: Path) -> None:
    password_file = tmp_path / "password"
    password_file.write_text("secret\n", encoding="utf-8")

    client = FakeClient()

    sync_feeds(
        client,
        [
            {
                "url": "https://example.com/feed.xml",
                "category": "All",
                "password_file": str(password_file),
            }
        ],
        base=tmp_path,
        dry_run=False,
    )

    assert client.created_feeds == [
        ("https://example.com/feed.xml", 1, {"password": "secret"})
    ]
    assert client.updated_feeds == []
    assert client.deleted_feeds == []


def test_sync_feeds_updates_existing_feed_in_place(tmp_path: Path) -> None:
    client = FakeClient(
        feeds=[
            {
                "id": 7,
                "feed_url": "https://example.com/feed.xml",
                "title": "Example",
                "crawler": False,
                "category": {"title": "All"},
            }
        ]
    )

    sync_feeds(
        client,
        [
            {
                "url": "https://example.com/feed.xml",
                "category": "All",
                "crawler": True,
            }
        ],
        base=tmp_path,
        dry_run=False,
    )

    assert client.created_feeds == []
    assert client.updated_feeds == [(7, {"crawler": True})]
    assert client.deleted_feeds == []


def test_sync_feeds_updates_existing_feed_category_in_place(tmp_path: Path) -> None:
    client = FakeClient(
        feeds=[
            {
                "id": 7,
                "feed_url": "https://example.com/feed.xml",
                "title": "Example",
                "category": {"title": "Old"},
            }
        ]
    )

    sync_feeds(
        client,
        [
            {
                "url": "https://example.com/feed.xml",
                "category": "All",
            }
        ],
        base=tmp_path,
        dry_run=False,
    )

    assert client.created_feeds == []
    assert client.updated_feeds == [(7, {"category_id": 1})]
    assert client.deleted_feeds == []


def test_sync_feeds_applies_update_only_settings_after_create(tmp_path: Path) -> None:
    client = FakeClient()

    sync_feeds(
        client,
        [
            {
                "url": "https://example.com/feed.xml",
                "category": "All",
                "title": "Declared title",
            }
        ],
        base=tmp_path,
        dry_run=False,
    )

    assert client.created_feeds == [("https://example.com/feed.xml", 1, {})]
    assert client.updated_feeds == [(42, {"title": "Declared title"})]
    assert client.deleted_feeds == []


def test_sync_feeds_reports_orphans_without_deleting(tmp_path: Path) -> None:
    client = FakeClient(
        feeds=[
            {
                "id": 7,
                "feed_url": "https://example.com/old.xml",
                "title": "Old",
                "category": {"title": "All"},
            }
        ]
    )

    sync_feeds(client, [], base=tmp_path, dry_run=False)

    assert client.created_feeds == []
    assert client.updated_feeds == []
    assert client.deleted_feeds == []
