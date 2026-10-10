// Copied by the Nix build into packages/desktop/tests/main after patching.
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { BrowserWindow, WebContents } from 'electron';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { parse } from 'smol-toml';
import { pinRustToolchain } from '../../../../scripts/nix-rust-toolchain.mjs';
import { startAutoUpdater, type UpdaterLike } from '../../src/main/auto-updater.ts';
import { resolveLocalOpCliInvocation } from '../../src/main/local-op-cli-invocation.ts';
import { resolveMenuCatalogDir } from '../../src/main/main-i18n.ts';
import { applyMenuDispatchRole } from '../../src/main/menu-dispatch-role.ts';
import { resolveDetachedSpawnArgs } from '../../src/main/resolve-detached-spawn-args.ts';
import { composeOkChildEnv, okChildEnvOptions } from '../../src/shared/ok-child-env.ts';

const resources = '/nix/store/test-openknowledge/share/openknowledge';
const cli = '/nix/store/test-openknowledge/bin/open-knowledge';
const node = '/nix/store/test-node/bin/node';
afterEach(() => vi.unstubAllEnvs());

describe('Nix Rust toolchain pinning', () => {
  test.each(['1.99.0', '2.0.0', 'stable'])('normalizes upstream channel %s', (channel) => {
    const input = `[toolchain]\nchannel = "${channel}"\nprofile = "minimal"\ntargets = ["aarch64-apple-darwin"]\n[metadata]\nowner = "upstream"\n`;
    expect(parse(pinRustToolchain(input, '1.92.0'))).toEqual({
      toolchain: { channel: '1.92.0', profile: 'minimal', targets: ['aarch64-apple-darwin'] },
      metadata: { owner: 'upstream' },
    });
  });

  test.each([
    'not valid toml',
    '',
    'toolchain = "stable"',
    '[toolchain]',
    '[toolchain]\nchannel = ""',
    '[toolchain]\nchannel = 123',
  ])('rejects malformed or missing toolchain data: %s', (input) => {
    expect(() => pinRustToolchain(input, '1.92.0')).toThrow();
  });

  test.each(['stable', '1.92', '1.92.0-nightly', '1.92.0 extra', ''])(
    'rejects a non-exact Nix Rust version: %s',
    (version) => {
      expect(() => pinRustToolchain('[toolchain]\nchannel = "stable"', version)).toThrow();
    },
  );
});

