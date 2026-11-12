// Atuin threads: the coding-agent sessions Atuin captured, newest first, for the shown
// space's repo (or every space). Type to search their transcripts; each hit shows the
// best-matching line under its title. Click or Enter resumes the thread in a new tab of
// that space, shift forks it instead. Atuin writes the session out from sync first when the
// machine doesn't have it, and resumes it in its own agent. The query and scope survive
// closing the panel, so ctrl-u clears it: the app takes Esc to close the dialog.

import { View, div, svg, image } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { exec, spaces, panes, run, theme, appHome, readTextFile, settings, props, closeOverlay, shared, setShared } from "herdr";

// `atuin` from the user's PATH, unless `local.json` beside this file names another build
// (`{ "atuin": "/path/to/atuin" }`): the CLI must match the running daemon.
const ATUIN = "atuin";
const LOCAL = "local.json";
const LIMIT = 80;
const SEARCH_LIMIT = 40;
const REFRESH = 30000;
const DEBOUNCE = 250;
const STATE = "atuin-threads.state";

// Row geometry, fixed so the list can place rows itself and keep the selection on screen.
const H_TITLE = 28;
const H_SNIP = 16;

// How each harness is drawn: its icon in the app's table, full color or a tinted glyph.
const ICON = {
  "claude-code": { file: "icons/claude.svg", tint: false },
  codex: { file: "icons/codex.svg", tint: false },
  copilot: { file: "icons/copilot.svg", tint: true },
  opencode: { file: "icons/opencode.svg", tint: true },
  pi: { file: "icons/pi.svg", tint: true },
  omp: { file: "icons/pi.svg", tint: true },
};

const base = (path) => path.replace(/\/+$/, "").split("/").pop() || path;
const inside = (dir, root) => dir === root || dir.startsWith(`${root}/`);
// Control characters become spaces one for one, so match offsets still line up.
const flat = (s) => (s ?? "").replace(/[\u0000-\u001f\u007f]/g, " ");
const line = (s) => flat(s).replace(/ {2,}/g, " ").trim();
const clamp = (v, lo, hi) => Math.max(lo, Math.min(v, hi));

