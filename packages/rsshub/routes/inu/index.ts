import { load } from 'cheerio';

import type { DataItem } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';

export const rootUrl = 'https://www.inu.ac.kr';
export const defaultLimit = 25;

export type NoticeItem = DataItem & {
    link: string;
};

export const boardUrl = (site: string, bbs: string) => `${rootUrl}/bbs/${site}/${bbs}/artclList.do`;

export const rssUrl = (site: string, bbs: string, row: number) => `${rootUrl}/bbs/${site}/${bbs}/rssList?row=${row}`;

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

const mimeForFilename = (name: string) => {
    const match = name.toLowerCase().match(/\.([a-z0-9]+)(?:$|[?#])/);
    return mimeMap[match?.[1] ?? ''] ?? 'application/octet-stream';
};

// `?layout=unknown` on detail URLs triggers a redirect to a different path.
// Strip it so RSSHub fetches the canonical `/bbs/.../artclView` page directly.
const canonicalDetailUrl = (link: string) => {
    try {
        const url = new URL(link);
        url.searchParams.delete('layout');
        return url.href;
    } catch {
        return link;
    }
};

const parseAttachments = ($: ReturnType<typeof load>, base: string): NonNullable<DataItem['attachments']> =>
    $('.view-file a[href*="/download"]')
        .toArray()
        .map((element) => {
            const link = $(element);
            const href = link.attr('href') ?? '';
            const title = link.text().replace(/\s+/g, ' ').trim();

            if (!href || !title) {
                return;
            }

            return {
                title,
                url: new URL(href, base).href,
                mime_type: mimeForFilename(title),
            };
        })
        .filter((attachment): attachment is NonNullable<DataItem['attachments']>[number] => attachment !== undefined);

const attachmentsHtml = (attachments: NonNullable<DataItem['attachments']>) =>
    attachments.length === 0
        ? ''
        : `<hr><p><strong>첨부파일</strong></p><ul>${attachments
              .map((attachment) => `<li><a href="${escapeHtml(attachment.url)}">${escapeHtml(attachment.title ?? attachment.url)}</a></li>`)
              .join('')}</ul>`;

const attachmentsText = (attachments: NonNullable<DataItem['attachments']>) =>
    attachments.length === 0 ? '' : `\n\n첨부파일\n${attachments.map((attachment) => `${attachment.title ?? attachment.url}: ${attachment.url}`).join('\n')}`;

const parseRssItems = (xml: string, limit: number): NoticeItem[] => {
    const $ = load(xml, { xmlMode: true });
    return $('item')
        .toArray()
        .slice(0, limit)
        .map((element): NoticeItem | undefined => {
            const item = $(element);
            const rawLink = item.find('link').text().trim();
            const title = item.find('title').text().trim();

            if (!rawLink || !title) {
                return;
            }

            const link = canonicalDetailUrl(rawLink);
            const pubDateText = item.find('pubDate').text().trim();

            return {
                title,
                link,
                guid: link,
                pubDate: pubDateText ? parseDate(pubDateText) : undefined,
            };
        })
        .filter((item): item is NoticeItem => item !== undefined);
};

export const fetchNoticeList = async (site: string, bbs: string, limit: number) => {
    const url = rssUrl(site, bbs, limit);
    const { data } = await got(url);
    const xml = typeof data === 'string' ? data : String(data);

    return {
        currentUrl: boardUrl(site, bbs),
        items: parseRssItems(xml, limit),
    };
};

export const fetchNoticeDetails = (items: NoticeItem[]) =>
    Promise.all(
        items.map((item) =>
            cache.tryGet(item.link, async () => {
                const { data: detailResponse } = await got(item.link);
                const $$ = load(detailResponse);
                const content = $$('.view-con');
                const attachments = parseAttachments($$, item.link);

                item.description = `${content.html() ?? ''}${attachmentsHtml(attachments)}`;
                item.attachments = attachments;
                item.content = {
                    html: item.description,
                    text: `${content.text().trim()}${attachmentsText(attachments)}`,
                };

                // RSSHub renders `attachments[]` only into JSON Feed output. RSS readers see
                // `<enclosure>` only when `enclosure_url` is set. Expose the first attachment
                // there so RSS-consuming readers receive at least one machine-readable link.
                if (attachments.length > 0) {
                    item.enclosure_url = attachments[0].url;
                    item.enclosure_type = attachments[0].mime_type;
                }

                return item;
            })
        )
    );
