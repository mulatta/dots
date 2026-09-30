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
  installAgentSkills = pkgs.installAgentSkills;

  herdr = aiTools.herdr.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installAgentSkills ];
    dontInstallAgentSkills = true;
    postInstall = (old.postInstall or "") + ''
      installSkill skills/herdr herdr
    '';
  });

  git-surgeon = aiTools.git-surgeon.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installAgentSkills ];
    dontInstallAgentSkills = true;
    postInstall = (old.postInstall or "") + ''
      installSkill skills/git-surgeon git-surgeon
    '';
  });

  ctx = aiTools.ctx.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installAgentSkills ];
    dontInstallAgentSkills = true;
    postInstall = (old.postInstall or "") + ''
      installSkill skills/ctx ctx
    '';
  });

  officecli = aiTools.officecli.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ installAgentSkills ];
    dontInstallAgentSkills = true;
    postInstall = (old.postInstall or "") + ''
      installSkill skills/officecli officecli
    '';
  });

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
      aiTools.qmd.override { cudaSupport = true; }
    else
      aiTools.qmd;

in
{
  imports = [
    inputs.skillz.homeModules.default
    inputs.research-skills.homeModules.default
    ./herdr
  ];

  programs.herdr = {
    enable = true;
    package = herdr;
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
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "shortcuts-cli" ];
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
    ".claude/skills/archify".source = "${selfPkgs.archify-cli}/share/skills/archify-cli/archify";
    ".claude/skills/open-knowledge-discovery".source =
      "${selfPkgs.openknowledge}/share/skills/openknowledge/discovery";
    ".claude/skills/git-review".source = "${selfPkgs.maiao}/share/skills/maiao/git-review";
    ".pi/agent/extensions/herdr-agent-state.ts".source =
      "${herdr}/share/herdr/integrations/pi/herdr-agent-state.ts";
    ".claude/skills/herdr".source = "${herdr}/share/skills/herdr/herdr";
    ".claude/skills/nixbot-cli".source = "${nixbot-cli}/share/skills/nixbot-cli/nixbot-cli";
    ".claude/skills/git-surgeon".source = "${git-surgeon}/share/skills/git-surgeon/git-surgeon";
    ".claude/skills/officecli".source = "${officecli}/share/skills/officecli/officecli";
    ".claude/skills/ctx".source = "${ctx}/share/skills/ctx/ctx";

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
    ctx
    git-surgeon
    aiTools.jscpd
    officecli
    aiTools.openspec
    aiTools.prime-agent
    aiTools.tuicr
    nixbot-cli
    pkgs.pueue
  ];
}
