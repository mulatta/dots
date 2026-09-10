{
  buildEnv,
  helix,
  helix-lsp-packages,
  symlinkJoin,
  uutils-coreutils-noprefix,
  writeShellApplication,
  helix-config ? ../../../home/.config/helix,
}:
let
  lspEnv = buildEnv {
    name = "helix-lsp-tools";
    paths = helix-lsp-packages;
  };
  hxWrapper = writeShellApplication {
    name = "hx";
    runtimeInputs = [ uutils-coreutils-noprefix ];
    text = ''
      export PATH=${lspEnv}/bin:${helix}/bin:$PATH

      # --config does not relocate languages.toml, so isolate Helix through XDG_CONFIG_HOME.
      HELIX_STANDALONE_XDG="''${XDG_CONFIG_HOME:-$HOME/.config}/helix-standalone"
      HELIX_STANDALONE="$HELIX_STANDALONE_XDG/helix"

      # Fresh copy each run so the isolated config cannot drift from its source.
      rm -rf "$HELIX_STANDALONE_XDG"
      mkdir -p "$HELIX_STANDALONE"
      cp -arfT '${helix-config}'/ "$HELIX_STANDALONE"
      chmod -R u+w "$HELIX_STANDALONE_XDG"
      export XDG_CONFIG_HOME="$HELIX_STANDALONE_XDG"

      exec hx "$@"
    '';
  };
in
symlinkJoin {
  name = "hx";
  paths = [
    hxWrapper
    # Preserve Helix completions while replacing its hx binary with the wrapper.
    "${helix}"
  ];
  postBuild = ''
    rm -rf $out/bin/hx
    cp ${hxWrapper}/bin/hx $out/bin/hx
  '';
}
