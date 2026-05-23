import { load } from 'cheerio';

import { config } from '@/config';
import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import { generatedHeaders, generateHeaders, PRESETS } from '@/utils/header-generator';
import { parseDate } from '@/utils/parse-date';
import type { Browser, Page } from '@/utils/playwright';

import { defaultDelayMs as sharedDefaultDelayMs, defaultJitterMs as sharedDefaultJitterMs, parseNonNegativeIntegerOption, parsePositiveIntegerOption, sleepWithJitter, type Sleep } from '../fetch-policy';
import playwright from '../stealth';

export const rootUrl = 'https://www.cell.com';
export const defaultKind = 'inpress';
export const defaultLimit = 20;
export const defaultDelayMs = sharedDefaultDelayMs;
export const defaultJitterMs = sharedDefaultJitterMs;
export const defaultRetries = 3;

const supportedKinds = new Set(['current', 'inpress']);
const supportedJournals = new Set([
    'cell',
    'molecular-cell',
    'cell-reports',
    'cell-systems',
    'stem-cell-reports',
    'iscience',
    'cell-genomics',
    'developmental-cell',
    'cancer-cell',
    'current-biology',
    'chem',
    'cell-host-microbe',
    'cell-reports-methods',
    'cell-reports-medicine',
    'cell-stem-cell',
    'matter',
    'structure',
    'biophysj',
]);

const genericLinkText = /^(full[-\s]*text|full text html|html|pdf|view article|article|open access)$/i;
const challengeText = /(just a moment|cloudflare|access denied|checking your browser|attention required)/i;
const articleHeadingText = /^(abstract|graphical abstract|introduction|results|discussion|star methods|methods|references|supplemental information|resource availability|materials and methods)$/i;

export type ListingItem = DataItem & {
    link: string;
};

export type ArticleFetchOptions = {
    delayMs: number;
    jitterMs?: number;
    random?: () => number;
    retries: number;
    sleep?: Sleep;
    useCache?: boolean;
};

export type PageFetcher = (browser: Browser, url: string, waitForSelector?: string) => Promise<string>;

export class CellPressChallengeError extends Error {
    constructor(message: string) {
        super(message);
        this.name = 'CellPressChallengeError';
    }
}

const cleanText = (value: string | undefined | null) => value?.replace(/\s+/g, ' ').trim() ?? '';

const absoluteUrl = (href: string | undefined, baseUrl: string) => {
    if (!href || href.startsWith('mailto:') || href.startsWith('javascript:')) {
        return;
    }

    try {
        const url = new URL(href, baseUrl);
        url.hash = '';
        return url.href;
    } catch {
        return;
    }
};

const parseMaybeDate = (value: string | undefined | null) => {
    const normalized = cleanText(value);
    return normalized ? parseDate(normalized) : undefined;
};

const pickText = (root: ReturnType<ReturnType<typeof load>>, selectors: string[]) => {
    for (const selector of selectors) {
        const text = cleanText(root.find(selector).first().text());
        if (text) {
            return text;
        }
    }
    return '';
};

const isBetterTitle = (candidate: string | undefined, current: string | undefined) => {
    const normalizedCandidate = cleanText(candidate);
    const normalizedCurrent = cleanText(current);

    if (!normalizedCandidate || genericLinkText.test(normalizedCandidate)) {
        return false;
    }
    if (!normalizedCurrent || genericLinkText.test(normalizedCurrent)) {
        return true;
    }
    return normalizedCandidate.length > normalizedCurrent.length;
};

const closestArticleCard = ($: ReturnType<typeof load>, anchor: ReturnType<ReturnType<typeof load>>) => {
    const card = anchor.closest('article, li, .article, .article-item, .toc__item, .issue-item, .search-result, .card, [class*="article"], [class*="Article"]');
    return card.length ? card : anchor.parent();
};

export const listingUrl = (journal: string, kind: string) => `${rootUrl}/${journal}/${kind}`;

