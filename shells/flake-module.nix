{
  perSystem =
    {
      inputs',
      pkgs,
      ...
    }:
    let
      clan = inputs'.clan-core.packages.clan-cli;
    in
    {
      devShells.default = pkgs.mkShellNoCC {
        nativeBuildInputs = [
          inputs'.clan-core.packages.default
          (clan.pythonRuntime.withPackages (ps: [
            ps.invoke
            (ps.toPythonModule clan)
          ]))
          pkgs.sops
          pkgs.ssh-to-age
          pkgs.age
        ];
      };
    };
}
