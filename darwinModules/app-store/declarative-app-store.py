"""Idempotently reconcile installed Mac App Store apps with a wanted list.

Adapted from Mic92/nix-config (MIT, Copyright (c) 2021 Jörg Thalheim):
  darwinModules/app-store/declarative-app-store.py
"""

import contextlib
import os
import subprocess
import sys


def mas(*args: str) -> bool:
    """Run mas and report success; a failed app must not abort activation."""
    maybe_sudo = ["sudo"] if os.geteuid() != 0 else []
    return subprocess.run([*maybe_sudo, "mas", *args], check=False).returncode == 0


def installed_apps() -> set[int] | None:
    ret = subprocess.run(
        ["mas", "list"], stdout=subprocess.PIPE, text=True, check=False
    )
    if ret.returncode != 0:
        return None
    installed: set[int] = set()
    for line in ret.stdout.splitlines():
        with contextlib.suppress(ValueError, IndexError):
            installed.add(int(line.split()[0]))
    return installed


def main() -> None:
    wanted = set(map(int, sys.argv[1:]))
    installed = installed_apps()
    if installed is None:
        print("warning: mas list failed; skipping App Store sync", file=sys.stderr)
        return

    failed: list[int] = []
    for store_id in sorted(installed - wanted):
        print(f"Removing App Store app {store_id}", file=sys.stderr)
        if not mas("uninstall", str(store_id)):
            failed.append(store_id)
    for store_id in sorted(wanted - installed):
        print(f"Installing App Store app {store_id}", file=sys.stderr)
        # install only covers apps this account already got; get also claims free apps.
        if not (mas("install", str(store_id)) or mas("get", str(store_id))):
            failed.append(store_id)

    if failed:
        print(
            f"warning: App Store sync failed for {' '.join(map(str, failed))}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
