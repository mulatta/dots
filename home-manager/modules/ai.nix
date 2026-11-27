{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  aiPkgs = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  hmodsPkgs = inputs.hmods.packages.${pkgs.stdenv.hostPlatform.system};
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  skillzPkgs = inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system};

  # Flake packages do not inherit the consuming host's nixpkgs configuration.
  qmd = aiPkgs.qmd.override {
    cudaSupport = pkgs.config.cudaSupport or false;
  };

  agentPython = pkgs.python3.withPackages (ps: [
    ps.polars
    ps.matplotlib
    ps.requests
    ps.pexpect
    ps.pyelftools
  ]);

  # hmeter files a Codex hook under the hook's HC_TERMINAL_ID. Under Codex's shared
  # app-server daemon every session's hook carries the daemon's terminal instead.
  codex = pkgs.symlinkJoin {
    inherit (aiPkgs.codex) name meta;
    paths = [ aiPkgs.codex ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codex --prefix PATH : ${agentPython}/bin --add-flags "-c daemon_auto_start=false"
    '';
  };

  claude = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [
      aiPkgs.claude-code
      pkgs.bun
    ];
    text = ''
      export SHELL=${pkgs.bashInteractive}/bin/bash
      export PATH="$HOME/.local/bin:$HOME/bin:${agentPython}/bin:$PATH"

      exec claude "$@"
    '';
  };

  nixbot-cli = inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system}.nixbot-cli;

in
{
  imports = [
    inputs.skillz.homeModules.default
  ];

  xdg.configFile."pi-agent-extensions/python/config.json".text = builtins.toJSON {
    python = "${agentPython}/bin/python3";
    prompt = "Includes polars, matplotlib, requests, pexpect, and pyelftools. Python runs with user permissions, outside the shell permission gate.";
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
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = selfPkgs.msmtp-with-sent;
      };
    };
  };

  # gh finds extensions only under its data dir, not on PATH.
  xdg.dataFile."gh/extensions/gh-stack/gh-stack".source = "${pkgs.gh-stack}/bin/gh-stack";

  home.file = {
    # skills
    ".claude/skills/archify".source = "${selfPkgs.archify-cli}/share/skills/archify-cli/archify";
    ".claude/skills/herdr-core".source = "${aiPkgs.herdr-core}/share/skills/herdr-core/herdr-core";
    ".claude/skills/nixbot-cli".source = "${nixbot-cli.src}/skill";
    ".claude/skills/git-surgeon".source = "${aiPkgs.git-surgeon}/share/skills/git-surgeon/git-surgeon";
    ".claude/skills/officecli".source = "${aiPkgs.officecli}/share/skills/officecli/officecli";
    ".claude/skills/gh-stack".source = "${pkgs.gh-stack}/share/skills/gh-stack/gh-stack";
    ".claude/skills/herdr-scene".source = "${hmodsPkgs.hscene}/share/skills/hscene/herdr-scene";

    # pi extensions
    ".pi/agent/extensions/herdr-meter.ts".source =
      "${hmodsPkgs.hmeter}/share/pi/herdr-meter/herdr-meter.ts";
  };

  home.packages = [
    qmd
    aiPkgs.herdr-core
    selfPkgs.archify-cli
    claude
    aiPkgs.pi
    hmodsPkgs.hmeter
    hmodsPkgs.hscene
    codex
    aiPkgs.ctx
    aiPkgs.agent-browser
    aiPkgs.agent-slack
    aiPkgs.git-surgeon
    aiPkgs.jscpd
    aiPkgs.officecli
    aiPkgs.openspec
    aiPkgs.tuicr
    nixbot-cli
    pkgs.nushell
    agentPython
    inputs.rhwp.packages.${pkgs.stdenv.hostPlatform.system}.rhwp-cli
  ];
}
