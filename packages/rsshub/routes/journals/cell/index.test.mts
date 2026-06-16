import { load } from 'cheerio';
import { describe, expect, it } from 'vitest';

import type { Browser } from '@/utils/playwright';

import { CellPressChallengeError, collectResearchArticles, fetchArticleDetailsSerial, fetchArticleWithRetries, isChallengeOrErrorPage, parseArticleHtml, parseListingHtml, parseRouteOptions, rootUrl, type ListingItem, type PageFetcher } from './index';

const listingFixture = `
<html>
  <body>
    <main>
      <article class="toc__item">
        <h3 class="article-title"><a href="/cell/fulltext/S0092-8674(25)00502-2">Human cell atlases reveal resilient circuits</a></h3>
        <div class="authors">Jane Smith, Arun Patel</div>
        <time datetime="2026-05-01">May 1, 2026</time>
        <a class="button" href="/cell/fulltext/S0092-8674(25)00502-2">Full text</a>
      </article>
      <article class="toc__item">
        <h3 class="article-title">Single-cell maps of development</h3>
        <div class="authors">Mina Kim</div>
        <span class="date">April 30, 2026</span>
        <a href="https://www.cell.com/cell/fulltext/S0092-8674(25)00503-4">Full-Text HTML</a>
      </article>
      <article class="toc__item">
        <h3 class="article-title"><a href="/molecular-cell/fulltext/S1097-2765(25)00444-1">Wrong journal</a></h3>
      </article>
      <a href="/cell/fulltext/S0092-8674(25)00502-2#related">Duplicate</a>
    </main>
  </body>
</html>
`;

const articleFixture = `
<html>
  <head>
    <title>Human cell atlases reveal resilient circuits - Cell</title>
    <meta name="citation_title" content="Human cell atlases reveal resilient circuits">
    <meta name="citation_doi" content="10.1016/j.cell.2026.05.002">
    <meta name="citation_author" content="Jane Smith">
    <meta name="citation_author" content="Arun Patel">
    <meta name="citation_publication_date" content="2026-05-01">
  </head>
  <body>
    <div class="login-modal">Login to your account</div>
    <div class="meta-panel__type">Article</div>
    <article id="article">
      <h1>Human cell atlases reveal resilient circuits</h1>
      <section id="graphical-abstract">
        <h2>Graphical abstract</h2>
        <figure><img src="/cms/asset/graphical.jpg" alt="Graphical abstract"></figure>
      </section>
      <section id="abstract">
        <h2>Abstract</h2>
        <p>Cell states remain stable under stress.</p>
      </section>
      <div id="bodymatter">
        <section id="sec1">
          <h2>Introduction</h2>
          <p>We profiled tissues and preserved <a href="/cell/fulltext/S0092-8674(25)00001-1">related work</a>.</p>
          <figure><img data-src="/cms/asset/figure1.jpg"><figcaption>Figure 1. Atlas overview.</figcaption></figure>
        </section>
        <section id="sec2">
          <h2>Results</h2>
          <p>Serial measurements found reproducible modules.</p>
        </section>
      </div>
      <section id="references">
        <h2>References</h2>
        <ol><li><a href="https://doi.org/10.1016/example">Reference article</a></li></ol>
      </section>
    </article>
  </body>
</html>
`;

const challengeFixture = `
<html>
  <head><title>Just a moment...</title></head>
  <body><h1>Just a moment...</h1><p>Cloudflare is checking your browser before accessing www.cell.com.</p></body>
</html>
`;

const listingItem = (link: string): ListingItem => ({
    guid: link,
    link,
    title: link,
});

const mockBrowser = {} as Browser;

