import { load } from 'cheerio';
import { describe, expect, it, vi } from 'vitest';

import { collectResearchArticleDetails, fetchArticleDetails, fetchListing, parseArticleDescription, parseArticleType, parseLimit, parseListItems, ScienceFetchError, type ScienceItem } from '@/routes/journals/science';

const listingHtml = `<!doctype html>
<html>
<head><title>Science Current Issue</title></head>
<body>
<section class="toc__section">
  <div class="card">
    <h3 class="article-title"><a href="/doi/abs/10.1126/science.adg8401" title="A quantum leap">A quantum leap</a></h3>
    <div class="card-meta__item"><time datetime="2026-05-20">20 May 2026</time></div>
    <div class="card-meta"><ul title="list of authors"><li>Ada Lovelace</li><li>Grace Hopper</li></ul></div>
  </div>
  <div class="card">
    <h3 class="article-title"><a href="/doi/full/10.1126/science.abc1234" title="Cells on the move">Cells on the move</a></h3>
    <div class="card-meta__item"><time>21 May 2026</time></div>
    <div class="card-meta"><ul title="list of authors"><li>Rosalind Franklin</li></ul></div>
  </div>
</section>
</body>
</html>`;

const articleHtml = `<!doctype html>
<html>
<head><title>Article</title></head>
<body>
<div id="abstracts">
  <section><h2>Structured Abstract</h2><p>Structured summary text.</p></section>
  <section><h2>Abstract</h2><p>Abstract summary text.</p></section>
</div>
<section id="bodymatter">
  <h2>Body</h2>
  <p>Full body paragraph.</p>
  <figure><figcaption>Figure caption.</figcaption></figure>
</section>
</body>
</html>`;

class FakePage {
    constructor(
        private readonly htmlForUrl: (url: string) => string,
        private readonly visited: string[]
    ) {}

    setUserAgent = vi.fn(async () => {});
    setExtraHTTPHeaders = vi.fn(async () => {});
    addInitScript = vi.fn(async () => {});
    setRequestInterception = vi.fn(async () => {});
    on = vi.fn(() => this);
    close = vi.fn(async () => {});
    private html = '';

    goto = vi.fn(async (url: string) => {
        this.visited.push(url);
        this.html = this.htmlForUrl(url);
        return { status: () => (this.html.includes('Access denied') ? 403 : 200) };
    });

    content = vi.fn(async () => this.html);

    waitForSelector = vi.fn(async (selector: string) => {
        const $ = load(this.html);
        if ($(selector).length === 0) {
            throw new Error(`missing selector ${selector}`);
        }
    });
}

class FakeBrowser {
    readonly visited: string[] = [];

    constructor(private readonly htmlForUrl: (url: string) => string) {}

    newPage = vi.fn(async () => new FakePage(this.htmlForUrl, this.visited) as any);
    close = vi.fn(async () => {});
}

const identityCache = async (_key: string, getter: () => Promise<any>) => getter();

