#!/usr/bin/env python3
"""Update pinned edwardkim/rhwp source and all source-derived hashes."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import Any

import tomllib

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PIN_PATH = REPO_ROOT / "packages/rhwp/pin.json"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
GOT_HASH_RE = re.compile(r"got:\s+(sha256-[A-Za-z0-9+/=]+)")
SRI_HASH_RE = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")
SEMVER_TAG_RE = re.compile(
    r"v?(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"command failed with exit code {result.returncode}: {cmd}")
    return result


def is_release_ref(ref: str) -> bool:
    return (
        SEMVER_TAG_RE.fullmatch(ref) is not None
        or re.fullmatch(r"[0-9a-f]{40}", ref) is not None
    )


def require_release_ref(ref: str) -> str:
    if not is_release_ref(ref):
        raise RuntimeError(f"not a semantic-version tag or full commit hash: {ref!r}")
    return ref


def select_release_tag(latest_release: str, fallback_tags: Iterable[str]) -> str:
    if SEMVER_TAG_RE.fullmatch(latest_release):
        return latest_release
    for tag in fallback_tags:
        if SEMVER_TAG_RE.fullmatch(tag):
            return tag
    raise RuntimeError("GitHub returned no semantic-version tag")


def latest_tag() -> str:
    release = run(
        ["gh", "api", "repos/edwardkim/rhwp/releases/latest", "--jq", ".tag_name"],
        check=False,
    )
    latest_release = release.stdout.strip() if release.returncode == 0 else ""
    if SEMVER_TAG_RE.fullmatch(latest_release):
        return latest_release

    tags = run(
        ["gh", "api", "--paginate", "repos/edwardkim/rhwp/tags", "--jq", ".[].name"]
    )
    return select_release_tag(latest_release, tags.stdout.splitlines())


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise TypeError(f"expected a JSON object in {path}")
    return data


def save_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n")


def parse_prefetch_result(output: str) -> tuple[str, Path]:
    data = json.loads(output)
    hash_value = data.get("hash")
    store_path = data.get("storePath")
    if not isinstance(hash_value, str) or SRI_HASH_RE.fullmatch(hash_value) is None:
        raise RuntimeError("nix store prefetch-file returned invalid hash")
    if not isinstance(store_path, str):
        raise TypeError("nix store prefetch-file returned no store path")
    return hash_value, Path(store_path)


def prefetch_source(ref: str) -> tuple[str, Path, str]:
    if re.fullmatch(r"[0-9a-f]{40}", ref):
        rev = ref
        url = f"https://github.com/edwardkim/rhwp/archive/{ref}.tar.gz"
    else:
        rev = run(
            [
                "gh",
                "api",
                f"repos/edwardkim/rhwp/git/ref/tags/{ref}",
                "--jq",
                ".object.sha",
            ]
        ).stdout.strip()
        url = f"https://github.com/edwardkim/rhwp/archive/refs/tags/{ref}.tar.gz"
    result = run(["nix", "store", "prefetch-file", "--json", "--unpack", url])
    hash_value, store_path = parse_prefetch_result(result.stdout)
    return hash_value, store_path, rev


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as file:
        data = tomllib.load(file)
    if not isinstance(data, dict):
        raise TypeError(f"expected TOML object in {path}")
    return data


def read_package_version(path: Path) -> str:
    package = load_toml(path).get("package")
    version = package.get("version") if isinstance(package, dict) else None
    if not isinstance(version, str):
        raise TypeError(f"package.version not found in {path}")
    return version


def read_locked_package_version(path: Path, package_name: str) -> str:
    packages = load_toml(path).get("package")
    if not isinstance(packages, list):
        raise TypeError(f"package list not found in {path}")
    versions = [
        package.get("version")
        for package in packages
        if isinstance(package, dict) and package.get("name") == package_name
    ]
    if len(versions) != 1 or not isinstance(versions[0], str):
        raise RuntimeError(f"expected exactly one {package_name!r} package in {path}")
    return versions[0]


def iter_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for nested in value.values():
            yield from iter_strings(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from iter_strings(nested)


def assert_no_fake_hashes(*objects: dict[str, Any]) -> None:
    count = sum(value == FAKE_HASH for data in objects for value in iter_strings(data))
    if count:
        raise RuntimeError(f"metadata contains {count} unresolved fake hash(es)")


def parse_single_got_hash(output: str) -> str:
    matches: list[str] = GOT_HASH_RE.findall(output)
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one fixed-output 'got:' hash, found {len(matches)}"
        )
    return matches[0]


def refresh_cargo_hash(data: dict[str, Any]) -> None:
    assert_no_fake_hashes(data)
    data["cargoHash"] = FAKE_HASH
    save_json(SOURCE_PIN_PATH, data)
    result = run(["nix", "build", "--no-link", ".#rhwp"], check=False)
    combined = result.stdout + result.stderr
    if result.returncode == 0:
        raise RuntimeError(".#rhwp unexpectedly built with fake cargoHash")
    try:
        data["cargoHash"] = parse_single_got_hash(combined)
    except RuntimeError:
        sys.stderr.write(combined)
        raise
    save_json(SOURCE_PIN_PATH, data)


def refresh_nix_update_hashes() -> None:
    run(
        [
            "nix-update",
            "--flake",
            "--version",
            "skip",
            "--override-filename",
            "packages/rhwp/studio.nix",
            "rhwp.studio",
        ]
    )
    run(
        [
            "nix-update",
            "--flake",
            "--version",
            "skip",
            "--override-filename",
            "packages/rhwp/wasm-bindgen-cli.nix",
            "rhwp.wasm-bindgen-cli",
        ]
    )


def update(ref: str, *, force: bool = False) -> bool:
    ref = require_release_ref(ref)
    data = load_json(SOURCE_PIN_PATH)
    assert_no_fake_hashes(data)

    managed_paths = (
        SOURCE_PIN_PATH,
        REPO_ROOT / "packages/rhwp/studio.nix",
        REPO_ROOT / "packages/rhwp/wasm-bindgen-cli.nix",
    )
    originals = {path: path.read_text() for path in managed_paths}
    try:
        source_hash, source_path, rev = prefetch_source(ref)
        version = read_package_version(source_path / "Cargo.toml")
        wasm_bindgen_version = read_locked_package_version(
            source_path / "Cargo.lock", "wasm-bindgen"
        )
        if data.get("rev") == rev and not force:
            return False

        data.update(
            {
                "version": version,
                "rev": rev,
                "hash": source_hash,
                "wasmBindgenVersion": wasm_bindgen_version,
            }
        )
        save_json(SOURCE_PIN_PATH, data)
        refresh_cargo_hash(data)
        refresh_nix_update_hashes()
        assert_no_fake_hashes(load_json(SOURCE_PIN_PATH))
    except BaseException:
        for path, contents in originals.items():
            path.write_text(contents)
        raise
    return any(path.read_text() != originals[path] for path in managed_paths)


def write_output(key: str, value: str) -> None:
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a") as file:
            file.write(f"{key}={value}\n")
    else:
        print(f"output: {key}={value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ref",
        "--tag",
        dest="ref",
        help="rhwp tag or full commit hash, defaults to latest tag",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="refresh hashes even when ref is already pinned",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    old_version = str(load_json(SOURCE_PIN_PATH).get("version"))
    ref = require_release_ref(args.ref) if args.ref else latest_tag()
    changed = update(ref, force=args.force)
    new_version = str(load_json(SOURCE_PIN_PATH).get("version"))
    write_output("old_version", old_version)
    write_output("new_version", new_version)
    write_output("updated", str(changed).lower())


if __name__ == "__main__":
    main()
