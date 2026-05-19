function hmg
    set current_gen (home-manager generations | head -n 1 | awk '{print $7}')
    home-manager generations | awk '{print $7}' | tac | fzf --preview "echo {} | xargs -I % sh -c 'nvd --color=always diff $current_gen %' | xargs -I{} bash {}/activate"
end
