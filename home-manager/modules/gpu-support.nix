# GPU support profile
# Rebuilds pkgs with cudaSupport=true; the qmd overlay selects its CUDA runtime
# independently so prebuilt binaries keep their matching library versions.
{
  lib,
  self,
  inputs,
  system,
  ...
}:
{
  _module.args.pkgs = lib.mkForce (
    import inputs.nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
        cudaSupport = true;
      };
      overlays = [
        self.overlays.default
      ];
    }
  );
}