describe('Cell Press route helpers', () => {
    it('extracts and deduplicates listing fulltext links', () => {
        const items = parseListingHtml(listingFixture, 'cell', 'inpress', 10);

        expect(items).toHaveLength(2);
        expect(items[0]).toMatchObject({
            author: 'Jane Smith, Arun Patel',
            link: `${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`,
            title: 'Human cell atlases reveal resilient circuits',
        });
        expect(items[1]).toMatchObject({
            author: 'Mina Kim',
            link: `${rootUrl}/cell/fulltext/S0092-8674(25)00503-4`,
            title: 'Single-cell maps of development',
        });
    });

    it('parses kind default and query limit', () => {
        const params: Record<string, string | undefined> = { journal: 'cell', kind: undefined };
        const query: Record<string, string | undefined> = { limit: '1' };
        const ctx = {
            req: {
                param: (name: string) => params[name],
                query: (name: string) => query[name],
            },
        };

        expect(parseRouteOptions(ctx)).toMatchObject({
            journal: 'cell',
            kind: 'inpress',
            limit: 1,
        });
    });

    it('renders article description with body, figures, references, and absolute URLs', () => {
        const item = parseArticleHtml(articleFixture, `${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`, listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`));

        expect(item).toMatchObject({
            author: 'Jane Smith, Arun Patel',
            doi: '10.1016/j.cell.2026.05.002',
            guid: '10.1016/j.cell.2026.05.002',
            title: 'Human cell atlases reveal resilient circuits',
        });
        expect(item.description).toContain('Graphical abstract');
        expect(item.description).toContain('Introduction');
        expect(item.description).toContain('References');
        expect(item.description).toContain('https://www.cell.com/cms/asset/graphical.jpg');
        expect(item.description).toContain('https://www.cell.com/cms/asset/figure1.jpg');
        expect(item.description).toContain('https://www.cell.com/cell/fulltext/S0092-8674(25)00001-1');
        expect(item.description).not.toContain('Login to your account');
    });

    it('detects challenge pages without rejecting content pages that include login UI', () => {
        expect(isChallengeOrErrorPage(load(challengeFixture))).toBe(true);
        expect(isChallengeOrErrorPage(load(articleFixture))).toBe(false);
        expect(() => parseArticleHtml(challengeFixture, `${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`, listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`))).toThrow(CellPressChallengeError);
    });

    it('retries challenge pages before returning article content', async () => {
        const calls: string[] = [];
        const fetcher: PageFetcher = async (_, url) => {
            calls.push(url);
            return calls.length === 1 ? challengeFixture : articleFixture;
        };

        const item = await fetchArticleWithRetries(mockBrowser, listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`), { delayMs: 0, retries: 2 }, fetcher);

        expect(calls).toHaveLength(2);
        expect(item.doi).toBe('10.1016/j.cell.2026.05.002');
    });

    it('fetches article details serially', async () => {
        const calls: string[] = [];
        const fetcher: PageFetcher = async (_, url) => {
            calls.push(url);
            await Promise.resolve();
            return articleFixture.replace('10.1016/j.cell.2026.05.002', url.endsWith('00503-4') ? '10.1016/j.cell.2026.05.003' : '10.1016/j.cell.2026.05.002');
        };
        const items = [listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`), listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00503-4`)];

        const detailed = await fetchArticleDetailsSerial(mockBrowser, items, { delayMs: 0, retries: 1, useCache: false }, fetcher);

        expect(calls).toEqual(items.map((item) => item.link));
        expect(detailed.map((item) => item.doi)).toEqual(['10.1016/j.cell.2026.05.002', '10.1016/j.cell.2026.05.003']);
    });

    it('applies listing limit', () => {
        expect(parseListingHtml(listingFixture, 'cell', 'current', 1)).toHaveLength(1);
    });

    it('extracts the article type label', () => {
        const item = parseArticleHtml(articleFixture, `${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`, listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`));
        expect(item.articleType).toBe('Article');
    });

    it('keeps only research-type articles and stops at the limit', async () => {
        const obituaryFixture = articleFixture.replace('<div class="meta-panel__type">Article</div>', '<div class="meta-panel__type">Obituary</div>');
        const fetcher: PageFetcher = async (_, url) => {
            await Promise.resolve();
            // The second candidate is an obituary; everything else is research.
            return url.endsWith('00503-4') ? obituaryFixture : articleFixture.replace('10.1016/j.cell.2026.05.002', `10.1016/j.cell.2026.05.${url.slice(-6, -2)}`);
        };
        const candidates = ['00502-2', '00503-4', '00504-6', '00505-8'].map((pii) => listingItem(`${rootUrl}/cell/fulltext/S0092-8674(25)${pii}`));

        const kept = await collectResearchArticles(mockBrowser, candidates, { delayMs: 0, retries: 1, useCache: false }, 2, fetcher);

        expect(kept).toHaveLength(2);
        expect(kept.every((item) => item.articleType === 'Article')).toBe(true);
        // The obituary (00503-4) is dropped, so the limit is filled from the
        // research candidates that follow it.
        expect(kept.map((item) => item.link)).toEqual([`${rootUrl}/cell/fulltext/S0092-8674(25)00502-2`, `${rootUrl}/cell/fulltext/S0092-8674(25)00504-6`]);
    });
});
