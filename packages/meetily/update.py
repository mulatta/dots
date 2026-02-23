#!/usr/bin/env python3
"""Update meetily from GitHub releases."""

import json
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen

GITHUB_API = "https://api.github.com/repos/Zackriya-Solutions/meeting-minutes/releases/latest"
DMG_PATTERN = "meetily_{version}_aarch64.dmg"


def get_latest_release() -> tuple[str, str]:
    """Get latest version and DMG download URL."""
    with urlopen(GITHUB_API) as resp:
        data = json.loads(resp.read())

    version = data["tag_name"].lstrip("v")

    dmg_name = DMG_PATTERN.format(version=version)
    for asset in data["assets"]:
        if asset["name"] == dmg_name:
            return version, asset["browser_download_url"]

    raise RuntimeError(f"DMG asset not found: {dmg_name}")


def nix_prefetch_url(url: str) -> str:
    """Get SRI hash for a URL."""
    result = subprocess.run(
        ["nix-prefetch-url", "--type", "sha256", url],
        capture_output=True,
        text=True,
        check=True,
    )
    result = subprocess.run(
        ["nix", "hash", "convert", "--hash-algo", "sha256", "--to", "sri",
         result.stdout.strip()],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def update_nix_file(nix_file: Path, version: str, sri_hash: str) -> None:
    """Update version and hash in default.nix."""
    text = nix_file.read_text()
    text = re.sub(r'version = "[^"]+";', f'version = "{version}";', text)
    text = re.sub(r'hash = "[^"]+";', f'hash = "{sri_hash}";', text)
    nix_file.write_text(text)


def main():
    pkg_dir = Path(__file__).parent
    nix_file = pkg_dir / "default.nix"

    current = re.search(r'version = "([^"]+)";', nix_file.read_text())
    current_version = current.group(1) if current else "unknown"

    version, url = get_latest_release()

    if current_version == version:
        print("Already up to date")
        return

    print(f"Updating {current_version} -> {version}")
    print(f"Fetching hash for {url}...")

    sri_hash = nix_prefetch_url(url)
    update_nix_file(nix_file, version, sri_hash)
    print(f"Updated default.nix")


if __name__ == "__main__":
    main()
