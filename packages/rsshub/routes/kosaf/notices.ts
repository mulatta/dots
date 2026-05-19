import InvalidParameterError from '@/errors/types/invalid-parameter';
import type { Route } from '@/types';

import { defaultLimit, fetchNoticeDetails, fetchNoticeList, noticeUrl, type NoticeItem } from './index';

type Board = {
    ctgrId1: string;
    ctgrId2?: string;
};

const boardIdPattern = /^\d{10}$/;

const parsePositiveInt = (value: string | undefined, fallback: number) => {
    const parsed = Number.parseInt(value ?? '', 10);
    return parsed > 0 ? parsed : fallback;
};

const parseBoard = (value: string): Board => {
    const [ctgrId1, ctgrId2, extra] = value.split('/');

    if (extra !== undefined || !boardIdPattern.test(ctgrId1) || (ctgrId2 !== undefined && !boardIdPattern.test(ctgrId2))) {
        throw new InvalidParameterError(`Invalid board '${value}'. Use ctgrId1 or ctgrId1/ctgrId2.`);
    }

    return { ctgrId1, ctgrId2 };
};

const itemTimestamp = (item: NoticeItem) => {
    if (item.pubDate instanceof Date) {
        return item.pubDate.getTime();
    }

    if (typeof item.pubDate === 'number') {
        return item.pubDate;
    }

    if (typeof item.pubDate === 'string') {
        const timestamp = new Date(item.pubDate).getTime();
        return Number.isNaN(timestamp) ? 0 : timestamp;
    }

    return 0;
};

const dedupeItems = (items: NoticeItem[]) => {
    const seen = new Set<string>();
    return items.filter((item) => {
        const key = item.guid ?? item.link;
        if (seen.has(key)) {
            return false;
        }
        seen.add(key);
        return true;
    });
};

export const handler = async (ctx) => {
    const query = new URL(ctx.req.url).searchParams;
    const boardValues = query.getAll('board').filter((board) => board.length > 0);

    if (boardValues.length === 0) {
        throw new InvalidParameterError('At least one board query parameter is required.');
    }

    const limit = parsePositiveInt(ctx.req.query('limit'), defaultLimit);
    const perBoardLimit = parsePositiveInt(ctx.req.query('perBoardLimit'), limit);
    const boards = boardValues.map(parseBoard);
    const results = await Promise.all(boards.map((board) => fetchNoticeList(board.ctgrId1, board.ctgrId2, perBoardLimit)));
    const items = dedupeItems(results.flatMap((result) => result.items))
        .sort((a, b) => itemTimestamp(b) - itemTimestamp(a))
        .slice(0, limit);
    const detailedItems = await fetchNoticeDetails(items);
    const title = '한국장학재단 공지사항 모음';

    return {
        title,
        description: `${title}: ${boards.map((board) => [board.ctgrId1, board.ctgrId2].filter(Boolean).join('/')).join(', ')}`,
        link: noticeUrl(boards[0].ctgrId1, boards[0].ctgrId2),
        item: detailedItems,
        language: 'ko',
    };
};

export const route: Route = {
    path: ['/notice', '/notices'],
    name: '공지사항 모음',
    url: 'kosaf.go.kr/ko/notice.do',
    maintainers: ['mulatta'],
    handler,
    example: '/kosaf/notices?board=0000000001/0000000001&board=0000000002/0000000023',
    parameters: {
        board: '반복 가능한 게시판 ID. ctgrId1 또는 ctgrId1/ctgrId2 형식. 예: board=0000000002/0000000023&board=0000000002/0000000025',
        limit: '선택. 전체 결과 개수. 기본값 25.',
        perBoardLimit: '선택. 각 게시판에서 가져올 개수. 기본값은 limit 값.',
    },
    categories: ['government'],
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: false,
        supportRadar: false,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
};
