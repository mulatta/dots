// Vendored from `ai-memory install-hooks --agent pi --apply`.
// Runtime credentials come from environment set by Home Manager's Pi wrapper.

import { execFileSync } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync as readMarkerText, readSync } from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";
import { homedir } from "node:os";

const SERVER = (process.env.AI_MEMORY_SERVER_URL ?? "").replace(/\/+$/, "");
const AGENT = "pi";
const TOKEN: string | null = process.env.AI_MEMORY_AUTH_TOKEN || null;

if (!SERVER || !TOKEN) {
  throw new Error("ai-memory Pi extension requires AI_MEMORY_SERVER_URL and AI_MEMORY_AUTH_TOKEN");
}

// capture-policy-v1 (generated; do not fork between adapters)
const CAPTURE_POLICY_V1 = 1;
const CAPTURE_MARKER_MAX_BYTES = 64 * 1024;
const CAPTURE_MAX_PATTERNS = 128;
const CAPTURE_MAX_PATTERN_CHARS = 1024;
const CAPTURE_MAX_PATH_CHARS = 4096;
const CAPTURE_MAX_CANDIDATES = 32;
const CAPTURE_MAX_WORK = 1000000;
const CAPTURE_MAX_CALL_ID_CHARS = 128;

type CaptureDisposition = "keep" | "drop" | "metadata-only";
type CaptureProtocol = { version: 1; disposition: CaptureDisposition; policy_state: "inactive" | "active" | "invalid"; tool_family: "file" | "search-list" | "non-file" | "unknown"; path_count: number; extraction_state: "not-applicable" | "extracted" | "missing-or-malformed" | "unsupported-schema" };

