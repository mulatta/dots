#!/usr/bin/env python3
"""
merge-when-green - PR workflow for jujutsu

Features:
- Auto-formatting with jmt before push
- Rebase merge with auto-delete branch
- CI monitoring with real-time status
- Rebase all local branches after merge
- Auto branch: merge-when-green-<user> when no bookmark exists
"""

import argparse
import json
import os
import subprocess
import sys
import time
from typing import Any


class Colors:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    GRAY = "\033[90m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def print_info(msg: str) -> None:
    print(msg)


def print_success(msg: str) -> None:
    print(f"{Colors.GREEN}{msg}{Colors.RESET}")


def print_warning(msg: str) -> None:
    print(f"{Colors.YELLOW}{msg}{Colors.RESET}")


def print_error(msg: str) -> None:
    print(f"{Colors.RED}{msg}{Colors.RESET}")


def print_header(msg: str) -> None:
    print(f"\n{Colors.BOLD}{msg}{Colors.RESET}")


def run(
    cmd: list[str], check: bool = True, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    """Run a command."""
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, cmd)
        return result
    return subprocess.run(cmd, check=check, text=True)


def get_default_branch() -> str:
    """Get default branch from GitHub."""
    result = run(
        ["gh", "repo", "view", "--json", "defaultBranchRef", "--jq", ".defaultBranchRef.name"],
        capture=True,
        check=False,
    )
    return result.stdout.strip() or "main"


def get_current_bookmark(default_branch: str = "main") -> str | None:
    """Get bookmark pointing to @ or @-. Prefer merge-when-green-* pattern."""
    for rev in ["@", "@-"]:
        result = run(
            ["jj", "log", "-r", rev, "--no-graph", "-T", "bookmarks"],
            capture=True,
            check=False,
        )
        if result.returncode != 0 or not result.stdout.strip():
            continue

        # Filter out remote bookmarks (containing @) and default branch
        # Strip trailing * from diverged bookmarks
        bookmarks = [
            b.rstrip("*") for b in result.stdout.strip().split()
            if "@" not in b and b.rstrip("*") != default_branch
        ]
        if not bookmarks:
            continue

        # Prefer merge-when-green-* pattern (reusable branch)
        for b in bookmarks:
            if b.startswith("merge-when-green-"):
                return b

        # Multiple bookmarks: warn and use first
        if len(bookmarks) > 1:
            print_warning(f"Multiple bookmarks: {', '.join(bookmarks)}. Using: {bookmarks[0]}")

        return bookmarks[0]

    return None


def is_commit_empty(rev: str) -> bool:
    """Check if a commit has no changes (empty)."""
    result = run(
        ["jj", "log", "-r", rev, "--no-graph", "-T", "empty"],
        capture=True,
        check=False,
    )
    return result.stdout.strip() == "true"


def has_conflict(rev: str) -> bool:
    """Check if a commit has conflicts."""
    result = run(
        ["jj", "log", "-r", rev, "--no-graph", "-T", "conflict"],
        capture=True,
        check=False,
    )
    return result.stdout.strip() == "true"


