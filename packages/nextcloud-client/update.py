#!/usr/bin/env python3
"""Update nextcloud-client from GitHub releases."""

import json
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen

GITHUB_API = "https://api.github.com/repos/nextcloud-releases/desktop/releases/latest"


def get_latest_version() -> str:
    """Get latest release version."""
    with urlopen(GITHUB_API) as resp:
        data = json.loads(resp.read())
    return data["tag_name"].lstrip("v")


def prefetch_github(owner: str, repo: str, tag: str) -> str:
    """Get SRI hash for a GitHub archive."""
    url = f"https://github.com/{owner}/{repo}/archive/refs/tags/{tag}.tar.gz"
    result = subprocess.run(
        ["nix-prefetch-url", "--unpack", "--type", "sha256", url],
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
    # Only replace the src hash (first occurrence after fetchFromGitHub)
    text = re.sub(
        r'(owner = "nextcloud-releases";\s+repo = "desktop";\s+tag = "v\$\{version\}";\s+hash = ")[^"]+"',
        rf'\g<1>{sri_hash}"',
        text,
    )
    nix_file.write_text(text)


def main():
    pkg_dir = Path(__file__).parent
    nix_file = pkg_dir / "default.nix"

    current = re.search(r'version = "([^"]+)";', nix_file.read_text())
    current_version = current.group(1) if current else "unknown"

    version = get_latest_version()

    if current_version == version:
        print("Already up to date")
        return

    print(f"Updating {current_version} -> {version}")
    print("Fetching source hash...")

    sri_hash = prefetch_github("nextcloud-releases", "desktop", f"v{version}")
    update_nix_file(nix_file, version, sri_hash)
    print("Updated default.nix")


if __name__ == "__main__":
    main()
