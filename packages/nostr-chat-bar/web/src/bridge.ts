import type { ConnectionStatus, Message, MessageStore } from "./model";

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
  setConnection(status: ConnectionStatus): void;
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

/// Exposes the native entry points and announces readiness. Swift
/// answers every `ready` with a full snapshot, so installing the API
/// is all a fresh or recovered page needs to converge.
export function installNativeAPI(store: MessageStore): NativeAPI {
  const api: NativeAPI = {
    replaceMessages: (messages) => store.replace(messages),
    upsertMessage: (message) => store.upsert(message),
    patchMessage: (id, patch) => store.patch(id, patch),
    removeMessage: (id) => store.remove(id),
    setConnection: (status) => store.setConnection(status),
    // Search lands with the renderer-owned hit state; the entry points
    // exist so the Swift call surface is stable from the start.
    setSearch: () => {},
    stepSearch: () => {},
    closeSearch: () => {},
  };
  window.nostrChat = api;
  postAction({ type: "ready" });
  return api;
}
