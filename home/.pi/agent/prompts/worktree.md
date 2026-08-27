---
description: Launch tasks in Herdr-managed git worktrees
argument-hint: "<task> [additional tasks...]"
---

Launch tasks in separate Herdr-managed git worktrees.

Tasks: $ARGUMENTS

Use the Herdr skill for all worktree, workspace, pane, and agent operations.
Treat invocation of this template as explicit authorization to create
worktrees. Stop with a clear explanation unless the current session satisfies
the Herdr skill's operating requirements.

The tasks may reference earlier discussion (for example, "do option 2"). Include
all relevant conversation context in each self-contained agent prompt, and
re-read any referenced plan or specification first.

Run independent tasks concurrently, preserve user focus, and report created
branches, workspaces, agent names, and final states. Do not answer approval
prompts on the user's behalf.