type CaptureConfig = { state: "inactive" | "active" | "invalid"; patterns: { path: string; windows: boolean; directory?: string }[]; base: string };
function readFileSync(path: string, encoding?: "utf8"): any { if (encoding) return readMarkerText(path, encoding); const fd = openSync(path, "r"); try { const bytes = Buffer.allocUnsafe(CAPTURE_MARKER_MAX_BYTES + 1); const count = readSync(fd, bytes, 0, bytes.length, 0); if (count > CAPTURE_MARKER_MAX_BYTES) throw new Error("marker too large"); const result = bytes.subarray(0, count); new TextDecoder("utf-8", { fatal: true }).decode(result); return result; } finally { closeSync(fd); } }
function captureTrimComment(line: string): string { let quote = ""; let escaped = false; for (let i = 0; i < line.length; i++) { const c = line[i]; if (escaped) { escaped = false; continue; } if (c === "\\" && quote === '"') { escaped = true; continue; } if ((c === '"' || c === "'") && (!quote || quote === c)) quote = quote ? "" : c; else if (c === "#" && !quote) { line = line.slice(0, i); break; } } if (line.trimStart().startsWith("[") && !/^\s*\[[^\]]+\]\s*$/.test(line)) throw new Error("invalid table header"); if (quote) throw new Error("unterminated string"); return line; }
function captureNormalize(path: string): { path: string; windows: boolean } | undefined { const p = path.replace(/\\/g, "/"); let root: string; let tail: string[]; if (p.startsWith("//")) { const x = p.slice(2).split("/").filter(Boolean); if (x.length < 2) return undefined; root = `//${x.shift()}/${x.shift()}`; tail = x; } else if (/^[A-Za-z]:\//.test(p)) { root = `${p[0].toUpperCase()}:/`; tail = p.slice(3).split("/"); } else if (p.startsWith("/")) { root = "/"; tail = p.slice(1).split("/"); } else return undefined; const out: string[] = []; for (const x of tail) { if (!x || x === ".") continue; if (x === "..") out.pop(); else out.push(x); } return { path: root + (out.length ? (root.endsWith("/") ? "" : "/") + out.join("/") : ""), windows: root !== "/" }; }
function captureJoin(base: string, child: string): string { if (/^[^A-Za-z]?:|^[A-Za-z]:[^/\\]/.test(child)) return child; return `${base.replace(/[\\/]+$/, "")}/${child}`; }
function captureValidGlob(p: string): boolean { return !!p && [...p].length <= CAPTURE_MAX_PATTERN_CHARS && !/[!{}\[\]()|^$%]/.test(p) && !p.includes("${") && !p.includes("***") && !p.replace(/\\/g, "/").split("/").includes("..") && (!p.startsWith("~") || p.startsWith("~/")) && !/^[^A-Za-z]?:/.test(p) && !/^[A-Za-z]:[^/\\]/.test(p); }
function captureParseArray(value: string): string[] | undefined { let i = 0; const out: string[] = []; const ws = () => { while (/\s/.test(value[i] ?? "")) i++; }; const basic = { b: "\b", t: "\t", n: "\n", f: "\f", r: "\r", '"': '"', "\\": "\\" } as Record<string, string>; ws(); if (value[i++] !== "[") return undefined; for (;;) { ws(); if (value[i] === "]") { i++; ws(); return i === value.length ? out : undefined; } const quote = value[i++]; if (quote !== '"' && quote !== "'") return undefined; let s = ""; for (;;) { if (i >= value.length) return undefined; const c = value[i++]; if (c === quote) break; if (c === "\\" && quote === '"') { const e = value[i++]; if (e in basic) s += basic[e]; else if (e === "u" || e === "U") { const count = e === "u" ? 4 : 8; const hex = value.slice(i, i + count); if (!new RegExp(`^[0-9A-Fa-f]{${count}}$`).test(hex)) return undefined; const n = Number.parseInt(hex, 16); if (n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff)) return undefined; s += String.fromCodePoint(n); i += count; } else return undefined; } else if (c === "\n" || c === "\r") return undefined; else s += c; } out.push(s); ws(); if (value[i] === ",") { i++; continue; } if (value[i] === "]") continue; return undefined; } }
function captureConfig(cwd: string | undefined): CaptureConfig {
  const marker = findMarker(cwd);
  const candidateBase = captureNormalize(cwd ? resolve(cwd) : "")?.path ?? "";
  if (!marker) return { state: "inactive", patterns: [], base: candidateBase };
  try {
    const bytes = readFileSync(marker);
    const markerBase = captureNormalize(dirname(marker))?.path ?? candidateBase;
    if (bytes.byteLength > CAPTURE_MARKER_MAX_BYTES) return { state: "invalid", patterns: [], base: candidateBase };
    let section = "";
    let value = "";
    let collecting = false;
    let seen = false;
    for (const raw of bytes.toString("utf8").split(/\r?\n/)) {
      const line = captureTrimComment(raw).trim();
      if (!line) continue;
      const table = /^\[([^\]]+)\]$/.exec(line);
      if (table) {
        if (collecting) return { state: "invalid", patterns: [], base: candidateBase };
        section = table[1];
        continue;
      }
      if (section !== "capture") continue;
      if (!seen) {
        const kv = /^([A-Za-z0-9_-]+)\s*=\s*(.*)$/.exec(line);
        if (!kv || kv[1] !== "ignore_paths") return { state: "invalid", patterns: [], base: candidateBase };
        seen = true;
        value = kv[2];
        collecting = !value.includes("]");
      } else if (collecting) {
        value += ` ${line}`;
        collecting = !value.includes("]");
      } else return { state: "invalid", patterns: [], base: candidateBase };
    }
    if (collecting) return { state: "invalid", patterns: [], base: candidateBase };
    if (!seen) return { state: "inactive", patterns: [], base: candidateBase };
    const strings = captureParseArray(value);
    if (!strings || strings.length > CAPTURE_MAX_PATTERNS) return { state: "invalid", patterns: [], base: candidateBase };
    const home = homedir();
    const patterns = strings.map((source) => {
      if (!captureValidGlob(source)) return undefined;
      const expanded = source.startsWith("~/")
        ? captureJoin(home, source.slice(2))
        : /^(?:\/|\\\\|[A-Za-z]:[\\/])/.test(source)
          ? source
          : captureJoin(markerBase, source);
      const normalized = captureNormalize(expanded);
      if (!normalized) return undefined;
      return { path: normalized.path, windows: normalized.windows, directory: normalized.path.endsWith("/**") ? (normalized.path.slice(0, -3) || "/") : undefined };
    });
    if (patterns.some((p) => !p)) return { state: "invalid", patterns: [], base: candidateBase };
    return patterns.length
      ? { state: "active", patterns: patterns as CaptureConfig["patterns"], base: candidateBase }
      : { state: "inactive", patterns: [], base: candidateBase };
  } catch (_e) {
    return { state: "invalid", patterns: [], base: candidateBase };
  }
}
function captureGlob(pattern: string, candidate: string, insensitive: boolean, budget: { work: number }): boolean | undefined { const p = [...pattern]; const c = [...candidate]; const eq = (a: string, b: string) => insensitive && a.charCodeAt(0) < 128 && b.charCodeAt(0) < 128 ? a.toLowerCase() === b.toLowerCase() : a === b; const previous = new Array<boolean>(p.length + 1).fill(false); previous[0] = true; for (let j = 1; j <= p.length; j++) previous[j] = p[j - 1] === "*" && p[j] !== "*" && previous[j - 1]; for (const ch of c) { const current = new Array<boolean>(p.length + 1).fill(false); for (let j = 1; j <= p.length; j++) { if (++budget.work > CAPTURE_MAX_WORK) return undefined; const x = p[j - 1]; current[j] = x === "*" && p[j] === "*" ? false : x === "*" && j >= 2 && p[j - 2] === "*" ? current[j - 2] || previous[j] : x === "*" ? current[j - 1] || (ch !== "/" && previous[j]) : x === "?" ? ch !== "/" && previous[j - 1] : eq(x, ch) && previous[j - 1]; } for (let j = 0; j <= p.length; j++) previous[j] = current[j]; } return previous[p.length]; }
function captureTool(payload: Record<string, unknown>): { family: CaptureProtocol["tool_family"]; paths?: string[]; extraction: CaptureProtocol["extraction_state"]; callID?: string } { const name = typeof payload.tool === "string" ? payload.tool.toLowerCase() : ""; const args = payload.args as Record<string, unknown> | undefined; const call = ["tool_use_id","toolUseId","tool_call_id","toolCallId","call_id","callId","callID"].map((k) => payload[k]).find((v): v is string => typeof v === "string" && /^[A-Za-z0-9_.-]{1,128}$/.test(v)); if (["search","grep","glob","find","list","ls","list_files","read_dir"].includes(name)) return { family: "search-list", extraction: "not-applicable", callID: call }; if (["bash","shell","execute","run_command","web_search"].includes(name)) return { family: "non-file", extraction: "extracted", callID: call }; if (!["read","write","edit","apply_patch","notebookedit","notebook_edit","create_file","delete_file","rename_file","move_file","multi_edit","multiedit","replace","replace_all"].includes(name)) return { family: "unknown", extraction: "extracted", callID: call }; const direct = (o: any): string[] | undefined => { if (!o || typeof o !== "object") return undefined; const r: string[] = []; for (const k of ["file_path","filePath","path","absolute_path","AbsolutePath","notebook_path"]) if (k in o) { if (typeof o[k] !== "string") return undefined; r.push(o[k]); } if ("paths" in o) { if (!Array.isArray(o.paths) || o.paths.some((x: unknown) => typeof x !== "string")) return undefined; r.push(...o.paths); } return r.length && r.length <= CAPTURE_MAX_CANDIDATES ? r : undefined; }; let paths = direct(args); if (["multi_edit","multiedit","replace_all"].includes(name)) { const entries = args?.edits ?? args?.replacements; if (!Array.isArray(entries) || !entries.length || entries.length > CAPTURE_MAX_CANDIDATES) paths = undefined; else { paths = paths ?? []; for (const entry of entries) { const more = direct(entry); if (!more || paths.length + more.length > CAPTURE_MAX_CANDIDATES) { paths = undefined; break; } paths.push(...more); } } } if (!paths || paths.some((p) => !p.trim() || [...p].length > CAPTURE_MAX_PATH_CHARS)) return { family: "file", extraction: "missing-or-malformed", callID: call }; return { family: "file", paths, extraction: "extracted", callID: call }; }
function capturePolicy(payload: Record<string, unknown>, cwd: string | undefined): { disposition: CaptureDisposition; protocol?: CaptureProtocol; payload: Record<string, unknown> } { const config = captureConfig(cwd); const tool = captureTool(payload); let disposition: CaptureDisposition = "keep"; if (config.state === "invalid" && tool.family === "file") disposition = "metadata-only"; else if (config.state === "active" && tool.family === "search-list") disposition = "drop"; else if (config.state === "active" && tool.family === "file") { if (!tool.paths) disposition = "metadata-only"; else { const candidates = tool.paths.map((p) => captureNormalize(/^(?:\/|\\\\|[A-Za-z]:[\\/])/.test(p) ? p : captureJoin(config.base, p))); if (candidates.some((p) => !p)) disposition = "metadata-only"; else { const budget = { work: 0 }; captureMatch: for (const candidate of candidates as { path: string; windows: boolean }[]) for (const pattern of config.patterns) { if (candidate.windows !== pattern.windows) continue; if (pattern.directory && captureGlob(pattern.directory, candidate.path, pattern.windows, budget)) { disposition = "drop"; break captureMatch; } const match = captureGlob(pattern.path, candidate.path, pattern.windows, budget); if (match === undefined) { disposition = "metadata-only"; break; } if (match) { disposition = "drop"; break captureMatch; } } } } } if (config.state === "inactive") return { disposition, payload }; const protocol: CaptureProtocol = { version: CAPTURE_POLICY_V1, disposition, policy_state: config.state, tool_family: tool.family, path_count: tool.paths?.length ?? 0, extraction_state: tool.extraction }; if (disposition === "metadata-only") { const session = payload.sessionID ?? payload.sessionId ?? payload.session_id; const routing = typeof payload.cwd === "string" ? payload.cwd : cwd; return { disposition, protocol, payload: { ...(typeof session === "string" ? { session_id: session } : {}), ...(typeof routing === "string" ? { cwd: routing } : {}), tool_family: tool.family, tool_name: tool.family, ...(tool.callID ? { tool_call_id: tool.callID } : {}), _ai_memory_capture: protocol } }; } if (disposition === "keep") return { disposition, protocol, payload: { ...payload, _ai_memory_capture: protocol } }; return { disposition, protocol, payload }; }


