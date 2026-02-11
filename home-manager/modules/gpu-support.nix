# GPU support profile
# Overrides pkgs with cudaSupport=true and applies llm-agents-cuda overlay for qmd
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
        self.overlays.llm-agents-cuda # overrides pkgs.qmd with CUDA support
      ];
    }
  );
}
