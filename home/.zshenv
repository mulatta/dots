# Point to zsh config directory
export ZDOTDIR="$HOME/.config/zsh"

# Source the real .zshenv if it exists
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
