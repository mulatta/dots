# Tech link template

Use for GitHub repositories, developer tools, libraries, APIs, technical posts,
papers, docs, PDFs, and technical web pages.

## Judgment

Use exactly one:

- `skip`: not useful enough to keep or revisit. Do not ask to save.
- `watch`: worth tracking, but not urgent.
- `read`: worth reading carefully.
- `try`: worth installing, running, or testing.
- `reference`: useful as a pattern, example, source evidence, or future citation.

## Response shape

Keep the brief compact. Use Korean by default, but keep project names, API names,
commands, and quoted source text in the original language.

```markdown
### <short title>

<one-sentence summary>

- **무엇**: <what it is>
- **왜 볼만함**: <why it may matter to the user>
- **핵심 아이디어**: <core mechanism, architecture, method, or differentiator>
- **주의점**: <adoption cost, limitation, uncertainty, ecosystem lock-in, or "특별한 주의점 없음">

**판단**: <skip|watch|read|try|reference>

**Linkwarden**: <이미 저장됨 | 저장 비추천 | 저장 제안>

- collection: <Inbox|Research|Academic|Engineering|Operations|Personal|Library>
- tags: `<metadata tags>`, `<existing plain topic tags if any>`
- why keep: <short reason>

저장할까?
```

Omit `저장할까?` and proposal bullets when the source is already saved or judgment
is `skip`. If already saved, include the link ID/collection when known.

## Linkwarden proposal

Ask to save when judgment is `watch`, `read`, `try`, or `reference` and no exact
Linkwarden URL match exists.

Recommended tags:

- Source: `source:rss`, `source:web`, `source:github`, `source:slack`, or the
  actual source system.
- Signal: usually `signal:noa-saved` for user-confirmed Noa saves.
- Kind:
  - GitHub repository: `kind:repo`
  - technical article/blog: `kind:article`
  - paper/preprint/PDF academic work: `kind:paper`
  - official docs/API reference/manual: `kind:docs`
  - standalone tool/app/service: `kind:tool` or `kind:repo` if the source is the
    repository.
- RSS category: `rss-category:<slug>` when source is RSS.
- Topic tags: optional existing plain tags, following the common tag policy.

Collection hints:

- `Engineering`: repos, developer tools, SDKs, libraries, implementation
  patterns, and agent/tooling integration examples.
- `Operations`: self-hosted services, deployment, monitoring, backup, runbooks,
  and production operations.
- `Research`: papers, research ideas, methods, experiments, and surveys.
- `Academic`: school/course/admin academic material.
- `Library`: canonical docs, specs, standards, manuals, and stable references.
- `Inbox`: useful but classification is uncertain.

## Style

- Prefer one paragraph and 3-4 bullets over long summaries.
- Ground claims in source text. Say when adoption fit or integration is unclear.
- For repo comparisons, contrast scope and integration model directly.
- Do not paste long README/PDF text.
