---
name: vikunja
description: Read Vikunja task context and submit template-aware task creation requests through n8n-hooks. Use for daily planning, due tasks, project/task lookup, and creating Vikunja tasks from selected sources.
---

# Vikunja via n8n-hooks

Use `n8n-hooks vikunja` for read-only Vikunja task context. Use `n8n-hooks vikunja-task-create` only when the user explicitly asks to create a task. The n8n workflow holds the Vikunja API token; opencrow does not.

## Boundary

- `n8n-hooks vikunja` operations are read-only.
- `n8n-hooks vikunja-task-create` is the task creation surface. It validates context against Markdown+YAML template schema before sending a create request.
- Do not claim that a task was created unless `n8n-hooks vikunja-task-create` returns success.

## Read context

Examples:

```bash
n8n-hooks vikunja list-projects
n8n-hooks vikunja list-labels
n8n-hooks vikunja list-tasks --filter 'done = false' --sort-by due_date --order-by asc --limit 50
n8n-hooks vikunja show-task <TASK_ID>
```

For morning planning, prefer open tasks that are due today, overdue, or near-term. Keep summaries concise and action-oriented. Calendar remains the source of time-specific commitments; Vikunja provides backlog and due-date context.

## Task creation workflow

When the user explicitly asks to create a Vikunja task, write a JSON context file with `summary`, `checklist`, optional `notes`, optional `proof`, and optional `sources`, then run:

```bash
n8n-hooks vikunja-task-create --project Inbox --title "메일 답장 준비" \
  --template communication --context context.json --due 2026-05-20 \
  --priority 3 --relation related:123
```

The command reads the selected Markdown+YAML template, validates the context against the template schema, and sends template defaults/schema plus context to n8n. Relation targets must be numeric Vikunja task ids.

Use only description fields inside `context`:

- `summary`: one-line outcome in the user's language.
- `checklist[]`: real progress milestones only.
- `notes[]`: concise facts, constraints, or unresolved questions.
- `proof[]`: expected completion evidence.
- `sources[]`: clickable or directly openable locators with `kind`, `locator`, and optional `title`.

Keep Vikunja-native metadata out of `context`: due/start/end/reminders/priority/project/bucket/assignees are task fields, and blockers/subtasks/ordering/related tasks are relations.
