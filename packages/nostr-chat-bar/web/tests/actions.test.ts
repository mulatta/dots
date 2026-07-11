import { afterEach, describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import MessageBubble from "../src/components/MessageBubble.vue";
import type { WebAction } from "../src/bridge";
import type { Message } from "../src/model";

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

afterEach(() => {
  delete window.webkit;
});

describe("bubble actions", () => {
  it("posts reply and copy with the message ID only", async () => {
    const actions = captureActions();
    const wrapper = bubble({});
    await wrapper.get(".action.reply").trigger("click");
    await wrapper.get(".action.copy").trigger("click");
    expect(actions).toEqual([
      { type: "reply", messageId: "a".repeat(64) },
      { type: "copy", messageId: "a".repeat(64) },
    ]);
  });

  it("offers retry and cancel only for undelivered own messages", async () => {
    expect(bubble({ mine: true, state: "pending" }).find(".action.retry").exists()).toBe(true);
    expect(bubble({ mine: true, tries: 2 }).find(".action.cancel").exists()).toBe(true);
    expect(bubble({ mine: true, state: "sent" }).find(".action.retry").exists()).toBe(false);
    expect(bubble({ mine: false, state: "pending" }).find(".action.retry").exists()).toBe(false);
  });

  it("posts retry and cancel with the message ID only", async () => {
    const actions = captureActions();
    const wrapper = bubble({ mine: true, state: "pending", tries: 1 });
    await wrapper.get(".action.retry").trigger("click");
    await wrapper.get(".action.cancel").trigger("click");
    expect(actions).toEqual([
      { type: "retry", messageId: "a".repeat(64) },
      { type: "cancel", messageId: "a".repeat(64) },
    ]);
  });

  it("turns link clicks into open-link actions instead of navigation", async () => {
    const actions = captureActions();
    const wrapper = bubble({ text: "[site](https://example.com)" });
    await wrapper.get(".message-body a").trigger("click");
    expect(actions).toEqual([{ type: "open-link", url: "https://example.com" }]);
  });
});
