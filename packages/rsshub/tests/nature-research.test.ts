import { describe, expect, it, beforeEach, vi } from 'vitest';

const mocks = vi.hoisted(() => {
    const cacheStore = new Map<string, unknown>();
    const cacheTryGet = vi.fn(async (key: string, getter: () => Promise<unknown>) => {
        if (cacheStore.has(key)) {
            return cacheStore.get(key);
        }

        const value = await getter();
        cacheStore.set(key, value);
        return value;
    });

    return {
        cacheStore,
        cacheTryGet,
        got: vi.fn(),
        ofetch: vi.fn(),
    };
});

vi.mock('@/utils/cache', () => ({
    default: {
        tryGet: mocks.cacheTryGet,
    },
}));

vi.mock('@/utils/got', () => ({
    default: mocks.got,
}));

vi.mock('@/utils/ofetch', () => ({
    default: mocks.ofetch,
}));

const { fetchArticleDetails, handler, parsePositiveInteger } = await import('../routes/journals/nature-research');

const articleUrl = (id: string) => `https://www.nature.com/articles/${id}`;

const listFixture = (items: Array<{ id: string; title: string; date: string }>) => `<!doctype html>
<html>
<head>
<meta name="description" content="Nature Biotechnology research articles">
<script data-test="dataLayer">window.dataLayer = [{"content":{"journal":{"title":"Nature Biotechnology"}}}];</script>
</head>
<body>
${items
    .map(
        (item) => `<article class="app-article-list-row__item">
<a href="/articles/${item.id}">${item.title}</a>
<div class="c-meta"><time datetime="${item.date}"></time></div>
</article>`
    )
    .join('\n')}
</body>
</html>`;

const detailFixture = (id: string, title: string) => `<!doctype html>
<html>
<head>
<title>${title}</title>
<script type="application/ld+json">${JSON.stringify({
    mainEntity: {
        isAccessibleForFree: true,
        sameAs: `https://doi.org/10.1038/${id}`,
        author: [{ name: 'Alice, A.' }, { name: 'Bob, B.' }],
        keywords: ['Biotechnology', 'Methods'],
        datePublished: '2026-05-01',
    },
})}</script>
</head>
<body>
<div class="c-article-body"><p>Full Nature body for ${title}</p></div>
</body>
</html>`;

const challengeFixture = `<!doctype html>
<html>
<head><title>Client Challenge</title></head>
<body><h1>Client Challenge</h1></body>
</html>`;

const jsonLdNullFixture = `<!doctype html>
<html>
<head>
<title>Broken Nature article</title>
<script type="application/ld+json">null</script>
</head>
<body><div class="c-article-body"><p>This must not be cached.</p></div></body>
</html>`;

const makeCtx = (query: Record<string, string | undefined>) =>
    ({
        req: {
            param: (name: string) => (name === 'journal' ? 'nbt' : undefined),
            query: (name: string) => query[name],
        },
    }) as any;

const nextTick = () => new Promise<void>((resolve) => setTimeout(resolve, 0));

const deferred = <T>() => {
    let resolve!: (value: T) => void;
    let reject!: (error: unknown) => void;
    const promise = new Promise<T>((promiseResolve, promiseReject) => {
        resolve = promiseResolve;
        reject = promiseReject;
    });

    return { promise, resolve, reject };
};

describe('journals/nature research route', () => {
    beforeEach(() => {
        mocks.cacheStore.clear();
        mocks.cacheTryGet.mockClear();
        mocks.got.mockReset();
        mocks.ofetch.mockReset();
    });

    it('fetches article details serially instead of bursting all detail requests', async () => {
        mocks.got.mockResolvedValue({
            data: listFixture([
                { id: 's41587-026-00001-1', title: 'Serial article one', date: '2026-05-01' },
                { id: 's41587-026-00002-2', title: 'Serial article two', date: '2026-05-02' },
            ]),
        });

        const firstDetail = deferred<string>();
        const secondDetail = deferred<string>();
        const calls: string[] = [];

        mocks.ofetch.mockImplementation((url: string) => {
            calls.push(url);
            if (calls.length === 1) {
                return firstDetail.promise;
            }
            if (calls.length === 2) {
                return secondDetail.promise;
            }
            throw new Error(`unexpected detail fetch: ${url}`);
        });

        const resultPromise = handler(makeCtx({ limit: '2', delayMs: '0', retries: '0' }));
        await nextTick();

        expect(calls).toEqual([articleUrl('s41587-026-00001-1')]);

        firstDetail.resolve(detailFixture('s41587-026-00001-1', 'Serial article one'));
        await nextTick();

        expect(calls).toEqual([articleUrl('s41587-026-00001-1'), articleUrl('s41587-026-00002-2')]);

        secondDetail.resolve(detailFixture('s41587-026-00002-2', 'Serial article two'));
        const result = await resultPromise;

        expect(result.item).toHaveLength(2);
        expect(result.item[0]).toMatchObject({
            title: 'Serial article one',
            link: articleUrl('s41587-026-00001-1'),
            doi: '10.1038/s41587-026-00001-1',
            author: 'Alice A., Bob B.',
            category: ['Biotechnology', 'Methods'],
        });
        expect(result.item[0].description).toContain('Full Nature body for Serial article one');
    });

    it('retries a Client Challenge page and caches only the successful article parse', async () => {
        mocks.ofetch.mockResolvedValueOnce(challengeFixture).mockResolvedValueOnce(detailFixture('s41587-026-00003-3', 'Retry article'));

        const items = await fetchArticleDetails([{ title: 'Retry article', link: articleUrl('s41587-026-00003-3') }], { delayMs: 0, retries: 1, partial: false });

        expect(mocks.ofetch).toHaveBeenCalledTimes(2);
        expect(items[0].description).toContain('Full Nature body for Retry article');
        expect(mocks.cacheStore.has(articleUrl('s41587-026-00003-3'))).toBe(true);
    });

    it('reports JSON-LD null as a clean failure and does not cache it', async () => {
        mocks.ofetch.mockResolvedValue(jsonLdNullFixture);

        await expect(fetchArticleDetails([{ title: 'Broken article', link: articleUrl('s41587-026-00004-4') }], { delayMs: 0, retries: 3, partial: false })).rejects.toThrow(/JSON-LD parsed to null/);

        expect(mocks.ofetch).toHaveBeenCalledTimes(1);
        expect(mocks.cacheStore.has(articleUrl('s41587-026-00004-4'))).toBe(false);
    });

    it('parses limit as a positive integer with a default fallback', () => {
        expect(parsePositiveInteger(undefined, 20)).toBe(20);
        expect(parsePositiveInteger('20', 20)).toBe(20);
        expect(parsePositiveInteger('1', 20)).toBe(1);
        expect(parsePositiveInteger('0', 20)).toBe(20);
        expect(parsePositiveInteger('-1', 20)).toBe(20);
        expect(parsePositiveInteger('1.5', 20)).toBe(20);
        expect(parsePositiveInteger('abc', 20)).toBe(20);
    });
});
