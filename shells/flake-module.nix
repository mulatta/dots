{
  perSystem =
    {
      inputs',
      pkgs,
      ...
    }:
    {
      devShells.default = pkgs.mkShellNoCC {
        nativeBuildInputs = [
          inputs'.clan-core.packages.default
          pkgs.sops
          pkgs.ssh-to-age
          pkgs.age
        ];
      };
    };
}
