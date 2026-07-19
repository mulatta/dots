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

  # git-surgeon ships a skill teaching agents how to use its git primitives.
  home.file.".claude/skills/git-surgeon".source =
    "${aiPkgs.git-surgeon}/share/git-surgeon/skills/git-surgeon";

  # Claude Code reads ~/.claude/skills directly; pi loads it via settings.json.
  home.file.".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";
  home.file.".claude/skills/ctx-agent-history-search/SKILL.md".source =
    "${aiPkgs.ctx.src}/skills/ctx-agent-history-search/SKILL.md";

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
