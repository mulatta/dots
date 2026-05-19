"""One-shot JMAP handoff for user-selected mail.

The service treats the server-side $flagged keyword as a send-to-Noa gesture:
flagged messages are copied into Noa's local Maildir, OpenCrow is notified via
its FIFO, and the source flag is cleared only after the local handoff exists.
"""

from __future__ import annotations

import base64
import errno
import json
import os
import pathlib
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

JMAP_CORE = "urn:ietf:params:jmap:core"
JMAP_MAIL = "urn:ietf:params:jmap:mail"
FLAGGED_KEYWORD = "$flagged"


@dataclass(frozen=True)
class Config:
    session_url: str
    username: str
    password: str
    maildir: pathlib.Path
    trigger_pipe: pathlib.Path
    account_id: str | None = None
    account_name: str | None = None
    api_url: str | None = None
    download_url: str | None = None
    mailbox_path: str | None = None
    limit: int = 50


class JmapError(RuntimeError):
    """Raised for JMAP protocol or transport errors."""


def read_password() -> str:
    if password := os.environ.get("JMAP_PASSWORD"):
        return password

    credentials_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if credentials_dir:
        for name in ("jmap-password", "imap-password"):
            path = pathlib.Path(credentials_dir) / name
            if path.exists():
                return path.read_text(encoding="utf-8").strip()

    raise JmapError("JMAP_PASSWORD or systemd credential jmap-password is required")


def load_config() -> Config:
    return Config(
        session_url=os.environ.get(
            "JMAP_SESSION_URL", "https://stalwart.mulatta.io/.well-known/jmap"
        ),
        api_url=os.environ.get("JMAP_API_URL"),
        download_url=os.environ.get("JMAP_DOWNLOAD_URL"),
        account_id=os.environ.get("JMAP_ACCOUNT_ID"),
        account_name=os.environ.get("JMAP_ACCOUNT_NAME"),
        username=os.environ.get("JMAP_USERNAME", "noa"),
        password=read_password(),
        mailbox_path=os.environ.get("JMAP_MAILBOX_PATH") or None,
        maildir=pathlib.Path(
            os.environ.get("JMAP_MAILDIR", "/var/lib/noa-maildir/Flagged")
        ),
        trigger_pipe=pathlib.Path(
            os.environ.get("JMAP_TRIGGER_PIPE", "/var/lib/noa-maildir/trigger.pipe")
        ),
        limit=int(os.environ.get("JMAP_LIMIT", "50")),
    )


def auth_header(config: Config) -> str:
    token = base64.b64encode(f"{config.username}:{config.password}".encode()).decode()
    return f"Basic {token}"


def http_json(
    config: Config, url: str, payload: dict[str, Any] | None = None
) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": auth_header(config),
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
        method="GET" if payload is None else "POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - configured URL
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise JmapError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise JmapError(f"request failed for {url}: {exc}") from exc


