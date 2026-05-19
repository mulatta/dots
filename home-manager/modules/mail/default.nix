{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [
    ./aerc.nix
    ./sieve.nix
  ];

  config = lib.mkMerge [
    {
      home.packages = [
        pkgs.msmtp-with-sent
      ]
      ++ (with pkgs; [
        afew
        inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system}.crabfit-cli
        email-sync
        gnupg
        isync
        khard
        notmuch
        rbw
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
