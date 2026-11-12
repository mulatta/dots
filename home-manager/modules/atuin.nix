{
  programs.atuin = {
    enable = true;
    daemon.enable = true;

    # Shell hooks live in the stowed dotfiles, including custom key bindings.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    enableZshIntegration = false;

    settings = {
      auto_sync = true;
      sync_address = "https://atuin.mulatta.io";
      daemon = {
        # Home Manager owns the daemon lifecycle on both platforms.
        autostart = false;
        sync_frequency = 3600;
      };
      threads.capture = true;
    };
  };
}
