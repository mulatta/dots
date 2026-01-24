#!/usr/bin/env python3
"""
sync-sieve: Bidirectional sieve synchronization with mail server

Usage:
    sync-sieve [pull|push|suggest|sync] [--yes]

Commands:
    pull     Download sieve from server (not implemented yet)
    push     Upload sieve to server
    suggest  Process pending suggestions
    sync     Full sync: suggest + push (default)

Options:
    --yes, -y    Auto-approve suggestions (non-interactive)
"""

import argparse
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

SIEVE_DIR = Path.home() / ".local/share/sieve"
DB_PATH = SIEVE_DIR / "suggestions.db"
THRESHOLD = 3

CATEGORIES = ["dev", "research", "university", "finance", "social", "notifications"]
FOLDER_MAP = {
    "dev": ".Dev",
    "research": ".Research",
    "university": ".University",
    "finance": ".Finance",
    "social": ".Social",
    "notifications": ".Notifications",
}


# =============================================================================
# Database
# =============================================================================


def init_db() -> None:
    """Initialize suggestions database."""
    SIEVE_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS suggestions (
            id INTEGER PRIMARY KEY,
            domain TEXT NOT NULL,
            target_folder TEXT NOT NULL,
            message_ids TEXT DEFAULT '[]',
            count INTEGER DEFAULT 1,
            first_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            applied INTEGER DEFAULT 0,
            UNIQUE(domain, target_folder)
        )
    """)
    conn.commit()
    conn.close()


def get_pending_suggestions() -> list[tuple[int, str, str, int]]:
    """Get suggestions that meet threshold and not yet applied."""
    if not DB_PATH.exists():
        return []

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.execute(
        """
        SELECT id, domain, target_folder, count
        FROM suggestions
        WHERE count >= ? AND applied = 0
        ORDER BY target_folder, count DESC
        """,
        (THRESHOLD,),
    )
    results = cursor.fetchall()
    conn.close()
    return results


def mark_applied(suggestion_ids: list[int]) -> None:
    """Mark suggestions as applied."""
    if not suggestion_ids:
        return

    conn = sqlite3.connect(DB_PATH)
    conn.executemany(
        "UPDATE suggestions SET applied = 1 WHERE id = ?",
        [(id,) for id in suggestion_ids],
    )
    conn.commit()
    conn.close()


# =============================================================================
# Sieve File Management
# =============================================================================


def parse_sieve_domains(sieve_path: Path) -> list[str]:
    """Extract domains from a sieve file."""
    if not sieve_path.exists():
        return []

    content = sieve_path.read_text()
    pattern = r'header\s+:contains\s+"from"\s+"([^"]+)"'
    return re.findall(pattern, content, re.IGNORECASE)


def add_domain_to_sieve(domain: str, category: str) -> tuple[bool, bool]:
    """Add a domain to category sieve file.

    Returns:
        (success, should_mark_applied): success indicates if domain was added,
        should_mark_applied indicates if suggestion should be marked as applied.
    """
    sieve_path = SIEVE_DIR / f"{category}.sieve"

    if not sieve_path.exists():
        print(f"  ! {category}.sieve not found, skipping")
        return False, False  # Don't mark as applied - might be config issue

    content = sieve_path.read_text()
    domains = parse_sieve_domains(sieve_path)

    # Check if already exists
    if domain in domains:
        print(f"  - {domain} already in {category}.sieve")
        return False, True  # Mark as applied - already done

    # Find the keep-sorted end marker
    marker = "# keep-sorted end"
    if marker not in content:
        print(f"  ! No keep-sorted marker in {category}.sieve, skipping")
        return False, False

    # Find the line before the marker and add comma if needed
    lines = content.split("\n")
    marker_idx = None
    for i, line in enumerate(lines):
        if marker in line:
            marker_idx = i
            break

    if marker_idx is None or marker_idx == 0:
        print(f"  ! Invalid sieve structure in {category}.sieve, skipping")
        return False, False

    # Find the last non-empty line before marker (the last condition)
    prev_idx = marker_idx - 1
    while prev_idx >= 0 and not lines[prev_idx].strip():
        prev_idx -= 1

    if prev_idx < 0:
        print(f"  ! No conditions found in {category}.sieve, skipping")
        return False, False

    # Add comma to the previous line if it doesn't have one
    prev_line = lines[prev_idx]
    if not prev_line.rstrip().endswith(","):
        lines[prev_idx] = prev_line.rstrip() + ","

    # Insert new domain line before the marker (without trailing comma)
    new_line = f'    header :contains "from" "{domain}"'
    lines.insert(marker_idx, new_line)

    content = "\n".join(lines)
    sieve_path.write_text(content)
    return True, True


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
# Suggestion Processing
# =============================================================================


def process_suggestions(auto_yes: bool = False) -> bool:
    """Process pending suggestions interactively or automatically."""
    suggestions = get_pending_suggestions()

    if not suggestions:
        print("No pending suggestions.")
        return False

    print("\n=== Pending Sieve Suggestions ===")
    for i, (id, domain, folder, count) in enumerate(suggestions, 1):
        print(f"  [{i}] {domain} -> {folder} ({count}x)")

    if auto_yes:
        confirm = True
        print("\nAuto-approving (--yes flag)")
    else:
        try:
            response = input("\nApply these suggestions? [y/N]: ")
            confirm = response.lower() in ("y", "yes")
        except (EOFError, KeyboardInterrupt):
            print("\nSkipped.")
            return False

    if not confirm:
        print("Skipped.")
        return False

    applied_ids = []
    has_changes = False
    for id, domain, folder, count in suggestions:
        added, should_mark = add_domain_to_sieve(domain, folder)
        if should_mark:
            applied_ids.append(id)
        if added:
            has_changes = True
            print(f"  + {folder}.sieve: {domain}")

    if applied_ids:
        mark_applied(applied_ids)

    return has_changes


# =============================================================================
# Main
# =============================================================================


def main() -> int:
    parser = argparse.ArgumentParser(description="Sieve synchronization tool")
    parser.add_argument(
        "command",
        nargs="?",
        default="sync",
        choices=["pull", "push", "suggest", "sync"],
        help="Command to run (default: sync)",
    )
    parser.add_argument(
        "--yes", "-y", action="store_true", help="Auto-approve suggestions"
    )
    args = parser.parse_args()

    init_db()

    if args.command == "pull":
        success = sieve_pull()

    elif args.command == "push":
        success = sieve_push()

    elif args.command == "suggest":
        has_changes = process_suggestions(args.yes)
        if has_changes:
            success = sieve_push()
        else:
            success = True

    elif args.command == "sync":
        # sync = suggest + push (if changes)
        has_changes = process_suggestions(args.yes)
        if has_changes:
            success = sieve_push()
        else:
            success = True

    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
