// Copied into packages/server/src/acp by the Nix build.
import { execFileSync } from 'node:child_process';
import { accessSync, constants, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { buildManagedServerEntry, isEntryUpToDate } from '../../../cli/src/commands/editors.ts';
import { createTestLogger } from '../logger.ts';
import { preflightLaunch, resolveRegistryLaunch, type ResolvedLaunch } from './launch.ts';

const log = createTestLogger('nix-runtime');
const shell = '@nixShell@';
const commands: Readonly<Record<string, string | null>> = JSON.parse('@nixAgentCommands@');

test.each(['codex-acp', 'claude-acp', 'pi-acp'])(
  '%s selects its configured Nix adapter',
  async (id) => {
    const cmd = commands[id] ?? null;
    if (cmd === null) {
      await expect(
        resolveRegistryLaunch(
          { id, name: id, version: '0.0.0', distribution: {} },
          null,
          log,
          '/unused',
        ),
      ).rejects.toMatchObject({ code: 'no-distribution' });
      return;
    }
    expect(() => accessSync(cmd, constants.X_OK)).not.toThrow();
    const prepare = async (launch: ResolvedLaunch) => ({
      ...launch,
      env: { ...launch.env, OK_NIX_TEST: 'prepared' },
    });
    const launch = await resolveRegistryLaunch(
      { id, name: id, version: '0.0.0', distribution: {} },
      null,
      log,
      '/unused',
      prepare,
    );
    expect(launch).toMatchObject({
      cmd,
      args: [],
      kind: 'custom',
      env: { OK_NIX_TEST: 'prepared' },
    });
    expect(cmd).toMatch(/^\/nix\/store\//);
  },
);

test.each(['unknown-agent', '__proto__', 'constructor'])(
  '%s retains upstream distribution handling',
  async (id) => {
    await expect(
      resolveRegistryLaunch(
        { id, name: id, version: '0.0.0', distribution: {} },
        null,
        log,
        '/unused',
      ),
    ).rejects.toMatchObject({ code: 'no-distribution' });
  },
);

test('local adapters honor cancelled preparation without acquiring a distribution', async () => {
  const id = Object.keys(commands).find((id) => commands[id] !== null);
  if (id === undefined) return;
  expect(
    await resolveRegistryLaunch(
      { id, name: id, version: '0.0.0', distribution: {} },
      null,
      log,
      '/unused',
      async () => null,
    ),
  ).toBeNull();
});

test('missing local adapters fail preflight instead of acquiring a replacement', async () => {
  await expect(
    preflightLaunch({
      cmd: '/nonexistent/nix-adapter',
      args: [],
      env: {},
      pathFromOverlay: false,
      kind: 'custom',
    }),
  ).rejects.toMatchObject({ code: 'command-not-found' });
});

test.each(['darwin', 'linux'] as const)(
  'Nix MCP launcher works without npx on %s',
  (platformName) => {
    const entry = buildManagedServerEntry({ platformName });
    expect(isEntryUpToDate(entry)).toBe(true);
    const args = entry.args as string[];
    expect(args[2]).toContain('/bin/open-knowledge" mcp');
    const dir = mkdtempSync(join(tmpdir(), 'ok-nix-mcp-'));
    try {
      // Execute the generated chain with a real local executable, not an MCP server.
      const probe = join(dir, 'probe');
      writeFileSync(probe, `#!${shell}\nprintf "%s" "$1"\n`, { mode: 0o755 });
      const chain = args[2].replace(
        /"\/nix\/store\/[^"\n]+\/bin\/open-knowledge"/,
        JSON.stringify(probe),
      );
      expect(
        execFileSync(shell, ['-c', chain], {
          env: { PATH: '/nonexistent', HOME: dir },
          encoding: 'utf8',
        }),
      ).toBe('mcp');
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  },
);
