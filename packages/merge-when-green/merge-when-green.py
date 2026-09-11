#!/usr/bin/env python3
"""
merge-when-green - Create PR and merge when CI passes
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from enum import Enum
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit

_gitea_api_url: str | None = None


class Colors:
    BLUE = "\033[94m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    GRAY = "\033[90m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


class Platform(Enum):
    GITHUB = "github"
    GITEA = "gitea"


def print_success(message: str) -> None:
    print(f"{Colors.GREEN}{message}{Colors.RESET}")


def print_error(message: str) -> None:
    print(f"{Colors.RED}{message}{Colors.RESET}")


def print_warning(message: str) -> None:
    print(f"{Colors.YELLOW}{message}{Colors.RESET}")


def print_header(message: str) -> None:
    print(f"\n{Colors.BOLD}{message}{Colors.RESET}")


def print_subtle(message: str) -> None:
    print(f"{Colors.GRAY}{message}{Colors.RESET}")


def run(
    cmd: list[str], check: bool = True, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    if capture:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
        if result.returncode != 0 and check:
            raise subprocess.CalledProcessError(result.returncode, cmd)
        return result
    return subprocess.run(cmd, check=check, text=True)


def detect_platform() -> Platform:
    api_url, _, _ = get_repo_info()
    host = urlsplit(api_url).hostname
    if host == "github.com":
        print_subtle("Detected GitHub")
        return Platform.GITHUB

    try:
        result = run(["tea", "logins", "list", "-o", "json"], check=False, capture=True)
    except FileNotFoundError:
        raise RuntimeError(f"No tea client available to identify {host}") from None
    if result.returncode != 0:
        raise RuntimeError("Could not read tea logins")
    remote = run(["git", "remote", "get-url", "origin"], capture=True).stdout.strip()
    global _gitea_api_url
    try:
        _gitea_api_url = select_gitea_url(
            json.loads(result.stdout),
            api_url,
            remote.startswith(("http://", "https://")),
        )
    except (ValueError, KeyError, TypeError, AttributeError):
        raise RuntimeError("Could not parse tea logins") from None
    print_subtle(f"Detected Gitea ({host})")
    return Platform.GITEA


def select_gitea_url(
    logins: list[dict[str, Any]], api_url: str, http_remote: bool
) -> str:
    """HTTP origins identify instances; SSH hosts map through tea configuration."""
    origin = urlsplit(api_url)
    urls = set()
    for login in logins:
        url = login["url"].rstrip("/")
        parsed = urlsplit(url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            raise RuntimeError("Invalid tea login URL")
        if http_remote:
            matches = (
                origin.scheme == parsed.scheme
                and origin.hostname == parsed.hostname
                and (origin.port or (443 if origin.scheme == "https" else 80))
                == (parsed.port or (443 if parsed.scheme == "https" else 80))
                and origin.path == parsed.path
            )
        else:
            matches = origin.hostname in (parsed.hostname, login.get("ssh_host"))
        if matches:
            urls.add(url)
    if len(urls) != 1:
        raise RuntimeError(
            f"Remote host {origin.hostname!r} needs an unambiguous tea login"
        )
    return urls.pop()


def get_default_branch(platform: Platform) -> str:
    if platform == Platform.GITHUB:
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
            capture=True,
        )
        return result.stdout.strip()

    branch = gitea_api("").get("default_branch")
    if not isinstance(branch, str) or not branch:
        raise RuntimeError("Gitea API returned no default branch")
    return branch


def get_repo_info() -> tuple[str, str, str]:
    """Parse origin; SSH ports are not HTTP API ports."""
    remote = run(["git", "remote", "get-url", "origin"], capture=True).stdout.strip()
    if "://" not in remote:
        match = re.fullmatch(r"(?:[^@/:]+@)?([^/:]+):(.+)", remote)
        if not match:
            raise RuntimeError(f"Could not parse remote URL: {remote}")
        host, path = match.groups()
        api_url = f"https://{host.lower()}"
    else:
        parsed = urlsplit(remote)
        if parsed.scheme not in ("http", "https", "ssh") or not parsed.hostname:
            raise RuntimeError("Unsupported origin URL")
        host = parsed.hostname
        authority = f"[{host}]" if ":" in host else host
        if parsed.scheme != "ssh" and parsed.port:
            authority += f":{parsed.port}"
        api_url = (
            f"{'https' if parsed.scheme == 'ssh' else parsed.scheme}://{authority}"
        )
        path = parsed.path.lstrip("/")
    parts = path.removesuffix(".git").split("/")
    if len(parts) != 2 or not all(parts):
        raise RuntimeError("Origin must specify owner/repository")
    return api_url, parts[0], parts[1]


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(
        self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str
    ) -> None:
        # Never forward repository credentials to a redirected origin.
        return None


def gitea_api(
    path: str, data: dict[str, Any] | None = None, *, expect_list: bool = False
) -> Any:
    """Use REST objects rather than tea's display-oriented PR output."""
    api_url, owner, repo = get_repo_info()
    token = os.environ.get("GITEA_TOKEN")
    if not token:
        raise RuntimeError("GITEA_TOKEN is required for Gitea")
    url = f"{_gitea_api_url or api_url}/api/v1/repos/{quote(owner, safe='')}/{quote(repo, safe='')}{path}"
    request = urllib.request.Request(
        url,
        data=json.dumps(data).encode() if data is not None else None,
        headers={"Authorization": f"token {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.build_opener(NoRedirects()).open(
            request, timeout=10
        ) as response:
            body = response.read()
            if not body and data is not None and path.endswith("/merge"):
                return None
            value = json.loads(body)
            if not isinstance(value, list if expect_list else dict):
                raise TypeError("Unexpected response type")
            if expect_list and any(not isinstance(item, dict) for item in value):
                raise TypeError("Unexpected list entry")
            return value
    except urllib.error.HTTPError as error:
        error.close()
        raise RuntimeError(f"Gitea API {path}: HTTP {error.code}") from None
    except (urllib.error.URLError, TimeoutError, ValueError, TypeError):
        raise RuntimeError(
            f"Gitea API {path}: request or JSON response failed"
        ) from None


def find_gitea_pr(branch: str, target: str | None = None) -> str | None:
    _, owner, repo = get_repo_info()
    page = 1
    while True:
        prs = gitea_api(f"/pulls?state=open&limit=50&page={page}", expect_list=True)
        if not prs:
            return None
        for pr in prs:
            head = pr.get("head") or {}
            head_repo = head.get("repo") or {}
            if (
                head.get("ref") == branch
                and head_repo.get("full_name") == f"{owner}/{repo}"
                and (target is None or pr.get("base", {}).get("ref") == target)
            ):
                return gitea_pr_number(pr)
        page += 1


def check_pr_exists(branch: str, platform: Platform, target: str | None = None) -> bool:
    if platform == Platform.GITHUB:
        result = run(
            ["gh", "pr", "view", branch, "--json", "state"],
            check=False,
            capture=True,
        )
        if result.returncode == 0:
            try:
                pr_data = json.loads(result.stdout)
                state = pr_data.get("state")
                return bool(state == "OPEN")
            except json.JSONDecodeError:
                pass
    else:
        return find_gitea_pr(branch, target) is not None
    return False


def create_pr_github(branch: str, target: str, title: str, body: str) -> str:
    """Create GitHub PR and enable auto-merge."""
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
            target,
            "--head",
            branch,
        ],
        check=False,
    )
    if result.returncode != 0:
        print_warning("PR creation failed, likely already exists")

    print_warning("Enabling auto-merge...")
    run(["gh", "pr", "merge", branch, "--auto", "--rebase"])
    print_success("✓ Auto-merge enabled")
    return branch


