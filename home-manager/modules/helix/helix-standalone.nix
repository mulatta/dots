{
  writeShellScriptBin,
  helix,
  buildEnv,
  # LSPs
  bash-language-server,
  marksman,
  nil,
  nixd,
  pyright,
  ruff,
  rust-analyzer,
  taplo,
  tinymist,
  yaml-language-server,
  vscode-langservers-extracted,
  # Formatters
  alejandra,
  nodePackages,
  shfmt,
  typstyle,
  helix-config ? ../../../home/.config/helix,
}:
let
  lspEnv = buildEnv {
    name = "helix-lsp-tools";
    paths = [
      # LSPs
      bash-language-server
      marksman
      nil
      nixd
      pyright
      ruff
      rust-analyzer
      taplo
      tinymist
      yaml-language-server
      vscode-langservers-extracted
      # Formatters
      alejandra
      nodePackages.prettier
      shfmt
      typstyle
    ];
  };
in
writeShellScriptBin "hx" ''
  set -efu

  export PATH=${lspEnv}/bin:${helix}/bin:$PATH

  XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-$HOME/.config}
  HELIX_CONFIG="$XDG_CONFIG_HOME/helix"

  mkdir -p "$HELIX_CONFIG"

  # Link config files if not exists (don't override user's stow config)
  for f in config.toml languages.toml; do
    if [[ ! -e "$HELIX_CONFIG/$f" ]]; then
      ln -sfn "${helix-config}/$f" "$HELIX_CONFIG/$f"
    fi
  done

  exec hx "$@"
''
