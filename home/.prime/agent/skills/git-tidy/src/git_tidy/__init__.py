"""Read-only history inventory and approval-gated backup support."""

import shlex
from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from rlm import bash


async def _git(repo: str, *args: str, optional: bool = False) -> str:
    result = await bash(shlex.join(["git", "--no-optional-locks", "-C", repo, *args]))
    if result.exit_code != 0:
        if optional:
            return ""
        raise ValueError(result.output.strip() or "Git command failed")
    return result.output.strip()


def _bounded(text: str) -> str:
    return (
        text
        if len(text) <= 3000
        else text[:3000] + "\n[truncated; inspect narrower history with git-surgeon]"
    )


async def _resolve(repo: str, ref: str) -> str:
    return await _git(
        repo, "rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}"
    )


async def _base(repo: str) -> str:
    remote = await _git(
        repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD", optional=True
    )
    candidates = (
        [remote.removeprefix("origin/")] if remote.startswith("origin/") else []
    )
    for name in [*candidates, "main", "master"]:
        ref = f"refs/heads/{name}"
        if await _git(repo, "rev-parse", "--verify", ref, optional=True):
            return ref
    raise ValueError("No local default branch; provide an explicit base")


async def _operations(repo: str) -> tuple[str, ...]:
    found = []
    for name in (
        "rebase-merge",
        "rebase-apply",
        "MERGE_HEAD",
        "CHERRY_PICK_HEAD",
        "REVERT_HEAD",
        "sequencer",
        "BISECT_LOG",
    ):
        path = await _git(
            repo, "rev-parse", "--path-format=absolute", "--git-path", name
        )
        if Path(path).exists():
            found.append(name)
    return tuple(found)


@dataclass(frozen=True)
class Snapshot:
    repo: str
    base_ref: str
    head_ref: str
    base_oid: str
    head_oid: str
    current_head: str
    branch: str
    merge_base: str
    tree: str
    status: str
    operations: tuple[str, ...]
    commits: str
    merges: str
    stat: str
    files: str


async def inspect(repo: str, base: str | None = None, head: str = "HEAD") -> Snapshot:
    """Inspect a range without modifying Git refs, index, or worktree."""
    repo = await _git(str(Path(repo).resolve()), "rev-parse", "--show-toplevel")
    base = base if base is not None else await _base(repo)
    base_oid = await _resolve(repo, base)
    head_oid = await _resolve(repo, head)
    merge_base = await _git(repo, "merge-base", base_oid, head_oid)
    range_ = f"{merge_base}..{head_oid}"
    return Snapshot(
        repo=repo,
        base_ref=base,
        head_ref=head,
        base_oid=base_oid,
        head_oid=head_oid,
        current_head=await _resolve(repo, "HEAD"),
        branch=await _git(repo, "symbolic-ref", "-q", "HEAD", optional=True),
        merge_base=merge_base,
        tree=await _git(repo, "rev-parse", f"{head_oid}^{{tree}}"),
        status=_bounded(
            await _git(repo, "status", "--porcelain=v1", "--untracked-files=all")
        ),
        operations=await _operations(repo),
        commits=_bounded(
            await _git(repo, "log", "--reverse", "--format=%H %s", range_)
        ),
        merges=_bounded(await _git(repo, "rev-list", "--merges", "--reverse", range_)),
        stat=_bounded(await _git(repo, "diff", "--stat", merge_base, head_oid)),
        files=_bounded(
            await _git(
                repo,
                "log",
                "--reverse",
                "--format=commit %H %s",
                "--name-status",
                range_,
            )
        ),
    )


async def backup(snapshot: Snapshot) -> str:
    """Create a retained ref only AFTER the user approves the rewrite plan.

    Reject stale inventory, dirty trees, detached/non-current heads, and Git
    operations. Callers must prevent concurrent repository writers throughout
    inspection, approval, and rewriting; Git cannot lock the whole worktree.
    """
    current = await inspect(snapshot.repo, snapshot.base_ref, snapshot.head_ref)
    if current != snapshot:
        raise ValueError("Repository changed; inspect again and obtain fresh approval")
    if not current.branch or current.head_oid != current.current_head:
        raise ValueError("Rewrite requires the attached current HEAD")
    if current.status or current.operations:
        raise ValueError(
            "Require a clean index/worktree and no Git operation in progress"
        )
    if not current.commits:
        raise ValueError("No commits to tidy")
    # A final ref check narrows the read/check gap before the create-only write.
    if (
        await _resolve(current.repo, "HEAD") != current.current_head
        or await _git(current.repo, "symbolic-ref", "-q", "HEAD", optional=True)
        != current.branch
    ):
        raise ValueError("HEAD or branch changed; obtain fresh approval")
    ref = f"refs/backup/tidy/{uuid4().hex}"
    await _git(
        current.repo, "update-ref", ref, current.head_oid, "0" * len(current.head_oid)
    )
    return ref


async def verify(snapshot: Snapshot, backup_ref: str) -> dict[str, str | bool]:
    """Compare current HEAD to the retained original; never mutate the repo."""
    if (
        not backup_ref.startswith("refs/backup/tidy/")
        or await _resolve(snapshot.repo, backup_ref) != snapshot.head_oid
    ):
        raise ValueError("Backup ref does not retain the inspected original HEAD")
    tree = await _git(snapshot.repo, "rev-parse", "HEAD^{tree}")
    return {
        "tree_matches": tree == snapshot.tree,
        "branch_matches": await _git(
            snapshot.repo, "symbolic-ref", "-q", "HEAD", optional=True
        )
        == snapshot.branch,
        "status": await _git(
            snapshot.repo, "status", "--porcelain=v1", "--untracked-files=all"
        ),
        "commits": await _git(
            snapshot.repo,
            "log",
            "--reverse",
            "--format=%H %s",
            f"{snapshot.merge_base}..HEAD",
        ),
        "backup_ref": backup_ref,
        "operations": ", ".join(await _operations(snapshot.repo)),
    }
