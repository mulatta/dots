// Prefix bindings that take more than one app command, delivered as "prefix.<command>"
// from keys.json. It lives in an empty layout block, so a key costs no mod start.
//
// go-left/down/up/right: from a zoomed tab, zoom the neighbor instead, as the herdr tui did.
// scratch, tuicr: a terminal in the focused folder, on the space's machine, shown as a
// popup that closes when its program exits. The same key shows it again while it runs.
// worktree: the New worktree dialog for the active space; mod.open cannot pass it props.

import { View, div } from "gpui-kit";
import { nextCommand, focused, panes, spaces, run, hc, openOverlay, closeOverlay } from "herdr";

const POPUP_BLOCK = "prefix-popup";
const POPUPS = {
  scratch: { argv: ["sh", "-c", 'exec "${SHELL:-sh}"'], width: 0.8, height: 0.7 },
  tuicr: { argv: ["sh", "-c", "tuicr --no-update-check -w || tuicr --no-update-check"], width: 0.9, height: 0.85 },
};

export default class Prefix extends View {
  init(_props, cx) {
    this.popups = {}; // popup name -> { address, overlay }
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        try {
          if (command.startsWith("go-")) this.go(command.slice(3), cx);
          else if (command === "worktree") this.worktree();
          else if (command in POPUPS) await this.popup(command);
        } catch (e) {
          console.log(`prefix ${command}: ${e.message ?? e}`);
        }
      }
    });
  }

  go(direction, cx) {
    const from = panes().find((p) => p.focused);
    const tab = spaces().find((s) => s.active)?.tabs.find((t) => t.active);
    if (!from || (!from.zoomed && !tab?.zoomed)) return run("pane.go", { direction });
    // A zoomed tab shows one pane, so pane.go has nowhere to go: unzoom, move, then zoom
    // where it landed (back where it was when there is nothing that way). Each step waits,
    // a frame at a time, for the previous one to land; sent together, the move still sees
    // one pane.
    run("pane.zoom", { pane: from.pane });
    this.until(cx, () => !panes().some((p) => p.zoomed), (cx) => {
      run("pane.go", { direction });
      this.until(cx, () => focused()?.pane !== from.pane, () => run("pane.zoom", { pane: focused()?.pane ?? from.pane }), 6);
    });
  }

  worktree() {
    const space = spaces().find((s) => s.active);
    if (!space) return;
    openOverlay({ mod: "worktree", kind: "dialog", width: 460, height: 280, props: { space: space.id, folder: focused()?.cwd, action: "new" } });
  }

  // Runs `then` once `ready()` holds, checking every frame, or anyway after `frames` frames.
  until(cx, ready, then, frames = 12) {
    if (ready() || frames <= 0) return then(cx);
    cx.timer.after(16, (cx) => this.until(cx, ready, then, frames - 1));
  }

  async popup(name) {
    const spec = POPUPS[name];
    const open = this.popups[name];
    if (open) {
      // Focused means shown: the key hides it. Hidden but running (a click beside the
      // dialog closes it, not its program): show it again.
      const f = focused();
      if (f?.terminal === open.address || f?.pane === POPUP_BLOCK) return closeOverlay(open.overlay);
      if (await this.alive(open.address)) return this.show(open, spec);
      delete this.popups[name];
    }
    const here = focused();
    const on = spaces().find((s) => s.active)?.machine ?? null;
    const args = ["run", "--bg", "--no-notify", "--rm", "--json"];
    if (on) args.push("--on", on);
    if (here?.cwd) args.push("--cwd", here.cwd);
    const r = await hc([...args, "--", ...spec.argv]);
    if (r.code !== 0) throw new Error(r.stderr || r.stdout);
    this.popups[name] = { address: JSON.parse(r.stdout).address, overlay: null };
    this.show(this.popups[name], spec);
  }

  async alive(address) {
    const r = await hc(["get", address, "--json"]);
    return r.code === 0 && JSON.parse(r.stdout).state === "live";
  }

  show(open, spec) {
    open.overlay = openOverlay({ layout: { id: POPUP_BLOCK, type: "block", content: { terminal: open.address } }, kind: "dialog", width: spec.width, height: spec.height });
  }

  render() {
    return div().size_0();
  }
}
