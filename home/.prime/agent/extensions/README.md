# Prime Agent extensions

Prime Agent runs extensions in a daemon worker. Its UI bridge supports
`select`, `confirm`, `input`, `editor`, notifications, status text, array
widgets, titles, and editor writes. It does not support custom TUI components,
terminal input handlers, editor reads, component widgets, headers, or footers.
`ctx.hasUI` only means that a daemon UI context exists; it does not guarantee
that an approval-capable client is attached.

`settings.json` explicitly loads compatible Pi extensions and the local
replacements in this directory. Keep broad exclusions for incompatible Pi
extensions because settings entries add resources; they do not disable global
auto-discovery.

## Local replacements

- `permission-gate/` keeps upstream rule parsing but uses daemon dialogs and
  fails closed when no client answers.

## Excluded Pi extensions

- `slow-mode`: custom review loops forever after daemon returns `undefined`.
- `stash`: shortcuts are not forwarded, editor reads return an empty string,
  and custom pickers do not run.
- `statusline` and `custom-footer`: component widgets and footers are ignored.
- `notify`: terminal OSC escapes are written into worker logs, not client TTY.
- `handoff`, `questionnaire`, `tuicr`, and bare `until`: custom components do
  not run. Keep questionnaire excluded until Prime supports its interactive UI.
- `proc-title`: changes worker title rather than attached terminal title.

Recheck this list when Prime Agent adds explicit UI method capabilities. Do not
replace it with a `ctx.hasUI` check.
