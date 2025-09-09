{
  perSystem = {
    inputs',
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShellNoCC {
      nativeBuildInputs = [
        inputs'.clan-core.packages.default
        inputs'.clan-core.packages.clan-app
        pkgs.sops
        pkgs.ssh-to-age
      ];
    };
  };
}
