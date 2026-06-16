import type { Cheerio, Element } from 'cheerio';
import { load } from 'cheerio';
import { raw } from 'hono/html';
import { renderToString } from 'hono/jsx/dom/server';

import type { DataItem } from '@/types';
import { generateHeaders, PRESETS } from '@/utils/header-generator';
import { parseDate } from '@/utils/parse-date';
import type { Browser, Page } from '@/utils/playwright';

import { isIncludedArticleType } from '../article-type';
import { defaultDelayMs as sharedDefaultDelayMs, defaultJitterMs as sharedDefaultJitterMs, parseNonNegativeIntegerOption, parsePositiveIntegerOption, sleepWithJitter, type Sleep } from '../fetch-policy';

export const baseUrl = 'https://www.science.org';
export const defaultJournal = 'science';
export const defaultLimit = 20;
export const defaultDelayMs = sharedDefaultDelayMs;
export const defaultJitterMs = sharedDefaultJitterMs;
export const defaultRetries = 3;

export const journals = {
    science: 'Science',
    sciadv: 'Science Advances',
    sciimmunol: 'Science Immunology',
    scirobotics: 'Science Robotics',
    signaling: 'Science Signaling',
    stm: 'Science Translational Medicine',
} as const;

type Journal = keyof typeof journals;
type RouteKind = 'current' | 'early';
type CacheGetter<T> = (key: string, getter: () => Promise<T>) => Promise<T>;

export type ScienceItem = DataItem & {
    doi?: string;
    link: string;
    articleType?: string;
};

export type FetchOptions = {
    delayMs?: number;
    jitterMs?: number;
    random?: () => number;
    retries?: number;
    sleep?: Sleep;
};

const selectors = {
    article: 'section#bodymatter, .news-article-content, .news-article-content--featured',
    currentList: '.toc__section .card',
    earlyList: '.toc__section .card, .card-content .card-header',
};

const fallbackUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';
const challengePattern = /just a moment|cloudflare|access denied|cf-browser-verification|cf-chl-|challenge-platform|attention required/i;
const blockedResourceTypes = new Set(['image', 'media', 'font']);

export class ScienceChallengeError extends Error {
    constructor(message: string) {
        super(message);
        this.name = 'ScienceChallengeError';
    }
}

export class ScienceFetchError extends Error {
    constructor(message: string, options?: { cause?: unknown }) {
        super(message, options);
        this.name = 'ScienceFetchError';
    }
}

export const parseLimit = (value: string | undefined) => parsePositiveIntegerOption(value, defaultLimit);
export const parseDelayMs = (value: string | undefined) => parseNonNegativeIntegerOption(value, defaultDelayMs);
export const parseJitterMs = (value: string | undefined) => parseNonNegativeIntegerOption(value, defaultJitterMs);
export const parseRetries = (value: string | undefined) => parsePositiveIntegerOption(value, defaultRetries);

export const normalizeJournal = (journal: string | undefined): Journal => {
    const normalized = (journal || defaultJournal).toLowerCase();
    if (normalized in journals) {
        return normalized as Journal;
    }
    throw new Error(`Unsupported Science journal: ${journal}`);
};

export const pageUrlFor = (kind: RouteKind, journal: Journal) => `${baseUrl}/toc/${journal}/${kind === 'current' ? 'current' : '0/0'}`;

const absoluteScienceUrl = (href: string | undefined) => {
    if (!href) {
        return '';
    }
    return new URL(href, baseUrl).href;
};

