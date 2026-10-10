{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  aiPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  bioPkgs = inputs.bioinformatics-toolkits.packages.${pkgs.stdenv.hostPlatform.system};
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  skillzPkgs = inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system};
  installAgentSkills = pkgs.installAgentSkills;

  agentPython = ps: [
    ps.polars
    ps.matplotlib
    ps.requests
    ps.pexpect
    ps.pyelftools
    (bioPkgs.pydna.override { python3Packages = ps; })
    (bioPkgs.biotite.override { python3Packages = ps; })
    (bioPkgs.primer3-py.override { python3Packages = ps; })
  ];

  primeAgent = aiPkgs.prime-agent.override {
    extraPythonPackages = agentPython;
  };

  piPython = pkgs.python3.withPackages agentPython;

  nixbot-cli =
    inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system}.nixbot-cli.overrideAttrs
      (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installAgentSkills ];
        dontInstallAgentSkills = true;
        postInstall = (old.postInstall or "") + ''
          chmod -R u+w "$out/share/skills/nixbot-cli"
          rm -rf "$out/share/skills/nixbot-cli"
          skillDir=$(mktemp -d)
          cp -r ${old.src}/skill "$skillDir/nixbot-cli"
          installSkill "$skillDir/nixbot-cli" nixbot-cli
        '';
      });

  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiPkgs.qmd.override { cudaSupport = true; }
    else
      aiPkgs.qmd;

in
{
  imports = [
    inputs.skillz.homeModules.default
    ./herdr
  ];

  programs.herdr = {
    enable = true;
    package = aiPkgs.herdr;
    plugins = [
      selfPkgs.herdr-sesh
      selfPkgs.herdr-autoname
    ];
  };

  xdg.configFile."herdr/autoname-hook.zsh".source = "${selfPkgs.herdr-autoname}/shell/hook.zsh";
  xdg.configFile."pi-agent-extensions/python/config.json".text = builtins.toJSON {
    python = "${piPython}/bin/python3";
    prompt = "Includes polars, matplotlib, requests, pexpect, pyelftools, pydna, biotite, and primer3. Python runs with user permissions, outside the shell permission gate.";
  };

  programs.skillz = {
    enable = true;
    skillDirs = [ ".claude/skills" ];
    skills = [
      "biorefs-cli"
      "calendar-cli"
      "context7-cli"
      "kmap-cli"
      "linkwarden-cli"
      "queue"
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = selfPkgs.msmtp-with-sent;
      };
    };
  };

  home.file = {
    ".claude/skills/archify".source = "${selfPkgs.archify-cli}/share/skills/archify-cli/archify";
    ".claude/skills/biomcp".source = "${bioPkgs.biomcp}/share/skills/biomcp/skills";
    ".claude/skills/git-review".source = "${selfPkgs.maiao}/share/skills/maiao/git-review";
    ".pi/agent/extensions/herdr-agent-state.ts".source =
      "${aiPkgs.herdr}/share/herdr/integrations/pi/herdr-agent-state.ts";
    ".claude/skills/herdr".source = "${aiPkgs.herdr}/share/skills/herdr/herdr";
    ".claude/skills/nixbot-cli".source = "${nixbot-cli}/share/skills/nixbot-cli/nixbot-cli";
    ".claude/skills/git-surgeon".source = "${aiPkgs.git-surgeon}/share/skills/git-surgeon/git-surgeon";
    ".claude/skills/officecli".source = "${aiPkgs.officecli}/share/skills/officecli/officecli";
    ".claude/skills/ctx".source = "${aiPkgs.ctx}/share/skills/ctx/ctx";
    ".claude/skills/agent-slack".source = "${aiPkgs.agent-slack}/share/skills/agent-slack/agent-slack";

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
        exec ${aiPkgs.pi}/bin/pi "$@"
      '';
    })
    aiPkgs.agent-slack
    aiPkgs.ccstatusline
    aiPkgs.codex
    aiPkgs.ctx
    aiPkgs.git-surgeon
    aiPkgs.jscpd
    aiPkgs.officecli
    aiPkgs.openspec
    (pkgs.writeShellApplication {
      name = "pa";
      text = ''
        ${pkgs.pueue}/bin/pueued -d > /dev/null 2>&1 || true
        exec ${primeAgent}/bin/prime-agent "$@"
      '';
    })
    aiPkgs.tuicr
    bioPkgs.biomcp
    nixbot-cli
    pkgs.pueue
    pkgs.nushell
    piPython
  ];
}
