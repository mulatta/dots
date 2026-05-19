import { load } from 'cheerio';

import { config } from '@/config';
import ConfigNotFoundError from '@/errors/types/config-not-found';
import type { Route } from '@/types';
import got from '@/utils/got';

const githubRoot = 'https://github.com';

const compact = (value: string | undefined | null) => value?.replaceAll(/\s+/g, ' ').trim() ?? '';

const parsePositiveInt = (value: string | undefined) => {
    const parsed = Number.parseInt(value ?? '', 10);
    return parsed > 0 ? parsed : undefined;
};

type TrendingRepo = {
    owner: string;
    name: string;
};

type Repository = {
    defaultBranchRef?: {
        name: string;
    } | null;
    description?: string | null;
    forkCount: number;
    nameWithOwner: string;
    openGraphImageUrl: string;
    primaryLanguage?: {
        name: string;
    } | null;
    stargazerCount: number;
};

const dedupeTrendingRepos = (repos: TrendingRepo[]) => {
    const seen = new Set<string>();
    return repos.filter((repo) => {
        const key = `${repo.owner}/${repo.name}`.toLowerCase();
        if (seen.has(key)) {
            return false;
        }
        seen.add(key);
        return true;
    });
};

const matchesRequestedLanguage = (repo: Repository, language: string) => {
    if (!language) {
        return true;
    }
    return compact(repo.primaryLanguage?.name).toLowerCase() === language.toLowerCase();
};

const fetchReadme = async (repo: string) => {
    try {
        const { data } = await got({
            method: 'get',
            url: `https://api.github.com/repos/${repo}/readme`,
            headers: {
                Accept: 'application/vnd.github.html+json',
                Authorization: `Bearer ${config.github?.access_token}`,
                'X-GitHub-Api-Version': '2022-11-28',
            },
        });
        return typeof data === 'string' ? data : '';
    } catch {
        return '';
    }
};

const encodePath = (value: string) => value.split('/').map(encodeURIComponent).join('/');

const isProtocolUrl = (value: string) => /^[a-z][a-z\d+.-]*:/i.test(value);

const repositoryParts = (repo: Repository) => {
    const [owner, name] = repo.nameWithOwner.split('/');
    return { owner, name };
};

const readmeDirectory = (readmePath: string | undefined) => {
    const pathParts = (readmePath ?? 'README.md').split('/').filter(Boolean);
    pathParts.pop();
    return pathParts.length > 0 ? `${encodePath(pathParts.join('/'))}/` : '';
};

const readmeRawBase = (repo: Repository, readmePath: string | undefined) => {
    const branch = repo.defaultBranchRef?.name ?? 'HEAD';
    return `https://raw.githubusercontent.com/${repo.nameWithOwner}/${encodeURIComponent(branch)}/${readmeDirectory(readmePath)}`;
};

const readmeRawRoot = (repo: Repository) => {
    const branch = repo.defaultBranchRef?.name ?? 'HEAD';
    return `https://raw.githubusercontent.com/${repo.nameWithOwner}/${encodeURIComponent(branch)}/`;
};

