/**
 * Custom Footer Extension - one line shaped like the statusline extension's widget (model,
 * plan usage, context, folder, branch, VCS state, extension statuses), followed by bar cells
 * like the Claude Code status line (home/.claude/statusline.sh): context, prompt cache TTL,
 * plan limits and cost. hmeter's per-terminal snapshot supplies the cache.
 */

import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
// The vendored statusline submodule (pinned by dots) sits beside this file in both the repo
// and ~/.pi/agent/extensions, so its jj/git status reader is reused instead of copied.
import {
  getVcsStatus,
  invalidateVcs,
  setVcsUpdateCallback,
} from "./statusline/src/vcs.js";

// Catppuccin Mocha as fixed RGB, not the pi theme, so the cells match Herdr's agents list.
const RGB = {
  SUB: [166, 173, 200],
  SURF: [69, 71, 90],
  OVL: [108, 112, 134],
  PEACH: [250, 179, 135],
  YEL: [249, 226, 175],
  RED: [243, 139, 168],
  BLUE: [137, 180, 250],
  MAUVE: [203, 166, 247],
  GREEN: [166, 227, 161],
  TEAL: [148, 226, 213],
} as const;
type Color = keyof typeof RGB;
const RAMP: Color[] = ["SUB", "YEL", "YEL", "PEACH", "RED"];
const BAR_CELLS = 7;
const TICK_MS = 30_000;
const STATUSLINE_STALE_MS = 15 * 60_000;
// The same commands the statusline extension watches for VCS changes.
const VCS_CHANGE_PATTERNS = [
  /\b(git|jj)\s+(checkout|switch|branch|merge|rebase|pull|reset|new|edit|abandon|squash|split|move|bookmark)\b/,
  /\bjj\s+(describe|commit|undo|restore)\b/,
  /\bgit\s+stash\s+(pop|apply)\b/,
];

const fg = (c: Color, s: string) =>
  `\x1b[38;2;${RGB[c][0]};${RGB[c][1]};${RGB[c][2]}m${s}\x1b[0m`;

interface Snapshot {
  v: number;
  sessionId?: string | null;
  cache?: { expiresAt?: number | null; ttl?: string | null } | null;
  limits?: {
    kind: string;
    windowMinutes?: number | null;
    usedPct: number;
    resetsAt?: number | null;
  }[];
  context?: { tokens?: number | null } | null;
  costUsd?: number | null;
}

interface PlanWindow {
  label: string;
  usedPercent: number;
  resetDescription?: string;
  resetAt?: string;
}

interface StatuslineCache {
  [provider: string]: {
    fetchedAt?: number;
    usage?: { windows?: PlanWindow[] };
  } | number | undefined;
}

/** A plan window for the bar cells: hours long, share used, reset in epoch seconds. */
interface Limit {
  hours: number;
  pct: number;
  resetsAt?: number;
}

/** One bar cell; `full` and `short` are the amounts shown at the first two fit levels. */
interface Cell {
  label: string;
  pct: number;
  hue: Color | "ramp";
  share: string;
  full: string;
  short: string;
}

/** Parses a JSON file again only when its mtime changes, since render runs on every keystroke. */
function jsonFile<T>(path: () => string | undefined) {
  let last: { path: string; mtime: number; value: T | undefined } | undefined;
  return (): T | undefined => {
    const p = path();
    if (!p) return undefined;
    let mtime: number;
    try {
      mtime = statSync(p).mtimeMs;
    } catch {
      return undefined;
    }
    if (last?.path !== p || last.mtime !== mtime) {
      let value: T | undefined;
      try {
        value = JSON.parse(readFileSync(p, "utf8")) as T;
      } catch {
        value = undefined;
      }
      last = { path: p, mtime, value };
    }
    return last.value;
  };
}

// The same contract the Claude Code status line reads.
const snapshotPath = () => {
  if (process.env.HMETER_SNAPSHOT) return process.env.HMETER_SNAPSHOT;
  const id = process.env.HC_TERMINAL_ID;
  if (!id) return undefined;
  const state = process.env.XDG_STATE_HOME || join(homedir(), ".local/state");
  return join(state, "herdr-meter/sessions", `${id}.json`);
};

