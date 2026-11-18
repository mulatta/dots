#!/usr/bin/env python3
"""Bridge agent-browser credential.resolve requests to an unlocked rbw vault.

Configure command="python3", args=["/absolute/path/to/plugins/rbw.py"],
name="rbw", capabilities=["credential.read"]. Use the default rbw profile;
an explicitly inherited RBW_PROFILE is respected. Pass the vault item name with --item.
Only HTTPS URIs are supported. Domain/default rules are narrowed to origin;
Host uses origin, Exact uses the full URL. Other match rules are rejected.
Unlock rbw yourself before use. stdout is a private protocol channel containing
credentials: do not run credential.resolve interactively or log its output.
"""

import json
import subprocess
import sys
from typing import Any
from urllib.parse import urlsplit

PROTOCOL = "agent-browser.plugin.v1"


def origin(value: str) -> tuple[str, str, int]:
    url = urlsplit(value)
    if (
        url.scheme != "https"
        or any(char.isspace() or ord(char) < 32 for char in value)
        or "\\" in value
        or not url.hostname
        or url.username is not None
        or url.password is not None
    ):
        raise ValueError("invalid_url")
    return url.scheme, url.hostname, 443 if url.port is None else url.port


def credential(entry: dict[str, Any], requested_url: Any) -> dict[str, str]:
    data = entry.get("data")
    if not isinstance(data, dict):
        raise TypeError("invalid_item")
    username, password = data.get("username"), data.get("password")
    if (
        not isinstance(username, str)
        or not username
        or not isinstance(password, str)
        or not password
    ):
        raise ValueError("invalid_login")
    urls: list[tuple[str, int | None]] = []
    for item in data.get("uris") or []:
        if not isinstance(item, dict) or not isinstance(item.get("uri"), str):
            continue
        rule = item.get("match_type")
        # rbw 1.15 serializes URI rules as integers, not display-name strings.
        if rule is not None and (type(rule) is not int or rule not in {0, 1, 3}):
            continue
        try:
            origin(item["uri"])
        except ValueError:
            continue
        urls.append((item["uri"], rule))
    if requested_url is not None:
        if not isinstance(requested_url, str):
            raise ValueError("invalid_url")
        # A CLI URL override must not release a vault item to an unrelated origin.
        target_origin = origin(requested_url)
        if not any(
            origin(url) == target_origin and (rule != 3 or url == requested_url)
            for url, rule in urls
        ):
            raise ValueError("origin_mismatch")
        url = requested_url
    elif urls:
        url = urls[0][0]
    else:
        raise ValueError("no_eligible_uri")
    return {"username": username, "password": password, "url": url}


def handle(message: Any) -> dict[str, Any]:
    if not isinstance(message, dict) or message.get("protocol") != PROTOCOL:
        raise ValueError("invalid_protocol")
    if message.get("type") == "plugin.manifest":
        return {
            "manifest": {
                "name": "rbw",
                "capabilities": ["credential.read"],
                "description": "Read login credentials from an unlocked rbw vault",
            }
        }
    if (
        message.get("type") != "credential.resolve"
        or message.get("capability") != "credential.read"
    ):
        raise ValueError("unsupported_request")
    request = message.get("request")
    if not isinstance(request, dict):
        raise TypeError("invalid_request")
    item = request.get("itemRef")
    if not isinstance(item, str):
        raise TypeError("item_name_required")
    if not item.strip():
        raise ValueError("item_name_required")
    # Fail early when locked. A lock between these calls can still trigger pinentry;
    # the get timeout bounds our wait, not the lifetime of rbw-agent's prompt.
    subprocess.run(["rbw", "unlocked"], capture_output=True, timeout=3, check=True)
    response = subprocess.run(
        ["rbw", "get", "--raw", "--", item],
        capture_output=True,
        text=True,
        timeout=8,
        check=True,
    )
    entry = json.loads(response.stdout)
    if not isinstance(entry, dict):
        raise TypeError("invalid_item")
    if entry.get("name") != item:
        raise ValueError("exact_item_name_required")
    return {"credential": credential(entry, request.get("url"))}


def main() -> None:
    try:
        raw = sys.stdin.read(65537)
        if len(raw) > 65536:
            raise ValueError("request_too_large")
        body = {"success": True, **handle(json.loads(raw))}
    except (ValueError, TypeError, OSError, subprocess.SubprocessError):
        # rbw errors and malformed item data can contain secrets or private URLs.
        body = {
            "success": False,
            "error": "Could not resolve credential; check request, rbw unlock, item and URL",
        }
    print(json.dumps({"protocol": PROTOCOL, **body}))


if __name__ == "__main__":
    main()
