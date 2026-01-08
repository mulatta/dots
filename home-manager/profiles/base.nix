{
  pkgs,
  lib,
  config,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  imports = [
    ../modules/atuin.nix
    ../modules/bat.nix
    ../modules/bitwarden.nix
    ../modules/btop.nix
    ../modules/direnv.nix
    ../modules/eza.nix
    ../modules/fish.nix
    ../modules/fzf.nix
    ../modules/git
    ../modules/helix
    ../modules/llm-agents.nix
    ../modules/nh.nix
    ../modules/niks3.nix
    ../modules/sops.nix
    ../modules/starship
    ../modules/stylix.nix
    ../modules/yazi
    ../modules/zellij
    ../modules/zoxide.nix
  ];

  home.packages =
    with pkgs;
    [
      nix-diff
      nix-output-monitor
      nix-prefetch
      nix-tree
      nixd
      nixfmt-rfc-style
      nixpkgs-review
      nurl
      nvd

      delta
      dust
      fd
      grex
      hyperfine
      jq
      ntfy-sh
      ouch
      procs
      pueue
      ripgrep
      sd
      xcp
      yq-go
    ]
    ++ [
      self.packages.${system}.jmt
      self.packages.${system}.merge-when-green
    ];

  xdg.enable = true;

  home.enableNixpkgsReleaseCheck = false;

  # better eval time
  manual.html.enable = false;
  manual.manpages.enable = false;
  manual.json.enable = false;

  home.username = lib.mkDefault "seungwon";
  home.stateVersion = "25.05";
  home.homeDirectory =
    if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

  programs.home-manager.enable = true;

  nixpkgs.config.allowUnfree = true;
}