const extractDoi = (href: string | undefined) => {
    if (!href) {
        return undefined;
    }

    const pathname = new URL(href, baseUrl).pathname;
    return pathname.replace(/^\/doi\//, '');
};

const text = (element: Cheerio<Element>, selector: string) => element.find(selector).text().replace(/\s+/g, ' ').trim();

export const parseListItems = (html: string, kind: RouteKind, limit = defaultLimit): ScienceItem[] => {
    const $ = load(html);
    const listSelector = kind === 'current' ? selectors.currentList : selectors.earlyList;

    return $(listSelector)
        .toArray()
        .map((element): ScienceItem | undefined => {
            const item = $(element);
            const titleLink = item.find('.article-title a, a[href*="/doi/"]').first();
            const title = titleLink.attr('title') || titleLink.text().replace(/\s+/g, ' ').trim();
            const href = titleLink.attr('href');
            const link = absoluteScienceUrl(href);

            if (!title || !link) {
                return;
            }

            const pubDateText = item.find('.card-meta__item time, time').first().attr('datetime') || text(item, '.card-meta__item time, time');
            const authors = item
                .find('.card-meta ul[title="list of authors"] li, .loa-authors li, .authors li')
                .toArray()
                .map((author) => $(author).text().replace(/\s+/g, ' ').trim())
                .filter(Boolean)
                .join(', ');

            return {
                title,
                link,
                doi: extractDoi(href),
                pubDate: pubDateText ? parseDate(pubDateText) : undefined,
                author: authors || undefined,
            };
        })
        .filter((item): item is ScienceItem => item !== undefined)
        .slice(0, limit);
};

export const renderDescription = (abstract: string | null | undefined, content: string | null | undefined): string =>
    renderToString(
        <>
            {abstract ? raw(abstract) : null}
            {content ? (
                <>
                    <br />
                    {raw(content)}
                </>
            ) : null}
        </>
    );

export const parseArticleDescription = (html: string) => {
    const $ = load(html);
    const abstract = $('div#abstracts').html();
    const content = $('.news-article-content--featured').length
        ? $('.news-article-content--featured').html()
        : $('.news-article-content').length
          ? $('.news-article-content').html()
          : $('.info-panel__formats a.btn__request-access').length || $('.info-panel__formats a.btn--access').length
            ? ''
            : $('section#bodymatter').html();

    return renderDescription(abstract, content);
};

const shouldBlockRequest = (resourceType: string) => blockedResourceTypes.has(resourceType);

const stealthHeaders = () => {
    const generated = generateHeaders(PRESETS.MODERN_MACOS_CHROME);
    const headers: Record<string, string> = {
        accept: generated.accept || 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'accept-language': generated['accept-language'] || 'en-US,en;q=0.9',
        referer: baseUrl,
        'user-agent': generated['user-agent'] || fallbackUserAgent,
    };

    for (const name of ['sec-ch-ua', 'sec-ch-ua-mobile', 'sec-ch-ua-platform', 'upgrade-insecure-requests', 'sec-fetch-site', 'sec-fetch-mode', 'sec-fetch-user', 'sec-fetch-dest', 'priority']) {
        if (generated[name]) {
            headers[name] = generated[name];
        }
    }

    return headers;
};

export const prepareStealthPage = async (page: Page) => {
    const headers = stealthHeaders();
    const { 'user-agent': userAgent, ...extraHeaders } = headers;

    await page.setUserAgent(userAgent);
    await page.setExtraHTTPHeaders(extraHeaders);
    await page.setRequestInterception(true);
    page.on('request', (request) => {
        if (shouldBlockRequest(request.resourceType())) {
            return request.abort();
        }
        return request.continue();
    });
};

const isChallenge = (html: string, status?: number | null) => {
    const $ = load(html);
    const title = $('title').text();
    const bodyText = $('body').text().slice(0, 5000);
    return status === 403 || challengePattern.test(title) || challengePattern.test(bodyText) || challengePattern.test(html.slice(0, 5000));
};

const fetchHtmlOnce = async (browser: Browser, url: string, expectedSelector: string) => {
    const page = await browser.newPage();

    try {
        await prepareStealthPage(page);
        const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });
        const status = response?.status();
        const html = await page.content();

        if (isChallenge(html, status)) {
            throw new ScienceChallengeError(`Science.org challenge page while fetching ${url}`);
        }

        try {
            await page.waitForSelector(expectedSelector, { timeout: 15000 });
        } catch (error) {
            const latestHtml = await page.content();
            if (isChallenge(latestHtml, status)) {
                throw new ScienceChallengeError(`Science.org challenge page while fetching ${url}`);
            }
            throw new ScienceFetchError(`Science.org page missing expected selector ${expectedSelector}: ${url}`, { cause: error });
        }

        return await page.content();
    } finally {
        await page.close();
    }
};

const policy = (options: FetchOptions) => ({
    delayMs: options.delayMs ?? defaultDelayMs,
    jitterMs: options.jitterMs ?? defaultJitterMs,
    random: options.random,
    sleep: options.sleep,
});