const statuslinePath = () =>
  join(
    process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
    "pi-agent-extensions/statusline/cache.json",
  );

// The widget's token format, so both context numbers on the line read the same.
function fmtTokens(n: number): string {
  if (n < 1000) return `${n}`;
  if (n < 100_000) return `${(n / 1000).toFixed(1)}k`;
  if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
  return `${(n / 1_000_000).toFixed(1)}M`;
}

function span(s: number): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  if (s >= 86400) return `${Math.floor(s / 86400)}d${pad(Math.floor((s % 86400) / 3600))}h`;
  if (s >= 3600) return `${Math.floor(s / 3600)}h${pad(Math.floor((s % 3600) / 60))}m`;
  if (s > 120) return `${Math.floor(s / 60)}m`;
  return `${s}s`;
}

function bar(p: number, hue: Color | "ramp"): string {
  let lit = Math.floor((p * BAR_CELLS + 50) / 100);
  if (p > 0 && lit === 0) lit = 1;
  lit = Math.min(lit, BAR_CELLS);
  let out = "";
  for (let i = 0; i < BAR_CELLS; i++) {
    if (i >= lit) out += fg("SURF", "▱");
    else out += fg(hue === "ramp" ? RAMP[Math.floor((i * 5) / BAR_CELLS)] : hue, "▰");
  }
  return out;
}

function effortColor(level: string): Color {
  if (level === "low") return "OVL";
  if (level === "high") return "YEL";
  if (level === "xhigh" || level === "max") return "RED";
  return "SUB";
}

/** The current provider's windows from the statusline cache, when fetched recently. */
function planWindows(
  cache: StatuslineCache | undefined,
  provider: string | undefined,
): PlanWindow[] {
  if (!cache || !provider) return [];
  const entry = cache[provider === "openai-codex" ? "codex" : provider];
  if (typeof entry !== "object" || !entry.fetchedAt) return [];
  if (Date.now() - entry.fetchedAt > STATUSLINE_STALE_MS) return [];
  return entry.usage?.windows ?? [];
}

/** Windows named by label ("5h", "Week", "168h") as hours, for the bar cells. */
function planLimits(windows: PlanWindow[]): Limit[] {
  return windows.flatMap((w) => {
    const h = /^(\d+)h$/i.exec(w.label);
    const hours = w.label === "Week" || w.label === "7d" ? 168 : h ? Number(h[1]) : 0;
    if (!hours) return [];
    const reset = w.resetAt ? Date.parse(w.resetAt) : NaN;
    return [{
      hours,
      pct: w.usedPercent,
      resetsAt: Number.isNaN(reset) ? undefined : Math.floor(reset / 1000),
    }];
  });
}

