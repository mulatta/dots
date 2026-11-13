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

  # Flake packages do not inherit the consuming host's nixpkgs configuration.
  qmd = aiPkgs.qmd.override {
    cudaSupport = pkgs.config.cudaSupport or false;
  };

  agentPython = ps: [
    ps.polars
    ps.matplotlib
    ps.requests
    ps.pexpect
    ps.pyelftools
    (bioPkgs.pydna.override { python3Packages = ps; })
    (bioPkgs.biotite.override { python3Packages = ps; })
    ps.primer3-py
    (bioPkgs.dna-features-viewer.override { python3Packages = ps; })
  ];

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

in
{
  imports = [
    inputs.skillz.homeModules.default
  ];

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
    ".claude/skills/git-review".source = "${selfPkgs.maiao}/share/skills/maiao/git-review";
    ".claude/skills/herdr-core".source = "${aiPkgs.herdr-core}/share/skills/herdr-core/herdr-core";
    ".claude/skills/nixbot-cli".source = "${nixbot-cli}/share/skills/nixbot-cli/nixbot-cli";
    ".claude/skills/git-surgeon".source = "${aiPkgs.git-surgeon}/share/skills/git-surgeon/git-surgeon";
    ".claude/skills/officecli".source = "${aiPkgs.officecli}/share/skills/officecli/officecli";
    ".claude/skills/ctx".source = "${pkgs.ctx}/share/skills/ctx/ctx";
  };

  home.packages = [
    qmd
    # herdr-app reaches other machines over SSH and looks for hc on their PATH.
    aiPkgs.herdr-core
    selfPkgs.archify-cli
    selfPkgs.claude-code
    selfPkgs.claude-md
    (pkgs.writeShellApplication {
      name = "pi";
      text = ''
        ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
        exec ${aiPkgs.pi}/bin/pi "$@"
      '';
    })
    aiPkgs.ccstatusline
    selfPkgs.codex
    pkgs.ctx
    aiPkgs.git-surgeon
    aiPkgs.jscpd
    aiPkgs.officecli
    aiPkgs.openspec
    aiPkgs.tuicr
    nixbot-cli
    pkgs.pueue
    pkgs.nushell
    piPython
  ];
}
