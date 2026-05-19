# Vikunja task templates

Template Markdown files describe work-shape metadata and the task context schema in YAML frontmatter. `vikunja-cli` reads the schema and type definitions from that frontmatter, then owns fixed description rendering and Vikunja-native task fields.

Each `*.md` file contains YAML frontmatter with:

- `name`
- `description`
- `defaults.priority`
- `defaults.labels`
- `schema` as JSON Schema-compatible YAML, including source types and template-specific limits
- `attachment_expectations`

Rendered descriptions use this fixed shape:

```markdown
## Summary

...

## Checklist

- [ ] ...

## Notes

- ...

## Proof

- ...

## Sources

- webmail: https://... — title
```

Vikunja-native metadata stays outside the description:

- due/deadline -> Vikunja due field
- blockers/order/hierarchy -> Vikunja relations
- priority/state/type -> Vikunja priority and labels
- reminders/assignees/project/bucket -> Vikunja fields

`Sources` must be clickable or directly openable. For email, prefer Bulwark `?email=<JMAP id>` webmail URLs when available. Bare email Message-Id values are not Vikunja sources; use notmuch/maildir locators only when directly searchable, or attach `.eml` when preservation matters.
