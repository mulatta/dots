---
name: todo
description: Manage todos using todoman and vdirsyncer. Use for listing, creating, completing, and editing CalDAV VTODO items.
---

# Todo tool access

Todos are stored in Stalwart CalDAV collections synced locally with vdirsyncer
and managed with todoman. Follow `AGENTS.md` for list selection and personal
todo policy; this skill only covers mechanics.

Available lists are `personal`, `academic`, `research`, and `dev`.

Config and data locations:

- vdirsyncer: `/var/lib/opencrow/.config/vdirsyncer/config`
- todoman: `/var/lib/opencrow/.config/todoman/config.py`
- local CalDAV cache: `/var/lib/opencrow/.local/share/calendars`

Always run `vdirsyncer sync` before reading todos and after creating,
completing, or editing todos.

Examples:

```bash
# Refresh local data before reading
vdirsyncer sync

# List open todos
todo list

# Create a todo
todo new --list academic --due 2026-04-01 "Submit form"
vdirsyncer sync

# Complete a todo by id
todo done 42
vdirsyncer sync
```
