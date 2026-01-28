# zsh config - managed by dotfiles (not home-manager)

# ===== Interactive shell only =====
[[ -o interactive ]] || return

# Session variables (from nix-profile if available)
[[ -f ~/.nix-profile/etc/profile.d/hm-session-vars.sh ]] && source ~/.nix-profile/etc/profile.d/hm-session-vars.sh

# PATH setup (NixOS: /run/wrappers/bin must come first for setuid binaries like sudo)
export PATH="/run/wrappers/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/local/bin:$HOME/bin:$PATH"

# XDG Base Directories (ensure consistency in devshells)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# XDG User Directories
export XDG_DESKTOP_DIR="$HOME/Desktop"
export XDG_DOCUMENTS_DIR="$HOME/Documents"
export XDG_DOWNLOAD_DIR="$HOME/Downloads"
export XDG_MUSIC_DIR="$HOME/Music"
export XDG_PICTURES_DIR="$HOME/Pictures"
export XDG_PUBLICSHARE_DIR="$HOME/Public"
export XDG_TEMPLATES_DIR="$HOME/.Templates"
export XDG_VIDEOS_DIR="$HOME/Videos"

# Environment variables
export NH_FLAKE="$HOME/dots"
export EDITOR=hx
export VISUAL=hx
export ZDOTDIR="$HOME/.config/zsh"
# Catppuccin Mocha theme for skim
export SKIM_DEFAULT_OPTIONS="--height=40% --layout=reverse --bind='ctrl-j:down,ctrl-k:up' \
  --color=bg+:#313244,spinner:#f5e0dc,hl:#f38ba8,fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc,marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
# Include hidden directories for Alt+D (cd), Alt+F (file)
export SKIM_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
export SKIM_CTRL_T_COMMAND="fd --type f --hidden --follow --exclude .git"

# ===== Aliases =====
# macOS: use GNU tar for cross-platform compatible archives (no ._* files, no SCHILY.* headers)
[[ "$OSTYPE" == darwin* ]] && alias tar='gtar'

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

# ===== Custom functions =====

## File/Directory utilities
# yazi wrapper with cwd sync
y() {
  local tmp=$(mktemp -t "yazi-cwd.XXXXX")
  command yazi "$@" --cwd-file="$tmp"
  local cwd
  if cwd=$(< "$tmp") && [[ -n "$cwd" && "$cwd" != "$PWD" && -d "$cwd" ]]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# mkdir + cd
mk() {
  [[ $# -eq 0 ]] && { echo "Usage: mk <directory_name>"; return 1; }
  mkdir -p "$1" && cd "$1"
}

# cd to git/jj repo root
reporoot() {
  cd "$(git rev-parse --show-toplevel)"
}

# resolve symlink to real path
real-which() {
  readlink -f "$(command which "$@")"
}

## Home Manager
# home-manager wrapper
hm() {
  nix run "$HOME/dots#hm" -- "$@"
}

# home-manager generation switcher with skim
hmg() {
  local current_gen=$(home-manager generations | head -n 1 | awk '{print $7}')
  home-manager generations | awk '{print $7}' | tac | \
    sk --preview "nvd --color=always diff $current_gen {}" | \
    xargs -I{} bash {}/activate
}

## Nix utilities
# get store path of a package
nix-pkg-path() {
  if [[ $# != 1 ]]; then
    echo "USAGE: nix-pkg-path <package>" >&2
    return 1
  fi
  nix-shell -p "$1" --run 'echo $buildInputs'
}

# extract package source to current directory (writable)
nix-unpack() {
  if [[ $# != 1 ]]; then
    echo "USAGE: nix-unpack <package>" >&2
    return 1
  fi
  local pkg=$1
  nix-shell \
    -E "with import <nixpkgs> {}; mkShell { buildInputs = [ (srcOnly pkgs.$pkg) ]; }" \
    --run "cp -r \$buildInputs $pkg; chmod -R +w $pkg"
}

# build a single .nix file with callPackage
nix-call-package() {
  if [[ $# -lt 1 ]]; then
    echo "USAGE: nix-call-package <file.nix> [args...]" >&2
    return 1
  fi
  local file=$1
  shift
  nix-build -E "with import <nixpkgs> {}; pkgs.callPackage $file {}" "$@"
}

# update nixpkgs package version
nix-update() {
  if [[ -f $HOME/git/nix-update/flake.nix ]]; then
    nix run $HOME/git/nix-update#nix-update -- "$@"
  else
    nix run nixpkgs#nix-update -- "$@"
  fi
}

# parallel nix builder
nix-fast-build() {
  nix run github:mic92/nix-fast-build -- "$@"
}

nixify() {
  if [[ -n "$1" ]]; then
    nix flake init -t "github:mulatta/flake-templates#$1"
  else
    nix flake init -t github:mulatta/flake-templates
  fi
}

## Todoman
# todoman wrapper with short subcommands
t() {
  case "$1" in
    n)  shift
        if [[ ! " $* " =~ " -s " ]]; then
          command todo new -s today "$@"
        else
          command todo new "$@"
        fi
        ;;
    l)  shift; command todo list "$@" ;;
    d)  shift; command todo done "$@" ;;
    e)  shift; command todo edit "$@" ;;
    s)  shift; command todo show "$@" ;;
    c)  shift; command todo cancel "$@" ;;
    rm) shift; command todo delete "$@" ;;
    mv) shift; command todo move "$@" ;;
    cp) shift; command todo copy "$@" ;;
    fl) shift; command todo flush "$@" ;;
    "") command todo list ;;
    *)  command todo "$@" ;;
  esac
}

