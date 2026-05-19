#!/usr/bin/env python3
"""Update quarkdown from GitHub releases."""

import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.request import urlopen

GITHUB_API = "https://api.github.com/repos/iamgio/quarkdown/releases/latest"
PLACEHOLDER_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def get_latest_version() -> str:
    """Get latest release version from GitHub."""
    with urlopen(GITHUB_API) as resp:
        data = json.loads(resp.read())
    return data["tag_name"].lstrip("v")


def nix_prefetch_url(url: str) -> str:
    """Get SRI hash for an archive URL."""
    result = subprocess.run(
        ["nix-prefetch-url", "--unpack", "--type", "sha256", url],
        capture_output=True,
        text=True,
        check=True,
    )
    result = subprocess.run(
        [
            "nix",
            "hash",
            "convert",
            "--hash-algo",
            "sha256",
            "--to",
            "sri",
            result.stdout.strip(),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def main():
    pkg_dir = Path(__file__).parent
    nix_file = pkg_dir / "default.nix"
    content = nix_file.read_text()

    match = re.search(r'version = "([^"]+)"', content)
    if not match:
        sys.exit("Error: could not find version in default.nix")
    current_version = match.group(1)

    latest_version = get_latest_version()
    print(f"  Current: {current_version}, Latest: {latest_version}")

    if current_version == latest_version:
        print("  Already up to date")
        return

    print(f"  Updating {current_version} -> {latest_version}")

    # Update version
    content = content.replace(
        f'version = "{current_version}"',
        f'version = "{latest_version}"',
    )

    # Set src hash to placeholder (updater framework will fix via nix build)
    content = re.sub(
        r'(url = "https://github.com/iamgio/quarkdown/releases/download/v\$\{finalAttrs\.version\}/quarkdown\.zip";\s*hash = ")([^"]+)(")',
        rf"\g<1>{PLACEHOLDER_HASH}\g<3>",
        content,
    )

    nix_file.write_text(content)
    print("  Updated default.nix")


if __name__ == "__main__":
    main()
