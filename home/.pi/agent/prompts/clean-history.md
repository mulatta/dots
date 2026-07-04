---
description: Clean git history into cohesive logical commits
argument-hint: "[base-ref] [head-ref]"
---

Clean up the current branch history.

Arguments: $ARGUMENTS

Goal: rewrite tangled incremental history into a clean sequence of cohesive
logical commits. Preserve the final tree and intent, but reorganize commits so
that mixed changes like `A -> A+B -> B` become clear commits such as `A -> B`.
Do not squash everything into one commit unless the whole change is truly one
small logical unit.

## Commit quality bar

Each final commit must:

- have one clear purpose
- be understandable on its own from its diff and message
- avoid mixing unrelated files or hunks
- include tests/docs/config changes with the code they validate or explain
- stay small enough to review without hiding multiple concerns
- leave the tree in a buildable, reviewable state when practical

Split a commit when it contains multiple independent concepts. Combine commits
only when one is a fixup, cleanup, rename-only support, or test/docs companion
for the same concept.

Use commit messages in this style:

- imperative mood
- concise subject, no conventional commit prefixes
- optional context prefix only when it adds clarity, e.g. `cli:` or `docs:`
- body paragraphs when needed
- explain why the change is needed, not just what changed

## Safety rules

- Inspect the repository state before rewriting history.
- If a rebase, merge, or cherry-pick is already in progress, handle that state
  explicitly before starting a new rewrite.
- If the worktree has unrelated uncommitted changes, ask before stashing,
  including, or discarding anything.
- Before rewriting, create a backup ref for the original HEAD.
- Do not force-push or update remote branches unless explicitly asked.
- Avoid interactive terminal commands. Use non-interactive git commands, patch
  files, or hunk-level tooling that works unattended.

## Workflow

1. Determine the rewrite range:
   - If arguments provide refs, use them as `[base-ref] [head-ref]`.
   - If no base ref is provided, infer the local base branch from
     `branch.<current>.workmux-base`, then `main`, then `master`.
   - If no head ref is provided, use `HEAD`.
2. Inspect current state with `git status --short`, recent history, and the diff
   for `<base-ref>..<head-ref>`.
3. Study commits and changed hunks. Identify the final logical commit sequence
   before changing history.
4. Present the rewrite plan first: final commit subjects, purpose, and which
   files/hunks belong to each commit.
5. Rewrite the branch using the safest method for the situation:
   - use fixup/squash/reword rebase when existing commits already map well
   - rebuild from `<base-ref>` with selective staging when commits are tangled
   - split hunks non-interactively when one file contains multiple concepts
6. Verify that the final tree matches the original intended tree. Compare the
   backup ref to the rewritten HEAD and explain any intentional differences.
7. Run relevant formatters, linters, or tests. Use the project's normal commands
   when discoverable; otherwise run the narrowest meaningful checks.
8. Inspect the final history and use `git range-diff` against the backup ref when
   useful to confirm that meaning was preserved.
9. Report the final commit list, verification commands, and any risks or
   follow-up work.

Prefer preserving logical review units over minimizing commit count.