## Calendar
# khal calendar wrapper (cal with no args → khal calendar, otherwise pass through)
cal() {
  if [[ $# -eq 0 ]]; then
    command khal calendar
  else
    command khal "$@"
  fi
}

## Jujutsu workspaces
JJ_WORKSPACE_DIR="${JJ_WORKSPACE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/jj-workspaces}"

# jt: select workspace and cd
jt() {
  jj root &>/dev/null || { echo "not in jj repo" >&2; return 1; }
  # Get main repo root (workspace's .jj/repo points to main repo)
  local repo_link=$(cat "$(jj root)/.jj/repo" 2>/dev/null)
  local main_repo=${repo_link:+${repo_link%/.jj/repo}}
  [[ -z "$main_repo" ]] && main_repo=$(jj root)
  local selected="${1:-$(jj workspace list --color=always | sk --ansi --prompt="workspace> " \
    --preview='ws=$(echo {} | awk "{print \$1}" | tr -d ":"); jj log -r "trunk()..$ws@" --limit 10 --color=always 2>/dev/null || echo "no commits"' \
    --preview-window=right:60% | awk '{print $1}' | tr -d ':')}"
  [[ -z "$selected" ]] && return 0
  local dir
  if [[ "$selected" == "default" ]]; then
    dir=$main_repo
  else
    dir="$JJ_WORKSPACE_DIR/${main_repo:t}/$selected"
  fi
  [[ -d "$dir" ]] && cd "$dir" && [[ -f .envrc ]] && direnv allow 2>/dev/null
}

# jn: create new workspace and cd
jn() {
  jj root &>/dev/null || { echo "not in jj repo" >&2; return 1; }
  local name="${1:?usage: jn NAME [-r REV]}"
  shift
  local repo_link=$(cat "$(jj root)/.jj/repo" 2>/dev/null)
  local main_repo=${repo_link:+${repo_link%/.jj/repo}}
  [[ -z "$main_repo" ]] && main_repo=$(jj root)
  local ws_dir="$JJ_WORKSPACE_DIR/${main_repo:t}/$name"
  mkdir -p "$ws_dir"
  jj workspace add "$ws_dir" --name "$name" "$@" || return 1
  cd "$ws_dir" && [[ -f .envrc ]] && direnv allow 2>/dev/null
}

# jd: delete workspace
jd() {
  jj root &>/dev/null || { echo "not in jj repo" >&2; return 1; }
  local repo_link=$(cat "$(jj root)/.jj/repo" 2>/dev/null)
  local main_repo=${repo_link:+${repo_link%/.jj/repo}}
  [[ -z "$main_repo" ]] && main_repo=$(jj root)
  local name="${1:-$(jj workspace list --color=always | sk --ansi --prompt="delete workspace> " \
    --preview='ws=$(echo {} | awk "{print \$1}" | tr -d ":"); jj log -r "trunk()..$ws@" --limit 10 --color=always 2>/dev/null || echo "no commits"' \
    --preview-window=right:60% --query='!default ' | awk '{print $1}' | tr -d ':')}"
  [[ -z "$name" || "$name" == "default" ]] && { echo "cannot delete default workspace" >&2; return 1; }
  local ws_dir="$JJ_WORKSPACE_DIR/${main_repo:t}/$name"
  jj workspace forget "$name" || return 1
  [[ -d "$ws_dir" ]] && rm -rf "$ws_dir" && echo "removed $ws_dir"
}

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

# 1. fzf-tab with skim backend (must be after compinit, before autosuggestions)
if [[ -f ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source ~/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh
  zstyle ':fzf-tab:*' fzf-command sk
  # Only show fzf-tab when there are many completions (threshold: 4)
  zstyle ':fzf-tab:*' fzf-min-height 4
  # Disable group headers (-- values --, etc.)
  zstyle ':fzf-tab:*' show-group none
  # Simpler display without descriptions
  zstyle ':fzf-tab:*' fzf-flags --height=40% --layout=reverse --no-info
  zstyle ':fzf-tab:*' switch-group '<' '>'
  # Preview only for file paths
  zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath 2>/dev/null || ls -1 $realpath'
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
  if (( $+widgets[autosuggest-accept] )); then
    ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(
      zhm_accept
      zhm_accept_or_insert_newline
      zhm_prompt_accept
      zhm_history_prev
      zhm_history_next
      zhm_move_up_or_history_prev
      zhm_move_down_or_history_next
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
# skim key bindings (Alt+D: cd, Alt+G: file)
if command -v sk &>/dev/null; then
  source ~/.nix-profile/share/skim/key-bindings.zsh 2>/dev/null
  # Disable defaults (conflicts with zellij/atuin)
  bindkey -r '^T' '^R' '\ec' 2>/dev/null
  # Alt+D for directory cd, Alt+G for file selection
  bindkey '\ed' skim-cd-widget 2>/dev/null
  bindkey '\eg' skim-file-widget 2>/dev/null
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

# Load direnv-instant integration for non-blocking prompt
if [[ -n "${commands[direnv-instant]}" ]]; then
  export DIRENV_INSTANT_MUX_DELAY=6
  eval "$(direnv-instant hook zsh)"
fi

# jujutsu completion (dynamic - supports aliases)
command -v jj &>/dev/null && {
  source <(COMPLETE=zsh jj)
  compdef j=jj
}

# ===== Zellij tab name auto-update =====
_zellij_update_tabname() {
  [[ -z "$ZELLIJ" ]] && return
  local current_dir="$PWD" tab_name
  if [[ "$current_dir" == "$HOME" ]]; then
    tab_name="~"
  else
    tab_name="${current_dir##*/}"
  fi
  # Check if in a git repo
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local git_root
    git_root=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -z "$git_root" ]] && git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$git_root" && "${git_root:l}" != "${current_dir:l}" ]]; then
      tab_name="${git_root##*/}/${current_dir##*/}"
    fi
  fi
  nohup zellij action rename-tab "$tab_name" &>/dev/null
}

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
# Both normal mode (^[[C) and application mode (^[OC) sequences
bindkey '^[[C' autosuggest-accept   # Right arrow (normal mode)
bindkey '^[OC' autosuggest-accept   # Right arrow (application mode)
bindkey '^E' autosuggest-accept     # Ctrl+E
# Partial accept with Alt+Right (word)
bindkey '^[^[[C' forward-word       # Alt+Right (normal mode)
bindkey '^[O3C' forward-word        # Alt+Right (application mode, some terminals)

# Edit command line in $EDITOR (Alt+E)
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^[e' edit-command-line
