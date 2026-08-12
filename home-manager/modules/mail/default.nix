{
  inputs,
  pkgs,
  config,
  lib,
  self,
  ...
}:
let
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  imports = [
    ./aerc.nix
    ./sieve.nix
  ];

  config = lib.mkMerge [
    {
      home.packages = [
        selfPkgs.msmtp-with-sent
      ]
      ++ (with pkgs; [
        afew
        inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system}.crabfit-cli
        selfPkgs.email-sync
        gnupg
        isync
        khard
        notmuch
        rbw
      ]);
    }

    (lib.mkIf pkgs.stdenv.isLinux {
      systemd.user.services.mbsync = {
        Unit.Description = "Mailbox synchronization";
        Service = {
          Type = "oneshot";
          ExecStart = "${selfPkgs.email-sync}/bin/email-sync";
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
          ProgramArguments = [ "${selfPkgs.email-sync}/bin/email-sync" ];
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
