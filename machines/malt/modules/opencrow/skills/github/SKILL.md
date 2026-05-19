---
name: github
description: Read-only GitHub API access through n8n-hooks. Use for inspecting issues, PRs, releases, commits, actions runs, and repository metadata.
---

# GitHub Access

Use `n8n-hooks github` for read-only GitHub API access. The n8n workflow holds
the GitHub credential, enforces GET server-side, and only permits repository
metadata paths under `/repos/{owner}/{repo}`.

```bash
n8n-hooks github <path> [-q k=v ...]  # GET allowed /repos/{owner}/{repo}/... paths
n8n-hooks github discover <term>      # grep endpoints
n8n-hooks github discover /<path>     # exact path → show params
```

Output is JSON. Pipe through `jq`. Use pagination when needed:

```bash
n8n-hooks github /repos/NixOS/nixpkgs/pulls/12345/files -q per_page=100 | jq '.[].filename'
n8n-hooks github /repos/owner/repo/actions/runs -q per_page=20 | jq '.workflow_runs[] | {name, status, conclusion}'
```

This hook is read-only. If GitHub mutation is needed, ask for explicit user confirmation and use the appropriate workflow for that task.
