# Sieve script upload via ManageSieve
#
# Strategy:
#   - Server-side: Folder classification (GitHub, Academic, Server)
#   - Client-side: Fine-grained tagging with afew
#
# Usage: sieve-upload (uploads ~/.config/sieve/default.sieve to server)
{ pkgs, ... }:
let
  sieve-upload = pkgs.writeShellApplication {
    name = "sieve-upload";
    runtimeInputs = with pkgs; [
      sieve-connect
      rbw
    ];
    text = ''
      set -euo pipefail

      SERVER="mail.mulatta.io"
      USER="seungwon"
      SCRIPT_NAME="default"
      SCRIPT_PATH="$HOME/.config/sieve/default.sieve"

      if [ ! -f "$SCRIPT_PATH" ]; then
        echo "Error: Sieve script not found at $SCRIPT_PATH"
        exit 1
      fi

      # Get password from rbw
      if ! rbw unlocked 2>/dev/null; then
        echo "rbw vault is locked, please unlock first: rbw unlock"
        exit 1
      fi

      PASS=$(rbw get "mulatta.io" --field password 2>/dev/null || rbw get "mail.mulatta.io" 2>/dev/null)

      if [ -z "$PASS" ]; then
        echo "Error: Could not get password from rbw"
        exit 1
      fi

      echo "Uploading sieve script to $SERVER..."

      # Upload the script
      echo "$PASS" | sieve-connect \
        --server "$SERVER" \
        --port 4190 \
        --user "$USER" \
        --passwordfd 0 \
        --localsieve "$SCRIPT_PATH" \
        --remotesieve "$SCRIPT_NAME" \
        --upload

      echo "Activating sieve script..."

      # Activate separately (workaround for timing issue)
      echo "$PASS" | sieve-connect \
        --server "$SERVER" \
        --port 4190 \
        --user "$USER" \
        --passwordfd 0 \
        --remotesieve "$SCRIPT_NAME" \
        --activate

      echo "Sieve script uploaded and activated successfully"
    '';
  };
in
{
  home.packages = [
    sieve-upload
    pkgs.sieve-connect
  ];
}
