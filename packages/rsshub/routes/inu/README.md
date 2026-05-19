# 인천대학교 RSSHub routes

Custom RSSHub routes for INU jiniweb-based notice boards. Original
`/bbs/{site}/{bbs}/rssList` already exposes a list, but does not populate
`<enclosure>` elements for attachments. This route enriches each item with
attachment metadata extracted from the detail page.

## Routes

```text
/inu/notice/:site/:bbs
```

- `site`: site ID under `inu.ac.kr/bbs/<site>/...`. e.g. `grad` (일반대학원).
- `bbs`: board ID. e.g. `1348` (일반대학원 공지사항).
- `limit`: optional query parameter, defaults to `25`.

Examples:

```text
http://127.0.0.1:1200/inu/notice/grad/1348
http://127.0.0.1:1200/inu/notice/grad/1348?limit=50
```

Miniflux runs on the same host as RSSHub, so register the localhost URLs above
as feed URLs.

## Output format and Miniflux

For consumers that need the full attachment list (e.g. agent-driven workflows
on starred entries), prefer the JSON Feed output:

```text
http://127.0.0.1:1200/inu/notice/grad/1348?format=json
```

The default RSS XML output exposes only the first attachment as a single
`<enclosure>` element (RSSHub renders `attachments[]` only into JSON Feed; the
remaining attachments are still listed inline in `<description>` HTML).
Miniflux supports both formats, so register the JSON URL when attachment
fidelity matters.

## Detail page parsing

Each item is fetched with the canonical URL (the `?layout=unknown` query
parameter from the upstream RSS triggers a redirect and is stripped). The
detail page exposes:

- `.view-con` — article body
- `.view-file a[href*="/download"]` — attachment links

Attachment metadata is exposed both inline in the item HTML (so readers without
enclosure support still see links) and as RSS `<enclosure>` entries via
`DataItem.attachments`.

The MIME type is inferred from the visible filename extension (`.hwp`,
`.hwpx`, `.pdf`, `.doc`, `.docx`, `.xls`, `.xlsx`, `.ppt`, `.pptx`, `.zip`,
images, plain text) and falls back to `application/octet-stream`. The INU
download endpoint returns `application/x-msdownload` regardless of the actual
file type, so server-reported MIME is not used.

## Verification

After deploying malt:

```sh
curl -fsS 'http://127.0.0.1:1200/inu/notice/grad/1348?limit=2'
```

Expected response:

- HTTP `200`
- `content-type: application/xml`
- `x-rsshub-route: /notice/:site/:bbs`
- Items with attachments expose the first attachment as `<enclosure>`. Use
  `?format=json` to retrieve the full attachment list.
