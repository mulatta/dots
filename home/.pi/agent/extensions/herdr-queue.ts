/**
 * Reports each response's prompt-cache state to `hq ingest pi` and shows the
 * time left in the footer. Pi knows the model's cache lifetime; hq owns the rest.
 */

import { spawn } from "node:child_process";
import type {
  ExtensionAPI,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";

const HQ = "hq";

// The footer shows whole minutes, so a coarser tick would lag by up to that much.
const TICK_MS = 30_000;

export default function (pi: ExtensionAPI) {
  let usage: unknown;
  let costUsd = 0;
  let expiresAt: number | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  // Pi invalidates a context when its session ends; timers and child exits outlive it.
  let live: ExtensionContext | undefined;

  const show = () => {
    const ctx = live;
    if (!ctx?.hasUI) return;
    if (expiresAt === undefined) return ctx.ui.setStatus("hq", undefined);
    const left = expiresAt - Date.now();
    ctx.ui.setStatus(
      "hq",
      left > 0 ? `cache ${Math.ceil(left / 60_000)}m` : "cache cold",
    );
  };

  const report = (ctx: ExtensionContext) => {
    if (usage === undefined) return;
    // Mirrors pi's own choice of retention tier for the request it just sent.
    const tier = process.env.PI_CACHE_RETENTION === "long" ? "long" : "short";
    const child = spawn(HQ, ["ingest", "pi"], {
      stdio: ["pipe", "pipe", "ignore"],
    });
    let out = "";
    child.stdout.on("data", (chunk) => (out += chunk));
    // hq is optional: without it pi works as before and the footer stays empty.
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.on("close", (code) => {
      if (code !== 0) return;
      const secs = Number.parseInt(out, 10);
      expiresAt = Number.isNaN(secs) ? undefined : secs * 1000;
      show();
    });
    child.stdin.end(
      JSON.stringify({
        sessionId: ctx.sessionManager.getSessionId(),
        cwd: ctx.cwd,
        model: ctx.model?.id,
        provider: ctx.model?.provider,
        usage,
        cacheTtlSecs: ctx.model?.promptCache?.[tier],
        contextTokens: ctx.getContextUsage()?.tokens,
        contextWindow: ctx.model?.contextWindow,
        costUsd,
      }),
    );
  };

  pi.on("session_start", (_event, ctx) => {
    live = ctx;
    usage = undefined;
    costUsd = 0;
    expiresAt = undefined;
    timer = setInterval(show, TICK_MS);
    timer.unref();
  });

  pi.on("session_shutdown", () => {
    clearInterval(timer);
    live = undefined;
  });

  pi.on("turn_end", (event, ctx) => {
    const message = event.message;
    if (
      message.role !== "assistant" ||
      message.stopReason === "aborted" ||
      message.stopReason === "error"
    )
      return;
    usage = message.usage;
    costUsd += message.usage.cost.total;
    report(ctx);
  });

  // An idle refresh extends the cache without a turn.
  pi.on("cache_warming_decision", (event, ctx) => {
    if (event.action === "warm") report(ctx);
  });
}
