# GPU support profile
# Rebuilds pkgs with cudaSupport=true; qmd picks up CUDA via a local override
# in the llm-agents module keyed off pkgs.config.cudaSupport.
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
        self.overlays.dots
      ];
    }
  );
}
