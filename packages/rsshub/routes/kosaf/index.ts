import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';

export const rootUrl = 'https://www.kosaf.go.kr';
export const defaultLimit = 25;

export type NoticeItem = DataItem & {
    link: string;
};

export const noticeUrl = (ctgrId1: string, ctgrId2?: string) => {
    const url = new URL('/ko/notice.do', rootUrl);
    url.searchParams.set('ctgrId1', ctgrId1);
    if (ctgrId2) {
        url.searchParams.set('ctgrId2', ctgrId2);
    }
    return url.href;
};

const absoluteUrl = (href: string) => new URL(href, `${rootUrl}/ko/notice.do`).href;

const downloadUrl = (saveKey: string, seqNo: string, fileNo: string) => {
    const url = new URL('/ko/download.do', rootUrl);
    url.searchParams.set('pPath', saveKey);
    url.searchParams.set('pSeq_No', seqNo);
    url.searchParams.set('pFile_No', fileNo);
    return url.href;
};

const escapeHtml = (value: string) =>
    value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

const mimeMap: Record<string, string> = {
    pdf: 'application/pdf',
    hwp: 'application/x-hwp',
    hwpx: 'application/hwp+zip',
    doc: 'application/msword',
    docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xls: 'application/vnd.ms-excel',
    xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    ppt: 'application/vnd.ms-powerpoint',
    pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    zip: 'application/zip',
    txt: 'text/plain',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    gif: 'image/gif',
};

// KOSAF attachment titles look like "붙임 1. ... .pdf (86 KB)" — pull the
// extension out of the filename rather than the trailing size suffix.
const mimeForTitle = (title: string) => {
    const match = title.toLowerCase().match(/\.([a-z0-9]+)\b/g);
    const last = match?.[match.length - 1]?.replace(/^\./, '') ?? '';
    return mimeMap[last] ?? 'application/octet-stream';
};

const parseAttachments = ($$: ReturnType<typeof load>): NonNullable<DataItem['attachments']> =>
    $$('#VIEW_FILE a[onclick*="fileDown"]')
        .toArray()
        .map((element) => {
            const link = $$(element);
            const onclick = link.attr('onclick') ?? '';
            const match = onclick.match(/fileDown\(\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*,\s*['"]([^'"]+)['"]\s*\)/);

            if (!match) {
                return;
            }

            const [, saveKey, seqNo, fileNo] = match;
            const title = link.text().replace(/\s+/g, ' ').trim() || `Attachment ${fileNo}`;

            return {
                title,
                url: downloadUrl(saveKey, seqNo, fileNo),
                mime_type: mimeForTitle(title),
            };
        })
        .filter((attachment): attachment is NonNullable<DataItem['attachments']>[number] => attachment !== undefined);

const attachmentsHtml = (attachments: NonNullable<DataItem['attachments']>) =>
    attachments.length === 0
        ? ''
        : `<hr><p><strong>첨부파일</strong></p><ul>${attachments.map((attachment) => `<li><a href="${escapeHtml(attachment.url)}">${escapeHtml(attachment.title ?? attachment.url)}</a></li>`).join('')}</ul>`;

const attachmentsText = (attachments: NonNullable<DataItem['attachments']>) =>
    attachments.length === 0 ? '' : `\n\n첨부파일\n${attachments.map((attachment) => `${attachment.title ?? attachment.url}: ${attachment.url}`).join('\n')}`;

const parseNoticeItems = ($: ReturnType<typeof load>, limit: number) =>
    $('table tbody tr')
        .toArray()
        .slice(0, limit)
        .map((row): NoticeItem | undefined => {
            const item = $(row);
            const link = item.find('td.subject a[href*="mode=view"]').first();
            const href = link.attr('href');
            const title = link.text().trim();

            if (!href || !title) {
                return;
            }

            const itemUrl = absoluteUrl(href);
            const seqNo = new URL(itemUrl).searchParams.get('seqNo') ?? itemUrl;

            return {
                title,
                link: itemUrl,
                guid: seqNo,
                pubDate: parseDate(item.find('td.day').text().trim(), 'YYYY.MM.DD'),
            };
        })
        .filter((item): item is NoticeItem => item !== undefined);

export const fetchNoticeList = async (ctgrId1: string, ctgrId2: string | undefined, limit: number) => {
    const currentUrl = noticeUrl(ctgrId1, ctgrId2);
    const { data: response } = await got(currentUrl);
    const $ = load(response);

    return {
        categoryName: $('a.on, a.current, strong.on').first().text().trim(),
        currentUrl,
        items: parseNoticeItems($, limit),
    };
};

export const fetchNoticeDetails = (items: NoticeItem[]) =>
    Promise.all(
        items.map((item) =>
            cache.tryGet(item.link, async () => {
                const { data: detailResponse } = await got(item.link);
                const $$ = load(detailResponse);
                const content = $$('#VIEW_MCONTENT');
                const attachments = parseAttachments($$);

                item.title = $$('#VIEW_TITLE').text().trim() || item.title;
                item.description = `${content.html() ?? ''}${attachmentsHtml(attachments)}`;
                item.attachments = attachments;
                item.content = {
                    html: item.description,
                    text: `${content.text().trim()}${attachmentsText(attachments)}`,
                };

                // RSSHub renders `attachments[]` only into JSON Feed output. Surface the
                // first attachment as `<enclosure>` so RSS-consuming readers can still
                // pick it up; the full set remains available via JSON Feed.
                if (attachments.length > 0) {
                    item.enclosure_url = attachments[0].url;
                    item.enclosure_type = attachments[0].mime_type;
                }

                return item;
            })
        )
    );

export const handler = async (ctx) => {
    const { ctgrId1, ctgrId2 } = ctx.req.param();
    const limit = Number.parseInt(ctx.req.query('limit') ?? `${defaultLimit}`, 10) || defaultLimit;
    const { categoryName, currentUrl, items } = await fetchNoticeList(ctgrId1, ctgrId2, limit);
    const detailedItems = await fetchNoticeDetails(items);

    const title = `한국장학재단 공지사항${categoryName ? ` - ${categoryName}` : ''}`;

    return {
        title,
        description: title,
        link: currentUrl,
        item: detailedItems,
        language: 'ko',
    };
};

export const route: Route = {
    path: '/notice/:ctgrId1/:ctgrId2?',
    name: '공지사항',
    url: 'kosaf.go.kr/ko/notice.do',
    maintainers: ['mulatta'],
    handler,
    example: '/kosaf/notice/0000000002',
    parameters: {
        ctgrId1: '1차 카테고리 ID. 예: 장학금 = 0000000002',
        ctgrId2: '2차 카테고리 ID. 예: 국가근로장학금 = 0000000004',
    },
    categories: ['government'],
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: false,
        supportRadar: true,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    radar: [
        {
            source: ['kosaf.go.kr/ko/notice.do?ctgrId1=:ctgrId1&ctgrId2=:ctgrId2'],
            target: '/notice/:ctgrId1/:ctgrId2',
        },
        {
            source: ['kosaf.go.kr/ko/notice.do?ctgrId1=:ctgrId1'],
            target: '/notice/:ctgrId1',
        },
    ],
};
