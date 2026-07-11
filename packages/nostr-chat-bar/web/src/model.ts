import { reactive } from "vue";

// Mirror of the Swift Row payload (WebBridge.swift). Swift owns the
// canonical collection; this store is a disposable DOM-side replica
// that any full snapshot must be able to rebuild.
export interface Message {
  id: string;
  mine: boolean;
  text: string;
  timestamp: number;
  ack: string;
  hasImage: boolean;
  replyTo: string;
  state: "pending" | "sent" | "";
  tries: number;
}

export interface ConnectionStatus {
  streaming: boolean;
  relaysUp: number;
  relaysTotal: number;
}

export interface MessageStore {
  readonly messages: Message[];
  readonly connection: ConnectionStatus;
  replace(messages: Message[]): void;
  upsert(message: Message): void;
  patch(id: string, patch: Partial<Message>): void;
  remove(id: string): void;
  setConnection(status: ConnectionStatus): void;
  replyPreview(replyTo: string): string | null;
}

const REPLY_UNAVAILABLE = "Original message unavailable";

export function createMessageStore(): MessageStore {
  const state = reactive({
    messages: [] as Message[],
    connection: { streaming: false, relaysUp: 0, relaysTotal: 0 } as ConnectionStatus,
  });

  function indexOf(id: string): number {
    return state.messages.findIndex((message) => message.id === id);
  }

  return {
    get messages() {
      return state.messages;
    },
    get connection() {
      return state.connection;
    },

    replace(messages) {
      state.messages = [...messages].sort((a, b) => a.timestamp - b.timestamp);
    },

    // Same semantics as the Swift insert: dedupe by ID, insert-sort by
    // timestamp so replay and live messages interleave.
    upsert(message) {
      const existing = indexOf(message.id);
      if (existing >= 0) {
        state.messages[existing] = { ...state.messages[existing], ...message };
        return;
      }
      let at = state.messages.length;
      while (at > 0 && state.messages[at - 1].timestamp > message.timestamp) at -= 1;
      state.messages.splice(at, 0, message);
    },

    patch(id, patch) {
      const at = indexOf(id);
      if (at < 0) return;
      // Never let a metadata patch rewrite identity or body.
      const { id: _id, text: _text, timestamp: _ts, ...rest } = patch;
      state.messages[at] = { ...state.messages[at], ...rest };
    },

    remove(id) {
      const at = indexOf(id);
      if (at >= 0) state.messages.splice(at, 1);
    },

    setConnection(status) {
      state.connection = status;
    },

    // The reply target may have aged out of maxHistory; the marker must
    // survive with a stable placeholder instead of disappearing.
    replyPreview(replyTo) {
      if (!replyTo) return null;
      const target = state.messages.find((message) => message.id === replyTo);
      if (!target) return REPLY_UNAVAILABLE;
      const flat = target.text.replace(/\n/g, " ");
      return flat.length > 80 ? `${flat.slice(0, 79)}…` : flat;
    },
  };
}
