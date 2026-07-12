import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import MessageBody from "../src/components/MessageBody.vue";
import { renderMarkdown } from "../src/markdown";
import { renderMermaidBlocks } from "../src/mermaid";

const render = vi.fn(async (id: string, source: string) => ({
  svg: `<svg id="${id}" data-source="${source}"></svg>`,
}));

vi.mock("mermaid", () => ({
  default: {
    initialize: vi.fn(),
    render,
  },
}));

function placeholders(count: number): HTMLElement {
  const host = document.createElement("div");
  host.innerHTML = Array.from({ length: count }, () =>
    renderMarkdown("```mermaid\ngraph TD\nA --> B\n```"),
  ).join("");
  return host;
}

afterEach(() => {
  render.mockClear();
  vi.unstubAllGlobals();
});

describe("Mermaid lifecycle", () => {
  it("generates unique SVG IDs for repeated diagram sources", async () => {
    const host = placeholders(2);
    await renderMermaidBlocks(host, "light");
    const ids = Array.from(host.querySelectorAll("svg"), (svg) => svg.id);
    expect(ids).toHaveLength(2);
    expect(new Set(ids).size).toBe(2);
    expect(render).toHaveBeenCalledTimes(2);
  });

  it("rerenders diagrams after system appearance changes", async () => {
    let dark = false;
    let listener: (() => void) | undefined;
    vi.stubGlobal("matchMedia", () => ({
      get matches() {
        return dark;
      },
      addEventListener: (_type: string, callback: () => void) => {
        listener = callback;
      },
      removeEventListener: vi.fn(),
    }));

    const wrapper = mount(MessageBody, {
      props: { text: "```mermaid\ngraph TD\nA --> B\n```" },
    });
    await flushPromises();
    expect(render).toHaveBeenCalledTimes(1);

    dark = true;
    listener?.();
    await wrapper.vm.$nextTick();
    await flushPromises();
    expect(render).toHaveBeenCalledTimes(2);

    wrapper.unmount();
  });
});
