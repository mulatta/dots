"""Bootstrap Miniflux users and API keys with parameterized SQL."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import psycopg
from psycopg.rows import dict_row


class BootstrapError(RuntimeError):
    """Raised when existing account state is unsafe to modify."""


@dataclass(frozen=True)
class BootstrapRequest:
    database_url: str
    username: str
    api_token: str
    api_key_description: str
    openid_connect_id: str | None = None
    webhook_enabled: bool | None = None
    webhook_url: str | None = None
    webhook_secret: str | None = None


def read_secret_file(path: Path) -> str:
    value = path.read_text(encoding="utf-8").strip()
    if not value:
        raise BootstrapError(f"secret file is empty: {path}")
    return value


def ensure_user_and_api_key(request: BootstrapRequest) -> int:
    """Ensure the minimal DB state required for Miniflux API provisioning."""
    if not request.username:
        raise BootstrapError("username must not be empty")
    if not request.api_token:
        raise BootstrapError("api token must not be empty")
    if not request.api_key_description:
        raise BootstrapError("api key description must not be empty")

    with psycopg.connect(request.database_url, row_factory=dict_row) as conn:
        with conn.transaction():
            with conn.cursor() as cur:
                user_id = _ensure_user(cur, request.username, request.openid_connect_id)
                _ensure_default_rows(cur, user_id)
                _ensure_api_key(
                    cur,
                    user_id,
                    request.api_token,
                    request.api_key_description,
                )
                _ensure_webhook_integration(
                    cur,
                    user_id,
                    enabled=request.webhook_enabled,
                    url=request.webhook_url,
                    secret=request.webhook_secret,
                )
                return user_id


def _ensure_user(
    cur: psycopg.Cursor, username: str, openid_connect_id: str | None
) -> int:
    cur.execute(
        """
        SELECT id, openid_connect_id
        FROM users
        WHERE username = LOWER(%s)
        """,
        (username,),
    )
    row = cur.fetchone()
    if row is None:
        cur.execute(
            """
            INSERT INTO users (username, password, is_admin, google_id, openid_connect_id)
            VALUES (LOWER(%s), '', FALSE, '', %s)
            RETURNING id
            """,
            (username, openid_connect_id or ""),
        )
        created = cur.fetchone()
        if created is None:
            raise BootstrapError("failed to create user")
        return int(created["id"])

    user_id = int(row["id"])
    current_openid_connect_id = row["openid_connect_id"] or ""
    if openid_connect_id is None:
        return user_id
    if current_openid_connect_id == openid_connect_id:
        return user_id
    if current_openid_connect_id == "":
        cur.execute(
            """
            UPDATE users
            SET openid_connect_id = %s
            WHERE id = %s
            """,
            (openid_connect_id, user_id),
        )
        return user_id
    raise BootstrapError(
        "refusing to overwrite openid_connect_id for "
        f"{username!r}: existing={current_openid_connect_id!r} "
        f"declared={openid_connect_id!r}"
    )


def _ensure_default_rows(cur: psycopg.Cursor, user_id: int) -> None:
    cur.execute(
        """
        INSERT INTO categories (user_id, title)
        VALUES (%s, 'All')
        ON CONFLICT (user_id, title) DO NOTHING
        """,
        (user_id,),
    )
    cur.execute(
        """
        INSERT INTO integrations (user_id)
        VALUES (%s)
        ON CONFLICT (user_id) DO NOTHING
        """,
        (user_id,),
    )


def _ensure_api_key(
    cur: psycopg.Cursor,
    user_id: int,
    api_token: str,
    api_key_description: str,
) -> None:
    cur.execute(
        """
        INSERT INTO api_keys (user_id, token, description)
        VALUES (%s, %s, %s)
        ON CONFLICT (user_id, description)
        DO UPDATE SET token = EXCLUDED.token
        """,
        (user_id, api_token, api_key_description),
    )


def _ensure_webhook_integration(
    cur: psycopg.Cursor,
    user_id: int,
    *,
    enabled: bool | None,
    url: str | None,
    secret: str | None,
) -> None:
    if enabled is None and url is None and secret is None:
        return
    if enabled is True and not url:
        raise BootstrapError("webhook_url is required when webhook is enabled")

    updates: list[str] = []
    values: list[object] = []
    if enabled is not None:
        updates.append("webhook_enabled = %s")
        values.append(enabled)
    if url is not None:
        updates.append("webhook_url = %s")
        values.append(url)
    if secret is not None:
        updates.append("webhook_secret = %s")
        values.append(secret)

    cur.execute(
        f"""
        UPDATE integrations
        SET {", ".join(updates)}
        WHERE user_id = %s
        """,
        (*values, user_id),
    )
