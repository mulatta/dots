# Notice template

Use for notices, deadlines, administrative announcements, school/agency updates,
forms, schedules, event pages, and action-oriented messages.

## Judgment

Use exactly one:

- `ignore`: not relevant or no action needed.
- `note`: useful to know, but no task or calendar entry needed.
- `todo`: user action or follow-up is needed.
- `calendar`: time-specific event, appointment, meeting, travel, or time block is
  needed.
- `ask`: important but missing information or ambiguous applicability requires a
  question before deciding.

## Response shape

```markdown
### <notice title>

<one-sentence summary>

- **핵심**: <what the notice says>
- **대상/조건**: <who it applies to and whether user likely matches>
- **마감/일시**: <date/time/timezone, or "명확한 마감 없음">
- **해야 할 일**: <concrete next action, or "조치 없음">
- **위험/주의**: <risk, missing info, required documents, source caveat>

**판단**: <ignore|note|todo|calendar|ask>

**제안**:

- Vikunja: <필요/불필요 + proposed task title/due/reminder if needed>
- Calendar: <필요/불필요 + proposed event title/date/time if needed>
- Linkwarden: <필요/불필요 + evidence/archive reason if needed>

진행할까?
```

Omit `진행할까?` when no write is recommended. If a write is recommended, ask
with concrete proposed fields.

## Action policy

- Calendar is for actual events, appointments, meetings, travel, or blocked time.
  Date-only deadlines are usually Vikunja tasks, not calendar events.
- Vikunja is for follow-ups, applications, submissions, checks, and deadlines.
- Linkwarden is for durable evidence/source-of-truth pages. If a task/calendar
  object only needs a reference URL, attach the URL there and do not archive
  unless the source page itself is worth preserving.
- Ask before creating calendar events, Vikunja tasks, Linkwarden links, sending
  messages, submitting forms, or changing shared/public state.

## Linkwarden proposal

Use only when source evidence should be preserved or user asks to archive.

Recommended tags:

- `source:rss`, `source:web`, `source:email`, or actual source.
- `signal:noa-saved` for confirmed Noa saves.
- `kind:notice`.
- `rss-category:<slug>` when source is RSS.
- Plain topic tags are optional existing plain tags, following the common tag
  policy.

Collection hints:

- `Academic`: university/school/course/research-admin notices.
- `Personal`: personal finance, health, travel, or life admin notices.
- `Operations`: service/admin/infra notices for operated systems.
- `Inbox`: useful evidence but classification is uncertain.

## Style

- Lead with dates, deadlines, eligibility, and next action.
- Quote short source phrases only when they disambiguate dates or requirements.
- Mark uncertainty clearly; do not turn vague estimates into confirmed dates.
- Keep output concise unless the notice has multiple required steps.
