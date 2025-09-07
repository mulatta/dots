{
  config,
  pkgs,
  ...
}:
{
  programs.git = {
    enable = true;
    userName = "mulatta";
    userEmail = "67085791+mulatta@users.noreply.github.com";
    delta.enable = true;
    lfs.enable = true;

    signing = {
      key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      format = "ssh";
      signByDefault = true;
      signer = "${pkgs.openssh}/bin/ssh-keygen";
    };

    extraConfig = {
      merge.ConflictStyle = "zdiff3";
      commit.verbose = true;
      diff.algorithm = "histogram";
      log.date = "iso";
      branch.sort = "committerdate";
      rerere.enabled = true;

      core = {
        editor = "hx";
        compression = -1;
        autocrlf = "input";
        whitespace = "trailing-space,space-before-tab";
        precomposeunicode = true;
      };

      delta = {
        enable = true;
        navigate = true;
        light = false;
        side-by-side = false;
        options.syntax-theme = "catppuccin";
      };

      color = {
        diff = "auto";
        status = "auto";
        branch = "auto";
        ui = true;
      };

      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      push.default = "current";
      pull.ff = "only";

      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };
}
