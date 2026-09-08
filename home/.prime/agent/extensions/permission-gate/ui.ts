import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  EVENTS,
  type GateResult,
} from "./types.ts";

export type MatchDetail = { label: string; evidence?: string };

export async function showReviewPrompt(
  ctx: ExtensionContext,
  command: string,
  labels: string,
  events?: {
    on: (name: string, handler: (payload: unknown) => void) => () => void;
    emit: (name: string, payload?: unknown) => void;
  },
  matches: MatchDetail[] = [],
): Promise<GateResult> {
  const controller = new AbortController();
  let removeRemoteListener: (() => void) | undefined;

  const remoteResult = new Promise<GateResult>((resolve) => {
    removeRemoteListener = events?.on(EVENTS.respond, (payload) => {
      const response = payload as { allow?: boolean; reason?: string } | undefined;
      if (response?.allow === true) {
        resolve({ allow: true });
      } else {
        resolve({
          allow: false,
          reason: response?.reason ?? `Blocked remotely (${labels})`,
        });
      }
    });
  });

  const evidence = matches
    .map((match) =>
      match.evidence ? `${match.label}: ${match.evidence}` : match.label,
    )
    .join("\n");
  const message = [
    `Matched: ${labels}`,
    evidence && `Evidence:\n${evidence}`,
    `Command:\n${command}`,
  ]
    .filter(Boolean)
    .join("\n\n");

  const uiResult = (async (): Promise<GateResult> => {
    const allow = await ctx.ui.confirm("Allow dangerous command?", message, {
      signal: controller.signal,
    });
    if (allow) return { allow: true };
    const reason = await ctx.ui.input(
      "Block reason",
      "Optional reason sent to model",
      { signal: controller.signal },
    );
    return {
      allow: false,
      reason: reason || `Dangerous command blocked (${labels})`,
    };
  })();

  events?.emit(EVENTS.waiting, { command, labels });
  const result = events ? await Promise.race([uiResult, remoteResult]) : await uiResult;
  controller.abort();
  removeRemoteListener?.();
  return result;
}
