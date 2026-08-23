#!/usr/bin/env python3
"""Update OpenLogi from its latest signed macOS release."""

import json
import subprocess
import urllib.request
from pathlib import Path
from typing import Any

GITHUB_API = "https://api.github.com/repos/AprilNEA/OpenLogi/releases/latest"


def fetch_latest_release() -> dict[str, Any]:
    """Fetch latest GitHub release metadata."""
    request = urllib.request.Request(
        GITHUB_API,
        headers={"User-Agent": "dots-openlogi-updater"},
    )
    with urllib.request.urlopen(request) as response:  # noqa: S310
        result: dict[str, Any] = json.load(response)
        return result


def get_latest_release() -> tuple[str, str]:
    """Return latest version and Apple Silicon DMG URL."""
    release = fetch_latest_release()
    version = str(release["tag_name"]).removeprefix("v")
    asset_name = f"OpenLogi-v{version}-macos-arm64.dmg"

    for asset in release["assets"]:
        if asset["name"] == asset_name:
            return version, str(asset["browser_download_url"])

    raise RuntimeError(f"release asset not found: {asset_name}")


def get_nix_hash(url: str) -> str:
    """Prefetch URL and return its SRI hash."""
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        capture_output=True,
        text=True,
        check=True,
    )
    data: dict[str, str] = json.loads(result.stdout)
    return data["hash"]


def main() -> None:
    pkg_dir = Path(__file__).parent
    srcs_file = pkg_dir / "srcs.json"
    current: dict[str, str] = json.loads(srcs_file.read_text())
    version, url = get_latest_release()

    if current.get("version") == version:
        print("Already up to date")
        return

    print(f"Updating {current.get('version', 'unknown')} -> {version}")
    hash_value = get_nix_hash(url)
    srcs_file.write_text(
        json.dumps(
            {"version": version, "url": url, "hash": hash_value},
            indent=2,
        )
        + "\n"
    )
    print(f"Updated to version {version}")


if __name__ == "__main__":
    main()
