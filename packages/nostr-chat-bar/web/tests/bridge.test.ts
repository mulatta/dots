import { afterEach, describe, expect, it } from "vitest";
import { installNativeAPI, postAction, type WebAction } from "../src/bridge";
import { createMessageStore, type Message } from "../src/model";

function captureActions(): WebAction[] {
  const actions: WebAction[] = [];
  window.webkit = {
    messageHandlers: {
      bridge: { postMessage: (action: WebAction) => actions.push(action) },
    },
  };
  return actions;
}

function message(overrides: Partial<Message>): Message {
  return {
    id: "a".repeat(64),
    mine: false,
    text: "hello",
    timestamp: 1000,
    ack: "",
    hasImage: false,
    replyTo: "",
    state: "",
    tries: 0,
    ...overrides,
  };
}

afterEach(() => {
  delete window.webkit;
  delete window.nostrChat;
});

describe("renderer → native actions", () => {
  it("posts exact action shapes with no extra fields", () => {
    const actions = captureActions();
    postAction({ type: "reply", messageId: "a".repeat(64) });
    postAction({ type: "open-link", url: "https://example.com" });
    postAction({ type: "search-status", current: 1, total: 3 });
    expect(actions).toEqual([
      { type: "reply", messageId: "a".repeat(64) },
      { type: "open-link", url: "https://example.com" },
      { type: "search-status", current: 1, total: 3 },
    ]);
    for (const action of actions) {
      expect(Object.keys(action).every((k) => ["type", "messageId", "url", "current", "total"].includes(k))).toBe(true);
    }
  });

  it("does nothing without a WebKit host", () => {
    expect(() => postAction({ type: "ready" })).not.toThrow();
  });
});

describe("native API installation", () => {
  it("registers window.nostrChat and announces readiness once", () => {
    const actions = captureActions();
    installNativeAPI(createMessageStore());
    expect(window.nostrChat).toBeDefined();
    expect(actions).toEqual([{ type: "ready" }]);
  });

  it("routes native calls into the store", () => {
    captureActions();
    const store = createMessageStore();
    const api = installNativeAPI(store);

    api.replaceMessages([message({ id: "b".repeat(64), timestamp: 2 }), message({ timestamp: 1 })]);
    expect(store.messages.map((m) => m.timestamp)).toEqual([1, 2]);

    api.upsertMessage(message({ id: "c".repeat(64), timestamp: 3 }));
    expect(store.messages).toHaveLength(3);

    api.patchMessage("c".repeat(64), { ack: "✓" });
    expect(store.messages[2].ack).toBe("✓");

    api.removeMessage("c".repeat(64));
    expect(store.messages).toHaveLength(2);
  });

  it("converges to any snapshot after simulated reload", () => {
    captureActions();
    const store = createMessageStore();
    const api = installNativeAPI(store);
    api.upsertMessage(message({}));
    // A reload reinstalls the API over fresh state; the snapshot Swift
    // sends after `ready` must fully describe the list.
    const reloadedStore = createMessageStore();
    const reloadedApi = installNativeAPI(reloadedStore);
    reloadedApi.replaceMessages([message({}), message({ id: "b".repeat(64), timestamp: 5 })]);
    expect(reloadedStore.messages).toHaveLength(2);
  });
});