describe('Nix helper behavior', () => {
  test.each([false, true])('uses the wrapper CLI with isPackaged=%s', (isPackaged) => {
    expect(
      resolveLocalOpCliInvocation({
        platform: 'linux',
        isPackaged,
        execPath: '/electron',
        resourcesPath: '/unused',
        parentEnv: { OK_NIX_CLI: cli },
      }),
    ).toEqual({ cliArgs: [cli] });
  });

  test('preserves the non-Nix development CLI fallback', () => {
    expect(
      resolveLocalOpCliInvocation({
        platform: 'linux',
        isPackaged: false,
        execPath: '/electron',
        resourcesPath: '/unused',
        parentEnv: {},
      }),
    ).toEqual({ cliArgs: ['open-knowledge'] });
  });

  test('puts the Nix CLI directory on child PATH and strips Electron markers', () => {
    const env = {
      HOME: '/home/test',
      PATH: '/usr/bin',
      OK_NIX_CLI: cli,
      ELECTRON_RUN_AS_NODE: '1',
      OK_LOCK_KIND: 'interactive',
    };
    const child = composeOkChildEnv(env, okChildEnvOptions(env, { platform: 'linux' }));
    expect(child.PATH.split(':')[0]).toBe('/nix/store/test-openknowledge/bin');
    expect(child.PATH.split(':')).toContain('/usr/bin');
    expect(child.ELECTRON_RUN_AS_NODE).toBeUndefined();
    expect(child.OK_LOCK_KIND).toBeUndefined();
    expect(env.ELECTRON_RUN_AS_NODE).toBe('1');
  });

  test('loads Nix locales without treating Electron as packaged', () => {
    const deps = {
      isPackaged: false,
      resourcesPath: '/electron/resources',
      mainDir: '/repo/packages/desktop/out/main',
    };
    vi.stubEnv('OK_NIX_RESOURCES', resources);
    expect(resolveMenuCatalogDir(deps)).toBe(join(resources, 'locales'));
    vi.stubEnv('OK_NIX_RESOURCES', undefined);
    expect(resolveMenuCatalogDir(deps)).toBe('/repo/packages/app/src/locales');
    expect(resolveMenuCatalogDir({ ...deps, isPackaged: true })).toBe(
      '/electron/resources/locales',
    );
  });

  test.each(['linux', 'darwin'] as const)(
    'spawns Nix Node on %s, not Electron/helper',
    (platform) => {
      const input = {
        platform,
        isPackaged: true,
        parentExecPath: '/electron',
        bundleCliMjsPath: join(resources, 'cli/dist/cli.mjs'),
        reactShellDistDir: join(resources, 'app'),
        contentDir: '/project',
        spawnErrorLogFd: 9,
        env: { OK_NIX_NODE: node, PATH: '/usr/bin', ELECTRON_RUN_AS_NODE: '1' },
      };
      const result = resolveDetachedSpawnArgs(input);
      expect(result.file).toBe(node);
      expect(result.args).toEqual([
        '--max-old-space-size=16384',
        input.bundleCliMjsPath,
        'start',
        '--react-shell-dist-dir',
        input.reactShellDistDir,
      ]);
      expect(result.opts).toMatchObject({
        detached: true,
        cwd: '/project',
        stdio: ['ignore', 'ignore', 9],
        env: { OK_LOCK_KIND: 'interactive' },
      });
      expect(result.opts.env?.ELECTRON_RUN_AS_NODE).toBeUndefined();
      expect(input.env.ELECTRON_RUN_AS_NODE).toBe('1');
      const fallback = resolveDetachedSpawnArgs({ ...input, isPackaged: false, env: {} });
      expect(fallback.file).toBe('/electron');
      expect(fallback.opts.env?.ELECTRON_RUN_AS_NODE).toBe('1');
    },
  );
});

describe('Nix updater policy', () => {
  test.each([false, true])(
    'stays inactive even with forceDevBypass (packaged=%s)',
    async (isPackaged) => {
      const updater: UpdaterLike = {
        autoDownload: true,
        autoInstallOnAppQuit: true,
        channel: null,
        allowPrerelease: false,
        allowDowngrade: false,
        forceDevUpdateConfig: false,
        requestHeaders: null,
        setFeedURL: vi.fn(),
        on: vi.fn().mockReturnThis(),
        off: vi.fn().mockReturnThis(),
        checkForUpdates: vi.fn(),
        downloadUpdate: vi.fn(),
        quitAndInstall: vi.fn(),
      };
      const ipcMain = { handle: vi.fn(), removeHandler: vi.fn() };
      const readState = vi.fn((): never => {
        throw new Error('must not read update state');
      });
      const writeState = vi.fn();
      const whenRendererReady = vi.fn();
      const clock = { setTimeout: vi.fn(), clearTimeout: vi.fn() };
      const handle = startAutoUpdater({
        updater,
        ipcMain,
        readState,
        writeState,
        getPrimaryWindow: () => null,
        getAppVersion: () => '0.8.5',
        isPackaged,
        forceDevBypass: true,
        whenRendererReady,
        clock,
      });
      expect(updater.autoDownload).toBe(false);
      expect(updater.autoInstallOnAppQuit).toBe(false);
      expect(await handle.checkForUpdatesNow()).toEqual({ kind: 'updater-inactive' });
      expect(handle.getActiveWhatsNew()).toBeNull();
      expect(handle.getPendingUpdate()).toBeNull();
      handle.suppressAutoInstallOnQuit();
      handle.recordInstallHandoffOnQuit();
      handle.destroy();
      for (const spy of [
        updater.setFeedURL,
        updater.on,
        updater.off,
        updater.checkForUpdates,
        updater.downloadUpdate,
        updater.quitAndInstall,
        ipcMain.handle,
        ipcMain.removeHandler,
        readState,
        writeState,
        whenRendererReady,
        clock.setTimeout,
        clock.clearTimeout,
      ]) {
        expect(spy).not.toHaveBeenCalled();
      }
    },
  );
});

