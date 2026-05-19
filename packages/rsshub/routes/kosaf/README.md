# KOSAF RSSHub routes

Custom RSSHub routes for KOSAF notice boards.

## Routes

```text
/kosaf/notice/:ctgrId1/:ctgrId2?
/kosaf/notice?board=:ctgrId1/:ctgrId2&board=:ctgrId1/:ctgrId2
/kosaf/notices?board=:ctgrId1/:ctgrId2&board=:ctgrId1/:ctgrId2
```

Single-board route:

- `ctgrId1`: top-level notice category ID
- `ctgrId2`: optional subcategory ID
- `limit`: optional query parameter, defaults to `25`

Aggregate route:

- `board`: repeatable query parameter in `ctgrId1` or `ctgrId1/ctgrId2` form
- `limit`: optional total item count, defaults to `25`
- `perBoardLimit`: optional item count fetched from each board, defaults to `limit`

Use `?` once to start query parameters, then `&` between repeated `board`
parameters.

Notice detail pages include KOSAF attachments from `#VIEW_FILE`. Attachment
links are appended inline to the item HTML and exposed as
`DataItem.attachments`. JSON Feed consumers (`?format=json`) see the full
list; RSS readers receive only the first attachment as a single `<enclosure>`
because RSSHub does not render `attachments[]` into RSS XML.

The MIME type is inferred from the visible filename extension (`.pdf`,
`.hwp`, `.docx`, etc.). KOSAF link text usually trails with a size suffix
like `(86 KB)`, so the inference picks the last extension token in the
title.

Examples:

```text
http://127.0.0.1:1200/kosaf/notice/0000000002
http://127.0.0.1:1200/kosaf/notice/0000000002/0000000004
http://127.0.0.1:1200/kosaf/notice/0000000002?limit=20
http://127.0.0.1:1200/kosaf/notice?board=0000000001/0000000001&board=0000000001/0000000003&board=0000000002/0000000023&board=0000000002/0000000025&limit=20
```

Miniflux runs on the same host as RSSHub, so register the localhost URLs above
as feed URLs.

## Top-level category IDs

| ctgrId1      | Category   |
| ------------ | ---------- |
| `0000000001` | 학자금대출 |
| `0000000002` | 장학금     |
| `0000000003` | 재단공지   |
| `0000000004` | 인재육성   |
| `0000000009` | 연합생활관 |
| `0000000010` | 창업기숙사 |
| `0000000011` | 고시/공고  |

## Subcategory IDs for `0000000001`

| ctgrId2      | Category                     |
| ------------ | ---------------------------- |
| `0000000001` | 취업후 상환 학자금대출       |
| `0000000003` | 일반 상환 학자금대출         |
| `0000000005` | 농촌출신대학(원)생학자금대출 |
| `0000000008` | 생활비대출(취업후 상환)      |
| `0000000010` | 생활비대출(일반)             |
| `0000000012` | 전환대출                     |
| `0000000013` | 유예대출                     |
| `0000000015` | 한국장학재단 전환대출        |

## Subcategory IDs for `0000000002`

| ctgrId2      | Category                                 |
| ------------ | ---------------------------------------- |
| `0000000004` | 국가근로장학금                           |
| `0000000005` | 대통령과학장학금                         |
| `0000000006` | 국가우수장학금(이공계)                   |
| `0000000007` | 인문100년장학금                          |
| `0000000011` | 푸른등대 기부장학금                      |
| `0000000012` | 소득연계형 국가장학금                    |
| `0000000013` | 우수고등학생 해외유학 장학금(드림장학금) |
| `0000000014` | 희망사다리장학금                         |
| `0000000015` | 예술체육비전장학금                       |
| `0000000016` | 장학금환수(이공계)                       |
| `0000000017` | 복권기금 꿈사다리 장학금                 |
| `0000000018` | 전문기술인재장학금                       |
| `0000000021` | 고졸 취업 활성화 지원사업                |
| `0000000022` | 주거안정장학금                           |
| `0000000023` | 대학원대통령과학장학금                   |
| `0000000024` | 석사우수장학금(이공계)                   |
| `0000000025` | 박사우수장학금(이공계)                   |

## Subcategory IDs for `0000000004`

| ctgrId2      | Category               |
| ------------ | ---------------------- |
| `0000000001` | 사회리더 대학생 멘토링 |
| `0000000002` | 대학생 지식멘토링      |
| `0000000003` | 기부                   |
| `0000000004` | 대한민국 인재상        |

## Verification

After deploying malt:

```sh
curl -fsS 'http://127.0.0.1:1200/kosaf/notice/0000000002?limit=2'
curl -fsS 'http://127.0.0.1:1200/kosaf/notice?board=0000000001/0000000001&board=0000000002/0000000023&limit=2'
```

Expected response:

- HTTP `200`
- `content-type: application/xml`
- `x-rsshub-route: /kosaf/notice/:ctgrId1/:ctgrId2?` for single-board feeds
- `x-rsshub-route: /kosaf/notice` for aggregate feeds
