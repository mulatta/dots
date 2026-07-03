{
  context,
  lib,
  pkgs,
}:
let
  inherit (context)
    commonProfileExtensions
    home
    piAgentDeps
    skillzPkgs
    ;

  toolPackages = [
    skillzPkgs.biorefs-cli
    skillzPkgs.paperfetch-cli
    skillzPkgs.zhost-cli
    skillzPkgs.crwl-cli
    pkgs.rbw
    pkgs.pueue
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.jq
    pkgs.findutils
    pkgs.bashInteractive
    pkgs.ncurses
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [
    pkgs.bubblewrap
    pkgs.util-linux
  ];

  stateDirs = [
    "${home}/.cache/biorefs-cli"
    "${home}/.cache/lim"
    "${home}/.cache/paperfetch-cli"
    "${home}/.cache/zhost-cli"
    "${home}/.claude/outputs"
    "${home}/.config/biorefs-cli"
    "${home}/.config/lim"
    "${home}/.config/paperfetch-cli"
    "${home}/.config/zhost-cli"
    "${home}/.local/share/lim"
  ];
in
{
  commands = [ "lim" ];
  inherit toolPackages;
  skillPackages = [
    skillzPkgs.biorefs-cli
    skillzPkgs.paperfetch-cli
    skillzPkgs.zhost-cli
    skillzPkgs.crwl-cli
  ];
  includeSkills = [
    "biorefs-cli"
    "paperfetch-cli"
    "zhost-cli"
    "crwl-cli"
  ];
  enabledTools = [
    "read"
    "bash"
    "grep"
    "glob"
    "ask"
  ];
  extensions = commonProfileExtensions;
  env.NODE_PATH = "${piAgentDeps}/node_modules";
  prompt.text = builtins.readFile ./prompt.md;
  ensureDirs = stateDirs;
  config.tools = {
    approvalMode = "always-ask";
    approval = {
      read = "allow";
      grep = "allow";
      glob = "allow";
      ask = "allow";
      bash = "prompt";
      web_search = "prompt";
      browser = "prompt";
      task = "prompt";
      write = "prompt";
      edit = "prompt";
    };
  };
  sandbox = {
    linuxBubblewrap = pkgs.stdenv.isLinux;
    rw = stateDirs;
    ro = [ "${home}/.config/rbw" ];
  };
}
