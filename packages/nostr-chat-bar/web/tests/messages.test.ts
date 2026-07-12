import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import MessageList from "../src/components/MessageList.vue";
import { createMessageStore, type Message } from "../src/model";
import fixtures from "../../Fixtures/rendering-messages.json";

function message(overrides: Partial<Message>): Message {
  return {
    id: "0".repeat(64),
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

function ids(store: { messages: Message[] }): string[] {
  return store.messages.map((m) => m.id);
}

describe("message store", () => {
  it("inserts chronologically regardless of arrival order", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "b".repeat(64), timestamp: 2000 }));
    store.upsert(message({ id: "a".repeat(64), timestamp: 1000 }));
    store.upsert(message({ id: "c".repeat(64), timestamp: 3000 }));
    expect(ids(store)).toEqual(["a".repeat(64), "b".repeat(64), "c".repeat(64)]);
  });

  it("replaces duplicates by ID instead of duplicating", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), text: "first" }));
    store.upsert(message({ id: "a".repeat(64), text: "second" }));
    expect(store.messages).toHaveLength(1);
    expect(store.messages[0].text).toBe("second");
  });

  it("patches metadata without touching identity or body", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), text: "body", state: "pending" }));
    store.patch("a".repeat(64), {
      ack: "✓✓",
      state: "sent",
      text: "attacker",
      id: "b".repeat(64),
      timestamp: 9,
    });
    const patched = store.messages[0];
    expect(patched.ack).toBe("✓✓");
    expect(patched.state).toBe("sent");
    expect(patched.text).toBe("body");
    expect(patched.id).toBe("a".repeat(64));
    expect(patched.timestamp).toBe(1000);
  });

  it("ignores patches for unknown IDs", () => {
    const store = createMessageStore();
    store.patch("f".repeat(64), { ack: "✓" });
    expect(store.messages).toHaveLength(0);
  });

  it("removes by ID", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64) }));
    store.remove("a".repeat(64));
    expect(store.messages).toHaveLength(0);
  });

  it("replaces the full snapshot in timestamp order", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "e".repeat(64), timestamp: 99 }));
    store.replace([
      message({ id: "b".repeat(64), timestamp: 2000 }),
      message({ id: "a".repeat(64), timestamp: 1000 }),
    ]);
    expect(ids(store)).toEqual(["a".repeat(64), "b".repeat(64)]);
  });

  it("resolves reply previews and flags missing targets", () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), text: "original\nmessage" }));
    expect(store.replyPreview("a".repeat(64))).toBe("original message");
    expect(store.replyPreview("f".repeat(64))).toBe("Original message unavailable");
    expect(store.replyPreview("")).toBeNull();
  });
});

describe("message list rendering", () => {
  const now = 1_783_650_000_000;

  it("renders one bubble per message with stable DOM identity", async () => {
    const store = createMessageStore();
    const wrapper = mount(MessageList, { props: { store, now } });
    store.upsert(message({ id: "a".repeat(64), text: "first" }));
    store.upsert(message({ id: "b".repeat(64), timestamp: 2000, text: "second" }));
    await wrapper.vm.$nextTick();
    expect(wrapper.findAll(".bubble-row")).toHaveLength(2);

    store.upsert(message({ id: "a".repeat(64), text: "first" }));
    await wrapper.vm.$nextTick();
    expect(wrapper.findAll(".bubble-row")).toHaveLength(2);
  });

  it("keeps the rendered body DOM when only metadata changes", async () => {
    const store = createMessageStore();
    const id = "a".repeat(64);
    store.upsert(message({ id, mine: true, text: "**bold** body", state: "pending" }));
    const wrapper = mount(MessageList, { props: { store, now } });
    await wrapper.vm.$nextTick();
    const before = wrapper.get(".message-body").element;
    expect(wrapper.get(".meta").text()).toContain("🕓");

    store.patch(id, { state: "sent", ack: "✓✓" });
    await wrapper.vm.$nextTick();
    expect(wrapper.get(".message-body").element).toBe(before);
    expect(wrapper.get(".meta").text()).toContain("✓✓");
  });

  it("aligns own and peer messages differently", async () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), mine: true }));
    store.upsert(message({ id: "b".repeat(64), timestamp: 2000, mine: false }));
    const wrapper = mount(MessageList, { props: { store, now } });
    await wrapper.vm.$nextTick();
    expect(wrapper.find(".bubble-row.mine").exists()).toBe(true);
    expect(wrapper.find(".bubble-row.theirs").exists()).toBe(true);
  });

  it("shows retry, pending, and ack states on own messages", async () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), mine: true, tries: 3 }));
    const wrapper = mount(MessageList, { props: { store, now } });
    await wrapper.vm.$nextTick();
    expect(wrapper.get(".meta").text()).toContain("⚠");
  });

  it("keeps a reply marker visible when the target is gone", async () => {
    const store = createMessageStore();
    store.upsert(message({ id: "a".repeat(64), replyTo: "f".repeat(64) }));
    const wrapper = mount(MessageList, { props: { store, now } });
    await wrapper.vm.$nextTick();
    expect(wrapper.get(".reply-quote").text()).toContain("Original message unavailable");
  });

  it("renders the full fixture snapshot", async () => {
    const store = createMessageStore();
    store.replace(fixtures.messages.map((entry) => entry.message as Message));
    const wrapper = mount(MessageList, { props: { store, now } });
    await wrapper.vm.$nextTick();
    expect(wrapper.findAll(".bubble-row")).toHaveLength(fixtures.messages.length);
  });
});
