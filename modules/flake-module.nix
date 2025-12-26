{
  flake.nixosModules = {
    imports = [
      ../nixosModules
    ];
  };
  flake.darwinModules = {
    imports = [
      ../darwinModules
    ];
  };
}
