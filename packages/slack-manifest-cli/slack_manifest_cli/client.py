"""Slack Web API client for app manifests."""

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from slack_manifest_cli.errors import SlackAPIError
from slack_manifest_cli.manifest import manifest_api_value, manifest_from_api


class Client:
    """Small Slack Web API client."""

    def __init__(self, token: str, api_base: str = "https://slack.com/api", timeout: int = 30):
        parsed = urllib.parse.urlparse(api_base)
        if parsed.scheme not in {"http", "https"}:
            raise SlackAPIError(f"unsupported Slack API URL scheme: {parsed.scheme}")
        self.token = token
        self.api_base = api_base.rstrip("/")
        self.timeout = timeout

    def post(self, method: str, fields: dict[str, str]) -> dict[str, Any]:
        """POST form fields to Slack API method."""
        body = urllib.parse.urlencode(fields).encode()
        request = urllib.request.Request(
            f"{self.api_base}/{method}",
            data=body,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                raw = response.read().decode()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            raise SlackAPIError(f"HTTP {e.code} from Slack API: {detail}") from e
        except urllib.error.URLError as e:
            raise SlackAPIError(f"failed to reach Slack API: {e}") from e

        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise SlackAPIError(f"Slack API returned invalid JSON: {raw[:200]}") from e
        if not isinstance(data, dict):
            raise SlackAPIError("Slack API returned non-object JSON")
        if not data.get("ok", False):
            error = data.get("error", "unknown_error")
            raise SlackAPIError(f"Slack API error: {error}")
        return data

    def validate(self, manifest: dict[str, Any]) -> dict[str, Any]:
        """Validate app manifest."""
        return self.post("apps.manifest.validate", {"manifest": manifest_api_value(manifest)})

    def create(self, manifest: dict[str, Any]) -> dict[str, Any]:
        """Create app from manifest."""
        return self.post("apps.manifest.create", {"manifest": manifest_api_value(manifest)})

    def update(self, app_id: str, manifest: dict[str, Any]) -> dict[str, Any]:
        """Update existing app from manifest."""
        return self.post(
            "apps.manifest.update",
            {"app_id": app_id, "manifest": manifest_api_value(manifest)},
        )

    def export(self, app_id: str) -> dict[str, Any]:
        """Export existing app manifest."""
        data = self.post("apps.manifest.export", {"app_id": app_id})
        manifest = manifest_from_api(data.get("manifest"))
        return {**data, "manifest": manifest}
