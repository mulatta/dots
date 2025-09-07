{
  programs.gh = {
    enable = true;
    settings = {
      aliases = {
        clone = "repo clone";
        V = "repo view";
        v = "repo view --web";
        ref = "!gh browse \"$1\" -c=$(git rev-parse HEAD) --no-browser | pbcopy";
      };
      "editor" = "hx";
      "git_protocol" = "ssh";
    };
  };
}
