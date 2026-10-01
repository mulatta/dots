import asyncio
import shlex
from pathlib import Path

import git_tidy
import pytest
from rlm import bash


def run(coro):
    return asyncio.run(coro)


def git(repo, *args):
    result = run(bash(shlex.join(["git", "-C", str(repo), *args])))
    assert result.exit_code == 0, result.output
    return result.output.strip()


@pytest.fixture
def repo(tmp_path):
    git(tmp_path, "init", "-b", "main")
    git(tmp_path, "config", "user.email", "test@example.org")
    git(tmp_path, "config", "user.name", "Test")
    (tmp_path / "file").write_text("base\n")
    git(tmp_path, "add", "file")
    git(tmp_path, "commit", "-m", "base")
    git(tmp_path, "checkout", "-b", "topic")
    (tmp_path / "file").write_text("topic\n")
    git(tmp_path, "commit", "-am", "topic")
    return tmp_path


def test_inspect_backup_verify(repo):
    before = git(repo, "show-ref")
    snapshot = run(git_tidy.inspect(str(repo)))
    assert git(repo, "show-ref") == before
    assert "topic" in snapshot.commits
    backup = run(git_tidy.backup(snapshot))
    assert git(repo, "rev-parse", backup) == snapshot.head_oid
    git(repo, "commit", "--amend", "-m", "better topic")
    assert run(git_tidy.verify(snapshot, backup))["tree_matches"]
    (repo / "file").write_text("different\n")
    git(repo, "commit", "-am", "different")
    assert not run(git_tidy.verify(snapshot, backup))["tree_matches"]


@pytest.mark.parametrize(
    "change",
    ["dirty", "index", "head", "branch", "base", "merge", "revert", "sequencer"],
)
def test_backup_rechecks(repo, change):
    snapshot = run(git_tidy.inspect(str(repo)))
    if change == "dirty":
        (repo / "new").write_text("untracked")
    elif change == "index":
        (repo / "file").write_text("staged")
        git(repo, "add", "file")
    elif change == "head":
        git(repo, "commit", "--amend", "-m", "changed")
    elif change == "branch":
        git(repo, "checkout", "-b", "other")
    elif change == "base":
        git(repo, "update-ref", "refs/heads/main", "HEAD")
    else:
        name = {
            "merge": "MERGE_HEAD",
            "revert": "REVERT_HEAD",
            "sequencer": "sequencer",
        }[change]
        path = Path(git(repo, "rev-parse", "--absolute-git-dir")) / name
        if change == "sequencer":
            path.mkdir()
        else:
            path.write_text(snapshot.head_oid)
    with pytest.raises(ValueError):
        run(git_tidy.backup(snapshot))
    assert not git(repo, "for-each-ref", "refs/backup/tidy")


def test_non_head_and_detached_refused(repo):
    snapshot = run(git_tidy.inspect(str(repo), head="main"))
    with pytest.raises(ValueError):
        run(git_tidy.backup(snapshot))
    git(repo, "checkout", "--detach")
    snapshot = run(git_tidy.inspect(str(repo)))
    with pytest.raises(ValueError):
        run(git_tidy.backup(snapshot))


def test_backup_unique_and_validated(repo):
    snapshot = run(git_tidy.inspect(str(repo)))
    first = run(git_tidy.backup(snapshot))
    second = run(git_tidy.backup(snapshot))
    assert first != second
    git(repo, "update-ref", first, "main")
    with pytest.raises(ValueError):
        run(git_tidy.verify(snapshot, first))


def test_verify_reports_active_operation(repo):
    snapshot = run(git_tidy.inspect(str(repo)))
    backup = run(git_tidy.backup(snapshot))
    path = Path(git(repo, "rev-parse", "--absolute-git-dir")) / "REVERT_HEAD"
    path.write_text(snapshot.head_oid)
    assert "REVERT_HEAD" in run(git_tidy.verify(snapshot, backup))["operations"]


def test_inventory_is_bounded(repo):
    git(repo, "commit", "--amend", "-m", "x" * 16000)
    snapshot = run(git_tidy.inspect(str(repo)))
    assert len(snapshot.commits) < 4000
    assert "truncated" in snapshot.commits


def test_default_base_prefers_local_remote_default(repo):
    git(repo, "branch", "trunk", "main")
    git(repo, "update-ref", "refs/remotes/origin/trunk", "main")
    git(repo, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/trunk")
    assert run(git_tidy.inspect(str(repo))).base_ref == "refs/heads/trunk"


def test_invalid_ref_is_not_option(repo):
    with pytest.raises(ValueError):
        run(git_tidy.inspect(str(repo), base="--help"))
