#!/usr/bin/env python3
"""Create a GitHub PR and wait for auto-merge."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


class Colors:
    BLUE = "\033[94m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    GRAY = "\033[90m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def print_info(message: str) -> None:
    print(message)


def print_success(message: str) -> None:
    print(f"{Colors.GREEN}{message}{Colors.RESET}")


def print_warning(message: str) -> None:
    print(f"{Colors.YELLOW}{message}{Colors.RESET}")


def print_error(message: str) -> None:
    print(f"{Colors.RED}{message}{Colors.RESET}")


def print_header(message: str) -> None:
    print(f"\n{Colors.BOLD}{message}{Colors.RESET}")


def print_subtle(message: str) -> None:
    print(f"{Colors.GRAY}{message}{Colors.RESET}")


def run(
    cmd: list[str], check: bool = True, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    """Run a command."""
    if capture:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
        if result.returncode != 0 and check:
            raise subprocess.CalledProcessError(result.returncode, cmd)
        return result
    return subprocess.run(cmd, check=check, text=True)


def get_default_branch() -> str:
    """Get the GitHub repository default branch."""
    result = run(
        [
            "gh",
            "repo",
            "view",
            "--json",
            "defaultBranchRef",
            "--jq",
            ".defaultBranchRef.name",
        ],
        check=False,
        capture=True,
    )
    return result.stdout.strip() or "main"


def get_remotes() -> list[str]:
    """Return configured git remote names."""
    result = run(["git", "remote"], check=False, capture=True)
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def get_upstream_remote() -> str:
    """Prefer upstream for comparing/fetching fork workflows."""
    remotes = get_remotes()
    return "upstream" if "upstream" in remotes else "origin"


def get_origin_owner() -> str | None:
    """Get the owner of origin for GitHub fork PR heads."""
    result = run(["git", "remote", "get-url", "origin"], check=False, capture=True)
    if result.returncode != 0:
        return None

    url = result.stdout.strip()
    match = re.match(r"(?:https?://|git@)[^/:]+[:/]([^/]+)/(.+?)(?:\.git)?$", url)
    if not match:
        return None
    return match.group(1)


def get_head_ref(branch: str) -> str:
    """Return a gh --head selector, including owner for fork workflows."""
    if "upstream" in get_remotes() and "origin" in get_remotes():
        owner = get_origin_owner()
        if owner:
            return f"{owner}:{branch}"
    return branch


def current_branch() -> str:
    """Return the current git branch name."""
    result = run(["git", "branch", "--show-current"], capture=True)
    branch = result.stdout.strip()
    if not branch:
        print_error("Detached HEAD is not supported. Create a branch first.")
        sys.exit(1)
    return branch


def branch_for_push(default_branch: str) -> str:
    """Use current branch, or a stable scratch branch when on default."""
    branch = current_branch()
    if branch == default_branch:
        return f"merge-when-green-{os.environ.get('USER', 'user')}"
    return branch


def run_format_check() -> bool:
    """Run flake-fmt for formatting."""
    print_header("Checking formatting...")
    result = run(["flake-fmt"], check=False, capture=True)
    if result.returncode != 0:
        print_error("flake-fmt failed")
        if result.stderr:
            print_error(result.stderr.strip())
        return False
    print_success("Formatting OK")
    return True


def prepare_repository(default_branch: str, upstream_remote: str) -> int:
    """Update from base branch and run formatting."""
    print_header("Preparing changes...")
    run(
        [
            "git",
            "-c",
            "submodule.recurse=false",
            "pull",
            "--rebase",
            upstream_remote,
            default_branch,
        ]
    )
    run(["git", "submodule", "update", "--init", "--recursive"], check=False)

    if not run_format_check():
        if shutil.which("git-absorb"):
            print_warning("Attempting to absorb formatting changes...")
            run(
                [
                    "git",
                    "absorb",
                    "--force",
                    "--and-rebase",
                    "--base",
                    f"{upstream_remote}/{default_branch}",
                ],
                check=False,
            )
        if sys.stdin.isatty() and sys.stdout.isatty() and shutil.which("lazygit"):
            run(["lazygit"], check=False)
        return 1

    result = run(
        ["git", "diff", "--quiet", f"{upstream_remote}/{default_branch}"], check=False
    )
    if result.returncode == 0:
        print_success("No changes to merge")
        return 1
    return 0


def get_pr_message_from_editor(
    default_branch: str, upstream_remote: str
) -> tuple[str, str]:
    """Get PR title/body by editing commit messages from the branch."""
    commits = run(
        [
            "git",
            "log",
            "--reverse",
            "--pretty=format:%s%n%n%b%n%n",
            f"{upstream_remote}/{default_branch}..HEAD",
        ],
        capture=True,
    ).stdout

    with tempfile.NamedTemporaryFile(
        mode="w+", suffix="_COMMIT_EDITMSG", delete=False
    ) as handle:
        handle.write(commits)
        handle.flush()
        editor = os.environ.get("EDITOR", "vim")
        subprocess.run([editor, handle.name], check=True)
        handle.seek(0)
        message = handle.read()
    Path(handle.name).unlink()

    lines = message.split("\n", 1)
    return lines[0], lines[1] if len(lines) > 1 else ""


def get_pr_message(
    message_arg: str | None, default_branch: str, upstream_remote: str
) -> tuple[str, str]:
    """Get PR title and body from --message or editor."""
    if message_arg:
        lines = message_arg.split("\n", 1)
        return lines[0], lines[1] if len(lines) > 1 else ""
    return get_pr_message_from_editor(default_branch, upstream_remote)


def push_branch(branch_name: str) -> None:
    """Push HEAD to origin branch."""
    print_header("Pushing changes...")
    run(["git", "push", "--force-with-lease", "origin", f"HEAD:{branch_name}"])
    print_success("Pushed")


def pr_exists(branch: str) -> bool:
    """Check whether an open PR exists for branch."""
    result = run(
        ["gh", "pr", "view", get_head_ref(branch), "--json", "state"],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        return False
    try:
        return json.loads(result.stdout).get("state") == "OPEN"
    except json.JSONDecodeError:
        return False


def create_pr(branch: str, default_branch: str, title: str, body: str) -> str:
    """Create a GitHub PR and enable auto-merge."""
    print_header("Creating pull request...")
    result = run(
        [
            "gh",
            "pr",
            "create",
            "--title",
            title,
            "--body",
            body,
            "--base",
            default_branch,
            "--head",
            get_head_ref(branch),
        ],
        check=False,
    )
    if result.returncode != 0:
        print_warning("PR creation failed, likely already exists")
    print_success("Pull request ready")
    return branch


def enable_auto_merge(branch: str) -> bool:
    """Enable GitHub auto-merge using rebase strategy."""
    print_info("Enabling auto-merge...")
    result = run(
        ["gh", "pr", "merge", get_head_ref(branch), "--auto", "--rebase"], check=False
    )
    if result.returncode != 0:
        print_warning("Could not enable auto-merge")
        return False
    print_success("Auto-merge enabled")
    return True


def get_pr_status(branch: str) -> dict[str, Any] | None:
    """Get GitHub PR status."""
    result = run(
        [
            "gh",
            "pr",
            "view",
            get_head_ref(branch),
            "--json",
            "number,state,mergeable,autoMergeRequest,statusCheckRollup,url",
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
    """Count check states as passed, failed, pending."""
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


def get_merge_queue_status(pr_number: int) -> tuple[bool, str | None]:
    """Return GitHub merge queue membership and a display label."""
    repo = run(
        ["gh", "repo", "view", "--json", "owner,name"], check=False, capture=True
    )
    if repo.returncode != 0:
        return False, None
    try:
        repo_data = json.loads(repo.stdout)
        owner = repo_data["owner"]["login"]
        name = repo_data["name"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return False, None

    query = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              isInMergeQueue
              mergeQueueEntry { state position }
            }
          }
        }
    """
    result = run(
        [
            "gh",
            "api",
            "graphql",
            "-f",
            f"query={query}",
            "-F",
            f"owner={owner}",
            "-F",
            f"name={name}",
            "-F",
            f"number={pr_number}",
        ],
        check=False,
        capture=True,
    )
    if result.returncode != 0:
        return False, None
    try:
        data = json.loads(result.stdout)["data"]["repository"]["pullRequest"]
    except (json.JSONDecodeError, KeyError, TypeError):
        return False, None

    in_queue = bool(data.get("isInMergeQueue"))
    entry = data.get("mergeQueueEntry") or {}
    label = None
    if in_queue and entry:
        state = entry.get("state", "")
        position = entry.get("position")
        label = f"queue pos {position}, {state}" if position is not None else state
    return in_queue, label


