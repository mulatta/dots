{
  writeShellScriptBin,
  yazi,
  yazi-plugins,
  yazi-preview-tools,
  yazi-config ? ../../../home/.config/yazi,
}:
writeShellScriptBin "yazi" ''
  set -efu

  export PATH=${yazi-preview-tools}/bin:${yazi}/bin:$PATH

  XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-$HOME/.config}
  YAZI_CONFIG="$XDG_CONFIG_HOME/yazi-standalone"

  # Clean and copy config (fresh every run like Mic92 nvim)
  rm -rf "$YAZI_CONFIG"
  mkdir -p "$YAZI_CONFIG"
  cp -arfT '${yazi-config}'/ "$YAZI_CONFIG"
  chmod -R u+w "$YAZI_CONFIG"

  # Copy plugins
  mkdir -p "$YAZI_CONFIG/plugins"
  cp -arfT '${yazi-plugins}/share/yazi/plugins'/ "$YAZI_CONFIG/plugins"
  chmod -R u+w "$YAZI_CONFIG/plugins"

  export YAZI_CONFIG_HOME="$YAZI_CONFIG"
  exec yazi "$@"
''
