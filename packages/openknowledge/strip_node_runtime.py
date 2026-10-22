"""Remove the known pnpm Node runtime layout, refusing unreviewed changes."""

import argparse
import json
import re
from pathlib import Path
from typing import Any


def strip_node_runtime(
    package: dict[str, Any], lock: str
) -> tuple[dict[str, Any], str]:
    engines = package.get("devEngines")
    if not isinstance(engines, dict):
        raise TypeError("expected a devEngines object")
    runtime = engines.get("runtime")
    if not isinstance(runtime, dict) or runtime.get("name") != "node":
        raise ValueError("expected devEngines.runtime to describe Node")
    version = runtime.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("expected an exact Node runtime version")
    if set(runtime) != {"name", "version", "onFail"} or runtime["onFail"] != "download":
        raise ValueError("upstream Node runtime policy changed")
    escaped = re.escape(version)

    # Preserve the rest of the lockfile byte-for-byte. Only the reviewed pnpm
    # layout is accepted; a new layout must not silently retain runtime downloads.
    for section, pattern in [
        (
            "importers",
            (
                rf"^      node:\n        specifier: runtime:{escaped}\n"
                rf"        version: runtime:{escaped}\n"
            ),
        ),
        (
            "packages",
            (rf"^  node@runtime:{escaped}:\n" r"(?:(?:    [^\n]*|)\n)+"),
        ),
        ("snapshots", rf"^  node@runtime:{escaped}: \{{\}}\n(?:\n)*"),
    ]:
        sections = list(
            re.finditer(
                rf"^{section}:\n(.*?)(?=^\S|\Z)", lock, re.MULTILINE | re.DOTALL
            )
        )
        if len(sections) != 1:
            raise ValueError(f"expected one {section} section")
        match = sections[0]
        body, count = re.subn(pattern, "", match[1], flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"expected one Node runtime entry in {section}")
        lock = lock[: match.start(1)] + body + lock[match.end(1) :]
    if re.search(r"(?<![\w-])runtime:", lock):
        raise ValueError("unhandled runtime references remain in pnpm-lock.yaml")

    # Validate everything before touching either input file or caller data.
    package = dict(package)
    package["devEngines"] = {
        key: value for key, value in engines.items() if key != "runtime"
    }
    if not package["devEngines"]:
        del package["devEngines"]
    return package, lock


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    manifest = args.directory / "package.json"
    lockfile = args.directory / "pnpm-lock.yaml"
    package, lock = strip_node_runtime(
        json.loads(manifest.read_text()), lockfile.read_text()
    )
    manifest.write_text(json.dumps(package, indent=2) + "\n")
    lockfile.write_text(lock)


if __name__ == "__main__":
    main()
