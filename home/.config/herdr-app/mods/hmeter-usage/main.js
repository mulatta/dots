// Claude and Codex rate-limit windows, as `hmeter usage` resolves them per account.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { exec, run, settings, theme } from "herdr";

const HMETER = "hmeter";
const LABELS = { claude: "Claude", codex: "Codex" };
// hmeter asks an agent at most every 5 minutes; asking it to every 10 keeps the endpoints quiet.
const REFRESH_EVERY = 10;
const ROW = 16;
const now = () => Math.floor(Date.now() / 1000);

function span(secs) {
  if (secs < 3600) return `${Math.max(1, Math.round(secs / 60))}m`;
  if (secs < 86400) return `${Math.floor(secs / 3600)}h ${String(Math.floor((secs % 3600) / 60)).padStart(2, "0")}m`;
  return `${Math.floor(secs / 86400)}d ${String(Math.floor((secs % 86400) / 3600)).padStart(2, "0")}h`;
}

const windowName = (m) => (m % 1440 === 0 ? `${m / 1440}d` : m % 60 === 0 ? `${m / 60}h` : `${m}m`);

async function hmeter(args) {
  // Asking both agents takes seconds each; the default timeout would be close.
  const r = await exec(HMETER, args, { timeout: 120000 });
  if (r.code !== 0) throw new Error(r.stderr.trim() || `exit ${r.code}`);
  return JSON.parse(r.stdout);
}

export default class Usage extends View {
  init(_props, cx) {
    this.accounts = [];
    this.failed = null;
    this.shown = "";
    this.width = 268;
    this.height = 0;
    this.ticks = 0;
    this.load(cx, true);
    // Each minute moves the countdowns and rereads; every tenth asks the agents again.
    cx.timer.every(60000, (cx) => this.load(cx, ++this.ticks % REFRESH_EVERY === 0));
  }

  load(cx, refresh) {
    cx.spawn(async (cx) => {
      try {
        this.accounts = await hmeter(refresh ? ["usage", "--refresh", "--json"] : ["usage", "--json"]);
        this.failed = null;
      } catch (e) {
        this.failed = String(e.message ?? e);
      }
      this.redraw(cx);
    });
  }

  rows() {
    const at = now();
    return this.accounts.map((a) => {
      const age = a.updatedAt != null ? at - a.updatedAt : null;
      const limits = a.limits.map((l) => {
        // Past its reset the reported percentage no longer holds.
        const over = l.resetsAt != null && l.resetsAt <= at;
        const name = l.windowMinutes ? windowName(l.windowMinutes) : l.kind.replace(/_/g, " ");
        return {
          // A model's window is told apart by the model; its length repeats the row above.
          name: l.scope ?? name,
          pct: over ? null : Math.round(l.usedPct),
          left: over || l.resetsAt == null ? "" : span(l.resetsAt - at),
        };
      });
      const stale = limits.length > 0 && limits.every((l) => l.pct == null);
      // A session's report stands in when the agent could not be asked; it knows less.
      const note = stale || !limits.length
        ? (age != null ? `last report ${span(age)} ago` : "no report")
        : a.source === "terminal"
          ? `from a session · ${span(age)} ago`
          : age >= 1500 ? `asked ${span(age)} ago` : "";
      return { label: LABELS[a.agent] ?? a.agent, limits: stale ? [] : limits, note };
    });
  }

  // The block is as tall as its rows: a third window or a note changes that.
  fit(rows) {
    // Nothing loaded yet: keep the height the block had instead of collapsing it.
    if (!rows.length) return;
    const lines = rows.reduce((n, r) => n + Math.max(1, r.limits.length + (r.note ? 1 : 0)), 0);
    const height = this.width < 160
      ? 16 + rows.length * 34
      : 16 + 1 + lines * ROW + (rows.length - 1) * 4;
    if (height === this.height) return;
    this.height = height;
    run("layout.resize", { id: "usage", px: height });
  }

  // Redraws repaint the whole window: only when the text would differ.
  redraw(cx) {
    const rows = this.rows();
    this.fit(rows);
    const key = JSON.stringify([rows, this.failed]);
    if (key === this.shown) return;
    this.shown = key;
    cx.notify();
  }

  render() {
    const t = theme();
    const rows = this.rows();
    this.shown = JSON.stringify([rows, this.failed]);
    const narrow = this.width < 160;
    const tone = (pct) => (pct == null ? t.dim : pct >= 80 ? t.blocked : t.muted);
    // Proportional digits differ in width: the terminal font keeps 4h 25m and 6d 04h in columns.
    const mono = settings().font_family;
    const named = rows.some((r) => r.limits.some((l) => l.name.length > 3));
    const nameWidth = named ? 34 : 18;
    // What the fixed columns and gaps leave of the row.
    const bar = Math.max(16, Math.round(this.width) - 28 - 48 - 8 - nameWidth - 30 - 48 - 18);

    const line = (l) =>
      h_flex().h(ROW).gap(6).items_center()
        .child(div().w(nameWidth).flex_none().whitespace_nowrap().text_color(t.dim).child(l.name))
        .child(div().w(bar).h(4).flex_none().rounded(2).bg(t.border)
          .child(div().h(4).rounded(2).w(Math.round((bar * Math.min(l.pct ?? 0, 100)) / 100)).bg(tone(l.pct))))
        .child(div().w(30).flex_none().flex().justify_end().font_family(mono).text_color(tone(l.pct)).child(l.pct == null ? "–" : `${l.pct}%`))
        .child(div().w(48).flex_none().flex().justify_end().whitespace_nowrap().font_family(mono).text_color(t.dim).child(l.left));

    const note = (text) => div().h(ROW).flex().items_center().whitespace_nowrap().text_color(t.dim).child(text);

    const wide = (r) =>
      h_flex().gap(8).items_start()
        .child(div().w(48).h(ROW).flex_none().flex().items_center().text_color(t.foreground).child(r.label))
        .child(v_flex().flex_1().children([...r.limits.map(line), ...(r.note ? [note(r.note)] : [])]));

    // The rail has room for one number: each agent's fullest window.
    const rail = (r) => {
      const pcts = r.limits.map((l) => l.pct).filter((p) => p != null);
      const top = pcts.length ? Math.max(...pcts) : null;
      return v_flex().items_center()
        .child(div().text_size(10).text_color(t.dim).child(r.label[0]))
        .child(div().text_color(tone(top)).child(top == null ? "–" : `${top}`));
    };

    const empty = !rows.length;

    return v_flex().id("root").size_full().bg(t.chrome).border_t(1).border_color(t.border)
      .px(narrow ? 0 : 14).py(8).gap(narrow ? 6 : 4).text_size(11).text_color(t.muted)
      .on_size_change((size, cx) => {
        // The rail and the full sidebar need different heights.
        if ((size.width < 160) !== (this.width < 160)) this.height = 0;
        this.width = size.width;
        this.fit(this.rows());
        cx.notify();
      })
      .when(empty, (el) => el.child(note(this.failed ? `hmeter: ${this.failed}` : "asking…")))
      .children(rows.map(narrow ? rail : wide));
  }
}
