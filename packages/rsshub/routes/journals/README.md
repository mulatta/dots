# Journal custom RSSHub routes

## Cell Press full content

```text
/journals/cell/:journal/:kind?
```

- `journal`: Cell Press journal slug.
- `kind`: `current` or `inpress`; defaults to `inpress`.
- `limit`: optional item count; defaults to `20`.
- `delayMs`: optional serial article-fetch delay; defaults to `1500`.
- `retries`: optional article retry count; defaults to `3`.

Supported journal slugs include `cell`, `molecular-cell`, `cell-reports`,
`cell-systems`, `stem-cell-reports`, `iscience`, `cell-genomics`,
`developmental-cell`, `cancer-cell`, `current-biology`, `chem`,
`cell-host-microbe`, `cell-reports-methods`, `cell-reports-medicine`,
`cell-stem-cell`, `matter`, `structure`, and `biophysj`.

The route uses Playwright against Cell listing and fulltext pages. It does not
use official publisher RSS, because feed output needs original full article
body content.

Examples:

```text
http://127.0.0.1:1200/journals/cell/cell/inpress?limit=10
http://127.0.0.1:1200/journals/cell/cell/current?limit=10
http://127.0.0.1:1200/journals/cell/molecular-cell/inpress?limit=10
```