export const parseRouteOptions = (ctx) => {
    const journal = ctx.req.param('journal');
    const kind = ctx.req.param('kind') || defaultKind;

    if (!supportedJournals.has(journal)) {
        throw new Error(`Unsupported Cell Press journal: ${journal}`);
    }
    if (!supportedKinds.has(kind)) {
        throw new Error(`Unsupported Cell Press feed kind: ${kind}`);
    }

    return {
        delayMs: parseNonNegativeIntegerOption(ctx.req.query('delayMs'), defaultDelayMs, 10000),
        jitterMs: parseNonNegativeIntegerOption(ctx.req.query('jitterMs'), defaultJitterMs, 10000),
        journal,
        kind,
        limit: parsePositiveIntegerOption(ctx.req.query('limit'), defaultLimit, 100),
        retries: parsePositiveIntegerOption(ctx.req.query('retries'), defaultRetries, 5),
    };
};

export const parseListingHtml = (html: string, journal: string, kind: string, limit = defaultLimit): ListingItem[] => {
    const $ = load(html);
    const baseUrl = listingUrl(journal, kind);
    const items = new Map<string, ListingItem>();

    $('a[href*="/fulltext/"]')
        .toArray()
        .forEach((element) => {
            const anchor = $(element);
            const link = absoluteUrl(anchor.attr('href'), baseUrl);
            if (!link) {
                return;
            }

            const url = new URL(link);
            if (!url.pathname.startsWith(`/${journal}/fulltext/`)) {
                return;
            }

            const card = closestArticleCard($, anchor);
            const title = cleanText(anchor.attr('title')) || pickText(card, ['[data-testid*="title"]', '[class*="title"]', '[class*="Title"]', 'h1', 'h2', 'h3', 'h4']) || cleanText(anchor.text()) || link;
            const author = pickText(card, ['[class*="authors"]', '[class*="Authors"]', '[class*="author-list"]', '[class*="loa"]', '[data-testid*="author"]']);
            const pubDate =
                parseMaybeDate(card.find('time').first().attr('datetime')) || parseMaybeDate(card.find('time').first().text()) || parseMaybeDate(pickText(card, ['[class*="date"]', '[class*="Date"]', '[data-testid*="date"]']));
            const existing = items.get(link);
            if (existing) {
                if (isBetterTitle(title, existing.title)) {
                    existing.title = title;
                }
                existing.author ||= author;
                existing.pubDate ||= pubDate;
                return;
            }

            items.set(link, {
                author,
                guid: link,
                link,
                pubDate,
                title: genericLinkText.test(title) ? link : title,
            });
        });

    return [...items.values()].slice(0, limit);
};

const absolutizeDocument = ($: ReturnType<typeof load>, baseUrl: string) => {
    $('a[href]').each((_, element) => {
        const link = absoluteUrl($(element).attr('href'), baseUrl);
        if (link) {
            $(element).attr('href', link);
        }
    });

    $('img').each((_, element) => {
        const image = $(element);
        const src = image.attr('src') || image.attr('data-src') || image.attr('data-original') || image.attr('data-lazy-src');
        const absoluteSrc = absoluteUrl(src, baseUrl);
        if (absoluteSrc) {
            image.attr('src', absoluteSrc);
        }

        const srcset = image.attr('srcset');
        if (srcset) {
            const absoluteSrcset = srcset
                .split(',')
                .map((candidate) => {
                    const [candidateUrl, descriptor] = candidate.trim().split(/\s+/, 2);
                    const absoluteCandidate = absoluteUrl(candidateUrl, baseUrl);
                    return absoluteCandidate ? [absoluteCandidate, descriptor].filter(Boolean).join(' ') : candidate.trim();
                })
                .join(', ');
            image.attr('srcset', absoluteSrcset);
        }
    });

    $('source[srcset]').each((_, element) => {
        const source = $(element);
        const srcset = source.attr('srcset');
        if (srcset) {
            source.attr(
                'srcset',
                srcset
                    .split(',')
                    .map((candidate) => {
                        const [candidateUrl, descriptor] = candidate.trim().split(/\s+/, 2);
                        const absoluteCandidate = absoluteUrl(candidateUrl, baseUrl);
                        return absoluteCandidate ? [absoluteCandidate, descriptor].filter(Boolean).join(' ') : candidate.trim();
                    })
                    .join(', ')
            );
        }
    });
};

