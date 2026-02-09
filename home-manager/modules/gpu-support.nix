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
        self.overlays.default
        self.overlays.llm-agents
        self.overlays.rag
        self.overlays.skillz
        self.overlays.llm-agents-cuda # CUDA override for qmd
      ];
    }
  );
}
