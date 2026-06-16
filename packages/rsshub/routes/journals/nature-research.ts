import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import ofetch from '@/utils/ofetch';
import { parseDate } from '@/utils/parse-date';

import { baseUrl, cookieJar, getArticleList, getDataLayer } from '../nature/utils';
import { defaultDelayMs as sharedDefaultDelayMs, defaultJitterMs as sharedDefaultJitterMs, sleepWithJitter } from './fetch-policy';

export const defaultLimit = 20;
export const defaultDelayMs = sharedDefaultDelayMs;
export const defaultJitterMs = sharedDefaultJitterMs;
export const defaultRetries = 3;

export type NatureResearchItem = DataItem & {
    link: string;
};

export type FetchDetailOptions = {
    delayMs: number;
    jitterMs: number;
    retries: number;
    partial: boolean;
};

const journalNames: Record<string, string> = {
    nature: 'Nature',
    ncomms: 'Nature Communications',
    nbt: 'Nature Biotechnology',
    nchembio: 'Nature Chemical Biology',
    nmeth: 'Nature Methods',
    nmicrobiol: 'Nature Microbiology',
    ncb: 'Nature Cell Biology',
    nprot: 'Nature Protocols',
    natbiomedeng: 'Nature Biomedical Engineering',
    nsmb: 'Nature Structural & Molecular Biology',
    ng: 'Nature Genetics',
    nplants: 'Nature Plants',
    nchem: 'Nature Chemistry',
    natmachintell: 'Nature Machine Intelligence',
};

class NatureArticleError extends Error {
    transient: boolean;

    constructor(message: string, transient = false) {
        super(message);
        this.name = 'NatureArticleError';
        this.transient = transient;
    }
}

class NatureClientChallengeError extends NatureArticleError {
    constructor(link: string) {
        super(`Nature returned Client Challenge page for ${link}`, true);
        this.name = 'NatureClientChallengeError';
    }
}

export const parsePositiveInteger = (value: string | undefined, fallback: number) => {
    if (!value || !/^[1-9]\d*$/.test(value)) {
        return fallback;
    }

    return Number.parseInt(value, 10);
};

export const parseNonNegativeInteger = (value: string | undefined, fallback: number) => {
    if (value === undefined || !/^\d+$/.test(value)) {
        return fallback;
    }

    return Number.parseInt(value, 10);
};

const fixFigure = ($: ReturnType<typeof load>) => {
    $('picture source').each((_, element) => {
        const item = $(element);
        const srcset = item.attr('srcset');

        if (
            srcset?.startsWith('//media.springernature.com/lw685/') ||
            srcset?.startsWith('//media.springernature.com/m312/') ||
            srcset?.startsWith('//media.springernature.com/relative-r300-703_m1050/') ||
            srcset?.startsWith('//media.springernature.com/w300/')
        ) {
            item.attr(
                'srcset',
                srcset
                    .replace('//media.springernature.com/lw685/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/m312/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/relative-r300-703_m1050/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/w300/', '//media.springernature.com/full/')
            );
        }
    });

    $('img').each((_, element) => {
        const item = $(element);
        const src = item.attr('src');

        if (
            src?.startsWith('//media.springernature.com/lw685/') ||
            src?.startsWith('//media.springernature.com/m312/') ||
            src?.startsWith('//media.springernature.com/relative-r300-703_m1050/') ||
            src?.startsWith('//media.springernature.com/w300/')
        ) {
            item.attr(
                'src',
                src
                    .replace('//media.springernature.com/lw685/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/m312/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/relative-r300-703_m1050/', '//media.springernature.com/full/')
                    .replace('//media.springernature.com/w300/', '//media.springernature.com/full/')
            );
        }
    });
};

const errorMessage = (error: unknown) => (error instanceof Error ? error.message : String(error));

const isTransientError = (error: unknown) => !(error instanceof NatureArticleError) || error.transient;

const getJsonLd = ($: ReturnType<typeof load>, link: string) => {
    const json = $('script[type="application/ld+json"]').first().html()?.trim();

    if (!json) {
        throw new NatureArticleError(`Nature article ${link} has no JSON-LD metadata`);
    }

    let meta;
    try {
        meta = JSON.parse(json);
    } catch (error) {
        throw new NatureArticleError(`Nature article ${link} has invalid JSON-LD metadata: ${errorMessage(error)}`);
    }

    if (meta === null) {
        throw new NatureArticleError(`Nature article ${link} JSON-LD parsed to null`);
    }

    if (!meta.mainEntity) {
        throw new NatureArticleError(`Nature article ${link} JSON-LD has no mainEntity`);
    }

    return meta;
};

