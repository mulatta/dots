# GPU support profile
# Rebuilds pkgs with cudaSupport=true; ai.nix forwards this to qmd,
# whose upstream package selects matching CUDA runtime libraries.
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
