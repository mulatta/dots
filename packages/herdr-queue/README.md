# herdr-queue

`hq` collects coding agents' prompt-cache and account-usage state for herdr.
The package provides only the binary; agent configuration belongs in dots.

```text
hq ingest claude [-- command...]
                   record status line JSON, then pass it to the command
hq ingest codex    record PostModelRequest hook JSON
hq ingest pi       record turn JSON and print the cache expiry
hq list [--json]   show terminal snapshots
hq usage [--refresh] [--json]
                   show account usage; --refresh asks Claude Code and Codex
```

## Agent integration

- Claude Code: `home/.claude/settings.json` wraps the status line script with
  `hq ingest claude -- ~/.claude/statusline.sh`, which reads this terminal's snapshot
  back for its cache TTL.
- Pi: `home/.pi/agent/extensions/herdr-queue.ts` reports turns and shows cache expiry
  in the footer. Stow deploys this file independently of the package.
- Codex: a `PostModelRequest` hook can send its JSON to `hq ingest codex`.

`hq` does not install extensions or modify agent configuration.

## State

Terminal snapshots require `HC_TERMINAL_ID` and live in
`$XDG_STATE_HOME/herdr-queue/sessions/<terminal>.json`. Claude Code cache
misses are appended to `events.jsonl`. Claude Code supplies exact cache
expiry; Codex and Pi expiry is estimated.

Account usage lives in `$XDG_STATE_HOME/herdr-queue/accounts/<agent>.json`.
`hq usage --refresh` asks `claude -p` via `get_usage` and `codex app-server`
via `account/rateLimits/read`; it does not read or renew tokens. Requests
are throttled to at most once every five minutes, with backoff on failure.
Neither request starts a turn or spends quota. Claude Code runs in safe
mode without hooks, MCP servers, or session persistence.

Recent account answers take precedence; failed or stale answers fall back
to terminal reports. Refreshing every ten minutes is sufficient.
