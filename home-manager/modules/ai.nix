{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  aiTools = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  skillzPkgs = inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system};
  nixbot-cli = inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system}.nixbot-cli;

  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiTools.qmd.override { cudaSupport = true; }
    else
      aiTools.qmd;

  officecliSkill = pkgs.runCommand "officecli-skill-${aiTools.officecli.version}" { } ''
    mkdir -p "$out"
    cp ${aiTools.officecli.src}/SKILL.md "$out/SKILL.md"
  '';
in
{
  imports = [
    inputs.skillz.homeModules.default
    inputs.research-skills.homeModules.default
    ./herdr
  ];

  programs.herdr = {
    enable = true;
    package = aiTools.herdr;
    plugins = [
      selfPkgs.herdr-sesh
      selfPkgs.herdr-autoname
    ];
  };

  xdg.configFile."herdr/autoname-hook.zsh".source = "${selfPkgs.herdr-autoname}/shell/hook.zsh";

  programs.skillz = {
    enable = true;
    skills = [
      "biorefs-cli"
      "calendar-cli"
      "context7-cli"
      "kmap-cli"
      "linkwarden-cli"
      "n8n-cli"
      "pexpect-cli"
      "queue"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = selfPkgs.msmtp-with-sent;
      };
    };
  };

  programs.research-skills = {
    enable = true;
    skills = [
      "biomcp"
      "pymol-cli"
    ];
  };

  home.file = {
    ".claude/skills/archify".source = "${selfPkgs.archify-cli}/share/skills/archify";

    # herdr's Pi integration reports agent state and session metadata.
    ".pi/agent/extensions/herdr-agent-state.ts".source =
      "${aiTools.herdr.src}/src/integration/assets/pi/herdr-agent-state.ts";

    # herdr's official skill exposes pane and workspace orchestration to agents.
    ".claude/skills/herdr/SKILL.md".source = "${aiTools.herdr.src}/SKILL.md";

    # nixbot-cli ships its agent skill alongside the binary.
    ".claude/skills/nixbot-cli".source = "${nixbot-cli}/share/skills/nixbot-cli";

    # git-surgeon ships a skill teaching agents how to use its git primitives.
    ".claude/skills/git-surgeon".source = "${aiTools.git-surgeon}/share/git-surgeon/skills/git-surgeon";

    # officecli ships its skill text in-source and CI keeps it byte-identical to
    # what the binary emits, so source it from officecli.src instead of vendoring
    # a copy that would drift. Pinning to .src version-locks the skill to the
    # binary and keeps the whole source tree out of the profile closure.
    ".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";

    ".claude/skills/ctx-agent-history-search/SKILL.md".source =
      "${aiTools.ctx.src}/skills/ctx-agent-history-search/SKILL.md";

  };

  home.packages = [
    qmd
    selfPkgs.archify-cli
    selfPkgs.claude-code
    selfPkgs.claude-md
    selfPkgs.pim
    (pkgs.writeShellApplication {
      name = "pi";
      text = ''
        ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
        exec ${aiTools.pi}/bin/pi "$@"
      '';
    })
    aiTools.apm
    aiTools.ccstatusline
    aiTools.codex
    aiTools.ctx
    aiTools.git-surgeon
    aiTools.jscpd
    aiTools.officecli
    aiTools.openspec
    aiTools.prime-agent
    aiTools.tuicr
    nixbot-cli
    pkgs.pueue
  ];
}