export default function (pi: ExtensionAPI) {
  const readSnapshot = jsonFile<Snapshot>(snapshotPath);
  const readStatusline = jsonFile<StatuslineCache>(statuslinePath);
  let rerender: (() => void) | undefined;

  // Refresh VCS state ourselves rather than rely on the statusline extension's handlers.
  const vcsChanged = () => {
    invalidateVcs();
    setTimeout(() => rerender?.(), 100);
  };
  pi.on("tool_result", async (event) => {
    const input = event.input as { command?: unknown } | undefined;
    if (
      event.toolName === "write" || event.toolName === "edit" ||
      (event.toolName === "bash" && typeof input?.command === "string" &&
        VCS_CHANGE_PATTERNS.some((p) => p.test(input.command as string)))
    ) vcsChanged();
  });
  pi.on("user_bash", async (event) => {
    if (VCS_CHANGE_PATTERNS.some((p) => p.test(event.command))) vcsChanged();
  });

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setFooter((tui, theme, footerData) => {
      rerender = () => tui.requestRender();
      const unsub = footerData.onBranchChange(rerender);
      // VCS status is fetched in the background; draw again once it lands.
      setVcsUpdateCallback(rerender);
      // The TTL counts down between turns, when nothing else redraws.
      const timer = setInterval(rerender, TICK_MS);
      timer.unref();

      return {
        dispose() {
          unsub();
          clearInterval(timer);
          setVcsUpdateCallback(null);
          rerender = undefined;
        },
        invalidate() {},
        render(width: number): string[] {
          const now = Math.floor(Date.now() / 1000);
          let snap = readSnapshot();
          // A terminal keeps the snapshot of the session it ran before this one.
          if (
            snap?.v !== 1 ||
            (snap.sessionId && snap.sessionId !== ctx.sessionManager.getSessionId())
          ) snap = undefined;
          const expiresAt = snap?.cache?.expiresAt;
          const windows = planWindows(readStatusline(), ctx.model?.provider);
          const usage = ctx.getContextUsage();
          const tokens = usage?.tokens ?? snap?.context?.tokens ?? null;
          const ctxWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
          const ctxPct = tokens !== null && ctxWindow > 0 ? (tokens / ctxWindow) * 100 : 0;

          // ---- the widget's segments, in its colors and formats ----
          const text: string[] = [];
          // Segments the cells repeat; the first to go when the line is narrow.
          const repeated = new Set<string>();
          if (ctx.model) {
            const name = (ctx.model.name || ctx.model.id).replace(/^Claude /, "");
            const thinking = pi.getThinkingLevel();
            text.push(
              theme.fg("text", name) +
                (thinking === "off"
                  ? ""
                  : theme.fg("dim", " · ") + fg(effortColor(thinking), thinking)),
            );
          }
          if (windows.length) {
            const usage = windows.map((w) => {
              const pct = Math.round(Math.max(0, Math.min(100, w.usedPercent)));
              const left = 100 - pct;
              const color = left <= 10 ? "error" : left <= 30 ? "warning" : "dim";
              const label = w.label.startsWith("Extra")
                ? "Ex"
                : w.label === "Week" || w.label === "7d"
                ? "W"
                : w.label === "Day"
                ? "D"
                : w.label;
              const reset = pct > 50 && w.resetDescription ? ` ${w.resetDescription}` : "";
              return theme.fg(color, `${label}:${pct}%${reset}`);
            }).join(theme.fg("dim", "│"));
            text.push(usage);
            repeated.add(usage);
          }
          if (tokens !== null && ctxWindow > 0) {
            const color = ctxPct > 90 ? "error" : ctxPct > 70 ? "warning" : "dim";
            const context = theme.fg(color, `${fmtTokens(tokens)}/${fmtTokens(ctxWindow)}`);
            text.push(context);
            repeated.add(context);
          }
          text.push(theme.fg("accent", basename(ctx.cwd) || ctx.cwd));
          const vcs = getVcsStatus(ctx.cwd);
          const branch = footerData.getGitBranch();
          // In a plain git repo the VCS segment already leads with the branch.
          if (branch && !(vcs?.kind === "git" && vcs.head === branch)) {
            text.push(theme.fg("success", branch));
          }
          if (vcs?.head) {
            const dirty = vcs.modified > 0 || vcs.added > 0 || vcs.removed > 0;
            let s = theme.fg(
              dirty ? "warning" : "success",
              vcs.kind === "jj" ? `◆ ${vcs.head}` : vcs.head,
            );
            if (vcs.modified > 0) s += " " + theme.fg("warning", `~${vcs.modified}`);
            if (vcs.added > 0) s += " " + theme.fg("success", `+${vcs.added}`);
            if (vcs.removed > 0) s += " " + theme.fg("error", `-${vcs.removed}`);
            text.push(s);
          }
          // hmeter's "cache 51m" status is redundant once the TTL cell shows.
          const statuses = [...footerData.getExtensionStatuses()]
            .filter(([key, value]) => value && !(key === "hmeter" && expiresAt != null))
            .map(([, value]) => value);
          if (statuses.length) text.push(statuses.join(theme.fg("dim", " ")));
          const arrow = theme.fg("dim", " ❯ ");
          const textLine = ` ${text.join(arrow)} `;

          // ---- bar cells ----
          const cells: Cell[] = [];
          if (tokens !== null && ctxWindow > 0) {
            const p = Math.round(ctxPct);
            cells.push({
              label: "CTX",
              pct: p,
              hue: "ramp",
              share: `${p}%`,
              full: fmtTokens(tokens) + fg("OVL", `/${fmtTokens(ctxWindow)}`),
              short: fmtTokens(tokens),
            });
          }

          // Warmth runs peach -> yellow -> blue as the TTL drains, like the agents list rings.
          if (expiresAt != null) {
            const ttl = snap?.cache?.ttl ?? "5m";
            const left = expiresAt - now;
            if (left > 0) {
              const frac = Math.floor((left * 100) / (ttl === "1h" ? 3600 : 300));
              const wc: Color = frac > 50 ? "PEACH" : frac > 15 ? "YEL" : "BLUE";
              const blink = left <= 120 ? "\x1b[5m" : "";
              cells.push({
                label: "TTL",
                pct: frac,
                hue: wc,
                share: fg(wc, `${blink}${frac}%`),
                full: fg(wc, `${blink}${span(left)}`) + fg("OVL", `/${ttl}`),
                short: fg(wc, `${blink}${span(left)}`),
              });
            } else {
              cells.push({
                label: "TTL",
                pct: 0,
                hue: "SURF",
                share: fg("OVL", "cold"),
                full: "",
                short: "",
              });
            }
          }

          const limits: Limit[] = snap?.limits?.length
            ? snap.limits.map((l) => ({
              hours: (l.windowMinutes ?? (l.kind === "seven_day" ? 10080 : 300)) / 60,
              // A window past its reset has started over.
              pct: l.resetsAt != null && l.resetsAt <= now ? 0 : l.usedPct,
              resetsAt: l.resetsAt ?? undefined,
            }))
            : planLimits(windows);
          for (const l of limits.sort((a, b) => a.hours - b.hours)) {
            const p = Math.round(l.pct);
            cells.push({
              label: l.hours >= 144 ? "WK" : `${Math.round(l.hours)}H`,
              pct: p,
              hue: "ramp",
              share: `${p}%`,
              full: l.resetsAt != null && l.resetsAt > now
                ? `${fg("OVL", "↻")} ${span(l.resetsAt - now)}`
                : "",
              short: "",
            });
          }

          let cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              cost += (e.message as AssistantMessage).usage.cost.total;
            }
          }
          cost = Math.max(cost, snap?.costUsd ?? 0);
          const price = cost > 0 ? fg("SUB", `$${cost.toFixed(2)}`) : "";

          // Fit levels: full cells, then without timers and denominators, then without bars.
          const sep = theme.fg("dim", " │ ");
          const cellLine = (level: number) =>
            [
              ...cells.map((c) => {
                const amount = level === 0 ? c.full : level === 1 ? c.short : "";
                return [
                  fg("OVL", c.label),
                  level < 2 ? bar(c.pct, c.hue) : "",
                  c.share,
                  amount,
                ].filter(Boolean).join(" ");
              }),
              price,
            ].filter(Boolean).join(sep);

          let tail = cellLine(0);
          // One line: text at the left, cells flush right, at least one space between.
          const left = textLine.trimEnd();
          const right = tail ? `${tail} ` : "";
          const gap = width - visibleWidth(left) - visibleWidth(right);
          if (gap >= 1) return [left + " ".repeat(gap) + right];
          // Too wide: the cells wrap to their own line before they lose detail.
          for (let level = 1; level <= 2 && visibleWidth(` ${tail}`) > width; level++) {
            tail = cellLine(level);
          }
          // Too narrow for the text too: drop what the cells repeat, then wrap at segment
          // boundaries; only a segment wider than the line by itself is cut.
          const lines: string[] = [];
          let line = "";
          const kept = visibleWidth(textLine) <= width
            ? text
            : text.filter((s) => !repeated.has(s));
          for (const seg of kept) {
            const next = line ? line + arrow + seg : ` ${seg}`;
            if (!line || visibleWidth(next) <= width) line = next;
            else {
              lines.push(line);
              line = ` ${seg}`;
            }
          }
          if (line) lines.push(line);
          for (let i = 0; i < lines.length; i++) {
            lines[i] = truncateToWidth(lines[i], width, theme.fg("dim", "…"));
          }
          if (tail) lines.push(truncateToWidth(` ${tail}`, width));
          return lines;
        },
      };
    });
  });
}
