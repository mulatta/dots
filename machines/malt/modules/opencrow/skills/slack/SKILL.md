---
name: slack
description: Read Slack context through n8n-hooks. Use for Slack threads, messages, channels, users, and files.
---

# Slack Access

Use `n8n-hooks slack` for read-only Slack context. The n8n workflow holds the
Slack credential and exposes a fixed set of read operations only.

```bash
n8n-hooks slack replies <CHANNEL_ID> <THREAD_TS>
n8n-hooks slack history <CHANNEL_ID> [-n 50]
n8n-hooks slack search "<query>" [-n 20]
n8n-hooks slack file-info <FILE_ID>
n8n-hooks slack file-content <FILE_ID>
n8n-hooks slack file-download <FILE_ID> -o /var/lib/opencrow/tmp
n8n-hooks slack list-channels
n8n-hooks slack list-users
```

Channel and user arguments use IDs (`C0123…`, `U0123…`). Prefer IDs from the
trigger line or user request. Use broad `search`, `history`, `list-channels`, or
`list-users` only when useful for the current user-scoped task.

Use `file-download` for PDF, Office, and HWP/HWPX attachments, then read the
saved file with the document-reading skill.

This skill is read-only. If Slack mutation is needed, prepare a draft/proposal and ask the user.
