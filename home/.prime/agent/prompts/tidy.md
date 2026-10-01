---
description: Plan and safely tidy branch history into cohesive commits
argument-hint: "[base-ref] [head-ref]"
---

Tidy branch history while preserving the final tree and intent.
Arguments: $ARGUMENTS

Read the git-tidy Python skill and git-surgeon skill before acting. Use git-tidy
for Git inventory, pre-rewrite checks, backup creation, and final verification.
Do not replace these checks with ad hoc shell commands.

Inspect the requested range first. A head ref other than the current HEAD is
read-only: do not rewrite the current branch for it. If the range includes merge
commits, explain their topology in the plan and do not flatten them without
explicit approval. Treat inventory as a starting point, not complete evidence. Use git-surgeon to inspect ambiguous commits and hunks.
Present a rewrite plan with each proposed commit's subject, purpose, and files
or hunks. Split independent concerns; combine fixups and their related tests,
docs, or config. Follow repository commit-message conventions.

Stop for explicit approval before creating the backup or rewriting history.
Require a clean worktree and index; never automatically stash or stage changes.
After approval, recheck the snapshot and create a retained backup through the
skill. If the branch or range changed, inspect again and seek fresh approval.

Use git-surgeon for the approved rewrite. Use lower-level Git only when it cannot
express the approved operation. Never push or change remote refs without a
separate explicit request. Verify that the final tree matches the backup, run
relevant narrow checks, and review the resulting history. Report final commits,
checks, any unresolved risks, and the retained backup ref. Mention
`git for-each-ref refs/backup/tidy` for listing backups.
