# OpenKnowledge Nix integration

The wrapper runs an unpackaged Electron app with Nix production resources.
**Do not override Electron's `app.isPackaged` or replace it globally.** Upstream
uses its real value for mutable installers, uninstallers and platform behavior.

## Agent runtimes

The package accepts `piSupport`, `claudeSupport`, and `codexSupport` (all false
by default), plus `extraPackages` for tools on the CLI and Desktop runtime
`PATH`. Dots enables all three and supplies adapters from `llm-agents.nix`:

```nix
pkgs.callPackage ./openknowledge {
  inherit (llmAgents) pi pi-acp claude-code claude-agent-acp codex codex-acp;
  piSupport = true;
  claudeSupport = true;
  codexSupport = true;
}
```

Enabled providers add their CLI and ACP adapter to the runtime PATH for discovery
and terminal launches. Registry agents use the corresponding immutable Nix ACP
adapter before any registry distribution is acquired. The adapters already wrap their Nix CLI
runtimes. A broken local adapter fails rather than silently downloading another
copy. Disabled and unknown agents retain upstream acquisition behavior. CLI and
Desktop share the same compiled runtime selection through the `desktop` output.

The managed Unix MCP launcher retains its ownership marker and invokes this
package's CLI directly, without relying on a GUI application's inherited PATH,
standard app bundle layout, or npx. Existing editor entries must be refreshed
through OpenKnowledge's connection setup after installing this package; no
activation script rewrites mutable editor configuration or restarts agents.

`runtime.patch` is a downstream Nix integration, not a pending upstream bugfix.
Both v0.86.16 and upstream main at
`5bcbbe91361aaf6dd139e951a944f3a3a34e5004` acquire registry distributions and
generate standard bundle/npx MCP launch chains without Nix runtime selection.
Updating alone does not supply this integration. Recheck these paths on updates.

`agentCommands` assigns a path or null to each provider directly from its support
flag. `postPatch` fills that table and the MCP CLI path into `runtime.patch`, then
applies the rendered patch with `--batch --forward --fuzz=0`. There is no generated helper
module or second pass over patched TypeScript. Package arguments are supplied by
the caller; support flags alone decide which runtimes enter the output.

This patch depends on upstream internals, not a stable extension API. Full hunk
context is required; offsets are allowed, fuzzy matching and automatic reversal
are not. An upstream
semantic change can still apply cleanly, so successful patching alone is not
validation. Review the registry resolver and managed-launcher ownership paths
on every update, and retain the behavioral tests.

## Update policy

- `desktop.patch` keeps the small CLI, locale, spawn, profile and updater
  overrides, plus the selected main-process production-runtime wiring.
- `postPatch` replaces only the repeated renderer and DevTools expressions in
  `index.ts`. Exact, fail-closed replacements avoid dependency on adjacent menu
  code. Moving a policy to another file or changing its meaning still needs
  review. Never use `--replace-warn` to make an update pass.
- `pin-rust-toolchain.mjs` parses upstream TOML using the locked `smol-toml`
  dependency. It selects Nix's Rust version while preserving other TOML values
  and the upstream exact-version guard. Compilation still checks compatibility;
  an upstream channel bump alone does not require a packaging edit.
- `nix-policy.test.ts` runs after compilation during every package build. It
  tests Rust normalization, CLI/path/locale/spawn helpers, forced updater
  inactivity and the DevTools gate. Main-process wiring has source assertions
  because importing `index.ts` would boot Electron. These are not GUI tests or
  proof against arbitrary future indirect changes to Electron's state.

Validate an update with `nix build .#openknowledge --no-link -L` on the native
platform, and separately apply `desktop.patch` to clean upstream sources with
`patch --batch --fuzz=0 -p1`. Offset-only movement does not require refreshing the
patch. Do not loosen policy assertions or drop failed hunks merely to build.
`nix-runtime.test.ts` additionally exercises package-selected registry launches,
unknown/prototype-key handling, cancelled preparation, executable availability,
managed MCP entry recognition, and execution of the generated shell chain without
npx. These are not authenticated agent sessions.
The shared checks module exposes local packages to CI, including this package.
Which platforms CI builds is controlled separately by nixbot scheduling.
