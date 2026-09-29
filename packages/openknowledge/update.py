#!/usr/bin/env python3
"""Update OpenKnowledge from npm."""

import json
import re
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path
from typing import Any

NPM_METADATA = "https://registry.npmjs.org/@inkeep/open-knowledge/latest"
PLACEHOLDER_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="


def fetch_json(url: str) -> dict[str, Any]:
    """Fetch JSON from npm."""
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "dots-openknowledge-updater"},
    )
    with urllib.request.urlopen(request) as response:  # noqa: S310
        result: dict[str, Any] = json.load(response)
        return result


def prefetch(url: str) -> str:
    """Fetch source and return its Nix SRI hash."""
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        capture_output=True,
        text=True,
        check=True,
    )
    data: dict[str, str] = json.loads(result.stdout)
    return data["hash"]


def production_manifest(archive: Path) -> dict[str, Any]:
    """Extract package metadata needed for an offline production install."""
    with tarfile.open(archive, "r:gz") as tar:
        member = tar.getmember("package/package.json")
        source = tar.extractfile(member)
        if source is None:
            raise RuntimeError("package.json missing from npm archive")
        manifest: dict[str, Any] = json.load(source)
    manifest.pop("devDependencies", None)
    manifest.pop("scripts", None)
    return manifest


def update_nix_file(path: Path, version: str, source_hash: str) -> None:
    """Update package version and fixed-output hashes."""
    text = path.read_text()
    text = re.sub(r'version = "[^"]+";', f'version = "{version}";', text)
    text = re.sub(r'hash = "[^"]+";', f'hash = "{source_hash}";', text, count=1)
    text = re.sub(
        r'npmDepsHash = "[^"]+";',
        f'npmDepsHash = "{PLACEHOLDER_HASH}";',
        text,
    )
    path.write_text(text)


def main() -> None:
    package_dir = Path(__file__).parent
    nix_file = package_dir / "default.nix"
    metadata = fetch_json(NPM_METADATA)
    version = str(metadata["version"])
    current_match = re.search(r'version = "([^"]+)";', nix_file.read_text())
    current_version = current_match.group(1) if current_match else "unknown"

    if current_version == version:
        print("Already up to date")
        return

    url = str(metadata["dist"]["tarball"])
    print(f"Updating {current_version} -> {version}")

    with tempfile.TemporaryDirectory() as temporary_dir:
        temporary = Path(temporary_dir)
        archive = temporary / "package.tgz"
        urllib.request.urlretrieve(url, archive)  # noqa: S310
        manifest = production_manifest(archive)
        manifest_path = temporary / "package.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        subprocess.run(
            ["npm", "install", "--package-lock-only", "--ignore-scripts"],
            cwd=temporary,
            check=True,
        )
        (package_dir / "package.json").write_text(manifest_path.read_text())
        (package_dir / "package-lock.json").write_text(
            (temporary / "package-lock.json").read_text()
        )

    update_nix_file(nix_file, version, prefetch(url))
    print(f"Updated to version {version}")


if __name__ == "__main__":
    main()