def http_bytes(config: Config, url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"Authorization": auth_header(config), "Accept": "message/rfc822"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - configured URL
            return response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise JmapError(f"HTTP {exc.code} from {url}: {body}") from exc
    except urllib.error.URLError as exc:
        raise JmapError(f"download failed for {url}: {exc}") from exc


def select_account_id(session: dict[str, Any], account_name: str | None) -> str | None:
    if account_name is not None:
        for account_id, account in session.get("accounts", {}).items():
            if account.get("name") == account_name:
                return str(account_id)
        raise JmapError(f"JMAP account not found by name: {account_name}")
    account_id = session.get("primaryAccounts", {}).get(JMAP_MAIL)
    return str(account_id) if account_id is not None else None


def load_session(config: Config) -> tuple[str, str, str]:
    if config.api_url and config.download_url and config.account_id:
        return config.api_url, config.download_url, config.account_id

    session = http_json(config, config.session_url)
    api_url = config.api_url or session.get("apiUrl")
    download_url = config.download_url or session.get("downloadUrl")
    account_id = config.account_id or select_account_id(session, config.account_name)

    if not api_url or not download_url or not account_id:
        raise JmapError(
            "JMAP session did not provide apiUrl, downloadUrl, and mail accountId"
        )
    return str(api_url), str(download_url), str(account_id)


class JmapClient:
    def __init__(
        self, config: Config, api_url: str, download_url: str, account_id: str
    ):
        self.config = config
        self.api_url = api_url
        self.download_url = download_url
        self.account_id = account_id

    def request(self, method_calls: list[list[Any]]) -> list[list[Any]]:
        payload = {"using": [JMAP_CORE, JMAP_MAIL], "methodCalls": method_calls}
        response = http_json(self.config, self.api_url, payload)
        method_responses = response.get("methodResponses")
        if not isinstance(method_responses, list):
            raise JmapError(f"invalid JMAP response: {response!r}")
        for name, args, _call_id in method_responses:
            if name == "error":
                raise JmapError(f"JMAP method error: {args!r}")
        return method_responses

    def download_blob(self, blob_id: str) -> bytes:
        url = expand_download_url(self.download_url, self.account_id, blob_id)
        return http_bytes(self.config, url)


def expand_download_url(template: str, account_id: str, blob_id: str) -> str:
    replacements = {
        "accountId": account_id,
        "blobId": blob_id,
        "name": "message.eml",
        "type": "message/rfc822",
    }
    result = template
    for key, value in replacements.items():
        result = result.replace("{" + key + "}", urllib.parse.quote(value, safe=""))
    return result


def build_flagged_filter(mailbox_id: str | None) -> dict[str, Any]:
    flagged = {"hasKeyword": FLAGGED_KEYWORD}
    if mailbox_id is None:
        return flagged
    return {"operator": "AND", "conditions": [flagged, {"inMailbox": mailbox_id}]}


def mailbox_path(mailbox: dict[str, Any], by_id: dict[str, dict[str, Any]]) -> str:
    parts: list[str] = []
    current: dict[str, Any] | None = mailbox
    seen: set[str] = set()
    while current is not None:
        mid = str(current.get("id", ""))
        if mid in seen:
            break
        seen.add(mid)
        name = str(current.get("name", ""))
        if name:
            parts.append(name)
        parent_id = current.get("parentId")
        current = by_id.get(parent_id) if parent_id else None
    return "/".join(reversed(parts))


def resolve_mailbox_id(client: JmapClient, wanted_path: str | None) -> str | None:
    if wanted_path is None:
        return None

    responses = client.request(
        [
            [
                "Mailbox/get",
                {
                    "accountId": client.account_id,
                    "ids": None,
                    "properties": ["id", "name", "parentId", "role"],
                },
                "mailboxes",
            ]
        ]
    )
    mailboxes = responses[0][1].get("list", [])
    by_id = {m["id"]: m for m in mailboxes if "id" in m}
    for mailbox in mailboxes:
        if mailbox_path(mailbox, by_id) == wanted_path:
            return str(mailbox["id"])
        if wanted_path.upper() == "INBOX" and mailbox.get("role") == "inbox":
            return str(mailbox["id"])
    raise JmapError(f"mailbox path not found: {wanted_path}")


def query_flagged(client: JmapClient, mailbox_id: str | None, limit: int) -> list[str]:
    responses = client.request(
        [
            [
                "Email/query",
                {
                    "accountId": client.account_id,
                    "filter": build_flagged_filter(mailbox_id),
                    "sort": [{"property": "receivedAt", "isAscending": True}],
                    "limit": limit,
                },
                "query",
            ]
        ]
    )
    ids = responses[0][1].get("ids", [])
    return [str(email_id) for email_id in ids]


def get_emails(client: JmapClient, ids: list[str]) -> list[dict[str, Any]]:
    if not ids:
        return []
    responses = client.request(
        [
            [
                "Email/get",
                {
                    "accountId": client.account_id,
                    "ids": ids,
                    "properties": [
                        "id",
                        "blobId",
                        "messageId",
                        "subject",
                        "receivedAt",
                        "keywords",
                    ],
                },
                "get",
            ]
        ]
    )
    return list(responses[0][1].get("list", []))


def clear_flagged(client: JmapClient, email_id: str) -> None:
    responses = client.request(
        [
            [
                "Email/set",
                {
                    "accountId": client.account_id,
                    "update": {email_id: {f"keywords/{FLAGGED_KEYWORD}": None}},
                },
                "clear",
            ]
        ]
    )
    method, args, _call_id = responses[0]
    if method != "Email/set":
        raise JmapError(f"unexpected clear response: {responses[0]!r}")
    not_updated = args.get("notUpdated", {})
    if email_id in not_updated:
        raise JmapError(
            f"failed to clear {FLAGGED_KEYWORD} on {email_id}: {not_updated[email_id]!r}"
        )
    updated = args.get("updated", {})
    if email_id not in updated:
        raise JmapError(
            f"failed to clear {FLAGGED_KEYWORD} on {email_id}: no updated response"
        )


def maildir_filename(message_ids: list[str] | None, fallback_id: str) -> str:
    raw = (message_ids or [fallback_id])[0] or fallback_id
    raw = raw.strip().strip("<>")
    raw = re.sub(r"[/\x00\s]+", "_", raw)
    raw = re.sub(r"[^A-Za-z0-9_.=@%+-]", "_", raw)
    raw = raw[:180] or fallback_id
    return f"{raw}:2,FS"


def ensure_maildir(maildir: pathlib.Path) -> pathlib.Path:
    cur = maildir / "cur"
    for subdir in (cur, maildir / "new", maildir / "tmp"):
        subdir.mkdir(parents=True, exist_ok=True)
    return cur


def deliver_raw(maildir: pathlib.Path, filename: str, raw: bytes) -> bool:
    cur = ensure_maildir(maildir)
    destination = cur / filename
    if destination.exists():
        return False

    fd, tmp_name = tempfile.mkstemp(prefix="noa-jmap-", dir=maildir / "tmp")
    tmp_path = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as tmp:
            tmp.write(raw)
        os.chmod(tmp_path, 0o640)
        os.replace(tmp_path, destination)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()
    return True


def trigger_field(name: str, value: object) -> str:
    return f"{name}={urllib.parse.quote(str(value), safe='')}"


def build_flagged_trigger_line(
    *,
    filename: str,
    email_id: str,
    message_ids: list[str] | None,
    subject: str,
    received_at: str,
) -> str:
    message_id = (message_ids or [""])[0] or ""
    fields = [
        trigger_field("schema", "opencrow.trigger.v1"),
        trigger_field("action", "handoff"),
        trigger_field("filename", filename),
        trigger_field("email_id", email_id),
        trigger_field("message_id", message_id),
        trigger_field("subject", subject),
        trigger_field("received_at", received_at),
        trigger_field("event_id", f"mail:flagged:{email_id}"),
    ]
    return " ".join(["mail.flagged", *fields])


def notify_trigger(pipe: pathlib.Path, line: str) -> None:
    try:
        fd = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
    except OSError as exc:
        if exc.errno in (errno.ENXIO, errno.ENOENT):
            return
        raise
    try:
        os.write(fd, (line.replace("\n", " ") + "\n").encode("utf-8"))
    finally:
        os.close(fd)


def run(config: Config) -> int:
    api_url, download_url, account_id = load_session(config)
    client = JmapClient(config, api_url, download_url, account_id)
    mailbox_id = resolve_mailbox_id(client, config.mailbox_path)
    ids = query_flagged(client, mailbox_id, config.limit)
    emails = get_emails(client, ids)

    added = 0
    notified = 0
    cleared = 0
    for email_obj in emails:
        email_id = str(email_obj["id"])
        filename = maildir_filename(email_obj.get("messageId"), email_id)
        destination = config.maildir / "cur" / filename
        if destination.exists():
            notify_trigger(
                config.trigger_pipe,
                build_flagged_trigger_line(
                    filename=filename,
                    email_id=email_id,
                    message_ids=email_obj.get("messageId"),
                    subject=str(email_obj.get("subject") or ""),
                    received_at=str(email_obj.get("receivedAt") or ""),
                ),
            )
            notified += 1
            clear_flagged(client, email_id)
            cleared += 1
            continue

        blob_id = email_obj.get("blobId")
        if not blob_id:
            print(f"jmap-handoff: skipping {email_id}: missing blobId", file=sys.stderr)
            continue
        raw = client.download_blob(str(blob_id))
        if deliver_raw(config.maildir, filename, raw):
            notify_trigger(
                config.trigger_pipe,
                build_flagged_trigger_line(
                    filename=filename,
                    email_id=email_id,
                    message_ids=email_obj.get("messageId"),
                    subject=str(email_obj.get("subject") or ""),
                    received_at=str(email_obj.get("receivedAt") or ""),
                ),
            )
            added += 1
            notified += 1
        clear_flagged(client, email_id)
        cleared += 1

    print(
        f"jmap-handoff: flagged={len(ids)} added={added} notified={notified} cleared={cleared}",
        file=sys.stderr,
    )
    return 0


def main() -> int:
    try:
        return run(load_config())
    except Exception as exc:  # noqa: BLE001 - systemd should log a concise failure
        print(f"jmap-handoff: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
