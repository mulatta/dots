#!/usr/bin/env python3
"""Update pinned Neko Chromium image from latest GitHub release."""

import json
import re
import subprocess
from http.client import HTTPSConnection
from pathlib import Path
from typing import Any

GITHUB_HOST = "api.github.com"
GITHUB_PATH = "/repos/m1k1o/neko/releases/latest"
IMAGE_NAME = "ghcr.io/m1k1o/neko/chromium"


def fetch_latest_release() -> dict[str, Any]:
    """Fetch latest Neko release metadata."""
    connection = HTTPSConnection(GITHUB_HOST, timeout=30)
    try:
        connection.request(
            "GET",
            GITHUB_PATH,
            headers={"User-Agent": "dots-neko-image-updater"},
        )
        response = connection.getresponse()
        if response.status != 200:
            raise RuntimeError(f"GitHub release request failed: HTTP {response.status}")
        result: dict[str, Any] = json.loads(response.read())
        return result
    finally:
        connection.close()


def get_latest_version() -> str:
    """Return latest release version without tag prefix."""
    return str(fetch_latest_release()["tag_name"]).removeprefix("v")


def get_current_version(nix_file: Path) -> str:
    """Read pinned final image tag from package expression."""
    match = re.search(r'finalImageTag = "([^"]+)";', nix_file.read_text())
    if match is None:
        raise RuntimeError(f"finalImageTag not found in {nix_file}")
    return match.group(1)


def prefetch_image(version: str) -> dict[str, str]:
    """Resolve registry digest and Nix docker archive hash."""
    result = subprocess.run(
        [
            "nix-prefetch-docker",
            "--image-name",
            IMAGE_NAME,
            "--image-tag",
            version,
            "--final-image-tag",
            version,
            "--os",
            "linux",
            "--arch",
            "amd64",
            "--json",
            "--quiet",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    data: dict[str, str] = json.loads(result.stdout)
    if data.get("imageName") != IMAGE_NAME:
        raise RuntimeError("prefetch returned unexpected image name")
    for field in ("imageDigest", "hash"):
        if not data.get(field):
            raise RuntimeError(f"prefetch result lacks {field}")
    return data


def replace_assignment(text: str, field: str, value: str) -> str:
    """Replace exactly one quoted Nix assignment."""
    result, count = re.subn(
        rf'({re.escape(field)} = ")[^"]+(";)',
        rf"\g<1>{value}\g<2>",
        text,
    )
    if count != 1:
        raise RuntimeError(f"expected one {field} assignment, found {count}")
    return result


def update_nix_file(nix_file: Path, version: str, image: dict[str, str]) -> None:
    """Update tag, immutable registry digest, and archive hash together."""
    text = nix_file.read_text()
    text = replace_assignment(text, "imageDigest", image["imageDigest"])
    text = replace_assignment(text, "hash", image["hash"])
    text = replace_assignment(text, "finalImageTag", version)
    nix_file.write_text(text)


def main() -> None:
    nix_file = Path(__file__).parent / "default.nix"
    current_version = get_current_version(nix_file)
    version = get_latest_version()

    if current_version == version:
        print("Already up to date")
        return

    print(f"Updating {current_version} -> {version}")
    image = prefetch_image(version)
    update_nix_file(nix_file, version, image)
    print(f"Updated to version {version}")


if __name__ == "__main__":
    main()
