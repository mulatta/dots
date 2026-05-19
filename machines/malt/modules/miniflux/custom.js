(() => {
  "use strict";

  const ENTRY_SELECTOR = ".entry-content";
  const SCROLL_TTL_MS = 7 * 24 * 60 * 60 * 1000;
  const SCROLL_KEY_PREFIX = "miniflux:entry-scroll:";
  const SVG_NS = "http://www.w3.org/2000/svg";

  const onReady = (callback) => {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback, { once: true });
      return;
    }
    callback();
  };

  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  const entryId = () => {
    const entry = document.querySelector(".entry[data-id]");
    const id = entry?.getAttribute("data-id");
    if (id) {
      return id;
    }
    return `${location.origin}${location.pathname}`;
  };

  const createSvgIcon = (pathData) => {
    const svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("aria-hidden", "true");
    svg.setAttribute("focusable", "false");

    const path = document.createElementNS(SVG_NS, "path");
    path.setAttribute("fill", "currentColor");
    path.setAttribute("d", pathData);
    svg.append(path);
    return svg;
  };

  const copyIcon = () =>
    createSvgIcon(
      "M16 1H4c-1.1 0-2 .9-2 2v12h2V3h12V1Zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2Zm0 16H8V7h11v14Z",
    );

  // Diagonal arrow used as a generic "open external" affordance.
  const externalIcon = () =>
    createSvgIcon(
      "M14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7Zm-9 4h7v2H7v8h8v-5h2v7H5V7Z",
    );

  const writeClipboard = async (text) => {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(text);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.left = "-9999px";
    textarea.style.top = "0";
    document.body.append(textarea);
    textarea.select();
    const ok = document.execCommand("copy");
    textarea.remove();
    if (!ok) {
      throw new Error("copy command failed");
    }
  };

  const setTemporaryLabel = (button, label, delay = 1300) => {
    const span = button.querySelector(".icon-label") ?? button;
    const old = span.textContent;
    span.textContent = label;
    window.setTimeout(() => {
      span.textContent = old;
    }, delay);
  };

  const setupReadingProgress = () => {
    const content = document.querySelector(ENTRY_SELECTOR);
    if (!content) {
      return;
    }

    const bar = document.createElement("div");
    bar.className = "miniflux-reading-progress";
    bar.setAttribute("aria-hidden", "true");
    document.body.append(bar);

    let ticking = false;
    const update = () => {
      ticking = false;
      const rect = content.getBoundingClientRect();
      const scrollTop = window.scrollY || document.documentElement.scrollTop;
      const top = scrollTop + rect.top;
      const bottom = top + content.scrollHeight;
      const range = Math.max(1, bottom - top - window.innerHeight);
      const progress = clamp((scrollTop - top) / range, 0, 1);
      bar.style.transform = `scaleX(${progress})`;
    };

    const schedule = () => {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(update);
      }
    };

    update();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule, { passive: true });
  };

  const setupScrollMemory = () => {
    if (!document.querySelector(ENTRY_SELECTOR)) {
      return;
    }

    const key = `${SCROLL_KEY_PREFIX}${entryId()}`;
    const now = Date.now();

    try {
      const raw = localStorage.getItem(key);
      if (raw && !location.hash) {
        const saved = JSON.parse(raw);
        if (typeof saved?.y === "number" && typeof saved?.t === "number") {
          if (now - saved.t <= SCROLL_TTL_MS) {
            window.setTimeout(() => {
              if ((window.scrollY || document.documentElement.scrollTop) < 32) {
                window.scrollTo({ top: saved.y, behavior: "instant" });
              }
            }, 60);
          } else {
            localStorage.removeItem(key);
          }
        }
      }
    } catch {
      localStorage.removeItem(key);
    }

    let ticking = false;
    const save = () => {
      ticking = false;
      try {
        localStorage.setItem(key, JSON.stringify({ y: window.scrollY, t: Date.now() }));
      } catch {
        // Storage can be disabled or full; reader behavior should continue.
      }
    };

    const scheduleSave = () => {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(save);
      }
    };

    window.addEventListener("scroll", scheduleSave, { passive: true });
    window.addEventListener("pagehide", save);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") {
        save();
      }
    });
  };

  const HIGHLIGHT_JS_URL = "https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@11.11.1/es/highlight.min.js";
  let highlightJsPromise = null;
  let trustedHtmlPolicy = null;

  const loadHighlightJs = () => {
    if (highlightJsPromise) {
      return highlightJsPromise;
    }

    highlightJsPromise = import(HIGHLIGHT_JS_URL).then((module) => module.default);
    return highlightJsPromise;
  };

  const trustedHtml = (value) => {
    if (!window.trustedTypes?.createPolicy) {
      return value;
    }
    if (!trustedHtmlPolicy) {
      trustedHtmlPolicy = window.trustedTypes.createPolicy("miniflux-highlight", {
        createHTML: (html) => html,
      });
    }
    return trustedHtmlPolicy.createHTML(value);
  };

  const highlightedCodeLanguage = (code) => {
    const languageClass = Array.from(code.classList).find((name) => name.startsWith("language-") || name.startsWith("highlight-source-"));
    if (!languageClass) {
      return null;
    }
    return languageClass.replace(/^language-/, "").replace(/^highlight-source-/, "");
  };

  const setupSyntaxHighlighting = async () => {
    const codeBlocks = [];

    document.querySelectorAll(`${ENTRY_SELECTOR} pre`).forEach((pre) => {
      if (pre.dataset.minifluxHighlighted) {
        return;
      }

      const existingCode = pre.querySelector("code");
      const code = existingCode ?? document.createElement("code");
      if (!existingCode) {
        code.textContent = pre.textContent ?? "";
        pre.replaceChildren(code);
      }
      code.classList.add("hljs");
      pre.dataset.minifluxHighlighted = "pending";
      codeBlocks.push(code);
    });

    if (codeBlocks.length === 0) {
      return;
    }

    try {
      const highlighter = await loadHighlightJs();
      codeBlocks.forEach((code) => {
        const source = code.textContent ?? "";
        const language = highlightedCodeLanguage(code);
        const result = language && highlighter.getLanguage(language) ? highlighter.highlight(source, { language, ignoreIllegals: true }) : highlighter.highlightAuto(source);
        code.innerHTML = trustedHtml(result.value);
        if (result.language) {
          code.classList.add(`language-${result.language}`);
        }
        code.closest("pre").dataset.minifluxHighlighted = "true";
      });
    } catch (error) {
      console.warn("Miniflux syntax highlighting failed", error);
      codeBlocks.forEach((code) => {
        code.closest("pre").dataset.minifluxHighlighted = "failed";
      });
    }
  };

  const setupCodeCopy = () => {
    document.querySelectorAll(`${ENTRY_SELECTOR} pre`).forEach((pre) => {
      if (pre.querySelector(".miniflux-code-copy")) {
        return;
      }

      const button = document.createElement("button");
      button.type = "button";
      button.className = "miniflux-code-copy";
      button.title = "Copy code";
      button.append(copyIcon());

      const label = document.createElement("span");
      label.className = "icon-label";
      label.textContent = "Copy";
      button.append(label);

      button.addEventListener("click", async () => {
        const code = pre.querySelector("code") ?? pre;
        try {
          await writeClipboard(code.textContent ?? "");
          setTemporaryLabel(button, "Copied");
        } catch {
          setTemporaryLabel(button, "Failed");
        }
      });

      pre.append(button);
    });
  };

  const text = (node) => node.textContent?.replace(/\s+/g, " ").trim() ?? "";

  const escapeMarkdown = (value) => value.replace(/([\\`*_{}[\]()#+\-.!|>])/g, "\\$1");

  const fenceFor = (value) => {
    const longest = Math.max(0, ...Array.from(value.matchAll(/`+/g), (match) => match[0].length));
    return "`".repeat(Math.max(3, longest + 1));
  };

  const codeLanguage = (pre) => {
    const code = pre.querySelector("code[class]");
    const classes = Array.from(code?.classList ?? []);
    const languageClass = classes.find((name) => name.startsWith("language-"));
    return languageClass ? languageClass.slice("language-".length) : "";
  };

  const childrenToMarkdown = (node) => Array.from(node.childNodes, nodeToMarkdown).join("");

  const block = (value) => {
    const trimmed = value.trim();
    return trimmed ? `${trimmed}\n\n` : "";
  };

  const listToMarkdown = (list, ordered) => {
    const items = Array.from(list.children).filter((child) => child.tagName === "LI");
    return `${items
      .map((item, index) => {
        const prefix = ordered ? `${index + 1}. ` : "- ";
        const rendered = childrenToMarkdown(item).trim().replace(/\n/g, "\n  ");
        return `${prefix}${rendered}`;
      })
      .join("\n")}\n\n`;
  };

  function nodeToMarkdown(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return escapeMarkdown(node.nodeValue ?? "");
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return "";
    }

    const element = node;
    if (element.matches(".miniflux-code-copy, .miniflux-copy-markdown, script, style, noscript")) {
      return "";
    }

    const tag = element.tagName;
    if (tag === "BR") {
      return "\n";
    }
    if (tag === "P") {
      return block(childrenToMarkdown(element));
    }
    if (/^H[1-6]$/.test(tag)) {
      const level = Number(tag.slice(1));
      return block(`${"#".repeat(level)} ${text(element)}`);
    }
    if (tag === "STRONG" || tag === "B") {
      return `**${childrenToMarkdown(element).trim()}**`;
    }
    if (tag === "EM" || tag === "I") {
      return `_${childrenToMarkdown(element).trim()}_`;
    }
    if (tag === "CODE") {
      if (element.closest("pre")) {
        return element.textContent ?? "";
      }
      const value = element.textContent ?? "";
      const fence = value.includes("`") ? "``" : "`";
      return `${fence}${value}${fence}`;
    }
    if (tag === "PRE") {
      const value = (element.querySelector("code")?.textContent ?? element.textContent ?? "").trimEnd();
      const fence = fenceFor(value);
      const language = codeLanguage(element);
      return `${fence}${language}\n${value}\n${fence}\n\n`;
    }
    if (tag === "A") {
      const label = childrenToMarkdown(element).trim() || text(element);
      const href = element.getAttribute("href") ?? "";
      if (!href) {
        return label;
      }
      if (!label || label === href) {
        return `<${href}>`;
      }
      return `[${label}](${href})`;
    }
    if (tag === "IMG") {
      const alt = element.getAttribute("alt") ?? "";
      const src = element.getAttribute("src") ?? "";
      return src ? `![${escapeMarkdown(alt)}](${src})` : "";
    }
    if (tag === "BLOCKQUOTE") {
      const rendered = childrenToMarkdown(element).trim();
      return rendered ? `${rendered.split("\n").map((line) => `> ${line}`).join("\n")}\n\n` : "";
    }
    if (tag === "UL" || tag === "OL") {
      return listToMarkdown(element, tag === "OL");
    }
    if (tag === "LI") {
      return childrenToMarkdown(element);
    }
    if (tag === "HR") {
      return "---\n\n";
    }
    if (tag === "TR") {
      const cells = Array.from(element.children)
        .filter((child) => child.tagName === "TH" || child.tagName === "TD")
        .map((child) => text(child).replace(/\|/g, "\\|"));
      return cells.length ? `| ${cells.join(" | ")} |\n` : "";
    }
    if (tag === "THEAD" || tag === "TBODY" || tag === "TFOOT") {
      return childrenToMarkdown(element);
    }
    if (tag === "TABLE") {
      const rows = Array.from(element.querySelectorAll("tr"));
      if (rows.length === 0) {
        return "";
      }
      const renderedRows = rows.map((row) => nodeToMarkdown(row)).join("");
      const firstCellCount = rows[0].children.length;
      const separator = firstCellCount > 0 ? `| ${Array(firstCellCount).fill("---").join(" | ")} |\n` : "";
      return `${renderedRows.split("\n", 1)[0]}\n${separator}${renderedRows.split("\n").slice(1).join("\n")}\n\n`;
    }
    if (["DIV", "SECTION", "ARTICLE", "ASIDE", "FIGURE", "FIGCAPTION"].includes(tag)) {
      return block(childrenToMarkdown(element));
    }

    return childrenToMarkdown(element);
  }

  const entryMarkdown = () => {
    const title = text(document.querySelector(".entry-header h1"));
    const url = document.querySelector(".entry-header h1 a")?.href ?? document.querySelector(".entry-external-link a")?.href ?? "";
    const content = document.querySelector(ENTRY_SELECTOR);
    const parts = [];
    if (title) {
      parts.push(`# ${title}`);
    }
    if (url) {
      parts.push(url);
    }
    if (content) {
      parts.push(childrenToMarkdown(content));
    }
    return `${parts.join("\n\n").replace(/\n{3,}/g, "\n\n").trim()}\n`;
  };

  const setupMarkdownCopy = () => {
    const actions = document.querySelector(".entry-actions ul");
    if (!actions || actions.querySelector(".miniflux-copy-markdown")) {
      return;
    }

    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.className = "page-button miniflux-copy-markdown";
    button.title = "Copy entry as Markdown";
    button.append(copyIcon());

    const label = document.createElement("span");
    label.className = "icon-label";
    label.textContent = "Copy entry as Markdown";
    button.append(label);

    button.addEventListener("click", async () => {
      try {
        await writeClipboard(entryMarkdown());
        setTemporaryLabel(button, "Copied");
      } catch {
        setTemporaryLabel(button, "Failed");
      }
    });

    item.append(button);
    actions.append(item);
  };

  // Miniflux renders the article URL twice: once as the entry title link and
  // once as a long URL link inside `.entry-meta` (`.entry-external-link`).
  // Hide the meta version (CSS) and promote a matching button into the
  // entry-actions toolbar so it lives next to Star/Share/etc. Source the URL
  // from whichever element the current Miniflux build exposes.
  const entryUrl = () => {
    const candidates = [".entry-external-link", ".entry-header h1 a", ".entry .item-title a", ".entry[data-id] a"];
    for (const selector of candidates) {
      const node = document.querySelector(selector);
      const href = node?.getAttribute("href");
      if (href && /^https?:\/\//.test(href)) {
        return href;
      }
    }
    return null;
  };

  const isGithubRepositoryUrl = (href) => {
    try {
      const url = new URL(href);
      const parts = url.pathname.split("/").filter(Boolean);
      return url.hostname === "github.com" && parts.length === 2;
    } catch {
      return false;
    }
  };

  const setupGithubReadme = () => {
    const content = document.querySelector(ENTRY_SELECTOR);
    const href = entryUrl();
    if (!content || !href || !isGithubRepositoryUrl(href)) {
      return;
    }

    content.classList.add("github-readme");

    content.querySelectorAll("table").forEach((table) => {
      const cells = Array.from(table.querySelectorAll("td"));
      const isMediaLayout = !table.querySelector("th") && cells.length > 0 && cells.every((cell) => cell.querySelector("img, picture") && !text(cell));
      if (isMediaLayout) {
        table.classList.add("github-readme-layout-table");
      }
    });
  };

  const setupExternalLinkButton = () => {
    const actions = document.querySelector(".entry-actions ul");
    if (!actions || actions.querySelector(".miniflux-external-link")) {
      return;
    }

    const href = entryUrl();
    if (!href) {
      return;
    }

    const item = document.createElement("li");
    const link = document.createElement("a");
    link.className = "page-button miniflux-external-link";
    link.href = href;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    link.title = "Open original article";
    link.append(externalIcon());

    const label = document.createElement("span");
    label.className = "icon-label";
    label.textContent = "Original";
    link.append(label);

    item.append(link);

    const markdownItem = actions.querySelector(".miniflux-copy-markdown")?.closest("li");
    if (markdownItem) {
      actions.insertBefore(item, markdownItem);
    } else {
      actions.append(item);
    }
  };

  const githubTrendingTitle = (value) => {
    const match = value.replace(/\s+/g, " ").trim().match(/^([^\s]+\/[^\s]+)\s+—\s+(.+)$/);
    if (!match) {
      return null;
    }
    return { repo: match[1], description: match[2] };
  };

  const replaceAnchorText = (anchor, value) => {
    const icon = anchor.querySelector("img");
    if (icon) {
      icon.remove();
    }
    anchor.textContent = value;
    if (icon) {
      anchor.prepend(icon, " ");
    }
  };

  const setupRssActionLabels = () => {
    document.querySelectorAll("[data-save-entry]").forEach((button) => {
      button.title = "Ask Noa to inspect this entry";
      button.dataset.labelDone = "Asked Noa";
      button.dataset.toastDone = "Asked Noa";
      const label = button.querySelector(".icon-label");
      if (label && !button.dataset.completed) {
        label.textContent = "Ask Noa";
      }
    });

    document.querySelectorAll("[data-toggle-starred]").forEach((button) => {
      const archived = button.dataset.value === "star";
      button.title = archived
        ? "Archived to Linkwarden; click to unstar in Miniflux only"
        : "Archive to Linkwarden";
      button.dataset.labelStar = "Archive";
      button.dataset.labelUnstar = "Archived";
      button.dataset.toastStar = "Archived to Linkwarden";
      button.dataset.toastUnstar = "Unstarred in Miniflux";
      const label = button.querySelector(".icon-label");
      if (label) {
        label.textContent = archived ? "Archived" : "Archive";
      }
    });
  };

  const setupGithubTrendingDescription = () => {
    document.querySelectorAll(".entry-item .item-title a").forEach((anchor) => {
      const parsed = githubTrendingTitle(text(anchor));
      if (!parsed) {
        return;
      }

      const item = anchor.closest(".entry-item");
      const title = anchor.closest(".item-title");
      const header = anchor.closest(".item-header");
      if (!item || !title || !header || header.querySelector(".github-trending-list-description")) {
        return;
      }

      replaceAnchorText(anchor, parsed.repo);
      item.classList.add("github-trending-entry");

      const description = document.createElement("p");
      description.className = "github-trending-list-description";
      description.textContent = parsed.description;
      header.append(description);
    });

    const entryTitle = document.querySelector(".entry-header h1 a");
    const parsed = entryTitle ? githubTrendingTitle(text(entryTitle)) : null;
    if (!entryTitle || !parsed) {
      return;
    }

    replaceAnchorText(entryTitle, parsed.repo);

    const heading = entryTitle.closest("h1");
    if (!heading || heading.parentElement?.querySelector(".github-trending-entry-description")) {
      return;
    }

    const description = document.createElement("p");
    description.className = "github-trending-entry-description";
    description.textContent = parsed.description;
    heading.insertAdjacentElement("afterend", description);
  };

  onReady(() => {
    setupReadingProgress();
    setupScrollMemory();
    setupGithubReadme();
    setupSyntaxHighlighting();
    setupCodeCopy();
    setupMarkdownCopy();
    setupExternalLinkButton();
    setupRssActionLabels();
    setupGithubTrendingDescription();
  });
})();
