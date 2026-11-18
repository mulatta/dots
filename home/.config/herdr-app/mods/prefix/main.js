// Prefix bindings that take more than one app command, delivered as "prefix.<command>"
// from keys.json. It lives in an empty layout block, so a key costs no mod start.
//
// go-left/down/up/right: from a zoomed tab, zoom the neighbor instead, as the herdr tui did.
// scratch, tuicr: a terminal in the focused folder, on the space's machine, attached to the
// focused session and peeked over its tab (keep promotes it to a pane). The same key
// shows it again while it runs, and hides it from inside the peek. Over an agent, tuicr
// exports to stdout and the popup sends that review to the agent as its next message;
// over a plain shell, pasting markdown would run it, so tuicr keeps its clipboard export.
// worktree: the New worktree dialog for the active space; mod.open cannot pass it props.

import { View, div } from "gpui-kit";
import { nextCommand, focused, panes, spaces, terminals, agents, run, hc, openOverlay } from "herdr";

const LABEL = "prefix.popup";
const ADOPT_POLL = 50;
const ADOPT_TIMEOUT = 5000;
const POPUPS = {
  scratch: { argv: ["sh", "-c", 'exec "${SHELL:-sh}"'] },
  tuicr: {
    argv: ["sh", "-c", "tuicr --no-update-check -w || tuicr --no-update-check"],
    // $1 is the agent's terminal. `-w` fails at startup when the tree is clean, so the
    // fallback opens the commit selector. An empty export (quit without comments) sends nothing.
    agentArgv: (agent) => [
      "sh",
      "-c",
      'out=$(tuicr --no-update-check -w --stdout || tuicr --no-update-check --stdout) && [ -n "$out" ] && exec hc send "$1" "$out"',
      "sh",
      agent,
    ],
  },
};

export default class Prefix extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        try {
          if (command.startsWith("go-")) this.go(command.slice(3), cx);
          else if (command === "worktree") this.worktree();
          else if (command in POPUPS) await this.popup(command, cx);
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

  // One popup terminal per name per session: a child of the focused terminal, found again
  // by its label and parent, so it ends with that session and survives a mod reload.
  async popup(name, cx) {
    const spec = POPUPS[name];
    const here = focused();
    if (!here?.terminal) return;
    const all = terminals();
    const mine = (t) => t.state === "live" && t.labels?.[LABEL] === name;
    // The key from inside its own peek hides it.
    if (all.some((t) => t.address === here.terminal && mine(t))) return run("overlay.close", {});
    const open = all.find((t) => mine(t) && t.parent === here.terminal);
    if (open) return run("terminal.peek", { terminal: open.address });
    const on = spaces().find((s) => s.active)?.machine ?? null;
    // The core wants the parent's id on its own machine, without the machine prefix.
    const parent = on && here.terminal.startsWith(`${on}/`) ? here.terminal.slice(on.length + 1) : here.terminal;
    const args = ["run", "--bg", "--no-notify", "--rm", "--json", "--parent", parent, "--label", `${LABEL}=${name}`];
    if (on) args.push("--on", on);
    if (here.cwd) args.push("--cwd", here.cwd);
    const agent = agents().some((a) => a.address === here.terminal);
    const argv = agent && spec.agentArgv ? spec.agentArgv(parent) : spec.argv;
    const r = await hc([...args, "--", ...argv]);
    if (r.code !== 0) throw new Error(r.stderr || r.stdout);
    const address = JSON.parse(r.stdout).address;
    // Peek fails until the window's next terminal listing includes the child, which can
    // take seconds when the core is busy or the space is on another machine.
    for (let waited = 0; waited < ADOPT_TIMEOUT && !terminals().some((t) => t.address === address); waited += ADOPT_POLL) {
      await cx.sleep(ADOPT_POLL);
    }
    run("terminal.peek", { terminal: address });
  }

  render() {
    return div().size_0();
  }
}
