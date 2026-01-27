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

    # Use separate config directory for standalone (like Mic92 nvim)
    HELIX_STANDALONE="$HOME/.config/helix-standalone"

    # Clean and copy config (fresh every run)
    rm -rf "$HELIX_STANDALONE"
    mkdir -p "$HELIX_STANDALONE"
    cp -arfT '${helix-config}'/ "$HELIX_STANDALONE"
    chmod -R u+w "$HELIX_STANDALONE"

    exec hx --config "$HELIX_STANDALONE/config.toml" "$@"
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
