{
  writeShellScriptBin,
  yazi,
  yazi-plugins,
  buildEnv,
  imagemagick,
  ffmpegthumbnailer,
  unar,
  poppler,
  glow,
  yazi-config ? ../../../home/.config/yazi,
}:
let
  previewEnv = buildEnv {
    name = "yazi-preview-tools";
    paths = [
      imagemagick
      ffmpegthumbnailer
      unar
      poppler
      glow
    ];
  };
in
writeShellScriptBin "yazi" ''
  set -efu

  export PATH=${previewEnv}/bin:${yazi}/bin:$PATH

  XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-$HOME/.config}
  YAZI_CONFIG="$XDG_CONFIG_HOME/yazi"

  # Ensure config directory exists
  mkdir -p "$YAZI_CONFIG/plugins"

  # Link config files if not exists (don't override user's stow config)
  for f in yazi.toml keymap.toml theme.toml; do
    if [[ ! -e "$YAZI_CONFIG/$f" ]]; then
      ln -sfn "${yazi-config}/$f" "$YAZI_CONFIG/$f"
    fi
  done

  # Link plugins from nix package
  for plugin in ${yazi-plugins}/share/yazi/plugins/*; do
    name=$(basename "$plugin")
    ln -sfn "$plugin" "$YAZI_CONFIG/plugins/$name"
  done

  exec yazi "$@"
''
