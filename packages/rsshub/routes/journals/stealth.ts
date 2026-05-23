import { config } from '@/config';
import type { Browser, Page } from '@/utils/playwright';
import StealthPlugin from 'puppeteer-extra-plugin-stealth';
import type { Browser as PlaywrightBrowser, BrowserContext, BrowserContextOptions, LaunchOptions, Page as PlaywrightPage, Request as PlaywrightRequest, Response as PlaywrightResponse, Route as PlaywrightRoute } from 'playwright';
import { chromium } from 'playwright-extra';

type SetCookieParam = Parameters<BrowserContext['addCookies']>[0][number];
type Cookie = Awaited<ReturnType<BrowserContext['cookies']>>[number];
type GotoOptions = Parameters<PlaywrightPage['goto']>[1] & {
    waitUntil?: 'load' | 'domcontentloaded' | 'networkidle' | 'networkidle0' | 'networkidle2';
};

type RouteRequest = {
    abort: (errorCode?: string) => Promise<void>;
    continue: (options?: Parameters<PlaywrightRoute['continue']>[0]) => Promise<void>;
    resourceType: () => ReturnType<PlaywrightRequest['resourceType']>;
    url: () => string;
};

type FinishedRequest = {
    response: () => {
        status: () => number;
    } | null;
    url: () => string;
};

type RequestHandler = (request: RouteRequest) => Promise<void> | void;
type RequestFinishedHandler = (request: FinishedRequest) => Promise<void> | void;
type HandledRouteRequest = RouteRequest & { handled: boolean };

chromium.use(StealthPlugin());

const normalizeWaitUntil = (waitUntil: GotoOptions['waitUntil']) => (waitUntil === 'networkidle0' || waitUntil === 'networkidle2' ? 'networkidle' : waitUntil);

const normalizeGotoOptions = (options?: GotoOptions): Parameters<PlaywrightPage['goto']>[1] | undefined =>
    options
        ? {
              ...options,
              waitUntil: normalizeWaitUntil(options.waitUntil),
          }
        : options;

const withDefaultCookiePath = (cookie: SetCookieParam): SetCookieParam => ('domain' in cookie && !('path' in cookie) ? { ...cookie, path: '/' } : cookie);

const getLaunchOptions = (): LaunchOptions => ({
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled', '--window-position=0,0', '--ignore-certificate-errors', '--ignore-certificate-errors-spki-list'],
    executablePath: config.chromiumExecutablePath || undefined,
    headless: true,
});

const getContextOptions = (): BrowserContextOptions => ({
    ignoreHTTPSErrors: true,
});

const createRouteRequest = (route: PlaywrightRoute): HandledRouteRequest => {
    const request = route.request();
    const routeRequest = {
        abort: async (errorCode) => {
            routeRequest.handled = true;
            await route.abort(errorCode);
        },
        continue: async (options) => {
            routeRequest.handled = true;
            await route.continue(options);
        },
        handled: false,
        resourceType: () => request.resourceType(),
        url: () => request.url(),
    } satisfies HandledRouteRequest;
    return routeRequest;
};

const runRequestHandlers = async (handlers: RequestHandler[], request: HandledRouteRequest, index = 0): Promise<void> => {
    if (request.handled || index >= handlers.length) {
        return;
    }

    await handlers[index](request);
    await runRequestHandlers(handlers, request, index + 1);
};

const createFinishedRequest = (request: PlaywrightRequest, response: PlaywrightResponse | null): FinishedRequest => ({
    response: () =>
        response
            ? {
                  status: () => response.status(),
              }
            : null,
    url: () => request.url(),
});

const patchPage = (page: PlaywrightPage, context: BrowserContext): Page => {
    const compatPage = page as Page;
    const requestHandlers: RequestHandler[] = [];
    const originalGoto = page.goto.bind(page);
    const originalOn = page.on.bind(page);
    const originalRoute = page.route.bind(page);
    const originalUnroute = page.unroute.bind(page);
    let routeHandler: ((route: PlaywrightRoute) => Promise<void>) | undefined;
    let requestInterceptionEnabled = false;

    compatPage.goto = (url, options) => originalGoto(url, normalizeGotoOptions(options));
    compatPage.cookies = (urls) => context.cookies(urls);
    compatPage.setCookie = async (...cookies) => {
        await context.addCookies(cookies.map((cookie) => withDefaultCookiePath(cookie)));
    };
    compatPage.authenticate = async () => {};
    compatPage.setUserAgent = async (userAgent) => {
        const contextWithCDP = context as BrowserContext & {
            newCDPSession?: (page: PlaywrightPage) => Promise<{
                detach: () => Promise<void>;
                send: (method: string, params?: Record<string, unknown>) => Promise<void>;
            }>;
        };
        if (contextWithCDP.newCDPSession) {
            const session = await contextWithCDP.newCDPSession(page);
            await session.send('Network.setUserAgentOverride', { userAgent });
            await session.detach();
            return;
        }
        await page.setExtraHTTPHeaders({
            'User-Agent': userAgent,
        });
    };
    compatPage.setRequestInterception = async (enabled) => {
        requestInterceptionEnabled = enabled;
        if (enabled && !routeHandler) {
            routeHandler = async (route) => {
                const request = createRouteRequest(route);
                await runRequestHandlers(requestHandlers, request);
                if (request.handled) {
                    return;
                }
                await route.continue();
            };
            await originalRoute('**/*', routeHandler);
        } else if (!enabled && routeHandler) {
            await originalUnroute('**/*', routeHandler);
            routeHandler = undefined;
        }
    };
    compatPage.on = ((event: string, handler: (...args: any[]) => any) => {
        if (event === 'request') {
            requestHandlers.push(handler as RequestHandler);
            if (!requestInterceptionEnabled) {
                originalOn(event, handler);
            }
            return compatPage;
        }
        if (event === 'requestfinished') {
            originalOn(event, async (request) => {
                let response: PlaywrightResponse | null = null;
                try {
                    response = await request.response();
                } catch {
                    // Browser may close before Playwright resolves response.
                }
                await (handler as RequestFinishedHandler)(createFinishedRequest(request, response));
            });
            return compatPage;
        }
        originalOn(event, handler);
        return compatPage;
    }) as Page['on'];

    return compatPage;
};

const createCompatBrowser = async (browser: PlaywrightBrowser, contextOptions: BrowserContextOptions): Promise<Browser> => {
    const context = await browser.newContext(contextOptions);
    const compatBrowser = browser as Browser;
    const originalClose = browser.close.bind(browser);

    compatBrowser.newPage = async () => patchPage(await context.newPage(), context);
    compatBrowser.setCookie = async (...cookies) => {
        await context.addCookies(cookies.map((cookie) => withDefaultCookiePath(cookie)));
    };
    compatBrowser.cookies = (urls) => context.cookies(urls) as Promise<Cookie[]>;
    compatBrowser.userAgent = () => config.ua;
    compatBrowser.close = async (options) => {
        try {
            await context.close();
        } catch {
            // Ignore already-closed contexts.
        }
        await originalClose(options);
    };

    return compatBrowser;
};

const launchStealthBrowser = async () => {
    const browser = await chromium.launch(getLaunchOptions());
    return createCompatBrowser(browser as unknown as PlaywrightBrowser, getContextOptions());
};

export default launchStealthBrowser;
