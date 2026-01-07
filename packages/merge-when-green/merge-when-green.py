#!/usr/bin/env python3
"""
merge-when-green - PR workflow for jujutsu

Features:
- Auto-formatting with jmt + jj fix before push
- Squash merge with auto-delete branch
- CI monitoring with real-time status
- Rebase all local branches after merge
"""

import argparse
import json
import os
import re
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


def get_current_bookmark() -> str | None:
    """Get bookmark pointing to current commit (@) or parent (@-) if @ is empty."""
    # Try @ first, then @- (after jj commit, @ is empty)
    for rev in ["@", "@-"]:
        result = run(["jj", "log", "-r", rev, "--no-graph", "-T", "bookmarks"], capture=True, check=False)
        if result.returncode != 0 or not result.stdout.strip():
            continue

        # Parse bookmarks, filter out remote tracking ones
        for bookmark in result.stdout.strip().split():
            if "@" not in bookmark:  # Skip remote bookmarks like "main@origin"
                return bookmark
    return None


def is_commit_empty(rev: str) -> bool:
    """Check if a commit has no changes (empty)."""
    result = run(
        ["jj", "log", "-r", rev, "--no-graph", "-T", "empty"],
        capture=True, check=False
    )
    return result.stdout.strip() == "true"


def get_description(rev: str) -> str:
    """Get first line of commit description."""
    result = run(
        ["jj", "log", "-r", rev, "--no-graph", "-T", "description.first_line()"],
        capture=True, check=False
    )
    return result.stdout.strip() if result.returncode == 0 else ""


class TargetRevisionError(Exception):
    """Raised when target revision cannot be determined."""
    pass


def get_target_revision(title_provided: bool = False) -> str:
    """Get the revision to use for PR.

    Logic:
    - @ has description → @
    - @ has changes but no description → error (unless --title provided)
    - @ is empty and has no description → @-

    Raises:
        TargetRevisionError: if @ has changes but no description and no --title
    """
    desc = get_description("@")
    empty = is_commit_empty("@")

    # @ has description → use @
    if desc:
        return "@"

    # @ has changes but no description
    if not empty:
        if title_provided:
            # --title provided, ok to proceed with @
            return "@"
        raise TargetRevisionError(
            "@ has changes but no description.\n"
            "Options:\n"
            "  1. jj describe -m 'your message'\n"
            "  2. merge-when-green --title 'your title'"
        )

    # @ is empty (no changes, no description) → use @-
    return "@-"


def create_bookmark(name: str | None = None, title_provided: bool = False) -> str:
    """Create bookmark from commit description if not provided."""
    rev = get_target_revision(title_provided=title_provided)

    if name:
        run(["jj", "bookmark", "create", name, "-r", rev])
        return name

    # Generate name from commit description or title
    desc = get_description(rev)

    # Convert to branch name: "feat(foo): bar baz" -> "feat-foo-bar-baz"
    name = re.sub(r"[^a-zA-Z0-9]+", "-", desc.lower()).strip("-")[:50]
    if not name:
        name = f"pr-{os.environ.get('USER', 'user')}"

    run(["jj", "bookmark", "create", name, "-r", rev])
    return name


def sync_repo(default_branch: str) -> None:
    """Fetch and rebase onto latest default branch."""
    print_header("Syncing repository...")
    run(["jj", "git", "fetch"])
    run(["jj", "rebase", "-d", f"{default_branch}@origin"], check=False)
    print_success("Synced")


def run_format_check() -> bool:
    """Run jmt for formatting (syncs config + runs jj fix)."""
    print_header("Checking formatting...")

    print_info("Running jmt...")
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
    # Filter out empty lines
    commits = [line for line in result.stdout.strip().split("\n") if line.strip()]
    return len(commits) > 0


def push_bookmark(bookmark: str) -> bool:
    """Push bookmark to origin."""
    print_header("Pushing...")
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


CONVENTIONAL_PREFIXES = {"feat", "fix", "chore", "docs", "refactor", "test", "ci", "perf", "style", "build"}


def bookmark_to_title(bookmark: str) -> str:
    """Convert bookmark name to PR title.

    feat/add-jmt → feat: add jmt
    fix/login-bug → fix: login bug
    feat-add-jmt → feat: add jmt
    add-jmt → add jmt
    """
    # Handle / separator
    if "/" in bookmark:
        prefix, rest = bookmark.split("/", 1)
        return f"{prefix}: {rest.replace('-', ' ')}"

    # Handle - separator with conventional prefix
    parts = bookmark.split("-", 1)
    if len(parts) == 2 and parts[0] in CONVENTIONAL_PREFIXES:
        return f"{parts[0]}: {parts[1].replace('-', ' ')}"

    return bookmark.replace("-", " ")


