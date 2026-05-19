#!/usr/bin/env python3
"""Update dbml-cli from npm registry."""

import json
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen

NPM_REGISTRY = "https://registry.npmjs.org/@dbml/cli/latest"


def get_latest_version() -> str:
    """Get latest version from npm registry."""
    with urlopen(NPM_REGISTRY) as resp:
        data = json.loads(resp.read())
    return data["version"]


def main():
    pkg_dir = Path(__file__).parent
    nix_file = pkg_dir / "default.nix"
    pkg_json = pkg_dir / "package.json"

    current = re.search(r'version = "([^"]+)";', nix_file.read_text())
    current_version = current.group(1) if current else "unknown"

    version = get_latest_version()

    if current_version == version:
        print("Already up to date")
        return

    print(f"Updating {current_version} -> {version}")

    # Update package.json
    pkg_data = json.loads(pkg_json.read_text())
    pkg_data["version"] = version
    pkg_data["dependencies"]["@dbml/cli"] = version
    pkg_json.write_text(json.dumps(pkg_data, indent=2) + "\n")

    # Regenerate package-lock.json
    subprocess.run(
        ["npm", "install", "--package-lock-only"],
        cwd=pkg_dir,
        check=True,
    )

    # Update version in default.nix
    text = nix_file.read_text()
    text = re.sub(r'version = "[^"]+";', f'version = "{version}";', text)
    # Reset npmDepsHash to trigger rebuild
    text = re.sub(
        r'npmDepsHash = "[^"]+";',
        'npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";',
        text,
    )
    nix_file.write_text(text)

    print("Updated package.json, package-lock.json, and default.nix")
    print("NOTE: Run nix build to get correct npmDepsHash")


if __name__ == "__main__":
    main()
