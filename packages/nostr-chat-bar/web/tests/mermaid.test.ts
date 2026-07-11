import { describe, expect, it } from "vitest";
import { renderMarkdown } from "../src/markdown";
import { renderMermaidBlocks } from "../src/mermaid";
import fixtures from "../../Fixtures/rendering-messages.json";

function fixtureText(name: string): string {
  const found = fixtures.messages.find((entry) => entry.case === name);
  if (!found) throw new Error(`missing fixture case ${name}`);
  return found.message.text;
}

function mount(html: string): HTMLElement {
  const host = document.createElement("div");
  host.innerHTML = html;
  document.body.appendChild(host);
  return host;
}

describe("mermaid classification", () => {
  it("marks fenced mermaid blocks as inert placeholders", () => {
    const host = mount(renderMarkdown(fixtureText("mermaid-diagram")));
    const placeholder = host.querySelector("pre > code.language-mermaid");
    expect(placeholder).not.toBeNull();
    expect(placeholder?.textContent).toContain("graph TD");
    expect(host.querySelector("svg")).toBeNull();
  });

  it("does not classify mermaid-looking content inside other fences", () => {
    const host = mount(renderMarkdown(fixtureText("fenced-code")));
    expect(host.querySelector("code.language-mermaid")).toBeNull();
  });
});

// Runtime tests use sources Mermaid rejects at parse time: jsdom lacks
// the SVG layout APIs needed to complete a successful render, so only
// the fast, deterministic error path is testable here. Successful
// rendering is covered by the WebKit acceptance checks.
describe("mermaid runtime", () => {
  const invalid = "```mermaid\nnot a diagram %%{ }%%\n```";

  it("keeps source visible and adds an error indicator on failure", async () => {
    const host = mount(renderMarkdown(invalid));
    await renderMermaidBlocks(host, "light");
    expect(host.textContent).toContain("not a diagram");
    expect(host.querySelector(".mermaid-error")).not.toBeNull();
  });

  it("never throws for hostile or malformed sources", async () => {
    for (const text of [
      "```mermaid\n<script>alert(1)</script>\n```",
      "```mermaid\n\n```",
    ]) {
      const host = mount(renderMarkdown(text));
      await expect(renderMermaidBlocks(host, "dark")).resolves.toBeUndefined();
      expect(host.querySelector("script")).toBeNull();
    }
  });

  it("processes each placeholder once", async () => {
    const host = mount(renderMarkdown(invalid));
    await renderMermaidBlocks(host, "light");
    const after = host.innerHTML;
    await renderMermaidBlocks(host, "light");
    expect(host.innerHTML).toBe(after);
  });
});
