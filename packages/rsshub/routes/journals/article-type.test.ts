import { describe, expect, it } from 'vitest';

import { isIncludedArticleType, normalizeArticleType } from './article-type';

describe('journal article-type allowlist', () => {
    it('normalizes human labels and dc.Type machine values to one form', () => {
        expect(normalizeArticleType('Research Article')).toBe('research article');
        expect(normalizeArticleType('research-article')).toBe('research article');
        expect(normalizeArticleType('Books et al.')).toBe('books et al');
        expect(normalizeArticleType('  Expert   Voices ')).toBe('expert voices');
        expect(normalizeArticleType(null)).toBe('');
    });

    it('keeps primary research and reviews', () => {
        // Cell Press and Science labels observed on real article pages.
        for (const type of ['Article', 'Research Article', 'Report', 'Resource', 'Review', 'research-article', 'review']) {
            expect(isIncludedArticleType(type)).toBe(true);
        }
    });

    it('drops front matter', () => {
        for (const type of ['Obituary', 'Editorial', 'Perspective', 'Preview', 'Letter', 'Expert Voices', 'Books et al.', 'Policy Article', 'Research Highlights', 'News', 'Commentary']) {
            expect(isIncludedArticleType(type)).toBe(false);
        }
    });

    it('fails open when the type is missing so selector drift does not drop real papers', () => {
        expect(isIncludedArticleType('')).toBe(true);
        expect(isIncludedArticleType(undefined)).toBe(true);
    });
});