function timeoutSignal(ms: number): AbortSignal | undefined {
  if (typeof AbortSignal === "undefined") return undefined;
  const factory = (AbortSignal as unknown as { timeout?: (ms: number) => AbortSignal }).timeout;
  return factory ? factory(ms) : undefined;
}

function authHeaders(): Record<string, string> {
  return TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {};
}

const HOOK_QUEUE_MAX = 100;
const HOOK_FLUSH_INTERVAL_MS = 2000;
const HOOK_FLUSH_THRESHOLD = 20;
const HOOK_INTER_REQUEST_DELAY_MS = 50;
const HOOK_REQUEST_TIMEOUT_MS = 2000;
const HOOK_IMMEDIATE_EVENTS = new Set(["session-start", "stop", "session-end", "pre-compact"]);

type HookQueueItem = { event: string; url: URL; payload: Record<string, unknown> };
const hookQueue: HookQueueItem[] = [];
let hookFlushTimer: ReturnType<typeof setTimeout> | undefined;
let hookDraining = false;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function scheduleHookFlush(): void {
  if (hookFlushTimer) return;
  hookFlushTimer = setTimeout(() => {
    hookFlushTimer = undefined;
    void drainHookQueue();
  }, HOOK_FLUSH_INTERVAL_MS);
  hookFlushTimer.unref?.();
}

