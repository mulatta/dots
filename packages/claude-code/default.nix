{
  pkgs,
  writeShellApplication,
  claude-code,
}:
writeShellApplication {
  name = "claude";
  runtimeInputs = [
    claude-code
    pkgs.pueue
    pkgs.nodejs_24
  ];
  text = ''
    # Set shell to bash for Claude Code
    export SHELL=${pkgs.bashInteractive}/bin/bash

    # Add ~/bin to PATH for user scripts (stowed from dots/home/bin)
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

    # Start pueued daemon if not already running
    if ! pueue status &>/dev/null; then
      echo "Starting pueue daemon..." >&2
      pueued -d
    fi

    exec claude  "$@"
  '';
}