describe('Science/AAAS full-content route helpers', () => {
    it('extracts listing items', () => {
        const items = parseListItems(listingHtml, 'current', 20);

        expect(items).toMatchObject([
            {
                title: 'A quantum leap',
                link: 'https://www.science.org/doi/abs/10.1126/science.adg8401',
                doi: 'abs/10.1126/science.adg8401',
                author: 'Ada Lovelace, Grace Hopper',
            },
            {
                title: 'Cells on the move',
                link: 'https://www.science.org/doi/full/10.1126/science.abc1234',
                doi: 'full/10.1126/science.abc1234',
                author: 'Rosalind Franklin',
            },
        ]);
    });

    it('fetches article details serially with delay', async () => {
        const items = parseListItems(listingHtml, 'current', 2);
        const browser = new FakeBrowser(() => articleHtml) as any;
        const sleep = vi.fn(async () => {});

        const details = await fetchArticleDetails(items, browser, identityCache, { delayMs: 25, jitterMs: 0, retries: 1, sleep });

        expect(browser.visited).toEqual(items.map((item) => item.link));
        expect(sleep).toHaveBeenCalledTimes(2);
        expect(sleep).toHaveBeenNthCalledWith(1, 25);
        expect(sleep).toHaveBeenNthCalledWith(2, 25);
        expect(details[0].description).toContain('Structured summary text.');
        expect(details[0].description).toContain('Full body paragraph.');
    });

    it('detects challenge pages and retries', async () => {
        let attempts = 0;
        const challengeHtml = '<html><head><title>Just a moment...</title></head><body>Cloudflare</body></html>';
        const browser = new FakeBrowser(() => (++attempts === 1 ? challengeHtml : listingHtml)) as any;
        const sleep = vi.fn(async () => {});

        const html = await fetchListing(browser, 'https://www.science.org/toc/science/current', 'current', { delayMs: 5, jitterMs: 0, retries: 2, sleep });

        expect(html).toContain('A quantum leap');
        expect(sleep).toHaveBeenCalledWith(5);
        expect(browser.visited).toEqual(['https://www.science.org/toc/science/current', 'https://www.science.org/toc/science/current']);
    });

    it('fails cleanly after challenge retries', async () => {
        const browser = new FakeBrowser(() => '<html><head><title>Access denied</title></head><body>Cloudflare</body></html>') as any;

        await expect(fetchListing(browser, 'https://www.science.org/toc/science/current', 'current', { delayMs: 0, retries: 2 })).rejects.toThrow(ScienceFetchError);
    });

    it('does not cache challenge pages', async () => {
        const items = parseListItems(listingHtml, 'current', 1);
        const stored = new Map<string, unknown>();
        const browser = new FakeBrowser(() => '<html><head><title>Access denied</title></head><body>Cloudflare</body></html>') as any;
        const tryGet = async (key: string, getter: () => Promise<any>) => {
            const value = await getter();
            stored.set(key, value);
            return value;
        };

        await expect(fetchArticleDetails(items, browser, tryGet, { delayMs: 0, retries: 1 })).rejects.toThrow(ScienceFetchError);
        expect(stored.size).toBe(0);
    });

    it('renders abstract and body content in description', () => {
        const description = parseArticleDescription(articleHtml);

        expect(description).toContain('Structured Abstract');
        expect(description).toContain('Abstract summary text.');
        expect(description).toContain('<br');
        expect(description).toContain('Full body paragraph.');
        expect(description).toContain('Figure caption.');
    });

    it('parses limit query', () => {
        expect(parseLimit('10')).toBe(10);
        expect(parseLimit('0')).toBe(20);
        expect(parseLimit('not-a-number')).toBe(20);
        expect(parseLimit(undefined)).toBe(20);
    });

    it('keeps only the research section of the current issue', () => {
        // Mirror the real markup: section heading is an <h4> and the first card's
        // <h3 class="article-title"> in the News section contains the word
        // "research" - the section filter must read the h4 label, not that title.
        const sectionedHtml = `<!doctype html><html><body>
<section class="toc__section"><h4 class="mb-2x sans-serif">News</h4>
  <div class="card"><h3 class="article-title text-deep-gray"><a href="/doi/10.1126/science.news1" title="In defense of the research project grant">In defense of the research project grant</a></h3></div>
</section>
<section class="toc__section"><h4 class="mb-2x sans-serif">Research</h4>
  <div class="card"><h3 class="article-title text-deep-gray"><a href="/doi/10.1126/science.res1" title="A research paper">A research paper</a></h3></div>
  <div class="card"><h3 class="article-title text-deep-gray"><a href="/doi/10.1126/science.res2" title="Another paper">Another paper</a></h3></div>
</section>
</body></html>`;

        const items = parseListItems(sectionedHtml, 'current', 20);

        expect(items.map((item) => item.title)).toEqual(['A research paper', 'Another paper']);
    });

    it('reads the article type from the panel label or dc.Type', () => {
        expect(parseArticleType('<html><body><div class="meta-panel__type">Research Article</div></body></html>')).toBe('Research Article');
        expect(parseArticleType('<html><head><meta name="dc.Type" content="editorial"></head><body></body></html>')).toBe('editorial');
        expect(parseArticleType('<html><body></body></html>')).toBe('');
    });

    it('flags the markerless news template as News so it is filtered out', () => {
        // science.org news items carry no meta-panel/dc.Type and no #bodymatter.
        expect(parseArticleType('<html><body><div class="news-article-content"><p>News.</p></div></body></html>')).toBe('News');
        // A scholarly page (has #bodymatter) with no marker stays unknown and
        // fails open, so real research is never dropped on markup drift.
        expect(parseArticleType('<html><body><section id="bodymatter"><p>Body.</p></section></body></html>')).toBe('');
    });

    it('keeps only research-type articles and stops at the limit', async () => {
        const research = (n: number) => `<html><body><div class="meta-panel__type">Research Article</div><section id="bodymatter"><p>Body ${n}.</p></section></body></html>`;
        const editorial = '<html><body><div class="meta-panel__type">Editorial</div><div class="news-article-content"><p>Opinion.</p></div></body></html>';
        const htmlForUrl = (url: string) => (url.includes('editorial') ? editorial : research(Number(url.slice(-1))));
        const browser = new FakeBrowser(htmlForUrl) as any;
        const items: ScienceItem[] = [
            { title: 'r1', link: 'https://www.science.org/doi/10.1126/science.r1' },
            { title: 'ed', link: 'https://www.science.org/doi/10.1126/science.editorial' },
            { title: 'r2', link: 'https://www.science.org/doi/10.1126/science.r2' },
            { title: 'r3', link: 'https://www.science.org/doi/10.1126/science.r3' },
        ];

        const kept = await collectResearchArticleDetails(items, browser, identityCache, { delayMs: 0, jitterMs: 0, retries: 1, sleep: vi.fn(async () => {}) }, 2);

        expect(kept).toHaveLength(2);
        expect(kept.every((item) => item.articleType === 'Research Article')).toBe(true);
        // The editorial is dropped, so the limit is filled from later research.
        expect(kept.map((item) => item.title)).toEqual(['r1', 'r2']);
    });
});
