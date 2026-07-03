{
  inputs,
  self,
  config,
  lib,
  pkgs,
  ...
}:
let
  context = import ./context.nix {
    inherit
      inputs
      config
      lib
      pkgs
      ;
  };

  inherit (context)
    aiPkgs
    calendarCli
    home
    nostoreEnvVar
    nostoreLib
    officecliSkill
    piAgentDeps
    qmd
    skillzPkgs
    system
    ;
in
{
  imports = [
    inputs.skillz.homeModules.default
    ../omp-profiles.nix
  ];

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
      calendar-cli = calendarCli;
    };
  };

  programs.ompProfiles = {
    enable = true;
    package = pkgs.omp-profile;
    backend = "${aiPkgs.omp}/bin/omp";

    profiles = {
      default = {
        agentDir = "${home}/.omp/agent";
        sessionDir = null;
        env.${nostoreEnvVar} = nostoreLib;
      };

      lim = import ./profiles/lim {
        inherit context lib pkgs;
      };
      pim = import ./profiles/pim {
        inherit context lib pkgs;
      };
    };
  };

  home.file = lib.mapAttrs (_: source: { inherit source; }) context.piExtensionFiles // {
    # git-surgeon ships a skill teaching agents how to use its git primitives.
    ".claude/skills/git-surgeon".source = "${aiPkgs.git-surgeon}/share/git-surgeon/skills/git-surgeon";

    # officecli skill for both agents — Claude Code reads ~/.claude/skills,
    # pi discovers ~/.pi/agent/skills.
    ".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";
    ".pi/agent/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";

    ".claude/skills/zat/SKILL.md".text = ''
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
  };

  home.packages =
    (with pkgs; [
      claude-md # dots overlay
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
        ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
        # Extensions are symlinked from dotfiles, so node walk-up misses
        # their npm deps. NODE_PATH points jiti at the prebuilt node_modules.
        export NODE_PATH="${piAgentDeps}/node_modules''${NODE_PATH:+:$NODE_PATH}"
        exec ${aiPkgs.pi}/bin/pi "$@"
      '')
    ];
}
