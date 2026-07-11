import { describe, expect, it } from "vitest";
import { renderMarkdown } from "../src/markdown";
import fixtures from "../../Fixtures/rendering-messages.json";

function fragment(html: string): DocumentFragment {
  const template = document.createElement("template");
  template.innerHTML = html;
  return template.content;
}

// Raw HTML in messages must end up as inert text, never as executable
// DOM: no active elements, no event handlers, no dangerous URL schemes.
function assertInert(html: string): void {
  const dom = fragment(html);
  expect(
    dom.querySelector("script, iframe, object, embed, form, style, link, meta"),
  ).toBeNull();
  for (const element of dom.querySelectorAll("*")) {
    for (const attribute of element.getAttributeNames()) {
      expect(attribute.startsWith("on"), `${attribute} on ${element.tagName}`).toBe(
        false,
      );
    }
  }
  for (const anchor of dom.querySelectorAll("a")) {
    const href = anchor.getAttribute("href") ?? "";
    expect(/^(javascript|data|vbscript|file):/i.test(href), href).toBe(false);
  }
  for (const image of dom.querySelectorAll("img")) {
    const src = image.getAttribute("src") ?? "";
    expect(/^https?:/i.test(src), src).toBe(false);
  }
}

describe("sanitization", () => {
  it("never emits script elements", () => {
    const html = renderMarkdown("<script>alert(1)</script>");
    expect(html).not.toContain("<script");
    assertInert(html);
  });

  it("keeps raw html visible as text instead of dropping it", () => {
    const dom = fragment(renderMarkdown("literal <angle brackets> stay"));
    expect(dom.textContent).toContain("<angle brackets>");
  });

  it("never emits event handler attributes", () => {
    assertInert(renderMarkdown("<img src=x onerror=alert(1)>"));
  });

  it("drops javascript URLs from links", () => {
    const dom = fragment(
      renderMarkdown(
        '<a href="javascript:alert(1)">bad</a>\n\n[also bad](javascript:alert(1))',
      ),
    );
    for (const anchor of dom.querySelectorAll("a")) {
      expect(anchor.getAttribute("href")).toBeNull();
    }
  });

  it("drops iframes", () => {
    assertInert(renderMarkdown('<iframe src="https://example.com"></iframe>'));
  });

  it("strips remote image sources so no network request can start", () => {
    const dom = fragment(renderMarkdown("![leak](https://evil.example/pixel.png)"));
    for (const img of dom.querySelectorAll("img")) {
      expect(img.getAttribute("src")).toBeNull();
    }
  });

  it("survives the hostile fixture without executable output", () => {
    const hostile = fixtures.messages.find((m) => m.case === "hostile-markup");
    if (!hostile) throw new Error("missing hostile-markup fixture");
    assertInert(renderMarkdown(hostile.message.text));
  });

  it("keeps raw style and form elements out of the live DOM", () => {
    assertInert(
      renderMarkdown(
        '<style>*{display:none}</style>\n\n<form action="https://x"><input type="text"></form>',
      ),
    );
  });
});