def get_description(rev: str) -> str:
    """Get first line of commit description."""
    result = run(
        ["jj", "log", "-r", rev, "--no-graph", "-T", "description.first_line()"],
        capture=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def validate_state() -> None:
    """Check for unsupported states before proceeding."""
    # Conflict check
    if has_conflict("@"):
        print_error("@ has conflicts. Resolve with: jj resolve")
        sys.exit(1)

    # Empty check (both @ and @-)
    if is_commit_empty("@") and is_commit_empty("@-"):
        print_error("No changes to push. Create a commit first.")
        sys.exit(1)


def get_target_revision(title_provided: bool = False) -> str:
    """Get the revision to use for PR."""
    desc = get_description("@")
    empty = is_commit_empty("@")

    if desc:
        return "@"

    if not empty:
        if title_provided:
            return "@"
        print_error(
            "@ has changes but no description.\n"
            "Options:\n"
            "  1. jj describe -m 'your message'\n"
            "  2. merge-when-green --title 'your title'"
        )
        sys.exit(1)

    return "@-"


def get_or_create_bookmark(default_branch: str = "main", title_provided: bool = False) -> str:
    """Get existing bookmark or create merge-when-green-<user>."""
    # 1. Check for existing bookmark (prefers merge-when-green-*)
    current = get_current_bookmark(default_branch)
    if current:
        return current

    # 2. No bookmark → use merge-when-green-<user>
    name = f"merge-when-green-{os.environ.get('USER', 'user')}"
    rev = get_target_revision(title_provided=title_provided)

    # Use 'set' to create or move the bookmark
    run(["jj", "bookmark", "set", name, "-r", rev], check=False)
    return name


def sync_repo(default_branch: str) -> None:
    """Fetch and rebase onto latest default branch."""
    print_header("Syncing repository...")
    run(["jj", "git", "fetch"])
    run(["jj", "rebase", "-d", f"{default_branch}@origin"], check=False)
    print_success("Synced")


def run_format_check() -> bool:
    """Run jmt for formatting."""
    print_header("Checking formatting...")
    result = run(["jmt"], check=False, capture=True)
    if result.returncode != 0:
        print_error("jmt failed")
        if result.stderr:
            print_error(result.stderr.strip())
        return False
    print_success("Formatting OK")
    return True


def has_changes(default_branch: str) -> bool:
    """Check if there are changes to merge."""
    result = run(
        ["jj", "log", "-r", f"{default_branch}@origin..@", "--no-graph", "-T", "commit_id"],
        capture=True,
    )
    commits = [line for line in result.stdout.strip().split("\n") if line.strip()]
    return len(commits) > 0


def push_bookmark(bookmark: str, rev: str = "@") -> bool:
    """Push bookmark to origin. Resolves divergence if needed."""
    print_header("Pushing...")

    # Force set bookmark to resolve any divergence (local wins)
    run(["jj", "bookmark", "set", bookmark, "-r", rev, "-B"], check=False)

    result = run(
        ["jj", "git", "push", "--bookmark", bookmark, "--allow-new"],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        print_error(f"Push failed: {result.stderr}")
        return False
    print_success("Pushed")
    return True


def pr_exists(bookmark: str) -> bool:
    """Check if PR exists for this bookmark."""
    result = run(
        ["gh", "pr", "view", bookmark, "--json", "state"],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        return False
    try:
        data = json.loads(result.stdout)
        return data.get("state") == "OPEN"
    except json.JSONDecodeError:
        return False


def create_pr(bookmark: str, title: str | None = None) -> bool:
    """Create PR."""
    # Use commit description as title if not provided
    if not title:
        title = get_description(get_target_revision(title_provided=False))
    if not title:
        title = bookmark

    print_header(f"Creating PR: {title}")
    result = run(
        [
            "gh", "pr", "create",
            "--fill",
            "--title", title,
            "--head", bookmark,
        ],
        check=False,
    )
    if result.returncode != 0:
        print_error("PR creation failed")
        return False
    print_success("PR created")
    return True


def enable_auto_merge(bookmark: str) -> bool:
    """Enable auto-merge with rebase strategy."""
    print_info("Enabling auto-merge (rebase)...")
    result = run(
        ["gh", "pr", "merge", bookmark, "--auto", "--rebase", "--delete-branch"],
        check=False,
    )
    if result.returncode != 0:
        print_warning("Could not enable auto-merge")
        return False
    print_success("Auto-merge enabled")
    return True


def get_pr_status(bookmark: str) -> dict[str, Any] | None:
    """Get PR status from GitHub."""
    result = run(
        [
            "gh", "pr", "view", bookmark,
            "--json", "state,mergeable,autoMergeRequest,statusCheckRollup",
        ],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def count_checks(checks: list[dict[str, Any]]) -> tuple[int, int, int]:
    """Count check states: (passed, failed, pending)."""
    passed = failed = pending = 0
    for check in checks:
        if check.get("__typename") == "CheckRun":
            status = check.get("status")
            conclusion = check.get("conclusion")
            if status != "COMPLETED":
                pending += 1
            elif conclusion in ["SUCCESS", "NEUTRAL", "SKIPPED"]:
                passed += 1
            else:
                failed += 1
        elif check.get("__typename") == "StatusContext":
            state = check.get("state")
            if state == "PENDING":
                pending += 1
            elif state in ["SUCCESS", "NEUTRAL"]:
                passed += 1
            else:
                failed += 1
    return passed, failed, pending


def wait_for_merge(bookmark: str) -> bool:
    """Wait for PR to be merged."""
    print_header(f"Waiting for PR '{bookmark}' to merge...")

    while True:
        pr_data = get_pr_status(bookmark)
        if not pr_data:
            print_error("Failed to get PR status")
            return False

        state = pr_data.get("state", "")

        if state == "MERGED":
            return True

        if state == "CLOSED":
            print_error("PR was closed without merging")
            return False

        if not pr_data.get("autoMergeRequest"):
            print_error("Auto-merge was disabled")
            return False

        if pr_data.get("mergeable") == "CONFLICTING":
            print_error("PR has merge conflicts")
            return False

        checks = pr_data.get("statusCheckRollup", [])
        passed, failed, pending = count_checks(checks)

        status_line = (
            f"[{time.strftime('%H:%M:%S')}] "
            f"{Colors.GREEN}Passed: {passed}{Colors.RESET}, "
            f"{Colors.RED}Failed: {failed}{Colors.RESET}, "
            f"{Colors.YELLOW}Pending: {pending}{Colors.RESET}"
        )
        print(status_line)

        if failed > 0 and pending == 0:
            print_error(f"\n{failed} checks failed")
            return False

        time.sleep(10)


def rebase_all_branches(default_branch: str) -> None:
    """Rebase all local mutable branches onto new default branch."""
    print_header("Rebasing all branches...")
    run(["jj", "git", "fetch"])

    result = run(
        [
            "jj", "rebase",
            "-s", f"roots({default_branch}@origin..) & mutable()",
            "-d", f"{default_branch}@origin",
        ],
        check=False,
    )
    if result.returncode == 0:
        print_success("All branches rebased")
    else:
        print_warning("Some branches may need manual rebase")


def delete_bookmark(bookmark: str) -> None:
    """Delete local bookmark after merge."""
    run(["jj", "bookmark", "delete", bookmark], check=False)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create PR and merge when CI passes (jujutsu workflow)"
    )
    parser.add_argument(
        "--no-wait", action="store_true",
        help="Don't wait for CI checks to complete"
    )
    parser.add_argument(
        "--title", "-t",
        help="PR title (default: commit message)"
    )
    args = parser.parse_args()

    default_branch = get_default_branch()
    print_info(f"Target: {Colors.BOLD}{default_branch}{Colors.RESET}")

    # 0. Validate state
    validate_state()

    # 1. Sync
    sync_repo(default_branch)

    # 2. Format check
    if not run_format_check():
        return 1

    # 3. Check for changes
    if not has_changes(default_branch):
        print_success("No changes to merge")
        return 0

    # 4. Get or create bookmark
    title_provided = bool(args.title)
    bookmark = get_or_create_bookmark(default_branch, title_provided=title_provided)
    target_rev = get_target_revision(title_provided=title_provided)
    print_info(f"Using bookmark: {bookmark}")

    # 5. Push (resolves divergence if any)
    if not push_bookmark(bookmark, rev=target_rev):
        return 1

    # 6. Create PR or use existing
    if pr_exists(bookmark):
        print_success("PR already exists")
    else:
        if not create_pr(bookmark, args.title):
            return 1

    # 7. Enable auto-merge (rebase strategy)
    pr_data = get_pr_status(bookmark)
    merged = pr_data and pr_data.get("state") == "MERGED"

    if merged:
        print_success("PR already merged!")
    else:
        enable_auto_merge(bookmark)

        # 8. Wait for merge
        if not args.no_wait:
            if not wait_for_merge(bookmark):
                return 1
            print_success("\nPR merged!")
            merged = True
        else:
            # Re-check if PR was instantly merged
            pr_data = get_pr_status(bookmark)
            merged = pr_data and pr_data.get("state") == "MERGED"

    # 9. Cleanup and rebase
    if merged:
        delete_bookmark(bookmark)
    rebase_all_branches(default_branch)
    print_success("Done!")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print_warning("\nInterrupted")
        sys.exit(130)
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
