import type { Message, MessageStore, SearchStatus } from "./model";
import { scrollToMessage } from "./scroll";

// Renderer → Swift. Actions identify messages by ID only; Swift
// resolves text, paths, and commands from its canonical model.
export type WebAction =
  | { type: "ready" }
  | { type: "reply"; messageId: string }
  | { type: "copy"; messageId: string }
  | { type: "retry"; messageId: string }
  | { type: "cancel"; messageId: string }
  | { type: "open-link"; url: string }
  | { type: "open-image"; messageId: string }
  | { type: "search-status"; current: number; total: number };

// Swift → renderer, invoked through callAsyncJavaScript.
export interface NativeAPI {
  replaceMessages(messages: Message[]): void;
  upsertMessage(message: Message): void;
  patchMessage(id: string, patch: Partial<Message>): void;
  removeMessage(id: string): void;
  setSearch(query: string): void;
  stepSearch(direction: -1 | 1): void;
  closeSearch(): void;
}

interface BridgeHandler {
  postMessage(action: WebAction): void;
}

declare global {
  interface Window {
    webkit?: { messageHandlers?: { bridge?: BridgeHandler } };
    nostrChat?: NativeAPI;
  }
}

export function postAction(action: WebAction): void {
  window.webkit?.messageHandlers?.bridge?.postMessage(action);
}

export interface UpsertContext {
  isNew: boolean;
  wasNearBottom: boolean;
}

// DOM concerns (scroll measurement, unseen indication) stay with the
// app shell; the bridge only orders them around store mutations.
export interface RendererHooks {
  measureNearBottom?: () => boolean;
  onUpsert?: (message: Message, context: UpsertContext) => void;
  onReplace?: () => void;
}

/// Exposes the native entry points and announces readiness. Swift
/// answers every `ready` with a full snapshot, so installing the API
/// is all a fresh or recovered page needs to converge.
export function installNativeAPI(store: MessageStore, hooks?: RendererHooks): NativeAPI {
  function reportSearch(status: SearchStatus, scroll = true): void {
    postAction({ type: "search-status", current: status.current, total: status.total });
    if (scroll && status.currentId) scrollToMessage(status.currentId);
  }

  function refreshSearch(): void {
    const status = store.activeSearchStatus();
    if (status) reportSearch(status, false);
  }

  const api: NativeAPI = {
    replaceMessages: (messages) => {
      store.replace(messages);
      hooks?.onReplace?.();
      refreshSearch();
    },
    upsertMessage: (message) => {
      // Measure before the DOM grows: whether the reader was at the
      // bottom decides sticking vs. the unseen indicator.
      const isNew = !store.messages.some((existing) => existing.id === message.id);
      const wasNearBottom = hooks?.measureNearBottom?.() ?? true;
      store.upsert(message);
      hooks?.onUpsert?.(message, { isNew, wasNearBottom });
      refreshSearch();
    },
    patchMessage: (id, patch) => store.patch(id, patch),
    removeMessage: (id) => {
      store.remove(id);
      refreshSearch();
    },
    setSearch: (query) => reportSearch(store.setSearch(query)),
    stepSearch: (direction) => reportSearch(store.stepSearch(direction)),
    closeSearch: () => store.closeSearch(),
  };
  window.nostrChat = api;
  postAction({ type: "ready" });
  return api;
}
