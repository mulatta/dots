{
  writeShellScriptBin,
  symlinkJoin,
  helix,
  helix-lsp-tools,
  helix-config ? ../../../home/.config/helix,
}:
let
  hxWrapper = writeShellScriptBin "hx" ''
    set -efu

    export PATH=${helix-lsp-tools}/bin:${helix}/bin:$PATH

    # --config does not relocate languages.toml, so isolate Helix through XDG_CONFIG_HOME.
    HELIX_STANDALONE_XDG="$HOME/.config/helix-standalone"
    HELIX_STANDALONE="$HELIX_STANDALONE_XDG/helix"

    # Clean and copy config (fresh every run)
    rm -rf "$HELIX_STANDALONE_XDG"
    mkdir -p "$HELIX_STANDALONE"
    cp -arfT '${helix-config}'/ "$HELIX_STANDALONE"
    chmod -R u+w "$HELIX_STANDALONE_XDG"
    export XDG_CONFIG_HOME="$HELIX_STANDALONE_XDG"

    exec hx "$@"
  '';
in
symlinkJoin {
  name = "hx";
  paths = [
    hxWrapper
    # Include helix's share directory for zsh completions
    "${helix}"
  ];
  # Only take bin from wrapper, share from helix
  postBuild = ''
    rm -rf $out/bin/hx
    cp ${hxWrapper}/bin/hx $out/bin/hx
  '';
}