const assertNotChallenge = ($: ReturnType<typeof load>, link: string) => {
    const pageText = `${$('title').text()}\n${$('body').text()}`;

    if (/Client Challenge/i.test(pageText)) {
        throw new NatureClientChallengeError(link);
    }
};

export const parseArticle = (item: NatureResearchItem, response: string) => {
    const $ = load(response);

    assertNotChallenge($, item.link);

    if (new URL(item.link).pathname.startsWith('/immersive/')) {
        let meta;
        try {
            meta = getDataLayer($);
        } catch (error) {
            throw new NatureArticleError(`Nature immersive article ${item.link} has invalid dataLayer metadata: ${errorMessage(error)}`);
        }

        item.doi = meta.content.article?.doi;
        item.author = meta.content.contentInfo.authors.join(', ');
        item.pubDate = parseDate(meta.content.contentInfo.publishedAt, 'X') || item.pubDate;
        return item;
    }

    const meta = getJsonLd($, item.link);
    const mainEntity = meta.mainEntity;
    const freeAccess = mainEntity.isAccessibleForFree;

    if (typeof mainEntity.sameAs === 'string' && mainEntity.sameAs.startsWith('https://doi.org/')) {
        item.doi = mainEntity.sameAs.replace('https://doi.org/', '');
    }
    if (Array.isArray(mainEntity.author)) {
        item.author = mainEntity.author.map((author) => author.name.replace(', ', ' ')).join(', ');
    }
    item.category = mainEntity.keywords;
    item.pubDate = parseDate(mainEntity.datePublished) || item.pubDate;

    fixFigure($);

    $('section[data-recommended=jobs], span[data-recommended=jobs]').remove();
    $('#further-reading-section').remove();
    $('figure div.u-text-right.u-hide-print').remove();

    let description;
    if (freeAccess) {
        description = $('.c-article-body').html();
    } else {
        $('div.c-article-access-provider, h2#access-options, div[data-component=entitlement-box], div[class^=LiveAreaSection-], nav.c-access-options').remove();
        description =
            $('.c-article-body').html() ||
            `${$('.c-article-teaser-text').html() ?? ''}${$('div.u-clear-both.c-article-wide-figure').html() ?? ''}${$('.article__teaser').html() ?? ''}${$('.c-article-references__container').html() ?? ''}`;
    }

    if (!description) {
        throw new NatureArticleError(`Nature article ${item.link} has no article body`);
    }

    if ($('div.c-pdf-download').length) {
        description += `<a href="${$('div.c-pdf-download a').attr('href')}">Download PDF</a>`;
    }

    item.description = description;
    return item;
};

export const getArticle = (item: NatureResearchItem) =>
    cache.tryGet(item.link, async () => {
        const response = await ofetch(item.link);
        return parseArticle(item, response);
    });

const getArticleWithRetries = async (item: NatureResearchItem, options: FetchDetailOptions) => {
    let lastError: unknown;

    for (let attempt = 0; attempt <= options.retries; attempt++) {
        try {
            return await getArticle(item);
        } catch (error) {
            lastError = error;

            if (!isTransientError(error) || attempt === options.retries) {
                break;
            }

            await sleepWithJitter(options, attempt + 1);
        }
    }

    throw new Error(`Failed to fetch Nature article ${item.link} after ${options.retries + 1} attempt(s): ${errorMessage(lastError)}`);
};

export const fetchArticleDetails = async (items: NatureResearchItem[], options: FetchDetailOptions) => {
    const detailedItems: NatureResearchItem[] = [];

    for (const item of items) {
        await sleepWithJitter(options);

        try {
            detailedItems.push(await getArticleWithRetries(item, options));
        } catch (error) {
            if (!options.partial) {
                throw error;
            }
            detailedItems.push(item);
        }
    }

    return detailedItems;
};

const getPageTitle = ($: ReturnType<typeof load>, journal: string) => {
    try {
        return getDataLayer($).content.journal.title;
    } catch {
        return journalNames[journal] ?? journal;
    }
};