describe('DevTools dependency gate', () => {
  test.each([false, true])('honors devToolsAllowed=%s', (devToolsAllowed) => {
    const toggleDevTools = vi.fn();
    const win = { isDestroyed: () => false, webContents: { toggleDevTools } };
    applyMenuDispatchRole('toggleDevTools', {} as WebContents, {
      quit: vi.fn(),
      showAboutPanel: vi.fn(),
      devToolsAllowed,
      resolveWindow: () => win as unknown as BrowserWindow,
    });
    expect(toggleDevTools).toHaveBeenCalledTimes(devToolsAllowed ? 1 : 0);
  });
});

// Source wiring assertions, not an Electron boot test: index.ts starts the app.
// Match policy-bearing expressions, not line numbers, fixed counts or snapshots.
describe('Nix main-process source wiring', () => {
  const source = (name: string) =>
    readFileSync(new URL(`../../src/main/${name}.ts`, import.meta.url), 'utf8');
  const index = source('index');
  const normalize = (value: string) => value.replace(/\s+/g, ' ').trim();

  test('uses a separate production flag and the Nix resource root', () => {
    expect(index).toMatch(/const\s+nixResources\s*=\s*process\.env\.OK_NIX_RESOURCES\s*;/);
    expect(index).toMatch(
      /const\s+isProductionRuntime\s*=\s*app\.isPackaged\s*\|\|\s*Boolean\(nixResources\)\s*;/,
    );
    expect(index).toMatch(
      /const\s+runtimeResources\s*=\s*nixResources\s*\?\?\s*process\.resourcesPath\s*;/,
    );
    expect(index).toMatch(/rendererDevUrl\s*=\s*isProductionRuntime\s*\?\s*null\s*:/);
  });

  test.each(['showDevToolsMenu', 'devToolsAllowed'])(
    '%s uses production runtime at every wiring site',
    (key) => {
      const expressions = [...index.matchAll(new RegExp(`\\b${key}\\s*:\\s*([^,;]+)`, 'g'))];
      expect(expressions.length).toBeGreaterThan(0);
      for (const [, expression] of expressions) {
        expect(normalize(expression)).toBe(
          "!isProductionRuntime || DESKTOP_VARIANT.name !== 'stable'",
        );
      }
    },
  );

  test('every rendererEntryPath uses production resources', () => {
    const paths = [
      ...index.matchAll(
        /\brendererEntryPath\s*[:=]\s*([^;]+?join\(__dirname,\s*'\.\.\/renderer\/index\.html'\))/g,
      ),
    ];
    const sites = [...index.matchAll(/\brendererEntryPath\s*[:=]/g)];
    expect(sites.length).toBeGreaterThan(0);
    expect(paths).toHaveLength(sites.length);
    for (const [, expression] of paths) {
      expect(normalize(expression)).toBe(
        "isProductionRuntime ? join(runtimeResources, 'app', 'index.html') : join(__dirname, '../renderer/index.html')",
      );
    }
    expect(index).not.toMatch(/join\(process\.resourcesPath,\s*'app',\s*'index\.html'\)/);
  });

  test.each(['entry', 'index'])('%s leaves Electron isPackaged unchanged', (name) => {
    const text = source(name);
    expect(text).not.toMatch(/app\s*(?:\.\s*isPackaged|\[\s*['"]isPackaged['"]\s*\])\s*=(?!=)/);
    expect(text).not.toMatch(/(?:Object|Reflect)\.defineProperty\(\s*app\s*,\s*['"]isPackaged['"]/);
    expect(text).not.toMatch(/Object\.assign\(\s*app\s*,\s*\{[^}]*\bisPackaged\s*:/);
  });
});