def gitea_pr_number(pr: dict[str, Any]) -> str:
    number = pr.get("number")
    if type(number) is not int or number <= 0:
        raise RuntimeError("Gitea API returned an invalid PR number")
    return str(number)


def gitea_head_sha(pr: dict[str, Any]) -> str:
    sha = (pr.get("head") or {}).get("sha")
    if not isinstance(sha, str) or not sha:
        raise RuntimeError("Gitea API returned no PR head SHA")
    return sha


def gitea_enable_automerge(pr_index: str) -> None:
    print_warning("Enabling auto-merge...")
    pr = gitea_api(f"/pulls/{pr_index}")
    sha = gitea_head_sha(pr)
    gitea_api(
        f"/pulls/{pr_index}/merge",
        {
            "do": "rebase",
            "head_commit_id": sha,
            "merge_when_checks_succeed": True,
            "delete_branch_after_merge": True,
        },
    )
    print_success("✓ Auto-merge enabled")


def create_pr_gitea(branch: str, target: str, title: str, body: str) -> str:
    pr = gitea_api(
        "/pulls", {"head": branch, "base": target, "title": title, "body": body}
    )
    pr_id = gitea_pr_number(pr)
    gitea_enable_automerge(pr_id)
    return pr_id


def check_gitea_pr_state(pr_id: str) -> bool | None:
    """Read the PR directly; fail once all reported commit checks settle."""
    pr = gitea_api(f"/pulls/{pr_id}")
    if pr.get("merged"):
        return True
    if pr.get("state") == "closed":
        print_error("PR was closed without merging")
        return False
    if pr.get("state") != "open":
        raise RuntimeError("Gitea API returned an invalid PR state")
    sha = quote(gitea_head_sha(pr), safe="")
    page = 1
    states: dict[str, str] = {}
    while True:
        result = gitea_api(f"/commits/{sha}/status?limit=50&page={page}")
        if "statuses" not in result:
            raise RuntimeError("Gitea API returned no commit statuses")
        statuses = result["statuses"] or []
        if not isinstance(statuses, list):
            raise TypeError("Invalid Gitea commit statuses")
        if not statuses:
            break
        for status in statuses:
            states.setdefault(status["context"], status["status"])
        page += 1
    pending = sum(
        state not in ("success", "skipped", "failure", "error", "warning")
        for state in states.values()
    )
    failed = sum(state in ("failure", "error", "warning") for state in states.values())
    if failed and not pending:
        print_error(f"{failed} checks failed")
        run_nixbot_log_if_needed(failed, pending, False)
        return False
    return None