// Fetch the research-articles listing, retrying when it comes back empty.
// nature.com intermittently serves a challenge/empty page to the plain `got`
// request - far more often for high-traffic flagship journals (nature, ncomms)
// than for the smaller ones - which otherwise yields zero items and a hard
// "route is empty" 503. Retrying the listing dodges those transient blocks.
const fetchListing = async (pageURL: string, limit: number, options: { delayMs: number; jitterMs: number; retries: number }) => {
    let pageCapture: ReturnType<typeof load> | undefined;

    for (let attempt = 0; attempt <= options.retries; attempt++) {
        try {
            const pageResponse = await got(pageURL, { cookieJar });
            pageCapture = load(pageResponse.data);
            const items = (getArticleList(pageCapture) as NatureResearchItem[]).slice(0, limit).map((item) => ({
                ...item,
                guid: item.link,
            }));
            if (items.length > 0) {
                return { pageCapture, items };
            }
        } catch {
            // Network/HTTP error: fall through to the retry delay below.
        }

        if (attempt < options.retries) {
            await sleepWithJitter(options, attempt + 1);
        }
    }

    return { pageCapture, items: [] as NatureResearchItem[] };
};

export const handler = async (ctx) => {
    const journal = ctx.req.param('journal') ?? 'nature';
    const limit = parsePositiveInteger(ctx.req.query('limit'), defaultLimit);
    const delayMs = parseNonNegativeInteger(ctx.req.query('delayMs'), defaultDelayMs);
    const jitterMs = parseNonNegativeInteger(ctx.req.query('jitterMs'), defaultJitterMs);
    const retries = parseNonNegativeInteger(ctx.req.query('retries'), defaultRetries);
    const partial = ctx.req.query('partial') === '1';
    const pageURL = `${baseUrl}/${journal}/research-articles`;

    const { pageCapture, items } = await fetchListing(pageURL, limit, { delayMs, jitterMs, retries });
    const pageTitle = pageCapture ? getPageTitle(pageCapture, journal) : (journalNames[journal] ?? journal);

    const detailedItems = await fetchArticleDetails(items, { delayMs, jitterMs, retries, partial });

    return {
        title: `Nature (${pageTitle}) | Latest Research`,
        description: pageCapture?.('meta[name="description"]').attr('content') || 'Nature, a nature research journal',
        link: pageURL,
        item: detailedItems,
    };
};

export const route: Route = {
    path: '/nature/research/:journal?',
    categories: ['journal'],
    example: '/journals/nature/research/nbt',
    parameters: {
        journal: 'short name for a Nature-family journal, `nature` by default',
    },
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: true,
        supportBT: false,
        supportPodcast: false,
        supportScihub: true,
    },
    radar: [
        {
            source: ['nature.com/:journal/research-articles', 'nature.com/:journal', 'nature.com/'],
            target: '/nature/research/:journal',
        },
    ],
    name: 'Nature Latest Research Full Content',
    maintainers: ['mulatta'],
    handler,
    description: `Local full-content Nature-family research route. It preserves RSSHub's Nature research item shape while fetching article details serially to avoid Nature Client Challenge bursts.

Examples:

- [/journals/nature/research/nbt](https://rsshub.app/journals/nature/research/nbt)
- [/journals/nature/research/ncomms?limit=20&delayMs=1500&jitterMs=1000](https://rsshub.app/journals/nature/research/ncomms?limit=20&delayMs=1500&jitterMs=1000)

Query parameters:

- \`limit\`: positive integer, defaults to \`${defaultLimit}\`.
- \`delayMs\`: non-negative integer base delay before article detail fetches and between retries, defaults to \`${defaultDelayMs}\`.
- \`jitterMs\`: non-negative integer random jitter added to each delay, defaults to \`${defaultJitterMs}\`.
- \`retries\`: non-negative integer retry count after the first attempt, defaults to \`${defaultRetries}\`.
- \`partial=1\`: keep list items when detail fetching fails. By default, any failed detail fetch fails the whole route so readers do not ingest challenge/error pages.

Supported journal short names include \`${Object.keys(journalNames).join('`, `')}\`.

Successful article detail parsing is cached through RSSHub cache. Client Challenge and malformed JSON-LD pages are rejected before caching.`,
};