const cleanElement = ($: ReturnType<typeof load>, element: ReturnType<ReturnType<typeof load>>) => {
    element
        .find(
            [
                'script',
                'style',
                'noscript',
                'iframe',
                'form',
                'button',
                'nav',
                'header',
                'footer',
                '.advertisement',
                '.ad',
                '[class*="advert"]',
                '[class*="Advertisement"]',
                '[id*="advert"]',
                '[id^="ad-"]',
                '[class*="login"]',
                '[id*="login"]',
                '[class*="toolbar"]',
                '[class*="share"]',
                '[aria-label*="advertisement"]',
                '[aria-label*="Advertisement"]',
            ].join(', ')
        )
        .remove();
};

const htmlOfFirst = ($: ReturnType<typeof load>, selector: string) => {
    const element = $(selector).first();
    if (!element.length) {
        return '';
    }

    const clone = element.clone();
    cleanElement($, clone);
    return cleanText(clone.text()) ? $.html(clone) : '';
};

const addUniqueHtml = (pieces: string[], seenText: Set<string>, $: ReturnType<typeof load>, html: string) => {
    if (!html) {
        return;
    }

    const text = cleanText(load(html).text()).slice(0, 500);
    if (!text || seenText.has(text)) {
        return;
    }

    seenText.add(text);
    pieces.push(html);
};

const renderArticleDescription = ($: ReturnType<typeof load>, url: string) => {
    absolutizeDocument($, url);

    const pieces: string[] = [];
    const seenText = new Set<string>();
    const leadingSelectors = ['#graphical-abstract', '.graphical-abstract', '[class*="graphical-abstract"]', '[class*="GraphicalAbstract"]', '#abstract', '#abstracts', 'section.abstract', '.abstract', '[class*="Abstract"]'];
    const bodySelectors = ['#bodymatter', '#article-body', '.article-body', '.article__body', '.ArticleBody', '[data-testid="article-body"]'];
    const referenceSelectors = ['#references', 'section.references', '.references', '[class*="References"]'];
    let hasBodyContainer = false;

    for (const selector of leadingSelectors) {
        addUniqueHtml(pieces, seenText, $, htmlOfFirst($, selector));
    }

    for (const selector of bodySelectors) {
        const html = htmlOfFirst($, selector);
        hasBodyContainer ||= Boolean(html);
        addUniqueHtml(pieces, seenText, $, html);
    }

    if (!hasBodyContainer) {
        $('section')
            .toArray()
            .forEach((element) => {
                const section = $(element);
                const heading = cleanText(section.find('h1, h2, h3').first().text());
                if (articleHeadingText.test(heading)) {
                    const clone = section.clone();
                    cleanElement($, clone);
                    addUniqueHtml(pieces, seenText, $, $.html(clone));
                }
            });
    }

    for (const selector of referenceSelectors) {
        addUniqueHtml(pieces, seenText, $, htmlOfFirst($, selector));
    }

    if (pieces.length === 0) {
        const fallback = $('main article, article, main, #page-body-id').first().clone();
        if (fallback.length) {
            cleanElement($, fallback);
            addUniqueHtml(pieces, seenText, $, $.html(fallback));
        }
    }

    return pieces.join('\n');
};

const metaContent = ($: ReturnType<typeof load>, selectors: string[]) => {
    for (const selector of selectors) {
        const content = cleanText($(selector).first().attr('content'));
        if (content) {
            return content;
        }
    }
    return '';
};

const metaContents = ($: ReturnType<typeof load>, selector: string) =>
    $(selector)
        .toArray()
        .map((element) => cleanText($(element).attr('content')))
        .filter(Boolean);