def run_buildbot_check_if_needed(
    pr_data: dict[str, Any], failed: int, pending: int, buildbot_check_done: bool
) -> bool:
    """Run buildbot-pr-check once when all checks have settled with failures."""
    if failed > 0 and pending == 0 and not buildbot_check_done:
        pr_url = pr_data.get("url", "")
        if pr_url and shutil.which("buildbot-pr-check"):
            print_warning("\n🔍 Running buildbot-pr-check for failure details...")
            run(["buildbot-pr-check", pr_url], check=False)
            print()
        return True
    return buildbot_check_done


def wait_for_merge(branch: str) -> bool:
    """Wait until the PR has merged or reached a terminal failure."""
    print_header(f"Waiting for PR '{branch}' to merge...")

    buildbot_check_done = False
    while True:
        pr_data = get_pr_status(branch)
        if not pr_data:
            print_error("Failed to get PR status")
            return False

        checks = pr_data.get("statusCheckRollup", [])
        passed, failed, pending = count_checks(checks)
        in_merge_queue, queue_label = get_merge_queue_status(
            int(pr_data.get("number", 0))
        )

        queue_suffix = (
            f" {Colors.BLUE}[merge queue: {queue_label}]{Colors.RESET}"
            if in_merge_queue
            else ""
        )
        print(
            f"[{time.strftime('%H:%M:%S')}] "
            f"{Colors.GREEN}Passed: {passed}{Colors.RESET}, "
            f"{Colors.RED}Failed: {failed}{Colors.RESET}, "
            f"{Colors.YELLOW}Pending: {pending}{Colors.RESET}"
            f"{queue_suffix}"
        )

        buildbot_check_done = run_buildbot_check_if_needed(
            pr_data, failed, pending, buildbot_check_done
        )

        state = pr_data.get("state", "")
        if state == "MERGED":
            return True
        if state == "CLOSED":
            print_error("PR was closed without merging")
            return False
        # GitHub clears autoMergeRequest after a PR enters the merge queue.
        if not pr_data.get("autoMergeRequest") and not in_merge_queue:
            print_error("Auto-merge was disabled")
            return False
        if pr_data.get("mergeable") == "CONFLICTING":
            print_error("PR has merge conflicts")
            return False
        if failed > 0 and pending == 0:
            print_error(f"\n{failed} checks failed")
            return False

        time.sleep(10)