function enqueueHook(event: string, url: URL, payload: Record<string, unknown>): void {
  if (hookQueue.length >= HOOK_QUEUE_MAX) hookQueue.shift();
  hookQueue.push({ event, url, payload });
  if (HOOK_IMMEDIATE_EVENTS.has(event) || hookQueue.length >= HOOK_FLUSH_THRESHOLD) {
    void drainHookQueue();
  } else {
    scheduleHookFlush();
  }
}

async function drainHookQueue(): Promise<void> {
  if (hookDraining) return;
  hookDraining = true;
  if (hookFlushTimer) {
    clearTimeout(hookFlushTimer);
    hookFlushTimer = undefined;
  }
  try {
    while (hookQueue.length > 0) {
      const item = hookQueue.shift();
      if (!item) break;
      try {
        await fetch(item.url, {
          method: "POST",
          headers: { "Content-Type": "application/json", ...authHeaders() },
          body: JSON.stringify(item.payload),
          signal: timeoutSignal(HOOK_REQUEST_TIMEOUT_MS),
        }).catch(() => undefined);
      } catch (_e) {
        // Best-effort capture. Hooks must never block the agent.
      }
      if (hookQueue.length > 0) await sleep(HOOK_INTER_REQUEST_DELAY_MS);
    }
  } finally {
    hookDraining = false;
    if (hookQueue.length > 0) void drainHookQueue();
  }
}

