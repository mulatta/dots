{
  context,
  lib,
  pkgs,
}:
let
  inherit (context)
    calendarCli
    commonProfileExtensions
    home
    piAgentDeps
    skillzPkgs
    ;

  recentEmailsPython = pkgs.writeText "pim-recent-emails.py" (builtins.readFile ./recent-emails.py);
  recentEmails = pkgs.writeShellScript "pim-recent-emails" ''
    set -eu
    nonce="$(${pkgs.coreutils}/bin/date +%s%N)"
    if email_json="$(${pkgs.notmuch}/bin/notmuch search --format=json --limit=10 \
      'date:7days.. AND NOT tag:trash AND NOT folder:"mulatta/Junk Mail"' 2>/dev/null)"; then
      export PIM_EMAIL_JSON="$email_json"
      unset PIM_EMAIL_ERROR || true
    else
      export PIM_EMAIL_JSON=""
      export PIM_EMAIL_ERROR=1
    fi
    ${pkgs.python3}/bin/python3 ${recentEmailsPython} "$nonce"
  '';

  toolPackages = [
    calendarCli
    skillzPkgs.crabfit-cli
    pkgs.vdirsyncer
    pkgs.todoman
    pkgs.notmuch
    pkgs.afew
    pkgs.mblaze
    pkgs.msmtp-with-sent
    pkgs.n8n-hooks
    skillzPkgs.miniflux-cli
    skillzPkgs.vikunja-cli
    skillzPkgs.biorefs-cli
    pkgs.isync
    pkgs.khard
    pkgs.email-sync
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
    "${home}/.cache/miniflux-cli"
    "${home}/.cache/notmuch"
    "${home}/.cache/rbw"
    "${home}/.cache/vdirsyncer"
    "${home}/.claude/outputs"
    "${home}/.config/biorefs-cli"
    "${home}/.local/share/calendars"
    "${home}/.local/share/contacts"
    "${home}/.local/share/mail"
    "${home}/.local/share/vdirsyncer"
  ];
in
{
  commands = [ "pim" ];
  inherit toolPackages;
  skillPackages = [
    calendarCli
    skillzPkgs.crabfit-cli
    skillzPkgs.miniflux-cli
    skillzPkgs.vikunja-cli
    skillzPkgs.biorefs-cli
  ];
  includeSkills = [
    "calendar-cli"
    "crabfit-cli"
    "miniflux-cli"
    "vikunja-cli"
    "biorefs-cli"
  ];
  enabledTools = [
    "read"
    "bash"
    "grep"
    "glob"
    "ask"
  ];
  extensions = commonProfileExtensions;
  env = {
    NODE_PATH = "${piAgentDeps}/node_modules";
    NOTMUCH_CONFIG = "${home}/.config/notmuch/default/config";
    ISYNC_CONFIG = "${home}/.config/isyncrc";
  };
  prompt = {
    text = builtins.readFile ./prompt.md;
    commands = [
      {
        label = "Current wall calendar";
        command = "cal -3";
        timeout = 5;
        fallback = "Unable to fetch wall calendar";
      }
      {
        label = "Recent emails";
        command = "${recentEmails}";
        timeout = 10;
        fallback = "Unable to fetch emails";
      }
    ];
  };
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
    ro = [
      "${home}/.claude/skills"
      "${home}/.config/afew"
      "${home}/.config/afew-cleanup"
      "${home}/.config/isyncrc"
      "${home}/.config/khard"
      "${home}/.config/miniflux-cli"
      "${home}/.config/msmtp"
      "${home}/.config/n8n-hooks"
      "${home}/.config/notmuch"
      "${home}/.config/rbw"
      "${home}/.config/todoman"
      "${home}/.config/vcal"
      "${home}/.config/vdirsyncer"
      "${home}/.config/vikunja-cli"
    ];
  };
}
