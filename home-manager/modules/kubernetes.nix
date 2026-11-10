{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.kind
    pkgs.kubectl
    pkgs.kubectx
    # nixpkgs' cargoSetupHook now makes zstd-sys and aws-lc-sys link system
    # libraries, which sofka's package does not provide.
    (inputs.sofka.packages.${pkgs.stdenv.hostPlatform.system}.sofka.overrideAttrs (old: {
      nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.pkg-config ];
      buildInputs = (old.buildInputs or [ ]) ++ [
        pkgs.aws-lc
        pkgs.zstd
      ];
    }))
  ];
}
