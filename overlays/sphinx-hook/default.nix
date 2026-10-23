_final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_pythonFinal: pythonPrev: {
      # Structured attrs expose sphinxBuilders as an array; reading it as a
      # scalar silently drops man pages. Both fixes are merged to staging but
      # absent from the pinned nixpkgs. Remove once they reach the input.
      # https://github.com/NixOS/nixpkgs/pull/573479
      # https://github.com/NixOS/nixpkgs/pull/576194
      sphinxHook = pythonPrev.sphinxHook.overrideAttrs (old: {
        buildCommand = old.buildCommand + ''
          substituteInPlace "$out/nix-support/setup-hook" \
            --replace-fail ${prev.lib.escapeShellArg "    if [ -n \"\${sphinxBuilders-}\" ]; then\n        eval \"__sphinxBuilders=($sphinxBuilders)\"\n    else\n        __sphinxBuilders=(html)\n    fi"} \
            ${prev.lib.escapeShellArg "    __sphinxBuilders=()\n    concatTo __sphinxBuilders sphinxBuilders=html"}
        '';
      });
    })
  ];
}
