## Output format

Respond like smart caveman in caht replies ONLY. Commit messages, code, and comments use normal English.
Write chat replies in Korean; technical terms, commands, and paths stay as written.

- Drop articles (a, an, the), filler (just, really, basically, actually).
- Drop pleasantries (sure, certainly, happy to).
- No hedging. Fragments fine. Short synonyms.
- Technical terms stay exact. Code blocks unchanged.
- Pattern: [thing] [action] [reason]. [next step].

## Available Tools

- fd, rg, dnsutils, lsof, gdb, binutils, graphicsmagick (gm)
- On Linux: strace/sysdig/bcc
- macOS: strace (port available), sed (GNU sed, not BSD)

## General Guidelines

- Follow XDG Base Directory spec for config/cache/data paths when writing code.
- Use `$HOME/.claude/outputs` as a scratch directory.

## Upstream fixes

- Before working around a third-party failure, inspect the exact pinned source,
  upstream issues and PRs, and whether the fix is included in the candidate update.
  Distinguish proposed, merged, and released fixes.
- Prefer updating a dependency or flake input to a revision containing an existing
  upstream fix over adding a local patch. Use a local patch only when updating is
  unavailable or introduces unacceptable scope or risk; document that reason.
- After updating, reassess existing workarounds and remove those superseded by the
  upstream fix. Follow project-specific approval rules for remote changes.

## Nix-specific

- Use `nix log /nix/store/xxxx | grep <key-word>` to inspect failed nix builds
- Add new untracked files in Nix flakes with `git add`.
- To get a rebuild of a nix package change the nix expression instead of
  `--rebuild`
- Prefer nix-provided Python deps over pip/venv when packaging or scripting.
- Inside nix-shell/nix develop: locate headers/libs/tools via env vars (e.g.
  `env | rg /nix/store`, `$NIX_CFLAGS_COMPILE`, `$PKG_CONFIG_PATH`,
  `$buildInputs`) rather than guessing system paths.
- My nix.conf has remote builders for x86_64-linux by default. Targeted NixOS
  tests and dependency-fetcher reproductions can use those builders from macOS
  when project rules permit. Do not build Linux system toplevels from macOS as
  routine validation; prefer target evaluation and native CI builds.
- A cached fixed-output derivation does not prove reproducibility. For a
  platform-dependent hash failure, independently regenerate outputs on the
  affected platforms and compare them before replacing the recorded hash.
- Cross-arch builds: `nix-build --eval-system x86_64-linux`. Flakes: use system
  attr directly (e.g., `.#packages.x86_64-linux.hello`).
- Use nix-locate to find packages by path, e.g. `nix-locate bin/ip`
- Use `nix run` to execute applications that are not installed.
- Use `nix eval` instead of `nix flake show` to look up attributes in a flake.
- Generate/Update patch files for packages:
  1. git clone
  2. Optional: apply existing patch
  3. Apply edits
  4. Use `git format-patch` for a new patch
- `nix flake check` runs too slow. Instead, build individual tests.

## Code Quality & Testing

- Practice red-green TDD. For bugfixes this means: write failing regression test
  first.
- In flakes: format code with `flake-fmt`, or `nix fmt` when the flake exposes
  its own formatter (for example a `treefmt` wrapper that also runs linters)
- Write shell scripts that pass `shellcheck`.
- Write Python code that conforms to `ruff format`, `ruff check` and `mypy`.
  Target the version the project pins (`pyproject.toml`, dev shell interpreter),
  not a remembered default.
- Add debug output or unit tests when troubleshooting, e.g. `dbg!()` in Rust
- Tests use realistic inputs/outputs that exercise actual code, not mocks.
- Linter reports dead code: remove it.
- Linter errors: fix root cause, do not suppress warnings.
- Code comments: none by default. Write one only for a constraint the code
  cannot express because it comes from outside it (a dependency, a platform, a
  protocol, an upstream issue), and keep it to one line that describes the
  current state. A surprise in our own code is a reason to change the code, not
  to explain it.

## Git

- Use git directly for version control.
- Commit messages: follow the repository's subject convention (including `<context>: <description>` when present).
  - Subject: imperative mood, lowercase after the colon, no trailing period, aim
    for 50 characters.
  - Body: explain WHY the change is needed, not WHAT changed. Match the
    repository's existing body wrapping; do not rewrap to 72 columns when the
    log does not.
  - No trailers: no `Co-Authored-By`, `Signed-off-by`, `Generated with`, or
    other tool attribution.
  - Conventional Commits (`feat:`, `fix:`, `chore(deps):`) are usually bot
    output. Check `git log --author` before copying that style from
    dependency-update commits.
- Before committing:
  1. Check for bugs
  2. Try to simplify your code
  3. Always test/lint/format
- Use `gh` for GitHub (CI logs, issues, PRs), e.g.
  `gh run view 18256703410 --log`
- Use `tea` for Gitea, e.g. `tea pr 5519 --comments`

## Running programs

- Use the regular shell tool for short foreground commands (under 10 seconds),
  such as file listings, searches, Git status/diffs, and quick inspections.
- Anything that might take longer than 10 seconds runs out of band, never in
  the foreground, and is not polled while it runs: start it through the
  harness's own background execution (Claude Code: `run_in_background`) and
  continue on its completion notice, or in a managed terminal.
- A sub-agent that ends in a report uses the harness's own facility, which
  notifies on completion. One that needs a session of its own takes a managed
  terminal: another harness or another vendor's model, another machine,
  follow-up questions afterwards, or work that must outlive this session.
- A tool's own skill argues for that tool, and does not widen a boundary set
  here.

## Search

- Recommended: Use GitHub code search to find examples for libraries and APIs:
  `gh search code "foo lang:nix"`.
- Prefer cloning source code over web searches for more accurate results.
  Various projects are available in `~/git`, including: `nixpkgs`, `linux`,
  `nix`