const splitPathSuffix = (value: string) => {
    const match = value.match(/^([^?#]*)([?#].*)?$/);
    return {
        pathname: match?.[1] ?? value,
        suffix: match?.[2] ?? '',
    };
};

const isLikelyFilePath = (pathname: string) => {
    const basename = pathname.split('/').filter(Boolean).pop() ?? '';
    return Boolean(basename.match(/\.[A-Za-z0-9]+$/)) || ['CODE_OF_CONDUCT', 'CONTRIBUTING', 'COPYING', 'LICENSE', 'NOTICE', 'README'].includes(basename.toUpperCase());
};

const githubReadmeWebBase = (repo: Repository, readmePath: string | undefined, pathname: string) => {
    const branch = repo.defaultBranchRef?.name ?? 'HEAD';
    const kind = pathname.endsWith('/') || !isLikelyFilePath(pathname) ? 'tree' : 'blob';
    return `${githubRoot}/${repo.nameWithOwner}/${kind}/${encodeURIComponent(branch)}/${readmeDirectory(readmePath)}`;
};

const resolveReadmeLinkUrl = (repo: Repository, value: string | undefined, readmePath: string | undefined) => {
    if (!value || value.startsWith('#') || isProtocolUrl(value)) {
        return value;
    }
    if (value.startsWith('//')) {
        return `https:${value}`;
    }

    const { owner, name } = repositoryParts(repo);
    const { pathname, suffix } = splitPathSuffix(value);
    if (pathname.startsWith(`/${owner}/${name}/`)) {
        return new URL(`${pathname}${suffix}`, githubRoot).toString();
    }
    if (pathname.startsWith('/')) {
        return new URL(`${pathname}${suffix}`, githubRoot).toString();
    }

    return `${new URL(pathname, githubReadmeWebBase(repo, readmePath, pathname)).toString()}${suffix}`;
};

const resolveReadmeImageUrl = (repo: Repository, value: string | undefined, readmePath: string | undefined) => {
    if (!value || value.startsWith('#') || isProtocolUrl(value)) {
        return value;
    }
    if (value.startsWith('//')) {
        return `https:${value}`;
    }

    const { owner, name } = repositoryParts(repo);
    const { pathname, suffix } = splitPathSuffix(value);
    if (pathname.startsWith(`/${owner}/${name}/`)) {
        return new URL(`${pathname}${suffix}`, githubRoot).toString();
    }
    if (pathname.startsWith('/')) {
        return `${new URL(pathname.slice(1), readmeRawRoot(repo)).toString()}${suffix}`;
    }

    return `${new URL(pathname, readmeRawBase(repo, readmePath)).toString()}${suffix}`;
};

const resolveSrcsetUrls = (value: string | undefined, resolver: (url: string) => string | undefined) =>
    value
        ?.split(',')
        .map((candidate) => {
            const trimmed = candidate.trim();
            const [url, ...descriptors] = trimmed.split(/\s+/);
            const resolved = resolver(url) ?? url;
            return [resolved, ...descriptors].join(' ');
        })
        .join(', ');

const renderRepositoryDescription = (repo: Repository, readme: string) => {
    if (!readme) {
        return '<p>README not found.</p>';
    }

    const $ = load(readme, null, false);
    const readmePath = $('#readme[data-path]').attr('data-path');

    $('a[href]').each((_, element) => {
        const link = $(element);
        const href = resolveReadmeLinkUrl(repo, link.attr('href'), readmePath);
        if (href) {
            link.attr('href', href);
        }
    });

    $('img').each((_, element) => {
        const image = $(element);
        const src = image.attr('src') ?? image.attr('data-canonical-src');
        const resolved = resolveReadmeImageUrl(repo, src, readmePath);
        if (resolved) {
            image.attr('src', resolved);
        }
        const srcset = resolveSrcsetUrls(image.attr('srcset'), (url) => resolveReadmeImageUrl(repo, url, readmePath));
        if (srcset) {
            image.attr('srcset', srcset);
        }
        image.removeAttr('data-canonical-src');
    });

    $('source[srcset]').each((_, element) => {
        const source = $(element);
        const srcset = resolveSrcsetUrls(source.attr('srcset'), (url) => resolveReadmeImageUrl(repo, url, readmePath));
        if (srcset) {
            source.attr('srcset', srcset);
        }
    });

    $('table').each((_, element) => {
        const table = $(element);
        const cells = table.find('td').toArray();
        const isMediaLayout = !table.find('th').length && cells.length > 0 && cells.every((cell) => $(cell).find('img, picture').length > 0 && !compact($(cell).text()));
        if (isMediaLayout) {
            table.addClass('github-readme-layout-table');
        }
    });

    const rendered = $.root().html() ?? readme;
    return `<div class="github-readme markdown-body">${rendered}</div>`;
};

export const route: Route = {
    path: '/trending-readme/:since/:language/:spoken_language?',
    categories: ['programming'],
    example: '/github/trending-readme/daily/rust',
    parameters: {
        since: {
            description: 'time range',
            options: [
                {
                    value: 'daily',
                    label: 'Today',
                },
                {
                    value: 'weekly',
                    label: 'This week',
                },
                {
                    value: 'monthly',
                    label: 'This month',
                },
            ],
        },
        language: {
            description: "the feed language, available in GitHub Trending URL; don't filter option is `any`",
            default: 'any',
        },
        spoken_language: {
            description: 'natural language filter code',
        },
    },
    features: {
        requireConfig: [
            {
                name: 'GITHUB_ACCESS_TOKEN',
                description: 'Used for GitHub GraphQL metadata and README API calls.',
            },
        ],
        requirePuppeteer: false,
        antiCrawler: false,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    name: 'Trending with README',
    maintainers: ['mulatta'],
    handler,
    url: 'github.com/trending',
};

async function handler(ctx) {
    if (!config.github?.access_token) {
        throw new ConfigNotFoundError('GitHub trending README RSS is disabled because GITHUB_ACCESS_TOKEN is missing.');
    }

    const since = ctx.req.param('since');
    const languageParam = ctx.req.param('language');
    const language = languageParam === 'any' ? '' : languageParam;
    const spokenLanguage = ctx.req.param('spoken_language') ?? '';
    const limit = parsePositiveInt(ctx.req.query('limit'));
    const now = new Date();
    const trendingUrl = `${githubRoot}/trending/${encodeURIComponent(language)}?since=${since}&spoken_language_code=${spokenLanguage}`;
    const { data: trendingPage } = await got({
        method: 'get',
        url: trendingUrl,
        headers: {
            Referer: trendingUrl,
        },
    });
    const $ = load(trendingPage);

    let trendingRepos: TrendingRepo[] = dedupeTrendingRepos(
        $('article')
            .toArray()
            .map((item) => {
                const [owner, name] = $(item).find('h2').text().split('/');
                return {
                    name: compact(name),
                    owner: compact(owner),
                };
            })
            .filter((repo) => repo.owner && repo.name),
    );

    if (trendingRepos.length === 0) {
        return {
            title: $('title').text(),
            link: trendingUrl,
            item: [],
        };
    }

    const { data: repoData } = await got({
        method: 'post',
        url: 'https://api.github.com/graphql',
        headers: {
            Authorization: `Bearer ${config.github.access_token}`,
        },
        json: {
            query: /* GraphQL */ `
            query {
            ${trendingRepos
                .map(
                    (repo, index) => `
                _${index}: repository(owner: "${repo.owner}", name: "${repo.name}") {
                    defaultBranchRef {
                        name
                    }
                    description
                    forkCount
                    nameWithOwner
                    openGraphImageUrl
                    primaryLanguage {
                        name
                    }
                    stargazerCount
                }
            `,
                )
                .join('\n')}
            }
            `,
        },
    });

    let repos = trendingRepos
        .map((_, index) => repoData.data[`_${index}`])
        .filter(Boolean)
        .filter((repo) => matchesRequestedLanguage(repo, language)) as Repository[];
    if (limit) {
        repos = repos.slice(0, limit);
    }
    const readmes = await Promise.all(repos.map((repo) => fetchReadme(repo.nameWithOwner)));

    return {
        title: `${$('title').text()} with README`,
        description: `GitHub ${since} trending repositories with README content`,
        link: trendingUrl,
        item: repos.map((repo, index) => {
            const repoDescription = compact(repo.description);
            const repoUrl = `${githubRoot}/${repo.nameWithOwner}`;
            return {
                title: repoDescription ? `${repo.nameWithOwner} — ${repoDescription}` : repo.nameWithOwner,
                author: repo.nameWithOwner.split('/')[0],
                description: renderRepositoryDescription(repo, readmes[index]),
                // Stable repository identity prevents Miniflux from creating
                // a fresh entry every time the same repo remains trending.
                guid: `${repoUrl}#github-trending-${since}-${languageParam}-${spokenLanguage || 'any'}`,
                link: repoUrl,
                pubDate: now,
            };
        }),
    };
}