function ago(iso) {
  const ms = Date.now() - Date.parse(iso);
  const m = Math.floor(ms / 60000);
  if (m < 1) return "now";
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h`;
  const d = Math.floor(h / 24);
  return d < 60 ? `${d}d` : `${Math.floor(d / 30)}mo`;
}

// Atuin reports matches as UTF-8 byte ranges; turn them into string index ranges of `text`.
function charRanges(text, ranges) {
  if (!ranges?.length) return [];
  const at = new Map();
  let b = 0;
  let i = 0;
  for (const ch of text) {
    at.set(b, i);
    const cp = ch.codePointAt(0);
    b += cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    i += ch.length;
  }
  at.set(b, i);
  return ranges.map(([s, e]) => [at.get(s), at.get(e)]).filter(([s, e]) => s !== undefined && e !== undefined && e > s);
}

// Case-insensitive occurrences of each query word in `text`, as string index ranges.
function findRanges(text, words) {
  const low = text.toLowerCase();
  const out = [];
  for (const w of words) {
    let from = 0;
    for (;;) {
      const k = low.indexOf(w, from);
      if (k < 0) break;
      out.push([k, k + w.length]);
      from = k + w.length;
    }
  }
  return out.sort((a, b) => a[0] - b[0]);
}

// A window of `text` that starts a little before its first match, with ranges shifted to it.
function excerpt(text, ranges, lead = 24, span = 220) {
  const start = ranges.length ? Math.max(0, ranges[0][0] - lead) : 0;
  const cut = text.slice(start, start + span);
  const shifted = ranges
    .map(([s, e]) => [s - start, Math.min(e - start, cut.length)])
    .filter(([s, e]) => s >= 0 && e > s);
  return start > 0 && !cut.startsWith("…") ? { text: `…${cut}`, ranges: shifted.map(([s, e]) => [s + 1, e + 1]) } : { text: cut, ranges: shifted };
}

// `text` cut into plain and matched runs.
function runs(text, ranges) {
  const out = [];
  let at = 0;
  for (const [s, e] of ranges) {
    if (s < at) continue;
    if (s > at) out.push({ s: text.slice(at, s), hit: false });
    out.push({ s: text.slice(s, e), hit: true });
    at = e;
  }
  if (at < text.length) out.push({ s: text.slice(at), hit: false });
  return out;
}

function icon(harness, t) {
  const spec = ICON[harness];
  if (!spec) return div().w(14).h(14).flex_none();
  return spec.tint ? svg(spec.file).size(14).flex_none().text_color(t.muted) : image(spec.file).w(14).h(14).flex_none();
}

// Where a space is now: its first terminal's live folder, else where it was made (as the
// spaces sidebar sees it).
function place(s, ps) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

export default class Threads extends View {
  init(_props, cx) {
    this.atuin = ATUIN;
    this.threads = [];
    this.hits = null; // search results, null without a query
    this.error = null;
    this.loaded = false;
    this.loading = false;
    this.searching = false;
    this.query = "";
    this.seq = 0;
    this.debounce = null;
    this.scope = "space"; // or "all"
    this.roots = {}; // machine:folder -> its repo root (the folder itself outside a repo)
    this.at = 0;
    this.scroll = 0;
    this.listHeight = 400;
    this.acted = 0;
    const saved = shared(STATE) ?? {};
    if (saved.scope === "all" || saved.scope === "space") this.scope = saved.scope;

    this.input = InputState.new({ placeholder: "Search threads…" });
    this.input.on("change", (_e, cx) => this.typed(cx));
    // Enter reaches the input as a submit; shift-enter may arrive here, as a key, or both.
    this.input.on("submit", (e, cx) => this.act(e.shift ? "fork" : "resume", cx));
    if (typeof saved.query === "string" && saved.query) {
      this.input.set_value(saved.query);
      this.typed(cx);
    }
    this.input.focus();
    cx.timer.after(600, () => this.input.focus());

    cx.spawn(async (cx) => {
      const local = await readTextFile(`${appHome()}/mods/atuin-threads/${LOCAL}`);
      if (local) {
        try {
          this.atuin = JSON.parse(local).atuin || ATUIN;
        } catch (e) {
          this.error = `${LOCAL}: ${e.message}`;
        }
      }
      this.refresh(cx);
    });
    cx.timer.every(REFRESH, (cx) => this.refresh(cx));
  }

  save() {
    setShared(STATE, { query: this.query, scope: this.scope });
  }

  // One action per keypress, however many paths report it.
  act(kind, cx) {
    const now = Date.now();
    if (now - this.acted < 300) return;
    const r = this.rows()[this.at];
    if (!r) return;
    this.acted = now;
    this.resume(r.th, kind === "fork", cx);
  }

  close() {
    const id = props()?.overlay;
    if (id) closeOverlay(id);
  }

  refresh(cx) {
    if (this.loading) return;
    this.loading = true;
    cx.spawn(async (cx) => {
      try {
        const r = await exec(this.atuin, ["threads", "search", "", "--limit", String(LIMIT), "--style", "json"]);
        if (r.code !== 0) throw new Error(line(r.stderr).split("Location:")[0] || `atuin exited ${r.code}`);
        // A subagent's thread resumes as its parent's, so only roots are listed.
        this.threads = JSON.parse(r.stdout).map((m) => m.session).filter((s) => !s.parent_atuin_id);
        this.error = null;
      } catch (e) {
        this.error = String(e.message ?? e);
      }
      this.loaded = true;
      this.loading = false;
      cx.notify();
    });
  }

  typed(cx) {
    this.query = this.input.value();
    this.at = 0;
    this.scroll = 0;
    this.save();
    if (this.debounce) this.debounce.cancel?.();
    const q = this.query.trim();
    if (q.length < 2) {
      this.hits = null;
      this.searching = false;
      cx.notify();
      return;
    }
    const seq = ++this.seq;
    this.debounce = cx.timer.after(DEBOUNCE, (cx) => this.search(q, seq, cx));
    cx.notify();
  }

  search(q, seq, cx) {
    if (seq !== this.seq) return;
    this.searching = true;
    cx.notify();
    cx.spawn(async (cx) => {
      let hits = [];
      let error = null;
      try {
        const r = await exec(this.atuin, ["threads", "search", "--limit", String(SEARCH_LIMIT), "--style", "json", "--", ...q.split(/\s+/)]);
        if (r.code !== 0) throw new Error(line(r.stderr).split("Location:")[0] || `atuin exited ${r.code}`);
        hits = JSON.parse(r.stdout).filter((m) => !m.session.parent_atuin_id);
      } catch (e) {
        error = String(e.message ?? e);
      }
      // Only the newest query's answer counts; an older one arriving late is dropped.
      if (seq !== this.seq) return;
      this.hits = hits;
      this.error = error;
      this.searching = false;
      cx.notify();
    });
  }

  // The repo root of `dir` on `machine`, looked up once; `dir` itself until known, and
  // outside a repo.
  root(dir, machine, cx) {
    const key = `${machine ?? ""}:${dir}`;
    if (key in this.roots) return this.roots[key];
    this.roots[key] = dir;
    cx.spawn(async (cx) => {
      try {
        const r = await exec("git", ["-C", dir, "rev-parse", "--show-toplevel"], { on: machine });
        if (r.code === 0 && r.stdout.trim()) {
          this.roots[key] = r.stdout.trim();
          cx.notify();
        }
      } catch {}
    });
    return dir;
  }

  // A new tab in the shown space, in the thread's folder when that space's machine has it
  // (else atuin picks one), running atuin's resume: it writes the session out if need be
  // and hands the terminal to the agent.
  // The panel closes only once the tab is asked for: closing it first drops this view and
  // the task with it.
  resume(th, fork, cx) {
    const space = spaces().find((s) => s.active);
    const on = space?.machine ?? null;
    const args = ["threads", "resume", th.atuin_id];
    if (fork) args.push("--fork");
    const name = line(th.title || th.preview).slice(0, 28) || undefined;
    cx.spawn(async () => {
      let has = false;
      if (th.cwd) {
        try {
          has = (await exec("test", ["-d", th.cwd], { on })).code === 0;
        } catch {}
      }
      run("tab.new", { space: space?.id, name, folder: has ? th.cwd : undefined, argv: [this.atuin, ...args] });
      this.close();
    });
  }

  // What the list shows, scoped: every thread without a query, else the search hits plus
  // threads whose title holds the query as written (atuin matches whole words only).
  rows() {
    const here = this.here;
    const mine = (th) => this.scope === "all" || (here && th.cwd && inside(th.cwd, here));
    if (!this.hits) return this.threads.filter(mine).map((th) => ({ th, title: line(th.title) || line(th.preview) || "(untitled)", tr: [], snip: null, index: null }));
    const words = this.query.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const seen = new Set();
    const out = [];
    for (const h of this.hits) {
      const th = h.session;
      if (!mine(th) || seen.has(th.atuin_id)) continue;
      seen.add(th.atuin_id);
      const rawTitle = flat(h.title?.text || th.title || th.preview || "");
      const title = rawTitle.trim() ? rawTitle : "(untitled)";
      const tr = h.title?.matches ? charRanges(rawTitle, h.title.matches) : findRanges(title, words);
      const ptext = flat(h.preview?.text ?? "");
      const snip = ptext.trim() ? excerpt(ptext, charRanges(ptext, h.preview.matches)) : null;
      out.push({ th, title, tr, snip, index: h.message_index ?? null });
    }
    for (const th of this.threads) {
      if (!mine(th) || seen.has(th.atuin_id)) continue;
      const title = line(th.title) || line(th.preview);
      const tr = findRanges(title, words);
      if (words.length && words.every((w) => title.toLowerCase().includes(w))) out.push({ th, title, tr, snip: null, index: null });
    }
    return out;
  }

  height(r) {
    return H_TITLE + (r.snip ? H_SNIP : 0);
  }

  move(d, rows, cx) {
    if (!rows.length) return;
    this.at = clamp(this.at + d, 0, rows.length - 1);
    // Keep the selection on screen.
    let top = 0;
    for (let i = 0; i < this.at; i++) top += this.height(rows[i]);
    const h = this.height(rows[this.at]);
    if (top < this.scroll) this.scroll = top;
    else if (top + h > this.scroll + this.listHeight) this.scroll = top + h - this.listHeight;
    cx.notify();
  }

  styled(text, ranges, t, color, size) {
    return h_flex()
      .flex_1()
      .min_w(0)
      .overflow_hidden()
      .whitespace_nowrap()
      .text_size(size)
      .text_color(color)
      .children(runs(text, ranges).map((p) => (p.hit ? div().flex_none().text_color(t.accent).font_semibold().child(p.s) : div().flex_none().child(p.s))));
  }

  row(t, r, i) {
    const th = r.th;
    const on = i === this.at;
    return v_flex()
      .id(`th-${th.atuin_id}`)
      .h(this.height(r))
      .flex_none()
      .rounded(7)
      .overflow_hidden()
      .when(on, (el) => el.bg(t.hover))
      .hover((el) => el.bg(t.hover))
      .on_click((e, cx) => {
        this.at = i;
        this.act(e.modifiers.shift ? "fork" : "resume", cx);
      })
      .child(
        h_flex()
          .h(H_TITLE)
          .flex_none()
          .px(8)
          .gap(7)
          .items_center()
          .child(icon(th.harness, t))
          .child(this.styled(r.title, r.tr, t, t.foreground, 12.5))
          .when(this.scope === "all" && Boolean(th.cwd), (el) => el.child(div().flex_none().max_w(90).truncate().text_size(11).text_color(t.dim).child(base(th.cwd))))
          .child(div().flex_none().text_size(11).text_color(t.dim).child(ago(th.updated_at))),
      )
      .when(Boolean(r.snip), (el) => el.child(h_flex().h(H_SNIP).flex_none().pl(29).pr(8).mt(-4).child(this.styled(r.snip.text, r.snip.ranges, t, t.dim, 11))));
  }

  tab(t, id, label, on) {
    return div()
      .id(id)
      .px(8)
      .h(22)
      .rounded(6)
      .flex()
      .items_center()
      .text_size(11.5)
      .text_color(on ? t.foreground : t.muted)
      .when(on, (el) => el.bg(t.raised))
      .hover((el) => el.bg(t.hover))
      .on_click((_e, cx) => {
        this.scope = id;
        this.save();
        this.at = 0;
        this.scroll = 0;
        cx.notify();
      })
      .child(label);
  }

  header(t, rows) {
    const busy = this.loading || this.searching;
    return v_flex()
      .flex_none()
      .px(10)
      .pt(10)
      .pb(6)
      .gap(6)
      .child(
        h_flex()
          .h(30)
          .px(8)
          .gap(6)
          .items_center()
          .rounded(8)
          .border_1()
          .border_color(t.border)
          .bg(t.background)
          .child(svg("mods/workspace-chrome/search.svg").size(13).flex_none().text_color(t.dim))
          .child(Input.new(this.input).flex_1().h_full().text_size(12.5).text_color(t.foreground))
          .child(
            div()
              .id("refresh")
              .size(20)
              .flex_none()
              .rounded(5)
              .flex()
              .items_center()
              .justify_center()
              .text_color(t.muted)
              .hover((el) => el.bg(t.hover))
              .on_click((_e, cx) => this.refresh(cx))
              .when(busy, (el) => el.child(svg("mods/workspace-chrome/spinner.svg").size(12).text_color(t.working).spin(900)))
              .when(!busy, (el) => el.child("↻")),
          ),
      )
      .child(
        h_flex()
          .gap(4)
          .items_center()
          .child(this.tab(t, "space", this.here ? base(this.here) : "This space", this.scope === "space"))
          .child(this.tab(t, "all", "All", this.scope === "all"))
          .child(div().flex_1())
          .child(div().text_size(10.5).text_color(t.dim).child(`${rows.length}${this.hits ? " found" : ""}`)),
      );
  }

  empty(t, text) {
    return div().px(12).py(10).text_size(12).text_color(t.dim).child(text);
  }

  render(cx) {
    const t = theme();
    const ps = panes();
    const space = spaces().find((s) => s.active);
    this.here = space ? this.root(place(space, ps), space.machine ?? null, cx) : null;
    const rows = this.rows();
    this.at = clamp(this.at, 0, Math.max(0, rows.length - 1));

    const tops = [];
    let y = 0;
    for (const r of rows) {
      tops.push(y);
      y += this.height(r);
    }
    const maxScroll = Math.max(0, y - this.listHeight);
    this.scroll = clamp(this.scroll, 0, maxScroll);

    let body;
    if (this.error) body = this.empty(t, `atuin: ${this.error}`).text_color(t.blocked);
    else if (!this.loaded) body = this.empty(t, "Loading…");
    else if (rows.length === 0)
      body = this.empty(t, this.hits ? "No matches." : this.scope === "space" ? `No threads in ${this.here ? base(this.here) : "this space"} yet.` : "No threads captured yet.");
    else
      body = v_flex()
        .id("list")
        .relative()
        .flex_1()
        .min_h(0)
        .mx(4)
        .overflow_hidden()
        .on_size_change((size, cx) => {
          const h = size.height / settings().zoom;
          if (Math.abs(h - this.listHeight) > 0.5) {
            this.listHeight = h;
            cx.notify();
          }
        })
        .on_scroll_wheel((e, cx) => {
          this.scroll = clamp(this.scroll - e.delta.y, 0, maxScroll);
          cx.notify();
        })
        .children(
          rows
            .map((r, i) => {
              const h = this.height(r);
              if (tops[i] + h < this.scroll || tops[i] > this.scroll + this.listHeight) return null;
              return this.row(t, r, i).absolute().left(0).right(0).top(tops[i] - this.scroll);
            })
            .filter(Boolean),
        );

    return v_flex()
      .id("root")
      .size_full()
      .bg(t.chrome)
      .text_size(12.5)
      .on_key_down((e, cx) => {
        const k = e.keystroke;
        if (k === "down" || k === "ctrl-j") this.move(1, rows, cx);
        else if (k === "up" || k === "ctrl-k") this.move(-1, rows, cx);
        else if (k === "shift-enter") this.act("fork", cx);
        else if (k === "enter" || k === "cmd-enter") this.act("resume", cx);
        else if (k === "ctrl-u" && this.query) {
          this.input.set_value("");
          this.typed(cx);
        } else return;
        cx.stop_propagation();
      })
      .child(this.header(t, rows))
      .child(div().flex_1().min_h(0).flex().flex_col().pb(6).child(body));
  }
}
