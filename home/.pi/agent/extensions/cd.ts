import {
  SessionManager,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type SessionEntry,
  type SessionHeader,
} from "@mariozechner/pi-coding-agent";
import type { AutocompleteItem } from "@mariozechner/pi-tui";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { realpath, readdir, stat, unlink, writeFile } from "node:fs/promises";
import { isAbsolute, join, resolve, sep } from "node:path";
import { homedir } from "node:os";

const COMMAND = "cd";
const CUSTOM_TYPE = "session.cd";
const MAX_COMPLETIONS = 50;

let currentCwdForCompletions = process.cwd();

export interface SessionSnapshot {
  cwd: string;
  sourceFile: string | undefined;
  sourceHeader: SessionHeader | null;
  entries: SessionEntry[];
  leafId: string | null;
}

export interface RelocateOptions {
  sessionDir?: string;
}

export interface RelocatedSession {
  sessionFile: string;
}

class InMemorySessionError extends Error {}

export function stripWrappingQuotes(input: string): string {
  const trimmed = input.trim();
  if (trimmed.length < 2) return trimmed;

  const first = trimmed[0];
  const last = trimmed[trimmed.length - 1];
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

export function expandHome(input: string): string {
  if (input === "~") return homedir();
  if (input.startsWith(`~${sep}`) || input.startsWith("~/")) {
    return join(homedir(), input.slice(2));
  }
  return input;
}

export function resolveTargetPath(
  rawArgs: string,
  cwd: string,
): Promise<string> {
  const rawPath = stripWrappingQuotes(rawArgs) || homedir();
  const expanded = expandHome(rawPath);
  return realpath(isAbsolute(expanded) ? expanded : resolve(cwd, expanded));
}

async function canonicalPath(path: string): Promise<string> {
  try {
    return await realpath(path);
  } catch {
    return resolve(path);
  }
}

export function displayPath(path: string): string {
  const home = homedir();
  if (path === home) return "~";
  if (path.startsWith(`${home}${sep}`)) {
    return `~${sep}${path.slice(home.length + 1)}`;
  }
  return path;
}

function createSnapshot(ctx: ExtensionCommandContext): SessionSnapshot {
  return {
    cwd: ctx.cwd,
    sourceFile: ctx.sessionManager.getSessionFile(),
    sourceHeader: ctx.sessionManager.getHeader(),
    entries: ctx.sessionManager.getEntries(),
    leafId: ctx.sessionManager.getLeafId(),
  };
}

function generateEntryId(existingIds: Set<string>): string {
  for (let i = 0; i < 100; i++) {
    const id = randomUUID().slice(0, 8);
    if (!existingIds.has(id)) return id;
  }

  for (;;) {
    const id = randomUUID();
    if (!existingIds.has(id)) return id;
  }
}

function createRelocationMarker(
  snapshot: SessionSnapshot,
  targetCwd: string,
): SessionEntry {
  const existingIds = new Set(snapshot.entries.map((entry) => entry.id));
  return {
    type: "custom",
    customType: CUSTOM_TYPE,
    id: generateEntryId(existingIds),
    parentId: snapshot.leafId,
    timestamp: new Date().toISOString(),
    data: {
      kind: "relocation",
      from: snapshot.cwd,
      to: targetCwd,
    },
  };
}

function getExistingParentSession(
  snapshot: SessionSnapshot,
): string | undefined {
  if (snapshot.sourceFile && existsSync(snapshot.sourceFile)) {
    return snapshot.sourceFile;
  }
  const parentSession = snapshot.sourceHeader?.parentSession;
  if (parentSession && existsSync(parentSession)) {
    return parentSession;
  }
  return undefined;
}

async function writeSessionFile(
  sessionFile: string,
  header: SessionHeader,
  entries: SessionEntry[],
): Promise<void> {
  const lines = [header, ...entries]
    .map((entry) => `${JSON.stringify(entry)}\n`)
    .join("");
  await writeFile(sessionFile, lines, { flag: "wx" });
}

function validateRelocatedSession(
  sessionFile: string,
  targetCwd: string,
  markerId: string,
): void {
  const opened = SessionManager.open(sessionFile);
  if (resolve(opened.getCwd()) !== resolve(targetCwd)) {
    throw new Error("Relocated session cwd mismatch");
  }
  if (opened.getLeafId() !== markerId) {
    throw new Error("Relocated session active leaf mismatch");
  }
}

async function relocateUnflushedSession(
  snapshot: SessionSnapshot,
  targetCwd: string,
  options: RelocateOptions,
): Promise<RelocatedSession> {
  const parentSession = getExistingParentSession(snapshot);
  const sessionManager = SessionManager.create(
    targetCwd,
    options.sessionDir,
    parentSession ? { parentSession } : undefined,
  );
  const sessionFile = sessionManager.getSessionFile();
  const header = sessionManager.getHeader();
  if (!sessionFile || !header) {
    throw new Error("Failed to create target session header");
  }

  const marker = createRelocationMarker(snapshot, targetCwd);
  try {
    await writeSessionFile(sessionFile, header, [...snapshot.entries, marker]);
    validateRelocatedSession(sessionFile, targetCwd, marker.id);
    return { sessionFile };
  } catch (error) {
    if ((error as { code?: unknown }).code !== "EEXIST") {
      await removeCreatedSession(sessionFile);
    }
    throw error;
  }
}

async function relocatePersistedSession(
  snapshot: SessionSnapshot,
  targetCwd: string,
  options: RelocateOptions,
): Promise<RelocatedSession> {
  if (!snapshot.sourceFile || !existsSync(snapshot.sourceFile)) {
    return relocateUnflushedSession(snapshot, targetCwd, options);
  }

  let forked: SessionManager;
  try {
    forked = SessionManager.forkFrom(
      snapshot.sourceFile,
      targetCwd,
      options.sessionDir,
    );
  } catch (error) {
    if (snapshot.entries.length === 0) throw error;
    return relocateUnflushedSession(snapshot, targetCwd, options);
  }

  const sessionFile = forked.getSessionFile();
  if (!sessionFile) {
    throw new Error(
      "Pi did not return a session file for the relocated session",
    );
  }

  try {
    if (snapshot.leafId) {
      forked.branch(snapshot.leafId);
    } else {
      forked.resetLeaf();
    }
    const markerData = {
      kind: "relocation",
      from: snapshot.cwd,
      to: targetCwd,
    };
    const markerId = forked.appendCustomEntry(CUSTOM_TYPE, markerData);
    validateRelocatedSession(sessionFile, targetCwd, markerId);
    return { sessionFile };
  } catch (error) {
    await removeCreatedSession(sessionFile);
    throw error;
  }
}

export async function relocateSession(
  snapshot: SessionSnapshot,
  targetCwd: string,
  options: RelocateOptions = {},
): Promise<RelocatedSession> {
  if (!snapshot.sourceFile) {
    throw new InMemorySessionError(
      "Cannot relocate an in-memory session; restart Pi in the target directory",
    );
  }
  const canonicalTargetCwd = await realpath(targetCwd);
  if (!(await stat(canonicalTargetCwd)).isDirectory()) {
    throw new Error(`Not a directory: ${displayPath(canonicalTargetCwd)}`);
  }
  return relocatePersistedSession(snapshot, canonicalTargetCwd, options);
}

export async function removeCreatedSession(sessionFile: string): Promise<void> {
  try {
    await unlink(sessionFile);
  } catch (error) {
    const code = (error as { code?: unknown }).code;
    if (code !== "ENOENT") throw error;
  }
}

function splitCompletionPrefix(rawPrefix: string): {
  dirPrefix: string;
  namePrefix: string;
} {
  if (rawPrefix === "~") return { dirPrefix: "~/", namePrefix: "" };

  const lastSlash = Math.max(
    rawPrefix.lastIndexOf("/"),
    rawPrefix.lastIndexOf(sep),
  );
  if (lastSlash >= 0) {
    return {
      dirPrefix: rawPrefix.slice(0, lastSlash + 1),
      namePrefix: rawPrefix.slice(lastSlash + 1),
    };
  }

  return { dirPrefix: "", namePrefix: rawPrefix };
}

async function isDirectory(path: string): Promise<boolean> {
  try {
    return (await stat(path)).isDirectory();
  } catch {
    return false;
  }
}

export async function completePath(
  prefix: string,
  cwd = currentCwdForCompletions,
): Promise<AutocompleteItem[] | null> {
  const rawPrefix = stripWrappingQuotes(prefix);
  const { dirPrefix, namePrefix } = splitCompletionPrefix(rawPrefix);
  const expandedDirPrefix = expandHome(dirPrefix || ".");
  const searchDir = isAbsolute(expandedDirPrefix)
    ? expandedDirPrefix
    : resolve(cwd, expandedDirPrefix);

  let dirEntries;
  try {
    dirEntries = await readdir(searchDir, { withFileTypes: true });
  } catch {
    return null;
  }

  const items: AutocompleteItem[] = [];
  if ("..".startsWith(namePrefix)) {
    items.push({
      value: `${dirPrefix}../`,
      label: "../",
      description: displayPath(resolve(searchDir, "..")),
    });
  }
  if (".".startsWith(namePrefix)) {
    items.push({
      value: `${dirPrefix}./`,
      label: "./",
      description: displayPath(searchDir),
    });
  }

  const includeHidden = namePrefix.startsWith(".");
  const sortedEntries = dirEntries
    .filter((entry) => includeHidden || !entry.name.startsWith("."))
    .filter((entry) => entry.name.startsWith(namePrefix))
    .sort((a, b) => a.name.localeCompare(b.name));

  for (const entry of sortedEntries) {
    if (items.length >= MAX_COMPLETIONS) break;
    const absoluteValue = join(searchDir, entry.name);
    if (
      !entry.isDirectory() &&
      (!entry.isSymbolicLink() || !(await isDirectory(absoluteValue)))
    ) {
      continue;
    }
    items.push({
      value: `${dirPrefix}${entry.name}/`,
      label: `${entry.name}/`,
      description: displayPath(absoluteValue),
    });
  }

  return items.length > 0 ? items : null;
}

export async function validateTargetDirectory(
  args: string,
  cwd: string,
): Promise<string> {
  let targetCwd: string;
  try {
    targetCwd = await resolveTargetPath(args, cwd);
  } catch {
    const rawPath = stripWrappingQuotes(args) || homedir();
    const expanded = expandHome(rawPath);
    const displayTarget = isAbsolute(expanded)
      ? expanded
      : resolve(cwd, expanded);
    throw new Error(`No such directory: ${displayPath(displayTarget)}`);
  }

  const targetStats = await stat(targetCwd);
  if (!targetStats.isDirectory()) {
    throw new Error(`Not a directory: ${displayPath(targetCwd)}`);
  }
  return targetCwd;
}

export async function sameDirectory(
  left: string,
  right: string,
): Promise<boolean> {
  return (await canonicalPath(left)) === (await canonicalPath(right));
}

export default function cdCommand(pi: ExtensionAPI) {
  pi.on("session_start", (_event, ctx) => {
    currentCwdForCompletions = ctx.cwd;
  });

  pi.registerCommand(COMMAND, {
    description:
      "Move this Pi session to another working directory, preserving the conversation",
    getArgumentCompletions: completePath,
    handler: async (args, ctx) => {
      await ctx.waitForIdle();

      let targetCwd: string;
      try {
        targetCwd = await validateTargetDirectory(args, ctx.cwd);
      } catch (error) {
        ctx.ui.notify(
          error instanceof Error ? error.message : String(error),
          "error",
        );
        return;
      }

      if (await sameDirectory(ctx.cwd, targetCwd)) {
        ctx.ui.notify(`Already in ${displayPath(targetCwd)}`, "info");
        return;
      }

      const snapshot = createSnapshot(ctx);
      let relocated: RelocatedSession;
      try {
        relocated = await relocateSession(snapshot, targetCwd);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(
          error instanceof InMemorySessionError
            ? message
            : `Failed to preserve session: ${message}`,
          "error",
        );
        return;
      }

      const result = await ctx.switchSession(relocated.sessionFile, {
        withSession: async (nextCtx) => {
          await nextCtx.sendMessage({
            customType: CUSTOM_TYPE,
            display: true,
            content:
              `Working directory changed from ${snapshot.cwd} to ${nextCtx.cwd}. ` +
              "Use the new directory for subsequent file and shell operations.",
            details: { from: snapshot.cwd, to: nextCtx.cwd },
          });
        },
      });

      if (result.cancelled) {
        try {
          await removeCreatedSession(relocated.sessionFile);
          ctx.ui.notify(`cd cancelled: ${displayPath(targetCwd)}`, "warning");
        } catch (error) {
          ctx.ui.notify(
            `cd cancelled, but cleanup failed: ${
              error instanceof Error ? error.message : String(error)
            }`,
            "warning",
          );
        }
      }
    },
  });
}