def count_check_states(checks: list[dict[str, Any]]) -> tuple[int, int, int]:
    pending = failed = passed = 0
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
            check_state = check.get("state")
            if check_state == "PENDING":
                pending += 1
            elif check_state in ["SUCCESS", "NEUTRAL"]:
                passed += 1
            else:
                failed += 1
    return pending, failed, passed


def check_pr_completion(
    pr_data: dict[str, Any], pending: int, failed: int, *, in_merge_queue: bool
) -> tuple[bool, str] | None:
    """Check if PR has reached a completion state. Returns None if still waiting."""
    state = pr_data.get("state", "UNKNOWN")
    mergeable = pr_data.get("mergeable", "UNKNOWN")
    auto_merge = pr_data.get("autoMergeRequest") is not None

    if state == "MERGED":
        return True, "PR successfully merged!"

    if state == "CLOSED":
        return False, "PR was closed"

    # Once a PR enters the merge queue GitHub clears autoMergeRequest, so only
    # treat a missing autoMergeRequest as "disabled" when the PR is not queued.
    if not auto_merge and not in_merge_queue:
        return False, "Auto-merge was disabled"

    if mergeable == "CONFLICTING":
        return False, "PR has merge conflicts"

    if failed > 0 and pending == 0:
        return False, f"{failed} checks failed"

    return None  # still waiting


def get_pr_status_github(pr_id: str) -> tuple[dict[str, Any] | None, str]:
    result = run(
        [
            "gh",
            "pr",
            "view",
            pr_id,
            "--json",
            "number,state,mergeable,autoMergeRequest,statusCheckRollup,url",
        ],
        check=False,
        capture=True,
    )

    if result.returncode != 0:
        return None, "Failed to get PR status"

    try:
        pr_data = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None, "Failed to parse PR status"
    else:
        return pr_data, ""


def get_merge_queue_status_github(pr_number: int) -> tuple[bool, str | None]:
    """Query merge-queue membership via GraphQL.

    `gh pr view --json` does not expose isInMergeQueue, so we need a direct
    GraphQL call. Returns (is_in_queue, human_readable_position_or_None).
    """
    repo = run(
        ["gh", "repo", "view", "--json", "owner,name"], check=False, capture=True
    )
    if repo.returncode != 0:
        return False, None
    try:
        repo_data = json.loads(repo.stdout)
        owner = repo_data["owner"]["login"]
        name = repo_data["name"]
    except (json.JSONDecodeError, KeyError):
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
    desc = None
    if in_queue and entry:
        state = entry.get("state", "")
        pos = entry.get("position")
        desc = f"queue pos {pos}, {state}" if pos is not None else state
    return in_queue, desc


