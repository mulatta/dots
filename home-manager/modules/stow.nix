{
  lib,
  pkgs,
  self,
  system,
  ...
}:
{
  systemd.user.services.stow-dotfiles = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    Unit.Description = "Stow dotfiles into home directory";

    Service = {
      Type = "oneshot";
      ExecStart = self.apps.${system}.stow-dotfiles.program;
      RemainAfterExit = true;
    };

    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.stow-dotfiles = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    enable = true;
    config = {
      Label = "org.mulatta.stow-dotfiles";
      ProgramArguments = [ self.apps.${system}.stow-dotfiles.program ];
      RunAtLoad = true;
      ProcessType = "Background";
    };
  };
}
