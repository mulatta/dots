---
name: loop
description: Run a prompt on a recurring interval, as `/loop <interval> <prompt>` does in Claude Code (e.g. `/loop 1h audit the queue`). Use when a playbook or the user says to arm `/loop`, to poll for status, or to repeat a task on a schedule. Not for a one-off task.
---

# Loop

`/loop <interval> <prompt>` means: send `<prompt>` back to this session every `<interval>`, as a new turn. This harness has no such command, so a terminal beside you sends it.

Start it with your shell tool, from any directory:

```sh
<this skill's folder>/scripts/loop.sh start 1h "<prompt>"
```

The interval is a number with `s`, `m`, or `h`. The script prints the loop's name. A tick that comes due while you are working waits until your turn ends, so ticks never interrupt you.

- `loop.sh list` names this session's loops.
- `loop.sh stop <name>`, or `loop.sh stop all`, ends them.

A loop ends with this session. When the prompt names a playbook or a file, keep the name in the prompt, so each tick re-reads it. When the work the loop watches is done, stop the loop.

The script needs herdr-core: it fails when `HC_TERMINAL_ID` is unset. Then say that the loop could not start, and why.
