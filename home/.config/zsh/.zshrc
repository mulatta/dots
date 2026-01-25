# zsh config - managed by dotfiles (not home-manager)

# ===== Interactive shell only =====
[[ -o interactive ]] || return

# Session variables (from nix-profile if available)
[[ -f ~/.nix-profile/etc/profile.d/hm-session-vars.sh ]] && source ~/.nix-profile/etc/profile.d/hm-session-vars.sh

# PATH setup (NixOS: /run/wrappers/bin must come first for setuid binaries like sudo)
export PATH="/run/wrappers/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

# Environment variables
export NH_FLAKE="$HOME/dots"
export EDITOR=hx
export VISUAL=hx
export ZDOTDIR="$HOME/.config/zsh"

# ===== Aliases (fish abbreviations equivalent) =====
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='clear'
alias cat='bat'
alias j='jj'
alias l='eza --group --header --group-directories-first --long --git --all --binary --all --icons always'
alias ls='eza'
alias nb='nix build'
alias nd='nix develop'
alias nfc='nix flake check'
alias nfca='nix flake check --all-systems'
alias nfs='nix flake show'
alias nfu='nix flake update'
alias nhs='nh home switch -b backup'
alias tf='tofu'
alias tg='terragrunt'
alias tmpd='cd $(mktemp -d)'
alias tree='eza --tree'
alias zj='zellij'
alias zja='zellij attach'
alias zjac='zellij attach -c'
alias zjda='zellij da'
alias zjka='zellij ka'
alias zjls='zellij ls'

# eza aliases
alias eza='eza --icons always --git --group-directories-first --header --color=always --long --no-filesize --no-time --no-user --no-permissions'
alias la='eza -a'
alias ll='eza -l'
alias lla='eza -la'
alias lt='eza --tree'

# direnv aliases
alias dra='direnv allow'
alias drb='direnv block'
alias drr='direnv reload'

# khal calendar wrapper (cal with no args → khal calendar, otherwise pass through)
function cal() {
  if [[ $# -eq 0 ]]; then
    command khal calendar
  else
    command khal "$@"
  fi
}

# ===== Custom functions =====
fpath=("$ZDOTDIR/functions" $fpath)
autoload -Uz y mk hmg t _zellij_update_tabname

# ===== Completion (must be before fzf-tab) =====
# Add zsh-completions to fpath
[[ -d ~/.nix-profile/share/zsh/site-functions ]] && fpath=(~/.nix-profile/share/zsh/site-functions $fpath)

autoload -Uz compinit
# Regenerate completion cache daily (faster startup, but fresh cache)
if [[ -n ~/.cache/zcompdump(#qN.mh+24) ]]; then
  compinit -d "$HOME/.cache/zcompdump"
else
  compinit -d "$HOME/.cache/zcompdump" -C
fi

# Completion styles
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'  # Case-insensitive
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 2 numeric
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/compcache"

# ===== Plugins (nix-managed) =====
# Load order matters! fzf-tab -> autosuggestions -> autopair -> helix-mode -> syntax-highlighting

# 1. fzf-tab (must be after compinit, before autosuggestions)
if [[ -f ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh
  # fzf-tab styles
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 $realpath'
  zstyle ':fzf-tab:complete:*:*' fzf-preview 'bat --color=always --style=numbers --line-range=:100 $realpath 2>/dev/null || cat $realpath 2>/dev/null || eza -1 --color=always $realpath 2>/dev/null'
  zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse --border
  zstyle ':fzf-tab:*' switch-group '<' '>'
fi

# 2. zsh-autosuggestions
[[ -f ~/.nix-profile/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source ~/.nix-profile/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# 3. zsh-autopair
[[ -f ~/.nix-profile/share/zsh/zsh-autopair/autopair.zsh ]] && {
  source ~/.nix-profile/share/zsh/zsh-autopair/autopair.zsh
  autopair-init
}

# 4. zsh-helix-mode
if [[ -f ~/.nix-profile/share/zsh-helix-mode/zsh-helix-mode.plugin.zsh ]]; then
  # Clipboard settings
  if [[ "$OSTYPE" == darwin* ]]; then
    export ZHM_CLIPBOARD_PIPE_CONTENT_TO="pbcopy"
    export ZHM_CLIPBOARD_READ_CONTENT_FROM="pbpaste"
  else
    export ZHM_CLIPBOARD_PIPE_CONTENT_TO="wl-copy"
    export ZHM_CLIPBOARD_READ_CONTENT_FROM="wl-paste"
  fi
  source ~/.nix-profile/share/zsh-helix-mode/zsh-helix-mode.plugin.zsh

  # Autosuggestions widget mapping for helix-mode
  if (( $+functions[autosuggest-accept] )); then
    ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(
      zhm_history_prev
      zhm_history_next
      zhm_history_search_backward
      zhm_history_search_forward
    )
  fi
fi

# 5. fast-syntax-highlighting (MUST be last among plugins)
if [[ -f ~/.nix-profile/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh ]]; then
  source ~/.nix-profile/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
  # Hook for helix-mode selection highlighting
  (( $+functions[zhm-add-update-region-highlight-hook] )) && zhm-add-update-region-highlight-hook
fi

# ===== Tool initializations =====
# fzf key bindings (Ctrl-R, Ctrl-T, Alt-C) - but NOT completion (fzf-tab handles that)
if command -v fzf &>/dev/null; then
  eval "$(fzf --zsh)"
  # Restore tab to use fzf-tab instead of fzf's completion
  bindkey '^I' fzf-tab-complete 2>/dev/null || bindkey '^I' expand-or-complete
fi

# nix-your-shell
command -v nix-your-shell &>/dev/null && eval "$(nix-your-shell zsh)"

# zoxide (replaces cd)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"

# starship prompt
if command -v starship &>/dev/null && [[ "$TERM" != "dumb" ]]; then
  eval "$(starship init zsh)"
fi

# atuin history
if command -v atuin &>/dev/null; then
  eval "$(atuin init zsh --disable-up-arrow)"
  # Bind to helix-mode keymaps (atuin only binds emacs/viins/vicmd)
  bindkey -M hxins '^R' atuin-search 2>/dev/null
  bindkey -M hxnor '^R' atuin-search 2>/dev/null
fi

# direnv (direnv-instant for faster cd performance)
if command -v direnv-instant &>/dev/null; then
  export DIRENV_INSTANT_MUX_DELAY=6
  eval "$(direnv-instant hook zsh)"
elif command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

# jujutsu completion (dynamic - supports aliases)
command -v jj &>/dev/null && {
  source <(COMPLETE=zsh jj)
  compdef j=jj
}

# ===== Zellij tab name auto-update =====
if [[ -n "$ZELLIJ" ]]; then
  chpwd_functions+=(_zellij_update_tabname)
  _zellij_update_tabname  # Initial call
fi

# ===== Ghostty shell integration =====
if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
  [[ -f "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration" ]] && \
    source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# ===== History settings =====
HISTFILE="$HOME/.local/state/zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY

# ===== Keybindings =====
# Autosuggestions: accept with Right arrow or Ctrl+E
bindkey '^[[C' autosuggest-accept   # Right arrow
bindkey '^E' autosuggest-accept     # Ctrl+E
# Partial accept with Alt+Right (word)
bindkey '^[^[[C' forward-word       # Alt+Right
