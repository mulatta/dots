import { describe, expect, it } from "vitest";
import { renderMarkdown } from "../src/markdown";
import fixtures from "../../Fixtures/rendering-messages.json";

function fixtureText(name: string): string {
  const found = fixtures.messages.find((entry) => entry.case === name);
  if (!found) throw new Error(`missing fixture case ${name}`);
  return found.message.text;
}

function fragment(html: string): DocumentFragment {
  const template = document.createElement("template");
  template.innerHTML = html;
  return template.content;
}

describe("markdown and GFM", () => {
  it("renders paragraphs from multiline text", () => {
    const dom = fragment(renderMarkdown("first paragraph\n\nsecond paragraph"));
    const paragraphs = dom.querySelectorAll("p");
    expect(paragraphs).toHaveLength(2);
    expect(paragraphs[0].textContent).toBe("first paragraph");
    expect(paragraphs[1].textContent).toBe("second paragraph");
  });

  it("renders headings and nested emphasis", () => {
    const dom = fragment(renderMarkdown("## Title\n\n**bold with *nested* text**"));
    expect(dom.querySelector("h2")?.textContent).toBe("Title");
    expect(dom.querySelector("strong em")?.textContent).toBe("nested");
  });

  it("renders inline and fenced code with its language class", () => {
    const dom = fragment(renderMarkdown(fixtureText("fenced-code")));
    const block = dom.querySelector("pre > code");
    expect(block?.classList.contains("language-typescript")).toBe(true);
    expect(block?.textContent).toContain('const fence = "~~~mermaid";');
    const inline = fragment(renderMarkdown("use `npm ci` here"));
    expect(inline.querySelector("code")?.textContent).toBe("npm ci");
  });

  it("keeps fence-like text inside a code block as code", () => {
    const dom = fragment(renderMarkdown(fixtureText("fenced-code")));
    expect(dom.querySelector("code.language-mermaid")).toBeNull();
  });

  it("renders ordered, unordered, and nested lists with quotes", () => {
    const dom = fragment(
      renderMarkdown("1. one\n2. two\n\n- a\n  - b\n\n> quoted\n> > deeper"),
    );
    expect(dom.querySelectorAll("ol > li")).toHaveLength(2);
    expect(dom.querySelector("ul ul li")?.textContent?.trim()).toBe("b");
    expect(dom.querySelector("blockquote blockquote")).not.toBeNull();
  });

  it("renders GFM tables, task lists, and strikethrough", () => {
    const dom = fragment(renderMarkdown(fixtureText("gfm-table-task-list")));
    expect(dom.querySelectorAll("table th")).toHaveLength(2);
    expect(dom.querySelectorAll("table td")).toHaveLength(4);
    const boxes = dom.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
    expect(boxes).toHaveLength(2);
    for (const box of boxes) expect(box.disabled).toBe(true);
    expect(dom.querySelector("del")?.textContent).toBe("obsolete");
  });

  it("preserves Hangul, emoji, and literal angle brackets", () => {
    const dom = fragment(renderMarkdown(fixtureText("plain-incoming-unicode")));
    expect(dom.textContent).toContain("안녕하세요");
    expect(dom.textContent).toContain("👋");
    expect(dom.textContent).toContain("<angle brackets>");
    expect(dom.querySelector("angle")).toBeNull();
  });

  it("keeps http, https, and nostr links", () => {
    const dom = fragment(
      renderMarkdown(
        "[web](https://example.com) [plain](http://example.com) " +
          "[note](nostr:note1qqqqqqqq)",
      ),
    );
    const hrefs = Array.from(dom.querySelectorAll("a")).map((a) =>
      a.getAttribute("href"),
    );
    expect(hrefs).toContain("https://example.com");
    expect(hrefs).toContain("http://example.com");
    expect(hrefs).toContain("nostr:note1qqqqqqqq");
  });

  it("drops link schemes outside the allowlist", () => {
    const dom = fragment(
      renderMarkdown("[bad](javascript:alert(1)) [mail](mailto:a@b.c) [file](file:///etc/passwd)"),
    );
    for (const anchor of dom.querySelectorAll("a")) {
      expect(anchor.getAttribute("href")).toBeNull();
    }
  });

  it("renders unknown fence languages as plain code", () => {
    const dom = fragment(renderMarkdown("```nonsense-lang\npayload\n```"));
    expect(dom.querySelector("pre > code")?.textContent).toContain("payload");
    expect(dom.querySelector("code.language-mermaid")).toBeNull();
  });

  it("renders an unterminated fence safely as code", () => {
    const dom = fragment(renderMarkdown(fixtureText("malformed-special-fence")));
    expect(dom.textContent).toContain("graph TD");
    expect(dom.textContent).toContain("After without a closing fence");
  });

  it("caches by text so identical messages render identical HTML", () => {
    const first = renderMarkdown("**cached** message");
    const second = renderMarkdown("**cached** message");
    expect(second).toBe(first);
  });
});

describe("math", () => {
  it("renders inline math with KaTeX markup", () => {
    const dom = fragment(renderMarkdown(fixtureText("inline-and-display-math")));
    expect(dom.querySelector(".katex")).not.toBeNull();
  });

  it("renders display math as a block", () => {
    const dom = fragment(renderMarkdown(fixtureText("inline-and-display-math")));
    expect(dom.querySelector(".katex-display")).not.toBeNull();
  });

  it("renders fenced math and latex blocks as display math", () => {
    for (const lang of ["math", "latex"]) {
      const dom = fragment(renderMarkdown("```" + lang + "\n\\frac{1}{2}\n```"));
      expect(dom.querySelector(".katex-display"), lang).not.toBeNull();
    }
  });

  it("keeps invalid math visible instead of throwing", () => {
    const html = renderMarkdown("$\\frac{$");
    expect(html).toContain("\\frac");
  });
});

describe("fixtures", () => {
  it("renders every fixture message without throwing", () => {
    for (const entry of fixtures.messages) {
      const html = renderMarkdown(entry.message.text);
      expect(html.length, entry.case).toBeGreaterThan(0);
    }
  });
});