def finalize_merge(branch: str, default_branch: str, upstream_remote: str) -> int:
    """Wait for merge and rebase local branch onto the updated base."""
    if not wait_for_merge(branch):
        return 1

    print_success("\nPR merged!")
    run(["git", "fetch", upstream_remote, default_branch])
    run(["git", "rebase", f"{upstream_remote}/{default_branch}"])
    print_success("Rebased onto latest changes")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Create PR and merge when CI passes")
    parser.add_argument(
        "--no-wait", action="store_true", help="Don't wait for CI checks to complete"
    )
    parser.add_argument(
        "-m", "--message", help="PR title and body, separated by newline"
    )
    args = parser.parse_args()

    print_subtle("Detected GitHub")
    default_branch = get_default_branch()
    upstream_remote = get_upstream_remote()
    print_info(f"Target: {Colors.BOLD}{default_branch}@{upstream_remote}{Colors.RESET}")

    if prepare_repository(default_branch, upstream_remote) != 0:
        return 1

    branch = branch_for_push(default_branch)
    push_branch(branch)

    if pr_exists(branch):
        print_success("Using existing pull request")
    else:
        title, body = get_pr_message(args.message, default_branch, upstream_remote)
        create_pr(branch, default_branch, title, body)

    pr_data = get_pr_status(branch)
    if pr_data and pr_data.get("state") == "MERGED":
        print_success("PR already merged!")
        return 0

    enable_auto_merge(branch)
    if not args.no_wait:
        return finalize_merge(branch, default_branch, upstream_remote)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print_warning("\nInterrupted")
        sys.exit(130)
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
