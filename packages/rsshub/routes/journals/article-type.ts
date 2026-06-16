// Shared article-type allowlist for the Cell Press and Science (AAAS) full
// content journal routes. Their listing pages (in-press / current issue) mix
// primary research with front matter - obituaries, editorials, perspectives,
// previews, letters, news, book reviews, policy pieces. Both publishers expose
// the content type on the article page through a `.meta-panel__type` label
// (Cell: "Article"/"Resource"/"Obituary"; Science: "Research Article"/
// "Perspective"/"Editorial"/...) and Science additionally through a
// `<meta name="dc.Type">` tag ("research-article", "review", "letter", ...).
//
// The feeds keep only the types below: primary research plus commissioned
// reviews. Everything else is dropped so readers ingest papers, not front
// matter.
const RESEARCH_ARTICLE_TYPES = new Set([
    'article', // Cell Press primary research
    'research article', // Science primary research
    'report', // Science short-form primary research
    'resource', // Cell Press methods/dataset research
    'review', // commissioned field review
]);

// Normalize both the human label (`.meta-panel__type`, e.g. "Research Article",
// "Books et al.") and the machine value (`dc.Type`, e.g. "research-article")
// into a single comparable form: lowercase, hyphens/underscores and trailing
// punctuation flattened to spaces.
export const normalizeArticleType = (raw: string | null | undefined): string =>
    (raw ?? '')
        .toLowerCase()
        .replace(/[-_]+/g, ' ')
        .replace(/[.\s]+/g, ' ')
        .trim();

// Fail open on an empty/unknown label: a missing type almost always means the
// page markup drifted or a challenge page slipped through, not a genuine
// non-research item (every observed front-matter item carried an explicit
// label). Keeping it avoids silently dropping a real paper when the selector
// breaks; only a positively-identified non-research label is filtered out.
export const isIncludedArticleType = (raw: string | null | undefined): boolean => {
    const normalized = normalizeArticleType(raw);
    if (!normalized) {
        return true;
    }
    return RESEARCH_ARTICLE_TYPES.has(normalized);
};