export const fetchHtmlWithRetries = async (browser: Browser, url: string, expectedSelector: string, options: FetchOptions = {}) => {
    const retries = options.retries ?? defaultRetries;
    let lastError: unknown;

    for (let attempt = 1; attempt <= retries; attempt++) {
        try {
            return await fetchHtmlOnce(browser, url, expectedSelector);
        } catch (error) {
            lastError = error;
            if (attempt < retries) {
                await sleepWithJitter(policy(options), attempt);
            }
        }
    }

    throw new ScienceFetchError(`Science.org fetch failed after ${retries} attempts: ${url}`, { cause: lastError });
};

export const fetchListing = async (browser: Browser, url: string, kind: RouteKind, options: FetchOptions = {}) => {
    const listSelector = kind === 'current' ? selectors.currentList : selectors.earlyList;
    return fetchHtmlWithRetries(browser, url, listSelector, options);
};

export const parseArticleType = (html: string): string => {
    const $ = load(html);
    const label = $('.meta-panel__type').first().text().replace(/\s+/g, ' ').trim() || ($('meta[name="dc.Type"]').attr('content') ?? '').trim();
    if (label) {
        return label;
    }
    // News/blog items (ScienceInsider, In Depth, New Products, ...) render
    // through a separate template that carries no scholarly type marker at all,
    // unlike Editorials/Perspectives/Letters which do. Without this they would
    // hit the keep-on-unknown fallback and leak into the feed, so flag the news
    // template explicitly. Genuine scholarly pages always carry `#bodymatter`,
    // so an unmarked page with only news content is news.
    if ($('.news-article-content, .news-article-content--featured').length && !$('section#bodymatter').length) {
        return 'News';
    }
    return '';
};

const enrichArticle = async (browser: Browser, item: ScienceItem, options: FetchOptions) => {
    const html = await fetchHtmlWithRetries(browser, item.link, selectors.article, options);
    return {
        ...item,
        articleType: parseArticleType(html),
        description: parseArticleDescription(html),
    };
};

export const fetchArticleDetails = async (items: ScienceItem[], browser: Browser, tryGet: CacheGetter<ScienceItem>, options: FetchOptions = {}) => {
    const details: ScienceItem[] = [];

    for (const item of items) {
        details.push(
            await tryGet(item.link, async () => {
                await sleepWithJitter(policy(options));
                return enrichArticle(browser, item, options);
            })
        );
    }

    return details;
};

// Walk the listing pool and keep only research-type articles (see
// article-type.ts) until `limit` are collected. The Science current/early
// listings interleave research with editorials, perspectives, letters, news
// and book reviews, and the type is only known after fetching the article page,
// so we over-fetch and stop early. A candidate whose fetch fails (challenge/
// missing selector) is skipped rather than failing the whole feed.
export const collectResearchArticleDetails = async (items: ScienceItem[], browser: Browser, tryGet: CacheGetter<ScienceItem>, options: FetchOptions, limit: number) => {
    const kept: ScienceItem[] = [];

    for (const item of items) {
        if (kept.length >= limit) {
            break;
        }
        let detailed: ScienceItem;
        try {
            detailed = await tryGet(item.link, async () => {
                await sleepWithJitter(policy(options));
                return enrichArticle(browser, item, options);
            });
        } catch {
            continue;
        }
        if (isIncludedArticleType(detailed.articleType)) {
            kept.push(detailed);
        }
    }

    return kept;
};

export const feedMeta = (kind: RouteKind, journal: Journal, pageUrl: string, html: string) => {
    const $ = load(html);
    const title = $('head > title, head title').first().text().trim();
    const journalName = journals[journal];

    if (kind === 'current') {
        return {
            title: `${title || journalName} | Current Issue`,
            description: `Current Issue of ${title || journalName}`,
            image: `${baseUrl}/apple-touch-icon.png`,
            link: pageUrl,
            language: 'en-US',
        };
    }

    return {
        title: title || `${journalName} | First Release`,
        description: $('.body02').text().trim() || `First Release of ${title || journalName}`,
        image: `${baseUrl}/apple-touch-icon.png`,
        link: pageUrl,
        language: 'en-US',
    };
};