def create_pr(bookmark: str, title: str | None = None, dry_run: bool = False) -> bool:
    """Create PR with squash merge and auto-delete."""
    # Title: explicit > bookmark-derived
    if not title:
        title = bookmark_to_title(bookmark)

    print_header(f"Creating PR: {title}")

    if dry_run:
        print_warning("[dry-run] Would create PR (body from --fill)")
        return True

    result = run(
        [
            "gh", "pr", "create",
            "--fill",  # Body from commit messages
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
    """Enable auto-merge with squash strategy."""
    print_info("Enabling auto-merge (squash)...")
    result = run(
        ["gh", "pr", "merge", bookmark, "--auto", "--squash", "--delete-branch"],
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

        # Check auto-merge status
        if not pr_data.get("autoMergeRequest"):
            print_error("Auto-merge was disabled")
            return False

        # Check for conflicts
        if pr_data.get("mergeable") == "CONFLICTING":
            print_error("PR has merge conflicts")
            return False

        # Show CI status
        checks = pr_data.get("statusCheckRollup", [])
        passed, failed, pending = count_checks(checks)

        status_line = (
            f"[{time.strftime('%H:%M:%S')}] "
            f"{Colors.GREEN}Passed: {passed}{Colors.RESET}, "
            f"{Colors.RED}Failed: {failed}{Colors.RESET}, "
            f"{Colors.YELLOW}Pending: {pending}{Colors.RESET}"
        )
        print(status_line)

        # Check for failures
        if failed > 0 and pending == 0:
            print_error(f"\n{failed} checks failed")
            return False

        time.sleep(10)


def rebase_all_branches(default_branch: str) -> None:
    """Rebase all local mutable branches onto new default branch."""
    print_header("Rebasing all branches...")
    run(["jj", "git", "fetch"])

    # Rebase only mutable roots (excludes remote tracking branches)
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


def get_bookmark_commits(bookmark: str, default_branch: str) -> list[str]:
    """Get change IDs for commits in bookmark range."""
    result = run(
        ["jj", "log", "-r", f"{default_branch}@origin..{bookmark}",
         "--no-graph", "-T", 'change_id ++ "\n"'],
        capture=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return []
    return [cid for cid in result.stdout.strip().split("\n") if cid]


def abandon_merged_commits(change_ids: list[str]) -> None:
    """Abandon commits that were squash-merged into main."""
    if change_ids:
        print_info(f"Abandoning {len(change_ids)} merged commits...")
        run(["jj", "abandon"] + change_ids, check=False)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create PR and merge when CI passes (jujutsu workflow)"
    )
    parser.add_argument(
        "--no-wait", action="store_true",
        help="Don't wait for CI checks to complete"
    )
    parser.add_argument(
        "--no-format", action="store_true",
        help="Skip formatting check (jmt + jj fix)"
    )
    parser.add_argument(
        "--sync", "-s", action="store_true",
        help="Just sync (fetch + rebase all branches)"
    )
    parser.add_argument(
        "--title", "-t",
        help="PR title (default: commit message)"
    )
    parser.add_argument(
        "--bookmark", "-b",
        help="Bookmark name (default: auto-detect or create)"
    )
    parser.add_argument(
        "--dry-run", "-n", action="store_true",
        help="Show what would be done without making changes"
    )
    parser.add_argument(
        "--keep-commits", action="store_true",
        help="Don't abandon original commits after merge"
    )
    args = parser.parse_args()

    default_branch = get_default_branch()
    print_info(f"Target: {Colors.BOLD}{default_branch}{Colors.RESET}")

    # Sync only mode
    if args.sync:
        rebase_all_branches(default_branch)
        return 0

    # 1. Sync (skip in dry-run)
    if args.dry_run:
        print_warning("[dry-run] Would sync repository (fetch + rebase)")
    else:
        sync_repo(default_branch)

    # 2. Format check (skip in dry-run)
    if not args.no_format:
        if args.dry_run:
            print_warning("[dry-run] Would run format check (jmt)")
        elif not run_format_check():
            return 1

    # 3. Check for changes
    if not has_changes(default_branch):
        print_success("No changes to merge")
        return 0

    # 4. Get or create bookmark
    title_provided = bool(args.title)
    bookmark = args.bookmark or get_current_bookmark()
    created_bookmark = False
    if not bookmark:
        try:
            bookmark = create_bookmark(title_provided=title_provided)
            created_bookmark = True
        except TargetRevisionError as e:
            print_error(str(e))
            return 1
        print_info(f"Created bookmark: {bookmark}")
    else:
        print_info(f"Using bookmark: {bookmark}")

    # Dry-run: show what would happen, then cleanup
    if args.dry_run:
        # Show commits that will be pushed
        commits = get_bookmark_commits(bookmark, default_branch)
        print_header("Commits to push:")
        result = run(
            ["jj", "log", "-r", f"{default_branch}@origin..{bookmark}",
             "--no-graph", "-T", '"  " ++ change_id.shortest(8) ++ " " ++ description.first_line() ++ "\n"'],
            capture=True, check=False,
        )
        if result.stdout.strip():
            print(result.stdout.strip())

        print_warning(f"\n[dry-run] Would push bookmark: {bookmark}")
        create_pr(bookmark, args.title, dry_run=True)
        print_warning("[dry-run] Would enable auto-merge and wait")
        if args.keep_commits:
            print_info(f"[dry-run] Would keep {len(commits)} commits (--keep-commits)")
        else:
            print_warning(f"[dry-run] Would abandon {len(commits)} commits after merge")

        # Cleanup: delete temporarily created bookmark
        if created_bookmark:
            delete_bookmark(bookmark)
            print_info(f"Cleaned up temporary bookmark: {bookmark}")
        return 0

    # 5. Push
    if not push_bookmark(bookmark):
        return 1

    # Save commits for later cleanup (before merge)
    commits_to_abandon = get_bookmark_commits(bookmark, default_branch)

    # 6. Create PR or enable auto-merge on existing
    if pr_exists(bookmark):
        print_success("PR already exists")
    else:
        if not create_pr(bookmark, args.title, dry_run=False):
            return 1

    # 7. Check if already merged, otherwise enable auto-merge and wait
    pr_data = get_pr_status(bookmark)
    already_merged = pr_data and pr_data.get("state") == "MERGED"

    if already_merged:
        print_success("PR already merged!")
    else:
        enable_auto_merge(bookmark)

        # 8. Wait for merge
        if not args.no_wait:
            if not wait_for_merge(bookmark):
                return 1
            print_success("\nPR merged!")

    # 9. Cleanup and rebase all (always run after merge)
    if already_merged or not args.no_wait:
        delete_bookmark(bookmark)
        if not args.keep_commits:
            abandon_merged_commits(commits_to_abandon)
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
