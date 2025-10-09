{pkgs, ...}: {
  programs.fish = rec {
    enable = true;
    interactiveShellInit = ''
      fish_config theme choose "Catppuccin Mocha"

      ${pkgs.nix-your-shell}/bin/nix-your-shell fish | source

      set -gx SHELL ${pkgs.fish}/bin/fish
      set -gx PATH /run/wrappers/bin /run/current-system/sw/bin /usr/bin /bin $HOME/.nix-profile/bin /nix/var/nix/profiles/default/bin /usr/local/bin ~/.local/bin $PATH

      # fifc setup
      set -Ux fifc_editor hx
      set -U fifc_keybinding \cx
      bind \cx _fifc
      bind -M insert \cx _fifc

      set -U fifc_bat_opts --style=numbers --color=always
      set -U fifc_fd_opts --hidden --color=always --follow --exclude .git
      set -U fifc_exa_opts --icons --tree --git --group-directories-first --header --all

      _fifc_ripgrep_rule

      # jujutsu completion
      if command -v jj >/dev/null 2>&1
        jj util completion fish | source
      end

       function __auto_zellij_update_tabname --on-variable PWD --description "Update zellij tab name on directory change"
         _zellij_update_tabname
       end

      if test -n "$SSH_CONNECTION"
        set -gx PUEUE_PROFILE local
      else
        set -gx PUEUE_PROFILE psi
      end
    '';

    shellAliases = {
      # Navigation
      "..." = "cd ../..";

      # Command replacements
      c = "clear";
      cd = "z";
      cdi = "zi";
      cat = "bat";
      ls = "eza";
      l = "eza --group --header --group-directories-first --long --git --all --binary --all --icons always";
      tree = "eza --tree";

      # Nix commands
      nhd = "nh darwin switch";
      nhh = "nh home switch";
      nho = "nh os switch";
      nhu = "nh os --update";
      drs = "sudo darwin-rebuild switch --flake $NH_FLAKE";
      nrs = "sudo nixos-rebuild switch --flake $NH_FLAKE";
      hms = "home-manager switch --flake $NH_FLAKE -b backup";

      nfu = "nix flake update";
      nfc = "nix flake check";
      nfca = "nix flake check --all-systems";
      nfs = "nix flake show";

      # devenvs
      nd = "nix develop";
      dra = "direnv allow";
      drb = "direnv block";
      drr = "direnv reload";

      # terraform
      tf = "tofu";
      tg = "terragrunt";

      # neomutt
      mt = "neomutt";

      # Jujutsu
      j = "jj";

      # zellij
      zj = "zellij";
    };

    shellAbbrs = shellAliases;

    functions = {
      fish_greeting = "";

      mk = ''
        if test (count $argv) -eq 0
          echo "Usage: mk <directory_name>"
          return 1
        end
        mkdir -p $argv[1] && cd $argv[1]
      '';

      hmg = ''
        set current_gen (home-manager generations | head -n 1 | awk '{print $7}')
        home-manager generations | awk '{print $7}' | tac | fzf --preview "echo {} | xargs -I % sh -c 'nvd --color=always diff $current_gen %' | xargs -I{} bash {}/activate"
      '';

      _zellij_update_tabname = ''
        if set -q ZELLIJ
          set current_dir $PWD
          if test $current_dir = $HOME
              set tab_name "~"
          else
              set tab_name (basename $current_dir)
          end

          if fish_git_prompt >/dev/null
              # we are in a git repo

              # if we are in a git superproject, use the superproject name
              # otherwise, use the toplevel repo name
              set git_root (git rev-parse --show-superproject-working-tree)
              if test -z $git_root
                  set git_root (git rev-parse --show-toplevel)
              end

              #  if we are in a subdirectory of the git root, use the relative path
              if test (string lower "$git_root") != (string lower "$current_dir")
                  set tab_name (basename $git_root)/(basename $current_dir)
              end
          end

          nohup zellij action rename-tab $tab_name >/dev/null 2>&1
        end
      '';

      fish_command_not_found = ''
        # If you run the command with comma, running the same command
        # will not prompt for confirmation for the rest of the session
        if contains $argv[1] $__command_not_found_confirmed_commands
          or ${pkgs.gum}/bin/gum confirm --selected.background=2 "Run using comma?"

          # Not bothering with capturing the status of the command, just run it again
          if not contains $argv[1] $__command_not_found_confirmed_commands
            set -ga __fish_run_with_comma_commands $argv[1]
          end

          comma -- $argv
          return 0
        else
          __fish_default_command_not_found_handler $argv
        end
      '';

      _fifc_ripgrep_rule = ''
        fifc -r '.*\*{2}.*' \
           -s 'rg --hidden -l --no-messages (string match -r -g \'.*\*{2}(.*)\' "$fifc_commandline")' \
           -p 'batgrep --color --paging=never (string match -r -g \'.*\*{2}(.*)\' "$fifc_commandline") "$fifc_candidate"' \
           -f "--query '''" \
           -o 'batgrep --color (string match -r -g \'.*\*{2}(.*)\' "$fifc_commandline") "$fifc_candidate" | less -R' \
           -O 1
      '';

      __pueue_cmd = ''
        set -l profile_arg
        if set -q PUEUE_PROFILE
          set profile_arg -p $PUEUE_PROFILE
        end
        pueue $profile_arg $argv
      '';

      pq = "__pueue_cmd $argv";
      pqa = "__pueue_cmd add $argv";
      pqs = "__pueue_cmd status $argv";
      pql = "__pueue_cmd log $argv";
      pqf = "__pueue_cmd follow $argv";
      pqk = "__pueue_cmd kill $argv";
      pqr = "__pueue_cmd remove $argv";
      pqc = "__pueue_cmd clean $argv";
      pqp = "__pueue_cmd pause $argv";
      pqst = "__pueue_cmd start $argv";
      pqw = "__pueue_cmd wait $argv";
      pqe = "__pueue_cmd edit $argv";
      pqpar = "__pueue_cmd parallel $argv";

      pueue_profile = ''
        if test (count $argv) -eq 0
          echo "Current: $PUEUE_PROFILE"
          echo "Available: local, psi, production, ..."
          return
        end
        set -gx PUEUE_PROFILE $argv[1]
        echo "→ $PUEUE_PROFILE"
      '';
    };

    plugins = [
      {
        name = "fifc";
        inherit (pkgs.fishPlugins.fifc) src;
      }
      {
        name = "gruvbox";
        inherit (pkgs.fishPlugins.gruvbox) src;
      }
      {
        name = "git-abbr";
        inherit (pkgs.fishPlugins.git-abbr) src;
      }
      {
        name = "helix-bindings";
        src = pkgs.fetchFromGitHub {
          owner = "tammoippen";
          repo = "fish-helix";
          rev = "8addfe9eae578e6e8efd8c7002c833574824c216";
          hash = "sha256-xTZ9Y/8yrQ7yM/R8614nezmbn05aVve5vMtCyjRMSOw=";
        };
      }
      {
        name = "jj-abbr";
        src = pkgs.fetchFromGitHub {
          owner = "kapsmudit";
          repo = "plugin-jj";
          rev = "593e00baaabac6a306b367103b5bea73316cc241";
          hash = "sha256-XMk5UquaBFOLwHnC4yFSjykU8LZymk0a0gbBQX5Ga80=";
        };
      }
      {
        name = "completion-sync";
        src = pkgs.fetchFromGitHub {
          owner = "iynaix";
          repo = "fish-completion-sync";
          rev = "4f058ad2986727a5f510e757bc82cbbfca4596f0";
          sha256 = "sha256-kHpdCQdYcpvi9EFM/uZXv93mZqlk1zCi2DRhWaDyK5g=";
        };
      }
      {
        name = "autopair";
        src = pkgs.fetchFromGitHub {
          owner = "jorgebucaran";
          repo = "autopair.fish";
          rev = "4d1752ff5b39819ab58d7337c69220342e9de0e2";
          hash = "sha256-qt3t1iKRRNuiLWiVoiAYOu+9E7jsyECyIqZJ/oRIT1A=";
        };
      }
    ];
  };

  catppuccin.fish.enable = true;
}
