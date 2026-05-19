# trigger-context extension plan

## Goal

Normalize plain OpenCrow FIFO trigger lines into a typed trigger context before Noa starts reasoning. n8n should remain a deterministic trigger source, while Noa and skills decide what to read and how to respond.

## Boundary

n8n responsibilities:

- Detect explicit events and schedules.
- Dedupe and cursor source events.
- Emit one-line, URL-encoded FIFO triggers.
- Avoid embedding large source context, summaries, or policy text.

OpenCrow extension responsibilities:

- Parse FIFO trigger lines.
- Decode key/value fields.
- Validate required fields for known trigger kinds.
- Render a canonical trigger context for the agent session.
- Keep parsing errors safe and explicit.

Skills and agent policy responsibilities:

- Decide what to read for each trigger kind.
- Use domain tools for calendar, todo, mail, RSS, Slack, and other context.
- Keep mutation policy outside n8n trigger payloads.

## Trigger line format

A trigger line starts with a kind token followed by URL-encoded `key=value` fields:

```text
<kind> schema=opencrow.trigger.v1 key=value key=value
```

Examples:

```text
routine.check schema=opencrow.trigger.v1 action=checkout routine_type=evening local_date=2026-05-12 local_time=23%3A00 timezone=Asia%2FSeoul weekday=Tue weekend=false event_id=routine%3Aevening%3A2026-05-12
rss.entry schema=opencrow.trigger.v1 action=triage entry_id=1419 category=Notification event_id=rss%3A1419%3Astarred%3Anotification
slack.reaction schema=opencrow.trigger.v1 action=calendar_draft channel=C123 ts=1778568648.690699 reaction=date event_id=slack%3AC123%3A1778568648.690699%3Adate%3AU04GMC10NNP
```

## Canonical session context

The extension should expose a compact context document such as `TRIGGER.md`:

```md
# Trigger

Kind: routine.check
Schema: opencrow.trigger.v1
Action: checkout
Event ID: routine:evening:2026-05-12

Fields:

- routine_type: evening
- local_date: 2026-05-12
- local_time: 23:00
- timezone: Asia/Seoul
- weekday: Tue
- weekend: false
```

Noa should read this context before using tools. The raw trigger line may be kept for debugging, but the canonical fields are the source of truth.

## Routine first rollout

Start with `routine.check` because it has no source-specific read payload and no external mutation requirements.

Required fields:

- `schema`
- `action`
- `routine_type`
- `local_date`
- `local_time`
- `timezone`
- `weekday`
- `weekend`
- `event_id`

Routine handling remains policy-driven:

- `daily_plan`: calendar today/tomorrow first, then due todos, then mail/RSS only if needed.
- `check_in`: changed blockers or urgent remaining work only.
- `work_review`: remaining work before checkout, finish/defer/escalate options.
- `checkout`: tomorrow preparation and follow-ups, no new external actions.

## Later trigger kinds

- `rss.entry`: read-only triage for starred Miniflux notification entries.
- `slack.reaction`: explicit Slack message/thread action hints.
- `mail.flagged`: explicit user-selected mail handoff from the flagged Maildir.

## Non-goals

- No long context accumulation in n8n static data.
- No source summaries in trigger payloads.
- No permission grants or scoped capabilities in trigger lines.
- No direct public/shared mutations from the extension.
