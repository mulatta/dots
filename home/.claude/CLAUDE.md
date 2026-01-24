## Communication

- Respond in Korean
- Be concise. Technical content only (no greetings/praise)
- Code comments, parameter names, CLI help in English
- Always explain WHY (reasoning behind decisions, how things work)
- Ask clarifying questions when uncertain (never assume)
- Prefer table format for summaries
- **CRITICAL**: Investigate → discuss → implement, strictly in order. Never implement directly.

## Work Style

- Always assess current state before implementing (code, config, logs)
- Present trade-off comparison tables when choices exist
- Always provide test/verification methods alongside solutions
- Immediately warn on security concerns (tokens, keys, access)

## General Guidelines

- No over-abstraction/wrapping. Prefer simple, direct code
- Prefer integrating into existing files over creating new ones
- No silent failures. Report errors explicitly
- Remove dead code on sight
- Use `$HOME/.claude/outputs` as scratch directory

## Available Tools

- fd, rg, sd, jq, tree, ast-grep, nix-locate, just

## CRITICAL: Version Control - Jujutsu ONLY

- **Never use git commands** (except jj git interop)
- Check state with `jj status`, `jj log`, `jj diff`
- Commit with `jj describe -m "msg"`
- Start new changes with `jj new`
- push/fetch requires user approval

## CRITICAL: Running Programs

- **Use pueue for ANY command that might take longer than 10 seconds**:
  ```bash
  pueue add -- 'command args'
  pueue wait <id> && pueue log <id>
  ```
- Applies to: nix build, nix flake check, cargo build/test, colmena apply, merge-when-green

## Nix Development

- **Always use flake-parts** for flake structure (perSystem, systems, imports)
- Inspect failed builds with `nix log /nix/store/xxx | grep <keyword>`
- New files in flakes: `jj file track <path>` or verify snapshot with `jj status` before building
- Prefer `nix eval` over `nix flake show` (faster)
- Find packages by path: `nix-locate bin/<name>` (e.g., `nix-locate bin/ip`)
- Run uninstalled apps with `nix run`
- `nix flake check` is slow — verify with individual builds instead
- Keep overlays minimal (single package, minimize unstable deps)
- Cross-arch: `nix-build --eval-system x86_64-linux` or `.#packages.x86_64-linux.hello`
- NixOS modules: prefer simple directly-importable modules over option/config wrapping
- Patches: git clone → edit → `git format-patch`

## Code Quality

- Start bug fixes with a failing regression test
- Use realistic inputs/outputs in tests (minimize mocks)
- Address root cause of lint errors (never suppress)
- Run format/lint/test before committing
- Commit messages: focus on WHY, conventional commits format

## Search (investigation phase)

- Local search first: rg, fd, ast-grep → reference ~/git (nixpkgs, linux, etc.)
- `gh search code "keyword lang:nix"` for library/API usage examples
- Use DeepWiki for understanding principles/architecture

## CRITICAL: Secrets Management

- clan + sops (age encryption)
- Never expose secret values in stdout/logs — pass via piping only
- Use only `sops -d file.yaml | command` pattern
