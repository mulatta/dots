#!/usr/bin/env python3
"""Regenerate rsshub's vendored pnpm-lock.yaml and pnpmDeps hash.

rsshub is consumed from nixpkgs via overrideAttrs (see ./default.nix); we
inject two extra npm dependencies (playwright-extra + a stealth plugin) used
by the custom routes under ./routes. pnpm requires the lockfile to be
consistent with package.json, so whenever nixpkgs bumps rsshub the lockfile
has to be re-resolved against the new package.json. This script automates
that: it takes nixpkgs' current rsshub source, applies the same package.json
edit the Nix build performs, runs `pnpm install --lockfile-only`, and writes
the resulting lockfile plus the matching fetchPnpmDeps hash back into this
directory.

Run it whenever the rsshub build fails on a stale lockfile:

    python3 packages/rsshub/update.py

Requires network access (queries the npm registry).
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOTS = HERE.parents[1]
LOCKFILE = HERE / "pnpm-lock.yaml"
DEFAULT_NIX = HERE / "default.nix"

# Extra dependencies injected into rsshub's package.json. Keep in sync with the
# substituteInPlace insertion in ./default.nix (same names and specifiers).
EXTRA_DEPS: dict[str, str] = {
    "playwright-extra": "^4.3.6",
    "puppeteer-extra-plugin-stealth": "^2.11.2",
}

# package.json line to anchor the insertion after. Must match the
# --replace-fail anchor in ./default.nix so the generated lockfile is
# consistent with what the Nix build produces.
ANCHOR = '"dependencies": {'

NIXPKGS_EXPR = (
    f"(import (builtins.getFlake (toString {DOTS})).inputs.nixpkgs "
    "{ system = builtins.currentSystem; })"
)


def run(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    print(f"$ {' '.join(cmd)}", file=sys.stderr)
    return subprocess.run(
        cmd,
        text=True,
        check=True,
        cwd=cwd,
        env=env,
        capture_output=capture_output,
    )


def realise_rsshub_src() -> Path:
    out = (
        run(
            [
                "nix",
                "build",
                "--no-link",
                "--print-out-paths",
                "--impure",
                "--expr",
                f"{NIXPKGS_EXPR}.rsshub.src",
            ],
            capture_output=True,
        )
        .stdout.strip()
        .splitlines()[-1]
    )
    return Path(out)


def inject_deps(package_json: Path) -> None:
    lines = package_json.read_text().splitlines(keepends=True)
    if any(f'"{name}"' in "".join(lines) for name in EXTRA_DEPS):
        return
    for i, line in enumerate(lines):
        if ANCHOR in line:
            indent = line[: len(line) - len(line.lstrip())]
            additions = [
                f'{indent}"{name}": "{spec}",\n' for name, spec in EXTRA_DEPS.items()
            ]
            lines[i + 1 : i + 1] = additions
            package_json.write_text("".join(lines))
            return
    raise SystemExit(f"anchor {ANCHOR!r} not found in {package_json}")


def regenerate_lockfile(src: Path) -> str:
    """Resolve the lockfile for src + injected deps and return its contents."""
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "rsshub"
        shutil.copytree(src, work)
        # store paths are read-only; make the whole tree writable so pnpm can
        # create its temp files and rewrite the lockfile.
        for p in (work, *work.rglob("*")):
            p.chmod(0o755 if p.is_dir() else 0o644)
        inject_deps(work / "package.json")
        run(
            [
                "nix",
                "shell",
                "--impure",
                "--expr",
                f"with {NIXPKGS_EXPR}; [ pnpm_10 nodejs ]",
                "-c",
                "pnpm",
                "install",
                "--lockfile-only",
                "--no-frozen-lockfile",
            ],
            cwd=work,
            env={"HOME": tmp, "PATH": _path()},
        )
        return (work / "pnpm-lock.yaml").read_text()


def _path() -> str:
    import os

    return os.environ.get("PATH", "/usr/bin:/bin")


def update_hash() -> None:
    fake = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    text = DEFAULT_NIX.read_text()
    DEFAULT_NIX.write_text(re.sub(r'hash = "sha256-[^"]*"', f'hash = "{fake}"', text))
    proc = subprocess.run(
        [
            "nix",
            "build",
            "--no-link",
            "--impure",
            "--expr",
            f"({NIXPKGS_EXPR}.callPackage {HERE} {{}}).pnpmDeps",
        ],
        text=True,
        capture_output=True,
    )
    got = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", proc.stderr)
    if not got:
        DEFAULT_NIX.write_text(text)
        raise SystemExit(f"could not parse hash from:\n{proc.stderr}")
    real = got.group(1)
    DEFAULT_NIX.write_text(re.sub(r'hash = "sha256-[^"]*"', f'hash = "{real}"', text))
    print(f"pnpmDeps hash = {real}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed lockfile is stale instead of rewriting it; "
        "a regression guard for rsshub version bumps",
    )
    args = parser.parse_args()

    src = realise_rsshub_src()
    print(f"rsshub src: {src}", file=sys.stderr)
    fresh = regenerate_lockfile(src)

    if args.check:
        current = LOCKFILE.read_text() if LOCKFILE.exists() else ""
        if fresh != current:
            print(
                f"STALE: {LOCKFILE.name} does not match a fresh resolve against "
                "the current nixpkgs rsshub; run update.py to regenerate.",
                file=sys.stderr,
            )
            raise SystemExit(1)
        print(f"{LOCKFILE.name} is up to date", file=sys.stderr)
        return

    LOCKFILE.write_text(fresh)
    print(f"wrote {LOCKFILE}", file=sys.stderr)
    update_hash()
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