const parseDoi = ($: ReturnType<typeof load>) => {
    const fromMeta = metaContent($, ['meta[name="citation_doi"]', 'meta[name="dc.Identifier"]', 'meta[name="DC.Identifier"]']);
    if (fromMeta) {
        return fromMeta.replace(/^doi:\s*/i, '');
    }

    const doiLink = cleanText($('a[href*="doi.org/"]').first().text()) || $('a[href*="doi.org/"]').first().attr('href') || '';
    const doiMatch = doiLink.match(/10\.\d{4,9}\/\S+/);
    return doiMatch?.[0]?.replace(/[).,;]+$/, '');
};

const hasExpectedArticleContent = ($: ReturnType<typeof load>) => {
    const title = metaContent($, ['meta[name="citation_title"]', 'meta[property="og:title"]']) || cleanText($('h1').first().text());
    const abstract = cleanText($('#abstract, #abstracts, section.abstract, .abstract, [class*="Abstract"]').first().text());
    const body = cleanText($('#bodymatter, #article-body, .article-body, .article__body, .ArticleBody, [data-testid="article-body"]').first().text());
    const knownSections = $('section')
        .toArray()
        .some((element) => articleHeadingText.test(cleanText($(element).find('h1, h2, h3').first().text())));

    return Boolean(title && (abstract || body || knownSections));
};

export const isChallengeOrErrorPage = ($: ReturnType<typeof load>) => {
    if (!challengeText.test(`${$('title').text()} ${$('body').text()}`)) {
        return false;
    }

    return !hasExpectedArticleContent($);
};

export const parseArticleHtml = (html: string, url: string, fallback: ListingItem): ListingItem => {
    const $ = load(html);

    if (isChallengeOrErrorPage($) || !hasExpectedArticleContent($)) {
        throw new CellPressChallengeError(`Cell Press article content missing or blocked for ${url}`);
    }

    const title = metaContent($, ['meta[name="citation_title"]', 'meta[property="og:title"]', 'meta[name="twitter:title"]']) || cleanText($('h1').first().text()) || fallback.title;
    const authors = metaContents($, 'meta[name="citation_author"]');
    const author = authors.length > 0 ? authors.join(', ') : pickText($('body'), ['[class*="authors"]', '[class*="Authors"]', '[class*="author-list"]', '[data-testid*="author"]']) || fallback.author;
    const pubDate =
        parseMaybeDate(metaContent($, ['meta[name="citation_publication_date"]', 'meta[name="citation_online_date"]', 'meta[property="article:published_time"]'])) ||
        parseMaybeDate($('time').first().attr('datetime')) ||
        parseMaybeDate($('time').first().text()) ||
        fallback.pubDate;
    const doi = parseDoi($) || fallback.doi;
    const description = renderArticleDescription($, url);

    if (!cleanText(load(description).text())) {
        throw new CellPressChallengeError(`Cell Press article description empty for ${url}`);
    }

    return {
        ...fallback,
        author,
        description,
        doi,
        guid: doi || fallback.guid || url,
        link: url,
        pubDate,
        title,
    };
};

const policy = (options: ArticleFetchOptions) => ({
    delayMs: options.delayMs,
    jitterMs: options.jitterMs ?? defaultJitterMs,
    random: options.random,
    sleep: options.sleep,
});

const configureStealthPage = async (page: Page, referer?: string) => {
    const headers = generateHeaders(PRESETS.MODERN_MACOS_CHROME);
    const userAgent = headers['user-agent'];

    if (userAgent) {
        await page.setUserAgent(userAgent);
    }

    await page.setExtraHTTPHeaders({
        ...Object.fromEntries([...generatedHeaders].filter((header) => headers[header]).map((header) => [header, headers[header]])),
        ...(referer ? { referer } : {}),
        'accept-language': headers['accept-language'] || 'en-US,en;q=0.9',
    });

    await page.setRequestInterception(true);
    page.on('request', (request) => {
        const resourceType = request.resourceType();
        if (resourceType === 'image' || resourceType === 'font' || resourceType === 'media') {
            return request.abort();
        }
        return request.continue();
    });
};

