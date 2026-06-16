import type { Route } from '@/types';
import cache from '@/utils/cache';

import playwright from '../stealth';
import { collectResearchArticleDetails, defaultDelayMs, defaultJitterMs, defaultRetries, feedMeta, fetchListing, normalizeJournal, pageUrlFor, parseDelayMs, parseJitterMs, parseLimit, parseListItems, parseRetries } from './index';

export const route: Route = {
    path: '/science/current/:journal?',
    categories: ['journal'],
    example: '/journals/science/current/science?limit=10',
    parameters: {
        journal: 'Short name for a journal: science, sciadv, sciimmunol, scirobotics, signaling, stm',
        limit: `Maximum article count. Defaults to 20`,
        delayMs: `Base delay before article detail fetches and between retries. Defaults to ${defaultDelayMs}`,
        jitterMs: `Random jitter added to each delay. Defaults to ${defaultJitterMs}`,
        retries: `Retry count for challenge/selector failures. Defaults to ${defaultRetries}`,
    },
    features: {
        requireConfig: false,
        requirePuppeteer: true,
        antiCrawler: true,
        supportBT: false,
        supportPodcast: false,
        supportScihub: true,
    },
    radar: [
        {
            source: ['science.org/journal/:journal', 'science.org/toc/:journal/current'],
            target: '/science/current/:journal',
        },
    ],
    name: 'Current Issue Full Content',
    maintainers: ['mulatta'],
    handler,
    description: `Full-content Science/AAAS current issue feed fetched through Playwright.

Examples:

- /journals/science/current/science?limit=10
- /journals/science/current/sciadv?limit=10`,
};

async function handler(ctx) {
    const { journal: journalParam } = ctx.req.param();
    const journal = normalizeJournal(journalParam);
    const limit = parseLimit(ctx.req.query('limit'));
    const options = {
        delayMs: parseDelayMs(ctx.req.query('delayMs')),
        jitterMs: parseJitterMs(ctx.req.query('jitterMs')),
        retries: parseRetries(ctx.req.query('retries')),
    };
    const pageUrl = pageUrlFor('current', journal);
    const browser = await playwright();

    try {
        const html = await fetchListing(browser, pageUrl, 'current', options);
        // Over-fetch candidates: the current issue interleaves research with
        // front matter, so walk up to 3x the limit (capped) and keep only
        // research types until `limit` are collected.
        const poolLimit = Math.min(limit * 3, 30);
        const list = parseListItems(html, 'current', poolLimit);
        const items = await collectResearchArticleDetails(list, browser, cache.tryGet, options, limit);

        return {
            ...feedMeta('current', journal, pageUrl, html),
            item: items,
        };
    } finally {
        await browser.close();
    }
}
