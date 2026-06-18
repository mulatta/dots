{
  inputs,
  self,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  pi-ext = inputs.pi-agent-extensions;
  aiPkgs = inputs.llm-agents.packages.${system};
  skillzPkgs = inputs.skillz.packages.${system};
  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiPkgs.qmd.override { cudaSupport = true; }
    else
      aiPkgs.qmd;
  piAgentDeps = pkgs.callPackage ../../home/.pi/agent/default.nix { };

  # officecli ships its skill text in-source and CI keeps it byte-identical to
  # what the binary emits, so source it from officecli.src instead of vendoring
  # a copy that would drift. Pinning to .src version-locks the skill to the
  # binary and keeps the whole source tree out of the profile closure.
  officecliSkill = pkgs.runCommand "officecli-skill-${aiPkgs.officecli.version}" { } ''
    mkdir -p "$out"
    cp ${aiPkgs.officecli.src}/SKILL.md "$out/SKILL.md"
  '';
  nostorePreload = pkgs.nostore-preload;
  nostoreEnvVar = nostorePreload.passthru.envVar;
  nostoreLib = "${nostorePreload}/lib/libnostore${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
in
{
  imports = [ inputs.skillz.homeModules.default ];

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
      "vikunja-cli"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = pkgs.msmtp-with-sent;
      };
    };
  };

  home.file.".pi/agent/extensions/direnv.ts".source = "${pi-ext}/direnv/index.ts";
  home.file.".pi/agent/extensions/questionnaire.ts".source = "${pi-ext}/questionnaire/index.ts";
  home.file.".pi/agent/extensions/slow-mode.ts".source = "${pi-ext}/slow-mode/index.ts";
  home.file.".pi/agent/extensions/notify.ts".source = "${pi-ext}/notify/index.ts";
  home.file.".pi/agent/extensions/stash".source = "${pi-ext}/stash";
  home.file.".pi/agent/extensions/statusline".source = "${pi-ext}/statusline";

  # git-surgeon ships a skill teaching agents how to use its git primitives.
  home.file.".claude/skills/git-surgeon".source =
    "${aiPkgs.git-surgeon}/share/git-surgeon/skills/git-surgeon";

  # officecli skill for both agents — Claude Code reads ~/.claude/skills,
  # pi discovers ~/.pi/agent/skills.
  home.file.".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";
  home.file.".pi/agent/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";

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

  home.packages =
    (with pkgs; [
      claude-md # dots overlay
      pim # dots overlay
      pueue
    ])
    ++ [
      self.packages.${system}.claude-code # custom wrapper, flake package output
      qmd # local binding; CUDA-grafted on GPU hosts
      skillzPkgs.biorefs-cli
      aiPkgs.apm
      aiPkgs.ccstatusline
      aiPkgs.codex
      aiPkgs.gemini-cli
      aiPkgs.git-surgeon
      aiPkgs.officecli
      aiPkgs.tuicr
      aiPkgs.workmux
      aiPkgs.zat
      (pkgs.writeShellScriptBin "pi" ''
        # Block readdir(/nix/store) for the agent and its children; exported
        # before pueued so queued tasks inherit it too.
        export ${nostoreEnvVar}="${nostoreLib}''${${nostoreEnvVar}:+:${"$"}${nostoreEnvVar}}"
        ${pkgs.pueue}/bin/pueued -d 2>/dev/null || true
        # Extensions are symlinked from dotfiles, so node walk-up misses
        # their npm deps. NODE_PATH points jiti at the prebuilt node_modules.
        export NODE_PATH="${piAgentDeps}/node_modules''${NODE_PATH:+:$NODE_PATH}"
        exec ${aiPkgs.pi}/bin/pi "$@"
      '')
    ];
}
