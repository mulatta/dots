{
  lib,
  pkgs,
  llmAgents,
  ...
}:
let
  inherit (llmAgents) aiPkgs skillzPkgs;

  # officecli ships its skill text in-source and CI keeps it byte-identical to
  # what the binary emits, so source it from officecli.src instead of vendoring
  # a copy that would drift. Pinning to .src version-locks the skill to the
  # binary and keeps the whole source tree out of the profile closure.
  officecliSkill = pkgs.runCommand "officecli-skill-${aiPkgs.officecli.version}" { } ''
    mkdir -p "$out"
    cp ${aiPkgs.officecli.src}/SKILL.md "$out/SKILL.md"
  '';
in
{
  programs.skillz = {
    enable = true;
    skills = [
      "biorefs-cli"
      "buildbot-pr-check"
      "calendar-cli"
      "context7-cli"
      "crwl-cli"
      "drawio-cli"
      "kmap-cli"
      "linkwarden-cli"
      "n8n-cli"
      "pexpect-cli"
      "pymol-cli"
      "vikunja-cli"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = pkgs.msmtp-with-sent;
      };
    };
  };

  home.file.".claude/skills/archify".source = "${pkgs.archify-cli}/share/skills/archify";

  # git-surgeon ships a skill teaching agents how to use its git primitives.
  home.file.".claude/skills/git-surgeon".source =
    "${aiPkgs.git-surgeon}/share/git-surgeon/skills/git-surgeon";

  # Claude Code reads ~/.claude/skills directly; pi loads it via settings.json.
  home.file.".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";
  home.file.".claude/skills/ctx-agent-history-search/SKILL.md".source =
    "${aiPkgs.ctx.src}/skills/ctx-agent-history-search/SKILL.md";

  home.file.".claude/skills/jj-forklift/SKILL.md".text = ''
    ---
    name: jj-forklift
    description: Use when working with jj-forklift stacked PRs, explaining its 1 jj change = 1 PR model, or running forklift submit/sync/get/merge/pr/unfreeze workflows in a Jujutsu repository.
    ---

    Use `jj` for stack editing and `forklift` for GitHub PR operations.

    Core model:
    - One jj change maps to one GitHub PR.
    - Stacked PR order follows the linear jj change stack from trunk to `@`.
    - Bottom PR targets trunk; each higher PR targets the branch for the change below it.
    - Multi-commit PR ranges are not the native model. Put related edits in one jj change or split them into separate changes.

    Before operations:
    - Run `jj log` or `jj status` to understand current stack.
    - Run `forklift --help` or subcommand `--help` when flags are unclear.
    - Ensure `gh` is authenticated when network/GitHub operations are needed.
    - Before mutating GitHub or trunk, run `forklift status --dry-run --verbose` to verify resolved config, trunk, tracked stack, PR bases, and planned actions.
    - Prefer `forklift submit --dry-run`, `forklift sync --dry-run --current`, or `forklift merge --dry-run <target>` before the real command.

    Common workflow:
    ```bash
    jj new <base>
    jj describe
    forklift submit
    forklift sync
    forklift merge
    ```

    Command guidance:
    - `forklift submit`: create or update PRs for current stack.
    - `forklift sync`: fetch/rebase tracked stacks onto trunk. Add `--submit` to submit after syncing.
    - `forklift get <target>`: import an existing stack by PR number, PR URL, branch, or change-id prefix.
    - `forklift merge`: land stack by fast-forwarding trunk; no merge queue.
    - `forklift pr`: open current PR.
    - `forklift status`: show tracked stacks and PR state.
    - `forklift track <target>`: adopt an existing branch and open PR into forklift tracking.
    - `forklift repair <target>`: rebuild bookmarks and cache for a stack.
    - `forklift ui`: open `jjui` filtered to tracked stacks.
    - `forklift unfreeze <target>`: turn a frozen dependency back into an owned, editable change.

    Conflict/collaboration rules:
    - Preserve both trunk/collaborator changes and local changes.
    - Imported or collaborator-owned changes are frozen; do not mutate frozen revisions unless explicitly unfreezing.
    - If stack shape or ownership is unclear, inspect before acting and ask for guidance before destructive operations.
  '';

  home.file.".claude/skills/zat/SKILL.md".text = ''
    ---
    name: zat
    description: Code outline viewer showing exported symbol signatures with line numbers. Use when you need signatures, not full implementation.
    ---

    Prefer `zat` over `cat`/`Read` when you need signatures, not full implementation. Use the line numbers in the output to `Read(offset, limit)` into specific sections.

    Supported languages: C, C++, C#, Go, Haskell, Java, JavaScript, Kotlin, Markdown, Python, Ruby, Rust, Swift, TypeScript/TSX

    ```
    zat <FILE>
    ```
  '';
}
