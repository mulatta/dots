import { nextTick } from "vue";

// The WebView document is the scroll container; "near bottom" uses a
// distance threshold, never exact equality.
const BOTTOM_THRESHOLD = 48;

export function isNearBottom(): boolean {
  const root = document.documentElement;
  return window.innerHeight + window.scrollY >= root.scrollHeight - BOTTOM_THRESHOLD;
}

export async function scrollToBottom(): Promise<void> {
  await nextTick();
  window.scrollTo?.(0, document.documentElement.scrollHeight);
}

export function scrollToMessage(id: string): void {
  document
    .querySelector(`[data-message-id="${id}"]`)
    ?.scrollIntoView?.({ block: "center" });
}

export type InsertBehavior = "stick" | "indicate";

/// Scroll rules for a newly inserted message: own sends always stick
/// to the bottom; incoming messages stick only when the reader was
/// already near the bottom, otherwise they surface as an unseen-count
/// indicator without moving the view.
export function insertBehavior(mine: boolean, wasNearBottom: boolean): InsertBehavior {
  return mine || wasNearBottom ? "stick" : "indicate";
}
