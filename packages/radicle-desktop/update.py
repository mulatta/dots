#!/usr/bin/env python3
"""Update radicle-desktop from Radicle seed node."""

import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import urlopen

RADICLE_API = "https://seed.radicle.xyz/api/v1/repos/rad:z4D5UCArafTzTQpDZNQRuqswh3ury"


def get_latest_commit() -> tuple[str, int]:
    """Get latest commit hash and timestamp."""
    url = f"{RADICLE_API}/commits?perPage=1"
    with urlopen(url) as resp:
        data = json.loads(resp.read())[0]
    return data["id"], data["committer"]["time"]


def nix_prefetch_git(url: str, rev: str) -> str:
    """Get hash for git repo using nix-prefetch-git."""
    result = subprocess.run(
        ["nix-prefetch-git", "--quiet", "--url", url, "--rev", rev],
        capture_output=True,
        text=True,
        check=True,
    )
    data = json.loads(result.stdout)
    return data["hash"]


def main():
    pkg_dir = Path(__file__).parent
    srcs_file = pkg_dir / "srcs.json"

    current = json.loads(srcs_file.read_text()) if srcs_file.exists() else {}

    rev, timestamp = get_latest_commit()
    dt = datetime.fromtimestamp(timestamp, tz=timezone.utc)
    version = f"0-unstable-{dt.strftime('%Y-%m-%d')}"

    if current.get("rev") == rev:
        print("Already up to date")
        return

    print(f"Updating to {rev} ({version})")

    # Fetch source hash
    src_url = "https://seed.radicle.xyz/z4D5UCArafTzTQpDZNQRuqswh3ury.git"
    print("Fetching source hash...")
    src_hash = nix_prefetch_git(src_url, rev)

    # npmDepsHash needs to be computed via nix build (manual for now)
    npm_hash = current.get(
        "npmDepsHash", "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    )

    srcs_file.write_text(
        json.dumps(
            {
                "version": version,
                "rev": rev,
                "srcHash": src_hash,
                "npmDepsHash": npm_hash,
            },
            indent=2,
        )
        + "\n"
    )

    print("Updated srcs.json")
    print("NOTE: Run nix build to compute npmDepsHash if source changed")


if __name__ == "__main__":
    main()
