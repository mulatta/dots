{
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.radicle-node ];

  # jujutsu radicle integration (based on radicle blog)
  # https://radicle.xyz/2025/08/14/jujutsu-with-radicle
  programs.jujutsu.settings = {
    aliases = {
      fresh = [
        "new"
        "trunk()"
      ];
      tug = [
        "bookmark"
        "set"
        "-r"
        "@-"
        "master"
      ];
    };
    revset-aliases = {
      # fallback: master@rad → main@origin → master@origin → root()
      "trunk()" = "latest(present(master@rad) | present(main@origin) | present(master@origin) | root())";
    };
  };

  # Git alias for rad patch
  programs.git.settings.alias.patch = "push rad HEAD:refs/patches";

  # fish abbreviations
  programs.fish.shellAbbrs = {
    rs = "rad sync";
    rp = "rad push";
    ri = "rad inspect";
  };
}
