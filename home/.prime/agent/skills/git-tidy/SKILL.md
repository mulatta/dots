---
name: git-tidy
description: Inspect Git history, create approved backups, and verify tree preservation for /tidy and branch-history cleanup. Use with git-surgeon for rewrites.
---

# Git Tidy

Python-backed skill; Git and the bundled Prime Agent `rlm.bash` runtime are required.
No rewriting or pushing is implemented here.

```python
snapshot = await git_tidy.inspect("/path/to/repo", base=None, head="HEAD")
# Present plan and wait for explicit user approval before this call:
backup_ref = await git_tidy.backup(snapshot)
# Perform only the approved rewrite with git-surgeon, then:
result = await git_tidy.verify(snapshot, backup_ref)
```

`inspect` is read-only and returns a frozen snapshot: refs and object IDs,
current branch/HEAD, merge base, tree, status, operations, commits, merge IDs,
final stat, and commit/file matrix. Each inventory text field is capped at 3,000
characters with an explicit truncation marker; inspect narrower history with
git-surgeon when truncated. Object IDs remain complete. Default base is the local counterpart of
origin/HEAD, then local main or master. Without one, supply an explicit base.
Inventory is structural evidence, not a complete patch review. Inspect ambiguous
commits and tangled hunks with git-surgeon `hunks --commit`, `--full`, `--blame`,
and `show`, rather than loading the entire branch patch.

## Quality and approval

Preserve final tree and intent. Turn tangled incremental changes such as
`A -> A+B -> B` into direct logical changes such as `A -> B`.
Each final commit must have one clear purpose, stand alone through its diff and
message, avoid unrelated hunks, and include related tests, docs, and config.
Keep commits small and reviewable, and buildable when practical. Split independent
concepts; combine only fixups, cleanups, rename support, or tests/docs for the same
concept. Do not squash everything unless the whole change is one small unit.
Use concise imperative subjects following repository conventions, scoped where
customary. Avoid Conventional Commit prefixes unless established by human
history. Bodies explain why, not merely what.

Present each proposed commit's subject, purpose, and files/hunks. Stop for
explicit approval before backup creation or any rewrite. Approval is a caller
responsibility, not an API-enforced permission; this skill cannot prevent raw Git
bypasses. Require a clean index
and worktree, including untracked files; never auto-stash or auto-stage. Ask how
to handle dirty state separately, then reinspect and seek fresh plan approval.
`backup` rejects stale snapshots, detached HEAD, non-current head ranges, empty
ranges, and active rebase/merge/cherry-pick/revert/sequencer/bisect operations.
A changed branch, range, or worktree requires fresh inspection and approval.
Do not run concurrent repository writers; checks cannot lock the entire worktree.
Merge ranges may be inspected, but rewriting needs a merge-aware plan that
preserves intent; stop if the available operation cannot support it.

After approval use git-surgeon `split`, `fold`, `move`, `squash`, `amend`, and
`reword`. Do not construct an interactive rebase manually. Lower-level Git is
allowed only when git-surgeon cannot express the approved operation. Never push,
force-push, or update remote refs without a separate explicit request.

## Verification

`backup` creates a unique create-only `refs/backup/tidy/…` ref and returns its
name. Retain it; never replace or delete it. `verify` validates that backup still
points to the original commit, then reports `tree_matches`, `branch_matches`,
current `status`, active `operations`, final `commits`, and `backup_ref`, without mutation.
Require an exact final tree match unless the user explicitly approved a difference;
a false result is not success. Check clean status and expected branch. Run narrow
formatters, linters, and tests in the repository's declared environment. Inspect
final history, using `git range-diff` when useful. Report commits, verification
commands, remaining risks, and retained backup. List backups with
`git for-each-ref refs/backup/tidy`.

## Development

Tests use real temporary Git repositories and the installed runtime. In the
Prime Agent REPL, locate the bundled runtime and create a narrow mypy search path:

```python
from pathlib import Path
import rlm

runtime = Path(rlm.__file__).parent.parent
scratch = Path.home() / ".claude/outputs/git-tidy-types"
scratch.mkdir(parents=True, exist_ok=True)
(scratch / "rlm").symlink_to(runtime / "rlm", target_is_directory=True)
```

From this skill directory, run through `queue` with those absolute paths:

```text
nix-shell -p 'python314.withPackages (p: [ p.pytest p.mypy ])' ruff --run 'ruff format --no-cache --check . && ruff check --no-cache . && MYPYPATH=<scratch> python -m mypy --cache-dir=<scratch>/mypy --follow-imports=silent src && PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=<runtime> python -m pytest -p no:cacheprovider -q'
```

The narrow runtime symlink exposes bundled types without shadowing Python's own
standard/dependency modules. No kernel-only project imports or runtime replacement.