def run_nixbot_log_if_needed(failed: int, pending: int, nixbot_log_done: bool) -> bool:
    """Show CI failure logs via nbo (nixbot's CLI) once all checks finished."""
    if failed > 0 and pending == 0 and not nixbot_log_done:
        if shutil.which("nbo"):
            print_warning("\nRunning nbo log to get failure details...")
            run(["nbo", "log"], check=False)
            print()
        return True
    return nixbot_log_done


def wait_for_merge(platform: Platform, pr_id: str) -> bool:
    print_header(f"Waiting for PR '{pr_id}' to merge...")

    if platform == Platform.GITEA:
        while True:
            result = check_gitea_pr_state(pr_id)
            if result is not None:
                return result
            print(f"[{time.strftime('%H:%M:%S')}] Waiting...")
            time.sleep(30)

    nixbot_log_done = False
    while True:
        pr_data, error = get_pr_status_github(pr_id)
        if pr_data is None:
            print_error(error)
            return False

        checks = pr_data.get("statusCheckRollup", [])
        pending, failed, passed = count_check_states(checks)

        in_merge_queue, queue_desc = get_merge_queue_status_github(
            int(pr_data.get("number", 0))
        )

        queue_suffix = (
            f" {Colors.BLUE}[merge queue: {queue_desc}]{Colors.RESET}"
            if in_merge_queue
            else ""
        )
        print(
            f"[{time.strftime('%H:%M:%S')}] "
            f"Checks - {Colors.GREEN}Passed: {passed}{Colors.RESET}, "
            f"{Colors.RED}Failed: {failed}{Colors.RESET}, "
            f"{Colors.YELLOW}Pending: {pending}{Colors.RESET}"
            f"{queue_suffix}"
        )

        nixbot_log_done = run_nixbot_log_if_needed(failed, pending, nixbot_log_done)

        completion = check_pr_completion(
            pr_data, pending, failed, in_merge_queue=in_merge_queue
        )
        if completion is not None:
            success, message = completion
            if not success:
                print_error(f"\n✗ {message}")
            return success

        time.sleep(10)


def get_pr_message_from_editor(default_branch: str) -> tuple[str, str]:
    remote = (
        "upstream"
        if "upstream" in run(["git", "remote"], capture=True).stdout
        else "origin"
    )
    commits = run(
        [
            "git",
            "log",
            "--reverse",
            "--pretty=format:%s%n%n%b%n%n",
            f"{remote}/{default_branch}..HEAD",
        ],
        capture=True,
    ).stdout

    with tempfile.NamedTemporaryFile(
        mode="w+", suffix="_COMMIT_EDITMSG", delete=False
    ) as f:
        f.write(commits)
        f.flush()
        editor = os.environ.get("EDITOR", "vim")
        subprocess.run([editor, f.name], check=True)
        f.seek(0)
        msg = f.read()
    Path(f.name).unlink()

    lines = msg.split("\n", 1)
    return lines[0], lines[1] if len(lines) > 1 else ""


def prepare_repository(default_branch: str) -> int:
    """Pull and format-check. Returns 0 if there is something to merge."""
    print_header("Preparing changes...")
    # submodule.recurse=true makes `pull --rebase` return 128 when the current
    # branch introduces a new submodule that the base branch doesn't have yet —
    # the recursive submodule checkout sees the initialized submodule as a
    # "local modification" and refuses. The rebase itself is fine; only the
    # recursive bit trips. Disable it for this call and sync submodules after.
    run(
        [
            "git",
            "-c",
            "submodule.recurse=false",
            "pull",
            "--rebase",
            "origin",
            default_branch,
        ]
    )
    run(["git", "submodule", "update", "--init", "--recursive"], check=False)

    print_header("Checking code formatting...")
    result = run(["flake-fmt"], check=False)
    if result.returncode != 0:
        print_warning("Formatting issues found. Attempting to fix...")
        run(
            [
                "git",
                "absorb",
                "--force",
                "--and-rebase",
                "--base",
                f"origin/{default_branch}",
            ],
            check=False,
        )
        if sys.stdin.isatty() and sys.stdout.isatty():
            run(["lazygit"], check=False)
        else:
            print_error("Formatting check failed. Please run 'flake-fmt' manually.")
        return 1

    result = run(["git", "diff", "--quiet", f"origin/{default_branch}"], check=False)
    if result.returncode == 0:
        print_success("✓ No changes to merge")
        return 1
    return 0


