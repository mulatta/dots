{
  writeShellApplication,
  claude-code,
  bun,
  bashInteractive,
}:
writeShellApplication {
  name = "claude";
  runtimeInputs = [
    claude-code
    bun
  ];
  text = ''
    export SHELL=${bashInteractive}/bin/bash

    # Add ~/bin to PATH for user scripts (stowed from dots/home/bin)
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

    exec claude  "$@"
  '';
}
