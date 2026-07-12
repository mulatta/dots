import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import MessageBubble from "../src/components/MessageBubble.vue";
import type { Message } from "../src/model";

function message(overrides: Partial<Message>): Message {
  return {
    id: "a".repeat(64),
    mine: true,
    text: "hello",
    timestamp: 1000,
    ack: "",
    hasImage: false,
    replyTo: "",
    state: "sent",
    tries: 0,
    ...overrides,
  };
}

function bubble(overrides: Partial<Message>) {
  return mount(MessageBubble, {
    props: {
      message: message(overrides),
      replyPreview: overrides.replyTo ? "quoted" : null,
      now: 1_783_650_000_000,
      searchHit: false,
      searchCurrent: false,
    },
  });
}

function mark(overrides: Partial<Message>): string {
  const wrapper = bubble(overrides);
  const delivery = wrapper.find(".delivery");
  return delivery.exists() ? delivery.text() : "";
}

// Ladder mirrors the upstream QML bubble: ⚠ → 🕓 → ✓ → ✓✓/reaction.
describe("delivery ladder", () => {
  it("shows ⚠ while retries pile up, with the failure reason", () => {
    const wrapper = bubble({ tries: 2, error: "relay timeout" });
    const delivery = wrapper.get(".delivery");
    expect(delivery.text()).toBe("⚠");
    expect(delivery.classes()).toContain("failed");
    expect(delivery.attributes("title")).toBe("relay timeout");
  });

  it("shows 🕓 and dims the bubble while pending", () => {
    const wrapper = bubble({ state: "pending" });
    expect(wrapper.get(".delivery").text()).toBe("🕓");
    expect(wrapper.get(".bubble-row").classes()).toContain("pending");
  });

  it("shows ✓ once sent without an ack", () => {
    expect(mark({ state: "sent", ack: "" })).toBe("✓");
  });

  it("shows ✓✓ for read receipts and reactions verbatim", () => {
    expect(mark({ ack: "+" })).toBe("✓✓");
    expect(mark({ ack: "✓" })).toBe("✓✓");
    expect(mark({ ack: "🔥" })).toBe("🔥");
  });

  it("shows no delivery mark on peer messages", () => {
    expect(mark({ mine: false, ack: "✓" })).toBe("");
  });

  it("prefers ⚠ over pending and never dims a failed bubble twice", () => {
    expect(mark({ state: "pending", tries: 1 })).toBe("⚠");
  });
});

describe("quote jump", () => {
  it("scrolls to the original message on quote click", async () => {
    const targetId = "b".repeat(64);
    const target = document.createElement("article");
    target.dataset.messageId = targetId;
    target.scrollIntoView = vi.fn();
    document.body.appendChild(target);

    const wrapper = bubble({ replyTo: targetId });
    await wrapper.get(".reply-quote").trigger("click");
    expect(target.scrollIntoView).toHaveBeenCalledWith({ block: "center" });
    target.remove();
  });

  it("is a no-op when the target left the history", async () => {
    const wrapper = bubble({ replyTo: "f".repeat(64) });
    await expect(
      wrapper.get(".reply-quote").trigger("click"),
    ).resolves.toBeUndefined();
  });
});
