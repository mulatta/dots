import { afterEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import MessageBubble from "../src/components/MessageBubble.vue";
import { installNativeAPI, type WebAction } from "../src/bridge";
import { createMessageStore, type Message } from "../src/model";
import { insertBehavior, scrollToMessage } from "../src/scroll";

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

describe("search", () => {
  function populated() {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), timestamp: 1, text: "alpha match" }));
    store.upsert(message({ id: "b".repeat(64), timestamp: 2, text: "unrelated" }));
    store.upsert(message({ id: "c".repeat(64), timestamp: 3, text: "MATCH again" }));
    return store;
  }

  it("finds case-insensitive hits newest-first", () => {
    const store = populated();
    const status = store.setSearch("match");
    expect(status).toEqual({ current: 1, total: 2, currentId: "c".repeat(64) });
    expect(store.isSearchHit("a".repeat(64))).toBe(true);
    expect(store.isSearchHit("b".repeat(64))).toBe(false);
    expect(store.isSearchCurrent("c".repeat(64))).toBe(true);
  });

  it("steps forward and backward with wraparound", () => {
    const store = populated();
    store.setSearch("match");
    expect(store.stepSearch(1).currentId).toBe("a".repeat(64));
    expect(store.stepSearch(1).currentId).toBe("c".repeat(64));
    expect(store.stepSearch(-1).currentId).toBe("a".repeat(64));
  });

  it("reports empty results and clears on close", () => {
    const store = populated();
    expect(store.setSearch("absent")).toEqual({ current: 0, total: 0, currentId: null });
    store.setSearch("match");
    store.closeSearch();
    expect(store.isSearchHit("a".repeat(64))).toBe(false);
  });

  it("reports search status over the bridge", () => {
    const actions = captureActions();
    const store = populated();
    const api = installNativeAPI(store);
    api.setSearch("match");
    api.stepSearch(1);
    expect(actions).toEqual([
      { type: "ready" },
      { type: "search-status", current: 1, total: 2 },
      { type: "search-status", current: 2, total: 2 },
    ]);
  });

  it("refreshes active search counts when messages change", () => {
    const actions = captureActions();
    const store = populated();
    const api = installNativeAPI(store);
    api.setSearch("match");
    actions.length = 0;

    const added = "d".repeat(64);
    api.upsertMessage(message({ id: added, timestamp: 4, text: "new match" }));
    api.removeMessage(added);

    expect(actions).toEqual([
      { type: "search-status", current: 1, total: 3 },
      { type: "search-status", current: 1, total: 2 },
    ]);
  });

  it("scrolls to message IDs without treating them as selectors", () => {
    const id = 'hostile"] [data-message-id="other';
    const target = document.createElement("article");
    target.dataset.messageId = id;
    target.scrollIntoView = vi.fn();
    document.body.appendChild(target);

    expect(() => scrollToMessage(id)).not.toThrow();
    expect(target.scrollIntoView).toHaveBeenCalledWith({ block: "center" });
  });
});

describe("scroll and unseen transitions", () => {
  it("own messages always stick to the bottom", () => {
    expect(insertBehavior(true, false)).toBe("stick");
    expect(insertBehavior(true, true)).toBe("stick");
  });

  it("incoming messages stick only near the bottom", () => {
    expect(insertBehavior(false, true)).toBe("stick");
    expect(insertBehavior(false, false)).toBe("indicate");
  });

  it("passes pre-mutation bottom state and novelty to hooks", () => {
    captureActions();
    const store = createMessageStore();
    const seen: Array<{ id: string; isNew: boolean; wasNearBottom: boolean }> = [];
    const api = installNativeAPI(store, {
      measureNearBottom: () => false,
      onUpsert: (m, context) => seen.push({ id: m.id, ...context }),
    });
    api.upsertMessage(message({}));
    api.upsertMessage(message({ ack: "✓" }));
    expect(seen).toEqual([
      { id: "a".repeat(64), isNew: true, wasNearBottom: false },
      { id: "a".repeat(64), isNew: false, wasNearBottom: false },
    ]);
  });
});

describe("attachments", () => {
  function bubble(overrides: Partial<Message>) {
    return mount(MessageBubble, {
      props: {
        message: message(overrides),
        replyPreview: null,
        now: 1_783_650_000_000,
        searchHit: false,
        searchCurrent: false,
      },
    });
  }

  it("derives the image URL from the message ID only", () => {
    const wrapper = bubble({ hasImage: true });
    expect(wrapper.get(".attachment img").attributes("src")).toBe(
      `nostr-chat-media://message/${"a".repeat(64)}`,
    );
  });

  it("posts open-image with the message ID on click", async () => {
    const actions = captureActions();
    const wrapper = bubble({ hasImage: true });
    await wrapper.get(".attachment img").trigger("click");
    expect(actions).toEqual([{ type: "open-image", messageId: "a".repeat(64) }]);
  });

  it("shows a stable unavailable state when loading fails", async () => {
    const wrapper = bubble({ hasImage: true });
    await wrapper.get(".attachment img").trigger("error");
    expect(wrapper.find(".attachment img").exists()).toBe(false);
    expect(wrapper.get(".attachment-missing").text()).toBe("attachment unavailable");
  });

  it("retries image loading when an attachment becomes available again", async () => {
    const wrapper = bubble({ hasImage: true });
    await wrapper.get(".attachment img").trigger("error");
    await wrapper.setProps({ message: message({ hasImage: false }) });
    await wrapper.setProps({ message: message({ hasImage: true }) });
    expect(wrapper.find(".attachment img").exists()).toBe(true);
  });

  it("renders no attachment markup without an image", () => {
    expect(bubble({}).find(".attachment").exists()).toBe(false);
  });
});
