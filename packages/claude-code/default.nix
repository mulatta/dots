{
  pkgs,
  lib,
  writeShellApplication,
  claude-code,
  ck,
}:
let
  mcpConfigJson = pkgs.writeText "mcp-servers.json" (
    builtins.toJSON (import ./servers.nix { inherit pkgs lib ck; })
  );
in
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

    # Add ~/.local/bin to PATH for user scripts
    export PATH="$HOME/.local/bin:$PATH"

    # Start pueued daemon if not already running
    if ! pueue status &>/dev/null; then
      echo "Starting pueue daemon..." >&2
      pueued -d
    fi

    # Run claude with MCP config
    exec claude --mcp-config ${mcpConfigJson} "$@"
  '';
}
