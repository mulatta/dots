---
name: merge-when-green
description: Push changes, create PR, and wait for CI merge using jj + merge-when-green
disable-model-invocation: true
---

Push changes and wait for CI-green auto-merge using the `merge-when-green` tool (jj workflow).

## What merge-when-green does

1. Validate state (no conflicts, non-empty commit)
2. Sync: `jj git fetch --all-remotes` + rebase onto default branch
3. Format check: run `jmt`
4. Get or create bookmark (`merge-when-green-<user>` if none exists)
5. Push bookmark to origin
6. Create PR via `gh pr create` (or reuse existing)
7. Add `auto-merge` label
8. Wait for CI checks to pass and PR to merge
9. Cleanup: delete bookmark, rebase all local branches, sync fork

## Usage

### Basic (uses commit description as PR title)

```bash
# Ensure current change is described
jj describe -m "feat: your change description"

# Run via pueue (recommended, avoids timeout)
pueue add -- 'merge-when-green'
pueue wait <task-id> && pueue log <task-id>
```

### With explicit title

```bash
pueue add -- 'merge-when-green --title "feat: explicit PR title"'
pueue wait <task-id> && pueue log <task-id>
```

### Non-blocking (don't wait for CI)

```bash
merge-when-green --no-wait
```

## On CI Failure

If checks fail:

1. Read pueue log to identify failures:
   ```bash
   pueue log <task-id>
   ```
2. Get details:
   ```bash
   gh run view <run-id> --log-failed
   ```
3. Fix the code (jj auto-tracks changes)
4. Verify and re-run:
   ```bash
   jj status
   jj diff
   pueue add -- 'merge-when-green --title "feat: fixed title"'
   pueue wait <task-id> && pueue log <task-id>
   ```

## Notes

- Bookmark is auto-created as `merge-when-green-<user>` if none exists on @ or @-
- Fork workflow supported: pushes to origin, PRs to upstream
- After merge, all local mutable branches are rebased onto updated default branch
- NEVER use git commands directly; this tool handles jj-git interop internally

User request: $ARGUMENTS