def get_pr_message(message_arg: str | None, default_branch: str) -> tuple[str, str]:
    if message_arg:
        lines = message_arg.split("\n", 1)
        return lines[0], lines[1] if len(lines) > 1 else ""
    return get_pr_message_from_editor(default_branch)


def push_branch(default_branch: str) -> str:
    """Push HEAD and return the branch name to use for the PR."""
    current_branch = run(
        ["git", "branch", "--show-current"], capture=True
    ).stdout.strip()

    if current_branch == default_branch:
        branch_name = f"merge-when-green-{os.environ.get('USER', 'user')}"
    else:
        branch_name = current_branch

    print_header("Pushing changes...")
    run(["git", "push", "--force", "origin", f"HEAD:{branch_name}"])
    return branch_name


def enable_automerge_existing_pr(
    branch_name: str, platform: Platform, target: str | None = None
) -> str:
    """Enable auto-merge on an existing PR. Returns the PR ID."""
    if platform == Platform.GITHUB:
        print_warning("Enabling auto-merge...")
        run(["gh", "pr", "merge", branch_name, "--auto", "--rebase"])
        print_success("✓ Auto-merge enabled")
        return branch_name

    pr_id = find_gitea_pr(branch_name, target)
    if pr_id is None:
        raise RuntimeError(f"No open Gitea PR for {branch_name}")
    gitea_enable_automerge(pr_id)
    return pr_id


def finalize_merge(platform: Platform, pr_id: str, default_branch: str) -> int:
    if wait_for_merge(platform, pr_id):
        print_success("\n✓ PR merged!")
        run(["git", "fetch", "origin", default_branch])
        run(["git", "rebase", f"origin/{default_branch}"])
        print_success("✓ Rebased onto latest changes")
        return 0
    return 1


def chdir_repo_root() -> None:
    """Change to the git repository root so all commands run from there."""
    result = run(["git", "rev-parse", "--show-toplevel"], check=False, capture=True)
    if result.returncode != 0:
        print_error("Not inside a git repository")
        raise SystemExit(1)
    os.chdir(result.stdout.strip())


def main() -> int:
    parser = argparse.ArgumentParser(description="Create PR and merge when CI passes")
    parser.add_argument(
        "--no-wait", action="store_true", help="Don't wait for CI checks to complete"
    )
    parser.add_argument(
        "-m", "--message", help="PR title and body (separated by newline)"
    )
    args = parser.parse_args()

    chdir_repo_root()

    platform = detect_platform()

    print_header("Getting repository information...")
    default_branch = get_default_branch(platform)
    print(f"Target branch: {Colors.BLUE}{default_branch}{Colors.RESET}")

    if prepare_repository(default_branch) != 0:
        return 1

    branch_name = push_branch(default_branch)

    if check_pr_exists(branch_name, platform, default_branch):
        print_success("✓ Using existing pull request")
        pr_id = enable_automerge_existing_pr(branch_name, platform, default_branch)
    else:
        title, body = get_pr_message(args.message, default_branch)
        print_header("Creating pull request...")
        if platform == Platform.GITHUB:
            pr_id = create_pr_github(branch_name, default_branch, title, body)
        else:
            pr_id = create_pr_gitea(branch_name, default_branch, title, body)
        print_success("✓ Pull request created")

    if not args.no_wait:
        return finalize_merge(platform, pr_id, default_branch)

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print_warning("\nInterrupted")
        sys.exit(130)
    except (KeyError, TypeError, AttributeError, ValueError):
        print_error("Invalid forge response or origin URL")
        sys.exit(1)
    except RuntimeError as e:
        print_error(str(e))
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
