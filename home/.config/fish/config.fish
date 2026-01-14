# fish config - managed by dotfiles (not home-manager)

# Only execute this file once per shell
set -q __fish_config_sourced; and return
set -g __fish_config_sourced 1

# Session variables (from nix-profile if available)
if test -f ~/.nix-profile/etc/profile.d/hm-session-vars.fish
    source ~/.nix-profile/etc/profile.d/hm-session-vars.fish
end

status is-login; and begin
    # Login shell initialisation
end

status is-interactive; and begin
    # PATH setup
    set -gx PATH \
        $HOME/.nix-profile/bin \
        /nix/var/nix/profiles/default/bin \
        /run/current-system/sw/bin \
        /usr/local/bin \
        ~/.local/bin \
        $PATH

    # Environment variables
    set -gx NH_FLAKE "$HOME/dots"
    set -gx EDITOR hx
    set -gx VISUAL hx

    # Abbreviations
    abbr --add -- ... 'cd ../..'
    abbr --add -- c clear
    abbr --add -- cat bat
    abbr --add -- cd z
    abbr --add -- cdi zi
    abbr --add -- dra 'direnv allow'
    abbr --add -- drb 'direnv block'
    abbr --add -- drr 'direnv reload'
    abbr --add -- j jj
    abbr --add -- l 'eza --group --header --group-directories-first --long --git --all --binary --all --icons always'
    abbr --add -- ls eza
    abbr --add -- nb 'nix build'
    abbr --add -- nd 'nix develop'
    abbr --add -- nfc 'nix flake check'
    abbr --add -- nfca 'nix flake check --all-systems'
    abbr --add -- nfs 'nix flake show'
    abbr --add -- nfu 'nix flake update'
    abbr --add -- nhs 'nh home switch -b backup'
    abbr --add -- tf tofu
    abbr --add -- tg terragrunt
    abbr --add -- tmpd 'cd $(mktemp -d)'
    abbr --add -- tree 'eza --tree'
    abbr --add -- zj zellij
    abbr --add -- zja 'zellij attach'
    abbr --add -- zjac 'zellij attach -c'
    abbr --add -- zjda 'zellij da'
    abbr --add -- zjka 'zellij ka'
    abbr --add -- zjls 'zellij ls'

    # Aliases
    alias eza 'eza --icons always --git --group-directories-first --header --color=always --long --no-filesize --no-time --no-user --no-permissions'
    alias la 'eza -a'
    alias ll 'eza -l'
    alias lla 'eza -la'
    alias lt 'eza --tree'

    # Tool initializations (PATH-based, Mic92 style)
    if type -q fzf
        fzf --fish | source
    end

    if type -q nix-your-shell
        nix-your-shell fish | source
    end

    if type -q zoxide
        zoxide init fish --cmd cd | source
    end

    if type -q starship
        if test "$TERM" != dumb
            starship init fish | source
            enable_transience
        end
    end

    if type -q atuin
        atuin init fish --disable-up-arrow | source
    end

    if type -q direnv
        direnv hook fish | source
    end

    # jujutsu completion
    if type -q jj
        jj util completion fish | source
    end

    # fifc setup (if available)
    if type -q _fifc
        set -Ux fifc_editor hx
        set -U fifc_keybinding \cx
        bind \cx _fifc
        bind -M insert \cx _fifc
        set -U fifc_bat_opts --style=numbers --color=always
        set -U fifc_fd_opts --hidden --color=always --follow --exclude .git
        set -U fifc_exa_opts --icons --tree --git --group-directories-first --header --all
    end

    # Zellij tab name auto-update
    function __auto_zellij_update_tabname --on-variable PWD --description "Update zellij tab name on directory change"
        if type -q _zellij_update_tabname
            _zellij_update_tabname
        end
    end

    # Ghostty shell integration
    if set -q GHOSTTY_RESOURCES_DIR
        if test -f "$GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
            source "$GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
        end
    end

    # Fish theme
    fish_config theme choose "Catppuccin Mocha"
end