export const fetchPageHtml: PageFetcher = async (browser, url, waitForSelector) => {
    const page = await browser.newPage();
    try {
        await configureStealthPage(page, rootUrl);
        await page.goto(url, {
            timeout: 60000,
            waitUntil: 'domcontentloaded',
        });
        if (waitForSelector) {
            await page.waitForSelector(waitForSelector, { timeout: 30000 }).catch(() => undefined);
        }
        await page.waitForTimeout(2000);
        return await page.evaluate(() => document.documentElement.outerHTML);
    } finally {
        await page.close();
    }
};

export const fetchArticleWithRetries = async (browser: Browser, item: ListingItem, options: ArticleFetchOptions, fetcher: PageFetcher = fetchPageHtml) => {
    let lastError: unknown;

    for (let attempt = 1; attempt <= options.retries; attempt++) {
        try {
            const html = await fetcher(browser, item.link, '#bodymatter, #article-body, .article-body, .article__body, .ArticleBody, [data-testid="article-body"]');
            return parseArticleHtml(html, item.link, item);
        } catch (error) {
            lastError = error;
            if (attempt < options.retries) {
                await sleepWithJitter(policy(options), attempt);
            }
        }
    }

    throw new Error(`Failed to fetch Cell Press article after ${options.retries} attempts: ${item.link}; ${lastError instanceof Error ? lastError.message : String(lastError)}`);
};

export const fetchArticleDetailsSerial = async (browser: Browser, items: ListingItem[], options: ArticleFetchOptions, fetcher: PageFetcher = fetchPageHtml) => {
    const detailedItems: ListingItem[] = [];

    for (const item of items) {
        const loadArticle = async () => {
            await sleepWithJitter(policy(options));
            return fetchArticleWithRetries(browser, item, options, fetcher);
        };
        detailedItems.push(options.useCache === false ? await loadArticle() : await cache.tryGet(`cellpress:article:${item.link}`, loadArticle, config.cache.contentExpire));
    }

    return detailedItems;
};

export const handler = async (ctx) => {
    const options = parseRouteOptions(ctx);
    const currentUrl = listingUrl(options.journal, options.kind);
    const browser = await playwright();

    try {
        const listingHtml = await fetchPageHtml(browser, currentUrl, 'a[href*="/fulltext/"]');
        const items = parseListingHtml(listingHtml, options.journal, options.kind, options.limit);
        const detailedItems = await fetchArticleDetailsSerial(browser, items, {
            delayMs: options.delayMs,
            jitterMs: options.jitterMs,
            retries: options.retries,
        });

        const title = `Cell Press ${options.journal} ${options.kind} full content`;
        return {
            title,
            description: title,
            link: currentUrl,
            item: detailedItems,
            language: 'en',
        };
    } finally {
        await browser.close();
    }
};

export const route: Route = {
    path: '/cell/:journal/:kind?',
    name: 'Cell Press full content',
    url: 'www.cell.com',
    maintainers: ['mulatta'],
    handler,
    example: '/journals/cell/cell/inpress?limit=10',
    parameters: {
        journal: 'Cell Press journal slug, for example `cell` or `molecular-cell`',
        kind: '`current` or `inpress`, defaults to `inpress`',
        limit: `Maximum article count. Defaults to ${defaultLimit}`,
        delayMs: `Base delay before article detail fetches and between retries. Defaults to ${defaultDelayMs}`,
        jitterMs: `Random jitter added to each delay. Defaults to ${defaultJitterMs}`,
        retries: `Retry count for challenge/selector failures. Defaults to ${defaultRetries}`,
    },
    categories: ['journal'],
    features: {
        requireConfig: false,
        requirePuppeteer: true,
        antiCrawler: true,
        supportRadar: true,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    radar: [
        {
            source: ['www.cell.com/:journal/:kind'],
            target: '/cell/:journal/:kind',
        },
    ],
};
