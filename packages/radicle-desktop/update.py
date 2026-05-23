#!/usr/bin/env python3
"""Update radicle-desktop by mirroring the macOS DMG to GitHub releases."""

import json
import os
import subprocess
import tempfile
import urllib.request
from pathlib import Path

LATEST_JSON_URL = (
    "https://files.radicle.xyz/releases/radicle-desktop/latest/latest.json"
)
LATEST_DMG_URL = "https://files.radicle.xyz/releases/radicle-desktop/latest/radicle-desktop-aarch64.dmg"
MIRROR_REPO = os.environ.get("RADICLE_DESKTOP_MIRROR_REPO", "mulatta/dots")
RELEASE_TAG = "radicle-desktop-mirror"


def read_srcs(pkg_dir: Path) -> dict[str, str]:
    """Read current srcs.json."""
    srcs_file = pkg_dir / "srcs.json"
    if srcs_file.exists():
        result: dict[str, str] = json.loads(srcs_file.read_text())
        return result
    return {}


def write_srcs(pkg_dir: Path, data: dict[str, str]) -> None:
    """Write srcs.json with consistent formatting."""
    (pkg_dir / "srcs.json").write_text(json.dumps(data, indent=2) + "\n")


def get_latest_version() -> dict[str, str]:
    """Fetch latest Radicle Desktop release metadata."""
    with urllib.request.urlopen(LATEST_JSON_URL) as response:  # noqa: S310
        result: dict[str, str] = json.loads(response.read().decode())
        return result


def get_nix_hash(url: str) -> str:
    """Get SRI hash for a URL with Nix."""
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", url],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(result.stdout)
    return data["hash"]


def run_gh(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    """Run GitHub CLI against mirror repo."""
    return subprocess.run(
        ["gh", *args, "--repo", MIRROR_REPO],
        capture_output=True,
        text=True,
        check=check,
    )


def mirror_to_github(version: str, sha: str) -> str:
    """Mirror latest DMG under a versioned GitHub release asset name."""
    filename = f"radicle-desktop-{version}-aarch64.dmg"

    with tempfile.TemporaryDirectory() as tmpdir:
        local_path = Path(tmpdir) / filename
        print(f"Downloading {LATEST_DMG_URL}...")
        urllib.request.urlretrieve(LATEST_DMG_URL, local_path)  # noqa: S310

        body = json.dumps({"version": version, "sha": sha})
        release_exists = run_gh(["release", "view", RELEASE_TAG], check=False)

        if release_exists.returncode == 0:
            run_gh(["release", "edit", RELEASE_TAG, "--notes", body])
        else:
            run_gh(
                [
                    "release",
                    "create",
                    RELEASE_TAG,
                    "--title",
                    "Radicle Desktop Mirror",
                    "--notes",
                    body,
                ]
            )

        print("Uploading to GitHub release...")
        run_gh(["release", "upload", RELEASE_TAG, str(local_path), "--clobber"])

    return (
        f"https://github.com/{MIRROR_REPO}/releases/download/{RELEASE_TAG}/{filename}"
    )


def main() -> None:
    pkg_dir = Path(__file__).parent
    current = read_srcs(pkg_dir)

    print("Fetching latest radicle-desktop version...")
    latest = get_latest_version()
    version = latest["version"]
    sha = latest["sha"]
    print(f"Latest version: {version} ({sha[:8]})")

    if current.get("version") == version:
        print("Already up to date")
        return

    url = mirror_to_github(version, sha)
    print(f"Mirrored to: {url}")

    print("Fetching hash...")
    hash_value = get_nix_hash(url)

    write_srcs(pkg_dir, {"version": version, "url": url, "hash": hash_value})
    print(f"Updated to version {version}")


if __name__ == "__main__":
    main()