function findMarker(cwd: string | undefined): string | undefined {
  if (!cwd) return undefined;
  let dir = resolve(cwd);
  const home = homedir();
  let boundary: string | undefined;
  if (home && (dir === home || dir.startsWith(home.endsWith(sep) ? home : home + sep))) {
    boundary = home;
  } else if (home) {
    let probe = dir;
    while (probe && probe !== dirname(probe)) {
      if (existsSync(join(probe, ".git"))) {
        boundary = probe;
        break;
      }
      probe = dirname(probe);
    }
    boundary ??= dir;
  }
  while (dir && dir !== dirname(dir)) {
    const marker = join(dir, ".ai-memory.toml");
    if (existsSync(marker)) return marker;
    if (boundary && dir === boundary) return undefined;
    dir = dirname(dir);
  }
  return undefined;
}

function tomlKey(text: string, key: string): string | undefined {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*"([^"]*)"`);
  for (const line of text.split(/\r?\n/)) {
    const match = re.exec(line);
    if (match) return match[1];
  }
  return undefined;
}


function repoRootProject(cwd: string | undefined): string | undefined {
  if (!cwd) return undefined;
  try {
    const inside = execFileSync("git", ["-C", cwd, "rev-parse", "--is-inside-work-tree"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (inside !== "true") return undefined;
    const common = execFileSync("git", ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (!common) return undefined;
    const root = dirname(common);
    if (!root || root === dirname(root)) return undefined;
    return basename(root);
  } catch (_e) {
    return undefined;
  }
}
const DEFAULT_PROJECT_STRATEGY = "repo-root";
function tomlFlag(text: string, key: string): string | undefined {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*(?:"([^"]*)"|([^#\\s]+))`);
  for (const line of text.split(/\r?\n/)) {
    const match = re.exec(line);
    if (match) return match[1] ?? match[2];
  }
  return undefined;
}
function applyMarkerParams(url: URL, cwd: string | undefined): void {
  const managedRun = process.env.AI_MEMORY_RUN_ID;
  if (managedRun) url.searchParams.set("managed_run", managedRun);
  if (!cwd) return;
  url.searchParams.set("cwd", cwd);
  let workspace: string | undefined;
  let project: string | undefined;
  let projectStrategy: string | undefined;
  let dropSubagent: string | undefined;
  let defaultGlobal: string | undefined;
  let briefing: string | undefined;
  let briefingBudget: string | undefined;
  const marker = findMarker(cwd);
  if (marker) {
    try {
      const body = readFileSync(marker, "utf8");
      workspace = tomlKey(body, "workspace");
      project = tomlKey(body, "project");
      projectStrategy = tomlKey(body, "project_strategy");
      dropSubagent = tomlKey(body, "drop_subagent_captures");
      defaultGlobal = tomlFlag(body, "default_global");
      briefing = tomlFlag(body, "inject_on_session_start");
      briefingBudget = tomlFlag(body, "max_chars");
    } catch (_e) {
    }
  }
  if (!projectStrategy) projectStrategy = DEFAULT_PROJECT_STRATEGY;
  if (!project && (projectStrategy === "repo-root" || projectStrategy === "repo_root")) {
    const repoProject = repoRootProject(cwd);
    if (repoProject) project = repoProject;
  }
  if (workspace) url.searchParams.set("workspace", workspace);
  if (project) url.searchParams.set("project", project);
  if (projectStrategy) url.searchParams.set("project_strategy", projectStrategy);
  if (dropSubagent) url.searchParams.set("drop_subagent", dropSubagent);
  if (defaultGlobal) url.searchParams.set("default_global", defaultGlobal);
  if (briefing) url.searchParams.set("briefing", briefing);
  if (briefingBudget) url.searchParams.set("briefing_budget", briefingBudget);
}

function sessionID(ctx: any): string | undefined {
  const id = ctx?.sessionManager?.getSessionId?.();
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

function modelName(model: any): string | undefined {
  const name = model?.id ?? model?.name ?? model?.model;
  return typeof name === "string" && name.length > 0 ? name : undefined;
}

function sessionPayload(ctx: any): Record<string, unknown> {
  return {
    sessionID: sessionID(ctx),
    cwd: ctx?.cwd,
    model: modelName(ctx?.model),
  };
}

function stringify(value: unknown): string {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  try {
    return JSON.stringify(value);
  } catch (_e) {
    return String(value);
  }
}

function contentToText(content: unknown): string {
  if (content === null || content === undefined) return "";
  if (!Array.isArray(content)) return stringify(content);
  return content
    .map((part: any) => {
      if (typeof part?.text === "string") return part.text;
      if (typeof part?.content === "string") return part.content;
      if (typeof part?.type === "string") return `[${part.type}]`;
      return stringify(part);
    })
    .filter(Boolean)
    .join("\n\n")
    .trim();
}

const startedSessions = new Set<string>();
const handoffChecked = new Set<string>();
const preCompactLast = new Map<string, number>();

function startSession(ctx: any, extra: Record<string, unknown> = {}): void {
  const id = sessionID(ctx);
  if (!id || startedSessions.has(id)) return;
  startedSessions.add(id);
  // Generated integrations inject through fetchHandoff below. In managed mode
  // a queued SessionStart response is not model-visible and must not consume
  // the workstream context before that synchronous fetch receives it.
  if (!process.env.AI_MEMORY_RUN_ID) {
    postHook("session-start", { ...sessionPayload(ctx), ...extra });
  }
}

function postPreCompact(ctx: any): void {
  startSession(ctx);
  const key = sessionID(ctx) || "unknown";
  const now = Date.now();
  const last = preCompactLast.get(key) ?? 0;
  if (now - last < 1000) return;
  preCompactLast.set(key, now);
  postHook("pre-compact", sessionPayload(ctx));
}

function postHook(event: string, payload: Record<string, unknown>): void {
  const url = new URL(`${SERVER}/hook`);
  url.searchParams.set("event", event);
  url.searchParams.set("agent", AGENT);
  applyMarkerParams(url, typeof payload.cwd === "string" ? payload.cwd : undefined);
  const policy = capturePolicy(payload, typeof payload.cwd === "string" ? payload.cwd : undefined);
  if (policy.disposition === "drop") return;
  try {
    enqueueHook(event, url, policy.payload);
  } catch (_e) {
    // Best-effort capture. Hooks must never block the agent.
  }
}

async function fetchHandoff(cwd: string, id: string | undefined): Promise<string | undefined> {
  const url = new URL(`${SERVER}/handoff`);
  url.searchParams.set("agent", AGENT);
  url.searchParams.set("cwd", cwd);
  if (id) url.searchParams.set("session_id", id);
  applyMarkerParams(url, cwd);
  try {
    const response = await fetch(url, {
      headers: authHeaders(),
      signal: timeoutSignal(1000),
    });
    const text = (await response.text()).trim();
    return text.length > 0 ? text : undefined;
  } catch (_e) {
    return undefined;
  }
}


// ---- MCP bridge ------------------------------------------------------------
const MCP_SERVER = deriveMcpServer(SERVER);
const MCP_REQUEST_TIMEOUT_MS = 10000;
let mcpRequestId = 0;

function deriveMcpServer(server: string): string {
  const trimmed = server.replace(/\/+$/, "");
  return trimmed.endsWith("/mcp") ? trimmed : `${trimmed}/mcp`;
}

function mcpSessionId(ctx: any): string | undefined {
  const id = sessionID(ctx) ?? ctx?.sessionId ?? ctx?.sessionID ?? ctx?.session?.id;
  return typeof id === "string" && id.length > 0 ? id : undefined;
}

function mcpSignal(signal?: AbortSignal): AbortSignal | undefined {
  const timeout = timeoutSignal(MCP_REQUEST_TIMEOUT_MS);
  if (!signal) return timeout;
  if (!timeout) return signal;
  const anyFactory = (AbortSignal as unknown as { any?: (signals: AbortSignal[]) => AbortSignal }).any;
  return anyFactory ? anyFactory([signal, timeout]) : timeout;
}

async function mcpRpc(method: string, params?: unknown, ctx?: any, signal?: AbortSignal): Promise<any> {
  const id = ++mcpRequestId;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
    ...authHeaders(),
  };
  const session = mcpSessionId(ctx);
  if (session) {
    headers["X-Memory-Actor-Session-Id"] = session;
    headers["Mcp-Session-Id"] = session;
  }
  const response = await fetch(MCP_SERVER, {
    method: "POST",
    headers,
    body: JSON.stringify({ jsonrpc: "2.0", id, method, params: params ?? {} }),
    signal: mcpSignal(signal),
  });
  if (!response.ok) throw new Error(`ai-memory MCP ${method} failed: HTTP ${response.status}`);
  const payload = await response.json();
  if (payload?.error) throw new Error(`ai-memory MCP ${method} failed: ${payload.error.message ?? JSON.stringify(payload.error)}`);
  if (payload?.result?.isError) throw new Error(`ai-memory MCP ${method} returned isError`);
  return payload?.result;
}

function toolInputSchema(tool: any): any {
  return tool?.inputSchema ?? { type: "object", additionalProperties: true };
}

async function bootstrapMcpBridge(pi: any): Promise<void> {
  try {
    await mcpRpc("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "ai-memory-pi-extension", version: "0.0.0" },
    });
    try { await mcpRpc("notifications/initialized"); } catch (_e) {}
    const listed = await mcpRpc("tools/list");
    for (const tool of listed?.tools ?? []) {
      try {
        pi.registerTool({
          name: tool.name,
          label: tool.name,
          description: tool.description,
          parameters: toolInputSchema(tool),
          execute: async (_toolCallId: string, params: unknown, signal?: AbortSignal, _onUpdate?: unknown, ctx?: any) => {
            const result = await mcpRpc("tools/call", { name: tool.name, arguments: params ?? {} }, ctx, signal);
            return { content: result?.content ?? [], details: result };
          },
        });
      } catch (_e) {
        // Duplicate registration or tool-shape mismatch must not break lifecycle capture.
      }
    }
  } catch (_e) {
    // MCP bridge is best-effort; extension load and lifecycle capture must survive.
  }
}

export default function AiMemoryExtension(pi: any): void {
  try { void bootstrapMcpBridge(pi); } catch (_e) {}
  pi.on("session_start", (_event: any, ctx: any) => {
    startSession(ctx);
  });

  pi.on("before_agent_start", async (event: any, ctx: any) => {
    startSession(ctx);
    postHook("user-prompt", {
      ...sessionPayload(ctx),
      prompt: event?.prompt,
      imageCount: Array.isArray(event?.images) ? event.images.length : undefined,
    });

    const id = sessionID(ctx);
    if (!id || handoffChecked.has(id)) return;
    handoffChecked.add(id);
    const handoff = await fetchHandoff(ctx?.cwd ?? "", id);
    if (!handoff) return;
    return {
      message: {
        customType: "ai-memory-handoff",
        content: handoff,
        display: false,
        attribution: "agent",
      },
    };
  });

  pi.on("tool_call", (event: any, ctx: any) => {
    startSession(ctx);
    postHook("pre-tool-use", {
      ...sessionPayload(ctx),
      tool: event?.toolName,
      callID: event?.toolCallId,
      args: event?.input,
    });
  });

  pi.on("tool_result", (event: any, ctx: any) => {
    startSession(ctx);
    postHook("post-tool-use", {
      ...sessionPayload(ctx),
      tool: event?.toolName,
      callID: event?.toolCallId,
      args: event?.input,
      output: contentToText(event?.content),
      details: event?.details,
      isError: event?.isError,
    });
  });

  pi.on("session_before_compact", (_event: any, ctx: any) => {
    postPreCompact(ctx);
  });

  pi.on("session_compact", (_event: any, ctx: any) => {
    postPreCompact(ctx);
  });


  pi.on("agent_end", (_event: any, ctx: any) => {
    startSession(ctx);
    postHook("stop", sessionPayload(ctx));
  });

  pi.on("session_shutdown", (_event: any, ctx: any) => {
    startSession(ctx);
    postHook("session-end", sessionPayload(ctx));
  });
}
