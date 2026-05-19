import type { Route } from '@/types';

import { boardUrl, defaultLimit, fetchNoticeDetails, fetchNoticeList } from './index';

export const handler = async (ctx) => {
    const { site, bbs } = ctx.req.param();
    const limit = Number.parseInt(ctx.req.query('limit') ?? `${defaultLimit}`, 10) || defaultLimit;
    const { currentUrl, items } = await fetchNoticeList(site, bbs, limit);
    const detailedItems = await fetchNoticeDetails(items);

    const title = `인천대학교 공지사항 - ${site}/${bbs}`;

    return {
        title,
        description: title,
        link: currentUrl,
        item: detailedItems,
        language: 'ko',
    };
};

export const route: Route = {
    path: '/notice/:site/:bbs',
    name: '공지사항',
    url: 'inu.ac.kr',
    maintainers: ['mulatta'],
    handler,
    example: '/inu/notice/grad/1348',
    parameters: {
        site: '사이트 ID. 예: grad (일반대학원)',
        bbs: '게시판 ID. 예: 1348 (일반대학원 공지사항)',
    },
    categories: ['university'],
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: false,
        supportRadar: true,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    radar: [
        {
            source: ['inu.ac.kr/bbs/:site/:bbs/artclList.do', 'inu.ac.kr/bbs/:site/:bbs/rssList'],
            target: '/notice/:site/:bbs',
        },
    ],
};
