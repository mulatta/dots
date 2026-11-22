## Output format

Chat replies are in Korean, and so are the one-line notes between tool calls.
Drift starts in those notes: after long English tool output or commit messages,
one note slips into English and the final report follows it.
Commit messages, code, and comments are in English.
Prose follows the `unslop` skill, chat replies included. Read `~/.claude/skills/unslop/SKILL.md` before the first reply of a session.

## Available Tools

- fd, rg
- On macOS, treat these tools as GNU compatible: coreutils such as `date` and `stat`, sed, grep, awk, find, xargs, diff, tar, and make.

## General Guidelines

- Follow XDG Base Directory spec for config/cache/data paths when writing code.
- Use `$HOME/.claude/outputs` as a scratch directory.

## Upstream fixes

- A third-party failure → the `upstream-triage` skill before any workaround.
- Prefer updating a dependency or flake input to a revision containing the fix
  over a local patch. Use a local patch only when updating is unavailable or
  brings unacceptable scope or risk, and record that reason with the patch.
- Prefer a supported mechanism the tool already has over a parallel one.
- After an update, remove the workarounds it supersedes. Follow
  project-specific approval rules for remote changes.

## Nix-specific

- Prefer nix-provided Python deps over pip/venv when packaging Python.
- My nix.conf has remote builders for x86_64-linux by default. Targeted NixOS
  tests and dependency-fetcher reproductions can use those builders from macOS
  when project rules permit.
- Use nix-locate to find packages by path, e.g. `nix-locate bin/ip`
- Use `nix run` to execute applications that are not installed.

## Code Quality & Testing

- Practice red-green TDD. For bugfixes this means: write failing regression test
  first.
- Write scripts in TypeScript run by bun, using only bun built-ins and `node:`
  modules, checked with `tsc --strict` and `bun test`. Shell is for short
  glue that only calls other commands, and passes `shellcheck`.
- In a Python project, write code that conforms to `ruff format`, `ruff check`
  and `mypy`. Target the version the project pins (`pyproject.toml`, dev shell
  interpreter), not a remembered default.
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
- PR descriptions, issues, and comments carry no tool attribution and no
  report of the agent's own status.
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
  Various projects are available in `~/git`.
