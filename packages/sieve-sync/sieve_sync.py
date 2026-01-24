#!/usr/bin/env python3
"""
sieve-sync: Sieve script synchronization with mail server

Usage:
    sieve-sync [pull|push|sync]

Commands:
    pull     Download sieve from server (not implemented yet)
    push     Upload sieve to server
    sync     Full sync: pull + push (default)
"""

import argparse
import subprocess
import sys
from pathlib import Path

SIEVE_DIR = Path.home() / ".local/share/sieve"
CATEGORIES = ["dev", "research", "university", "finance", "social", "notifications"]


# =============================================================================
# Server Sync
# =============================================================================


def sieve_pull() -> bool:
    """Download sieve scripts from server (placeholder)."""
    print("Pull from server not implemented yet.")
    print("Sieve files are managed locally in ~/.local/share/sieve/")
    return True


def sieve_push() -> bool:
    """Upload sieve scripts to server."""
    print("Pushing sieve to server...")

    server = "mail.mulatta.io"
    user = "seungwon"

    # Check rbw vault
    result = subprocess.run(["rbw", "unlocked"], capture_output=True)
    if result.returncode != 0:
        print("  ! rbw vault is locked, please unlock first: rbw unlock")
        return False

    # Get password
    result = subprocess.run(
        ["rbw", "get", "mulatta.io", "--field", "password"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        result = subprocess.run(
            ["rbw", "get", "mail.mulatta.io"],
            capture_output=True,
            text=True,
        )
    if result.returncode != 0 or not result.stdout.strip():
        print("  ! Could not get password from rbw")
        return False
    password = result.stdout.strip()

    # Upload each category sieve file
    success = True
    for category in CATEGORIES:
        sieve_path = SIEVE_DIR / f"{category}.sieve"
        if not sieve_path.exists():
            continue

        print(f"  Uploading {category}.sieve...")
        result = subprocess.run(
            [
                "sieve-connect",
                "--server", server,
                "--port", "4190",
                "--user", user,
                "--passwordfd", "0",
                "--localsieve", str(sieve_path),
                "--remotesieve", category,
                "--upload",
            ],
            input=password,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"    Failed: {result.stderr}")
            success = False

    # Upload and activate default.sieve
    default_sieve = SIEVE_DIR / "default.sieve"
    if default_sieve.exists():
        print("  Uploading default.sieve...")
        result = subprocess.run(
            [
                "sieve-connect",
                "--server", server,
                "--port", "4190",
                "--user", user,
                "--passwordfd", "0",
                "--localsieve", str(default_sieve),
                "--remotesieve", "default",
                "--upload",
            ],
            input=password,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"    Failed: {result.stderr}")
            success = False
        else:
            print("  Activating default script...")
            result = subprocess.run(
                [
                    "sieve-connect",
                    "--server", server,
                    "--port", "4190",
                    "--user", user,
                    "--passwordfd", "0",
                    "--remotesieve", "default",
                    "--activate",
                ],
                input=password,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                print(f"    Activation failed: {result.stderr}")
                success = False

    if success:
        print("  Sieve uploaded successfully")
    return success


# =============================================================================
# Main
# =============================================================================


def main() -> int:
    parser = argparse.ArgumentParser(description="Sieve synchronization tool")
    parser.add_argument(
        "command",
        nargs="?",
        default="sync",
        choices=["pull", "push", "sync"],
        help="Command to run (default: sync)",
    )
    args = parser.parse_args()

    if args.command == "pull":
        success = sieve_pull()
    elif args.command == "push":
        success = sieve_push()
    elif args.command == "sync":
        sieve_pull()
        success = sieve_push()

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
