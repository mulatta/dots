# OpenKnowledge Nix integration

The wrapper runs an unpackaged Electron app with Nix production resources.
**Do not override Electron's `app.isPackaged` or replace it globally.** Upstream
uses its real value for mutable installers, uninstallers and platform behavior.

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
The shared checks module exposes local packages to CI, including this package.
Which platforms CI builds is controlled separately by nixbot scheduling.
