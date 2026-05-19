#!/usr/bin/env python3
"""Update chartdb from GitHub releases."""

import json
import subprocess
import tarfile
import tempfile
from pathlib import Path
from urllib.request import urlopen, urlretrieve

GITHUB_API = "https://api.github.com/repos/chartdb/chartdb/releases/latest"


def get_latest_version() -> str:
    """Get latest release version."""
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


def prefetch_npm_deps(source_url: str) -> str:
    """Download source, extract, and compute npmDepsHash via prefetch-npm-deps."""
    with tempfile.TemporaryDirectory() as tmpdir:
        tarball = Path(tmpdir) / "source.tar.gz"
        urlretrieve(source_url, tarball)

        with tarfile.open(tarball) as tf:
            tf.extractall(tmpdir)

        # GitHub archives extract to <repo>-<version>/
        extracted = [
            p for p in Path(tmpdir).iterdir() if p.is_dir() and p.name != "__MACOSX"
        ]
        if len(extracted) != 1:
            raise RuntimeError(f"Expected 1 extracted dir, got {len(extracted)}")
        src_dir = extracted[0]

        lock_file = src_dir / "package-lock.json"
        if not lock_file.exists():
            raise RuntimeError(f"No package-lock.json in {src_dir}")

        result = subprocess.run(
            ["prefetch-npm-deps", str(lock_file)],
            capture_output=True,
            text=True,
            check=True,
        )
        return result.stdout.strip()


def main():
    pkg_dir = Path(__file__).parent
    srcs_file = pkg_dir / "srcs.json"

    current = json.loads(srcs_file.read_text())
    current_version = current.get("version", "unknown")

    version = get_latest_version()
    url = f"https://github.com/chartdb/chartdb/archive/refs/tags/v{version}.tar.gz"

    version_changed = current_version != version

    if version_changed:
        print(f"Updating {current_version} -> {version}")
        src_hash = nix_prefetch_url(url)
    else:
        src_hash = current["srcHash"]

    # Always verify npmDepsHash (catches registry-side changes)
    print("Verifying npmDepsHash...")
    npm_hash = prefetch_npm_deps(url)
    old_npm_hash = current.get("npmDepsHash", "")

    if not version_changed and npm_hash == old_npm_hash:
        print("Already up to date")
        return

    if npm_hash != old_npm_hash:
        print(f"npmDepsHash changed: {old_npm_hash[:20]}... -> {npm_hash[:20]}...")

    srcs_file.write_text(
        json.dumps(
            {
                "version": version,
                "srcHash": src_hash,
                "npmDepsHash": npm_hash,
            },
            indent=2,
        )
        + "\n"
    )

    print("Updated srcs.json")


if __name__ == "__main__":
    main()
