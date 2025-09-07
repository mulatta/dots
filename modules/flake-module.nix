{
  flake.nixosModules = {
    imports = [
      ./nixos
    ];
  };
  flake.darwinModules = {
    imports = [
      ./darwin
    ];
  };
}
