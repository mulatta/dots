# GPU support profile
# Overrides pkgs with cudaSupport=true and applies llm-agents-cuda overlay
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
        inputs.llm-agents.overlays.default # expose llm-agents packages
        self.overlays.default # existing overlays
        self.overlays.llm-agents-cuda # GPU override for ck, qmd
      ];
    }
  );
}
