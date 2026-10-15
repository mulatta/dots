{ llm-agents }:
_final: prev:
let
  upstream = llm-agents.packages.${prev.stdenv.hostPlatform.system}.qmd;
in
{
  # node-llama-cpp ships a CUDA 12 fallback, but upstream takes the default
  # cudaPackages (now CUDA 13) while requiring CUDA 12 libraries at fixup.
  # Keep this scoped to qmd until upstream selects the matching runtime.
  # https://github.com/numtide/llm-agents.nix/issues/2957
  qmd =
    if
      (prev.config.cudaSupport or false)
      && prev.stdenv.hostPlatform.isLinux
      && prev.stdenv.hostPlatform.isx86_64
    then
      upstream.override {
        cudaSupport = true;
        cudaPackages = prev.cudaPackages_12;
      }
    else
      upstream;
}
