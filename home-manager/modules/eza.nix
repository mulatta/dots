{
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    enableFishIntegration = true;
    extraOptions = [
      "--group-directories-first"
      "--header"
      "--color=always"
      "--long"
      "--no-filesize"
      "--no-time"
      "--no-user"
      "--no-permissions"
    ];
    git = true;
    icons = "always";
  };
}
