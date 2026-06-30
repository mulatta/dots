{
  writeShellApplication,
  claude-code,
  pueue,
  nodejs_24,
  bashInteractive,
}:
writeShellApplication {
  name = "claude";
  runtimeInputs = [
    claude-code
    pueue
    nodejs_24
  ];
  text = ''
    export SHELL=${bashInteractive}/bin/bash

    # Add ~/bin to PATH for user scripts (stowed from dots/home/bin)
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

    if ! pueue status &>/dev/null; then
      pueued -d >/dev/null 2>&1 || true
    fi

    exec claude  "$@"
  '';
}
