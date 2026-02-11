{
  pkgs,
  config,
  lib,
  ...
}:
let
  maildir = "${config.home.homeDirectory}/mail";

  msmtp-wrapper = pkgs.writeShellScriptBin "msmtp" ''
    tmpfile=$(mktemp)
    trap "rm -f $tmpfile" EXIT

    cat > "$tmpfile"

    if ${pkgs.msmtp}/bin/msmtp "$@" < "$tmpfile"; then
      timestamp=$(date +%s)
      hostname=$(hostname)
      pid=$$
      random=$RANDOM
      filename="''${timestamp}.''${pid}_''${random}.''${hostname}:2,S"

      mkdir -p "${maildir}/.Sent/cur"
      cp "$tmpfile" "${maildir}/.Sent/cur/$filename"

      ${pkgs.notmuch}/bin/notmuch new >/dev/null 2>&1 || true
      exit 0
    else
      exit $?
    fi
  '';
in
{
  imports = [
    ./aerc.nix
    ./sieve.nix
  ];

  config = lib.mkMerge [
    {
      home.packages = [
        msmtp-wrapper
      ]
      ++ (with pkgs; [
        afew
        email-sync
        gnupg
        isync
        khard
        notmuch
        rbw
        sieve-sync
        w3m
      ]);
    }

    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.services.mbsync = {
        Unit.Description = "Mailbox synchronization";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.email-sync}/bin/email-sync";
        };
      };

      systemd.user.timers.mbsync = {
        Unit.Description = "Mailbox synchronization timer";
        Timer = {
          OnBootSec = "2m";
          OnUnitActiveSec = "5m";
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })

    (lib.mkIf pkgs.stdenv.isDarwin {
      launchd.enable = true;
      launchd.agents.mbsync = {
        enable = true;
        config = {
          ProgramArguments = [ "${pkgs.email-sync}/bin/email-sync" ];
          StartInterval = 300;
          RunAtLoad = true;
          StandardOutPath = "${config.xdg.stateHome}/mbsync.log";
          StandardErrorPath = "${config.xdg.stateHome}/mbsync.err";
          EnvironmentVariables = {
            HOME = config.home.homeDirectory;
          };
        };
      };
    })
  ];
}
