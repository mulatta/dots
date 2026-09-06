"""Minimal Stalwart management and JMAP client used by provisioning scripts."""

from __future__ import annotations

import base64
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

# Stalwart answers management and JMAP requests about half a second after
# start, so this budget only has to absorb a cold boot, not a slow service.
READY_DEADLINE_SECONDS = 30.0
RETRY_DELAY_SECONDS = 0.5
REQUEST_TIMEOUT_SECONDS = 30


def read_password(path: Path) -> str:
    password = path.read_text().strip()
    if not password:
        msg = f"admin password file is empty: {path}"
        raise ValueError(msg)
    return password


class StalwartClient:
    """Authenticated client for the Stalwart management API and JMAP endpoint."""

    def __init__(self, base_url: str, username: str, password: str) -> None:
        self.base_url = base_url.rstrip("/")
        credentials = base64.b64encode(f"{username}:{password}".encode()).decode()
        self.headers = {
            "Authorization": f"Basic {credentials}",
            "Accept": "application/json",
        }

    def _open(self, request: urllib.request.Request) -> bytes | None:
        deadline = time.monotonic() + READY_DEADLINE_SECONDS
        while True:
            try:
                with urllib.request.urlopen(
                    request, timeout=REQUEST_TIMEOUT_SECONDS
                ) as response:
                    return bytes(response.read())
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    return None
                detail = error.read().decode(errors="replace")
                msg = f"{request.method} {request.full_url} failed with HTTP {error.code}: {detail}"
                raise RuntimeError(msg) from error
            except urllib.error.URLError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(RETRY_DELAY_SECONDS)

    def request(self, method: str, url: str, body: Any | None = None) -> Any:
        data = (
            None if body is None else json.dumps(body, separators=(",", ":")).encode()
        )
        headers = dict(self.headers)
        if data is not None:
            headers["Content-Type"] = "application/json"
        payload = self._open(
            urllib.request.Request(url, data=data, headers=headers, method=method)
        )
        if payload is None:
            return None
        parsed = json.loads(payload) if payload else None
        if isinstance(parsed, dict) and parsed.get("error") == "notFound":
            return None
        if isinstance(parsed, dict) and "data" in parsed:
            return parsed["data"]
        return parsed

    def principal(self, name: str) -> dict[str, Any] | None:
        result = self.request(
            "GET", f"{self.base_url}/api/principal/{quote_name(name)}"
        )
        if result is not None and not isinstance(result, dict):
            msg = f"management API returned an unexpected principal for {name}"
            raise RuntimeError(msg)
        return result

    def create_principal(self, principal: dict[str, Any]) -> None:
        self.request("POST", f"{self.base_url}/api/principal", principal)

    def patch_principal(self, name: str, patch: list[dict[str, Any]]) -> None:
        self.request(
            "PATCH", f"{self.base_url}/api/principal/{quote_name(name)}", patch
        )

    def jmap_session(self) -> dict[str, Any]:
        session = self.request("GET", f"{self.base_url}/.well-known/jmap")
        if not isinstance(session, dict):
            msg = "JMAP session endpoint returned an unexpected response"
            raise RuntimeError(msg)
        return session

    def jmap(self, request: dict[str, Any]) -> dict[str, Any]:
        response = self.request("POST", f"{self.base_url}/jmap/", request)
        if not isinstance(response, dict):
            msg = "JMAP endpoint returned an unexpected response"
            raise RuntimeError(msg)
        return response


def method_response(response: dict[str, Any], name: str) -> dict[str, Any]:
    for call in response.get("methodResponses", []):
        if call[0] == name:
            result = call[1]
            if isinstance(result, dict):
                return result
    msg = f"JMAP response contains no {name} result"
    raise RuntimeError(msg)


def quote_name(name: str) -> str:
    return urllib.parse.quote(name, safe="")
