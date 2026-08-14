# Shared defaults for LLM agent containers, imported inside container configs.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    bash
    bc
    cacert
    coreutils
    curl
    diffutils
    fd
    file
    findutils
    git
    gnugrep
    gnused
    gnutar
    gzip
    htmlq
    hurl
    jq
    less
    libarchive
    nix
    openssh
    patch
    procps
    python3
    ripgrep
    tree
    unzip
    util-linux
    w3m
    wget
    which
    xz
    yq-go
    zip
    zstd
  ];

  # nixos-containers bind-mount the host store and daemon socket, so agent
  # containers use the host daemon instead of owning an inner store.
  nix = {
    enable = true;
    settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
    registry.nixpkgs.to = {
      type = "path";
      path = pkgs.path;
    };
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
  };

  environment.variables.NIX_REMOTE = "daemon";
}
