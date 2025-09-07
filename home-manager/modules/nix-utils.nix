{
  pkgs,
  config,
  ...
}:
{
  # ======== Nix Development Tools ========
  home.packages = with pkgs; [
    nixd # Nix LSP
    nixfmt-rfc-style # RFC style formatter
    nvd # Nix differ
    nix-diff # Another differ
    nix-output-monitor # Better nix build output
    nh # Nix helper
    nurl # Generate nix fetcher calls
  ];

  # ======== NH Configuration ========
  programs.nh = {
    enable = true;
    flake = "${config.home.homeDirectory}/dots";
    clean = {
      enable = true;
      dates = "monthly";
      extraArgs = "--keep 5 --keep-since 1m";
    };
  };

  # ======== Nix-Init Configuration ========
  programs.nix-init = {
    enable = true;
    settings = {
      maintainers = [ "mulatta" ];
      nixpkgs = "<nixpkgs>";
      commit = true;
      access-tokens = {
        "github.com" = {
          file = config.sops.secrets.github_token.path;
        };
      };
    };
  };

  sops.secrets.github_token = { };
}
