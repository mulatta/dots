import { describe, expect, it } from "vitest";
import { mount } from "@vue/test-utils";
import App from "../src/App.vue";

describe("renderer shell", () => {
  it("mounts the history root", () => {
    const wrapper = mount(App);
    expect(wrapper.get("main.history").attributes("data-renderer")).toBe(
      "nostr-chat-bar-web",
    );
  });
});
