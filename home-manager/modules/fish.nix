{
  pkgs,
  config,
  ...
}:
let
  c = config.lib.stylix.colors.withHashtag;
in
{
  programs.fish = rec {
    enable = true;
    interactiveShellInit = ''
       # Colors from stylix (base16)
       set -U fish_color_normal ${c.base05}
       set -U fish_color_command ${c.base0D}
       set -U fish_color_keyword ${c.base0E}
       set -U fish_color_quote ${c.base0B}
       set -U fish_color_redirection ${c.base0E}
       set -U fish_color_end ${c.base09}
       set -U fish_color_comment ${c.base03}
       set -U fish_color_error ${c.base08}
       set -U fish_color_param ${c.base05}
       set -U fish_color_option ${c.base0E}
       set -U fish_color_operator ${c.base0C}
       set -U fish_color_escape ${c.base09}
       set -U fish_color_autosuggestion ${c.base04}
       set -U fish_color_cwd ${c.base0A}
       set -U fish_color_cwd_root ${c.base08}
       set -U fish_color_user ${c.base0C}
       set -U fish_color_host ${c.base0D}
       set -U fish_color_host_remote ${c.base0A}
       set -U fish_color_status ${c.base08}
       set -U fish_color_cancel ${c.base08}
       set -U fish_color_search_match --background=${c.base02}
       set -U fish_color_selection --background=${c.base02}
       set -U fish_color_valid_path --underline
       set -U fish_pager_color_progress ${c.base0D}
       set -U fish_pager_color_prefix ${c.base0E}
       set -U fish_pager_color_completion ${c.base05}
       set -U fish_pager_color_description ${c.base03}

       ${pkgs.nix-your-shell}/bin/nix-your-shell fish | source

       set -gx SHELL ${pkgs.fish}/bin/fish
       set -gx PATH /run/wrappers/bin /run/current-system/sw/bin /usr/bin /bin $HOME/.nix-profile/bin /nix/var/nix/profiles/default/bin /usr/local/bin ~/.local/bin $PATH

       # nh flake path
       set -gx NH_FLAKE "$HOME/dots"

       # fifc setup
       set -Ux fifc_editor hx
       set -U fifc_keybinding \cx
       bind \cx _fifc
       bind -M insert \cx _fifc

       # Enable helix-style key bindings (set as universal variable)
       set -U fish_key_bindings fish_helix_key_bindings

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

      nhs = "nh home switch -b backup";
      nfu = "nix flake update";
      nfc = "nix flake check";
      nfca = "nix flake check --all-systems";
      nfs = "nix flake show";
      nb = "nix build";
      nd = "nix develop";

      dra = "direnv allow";
      drb = "direnv block";
      drr = "direnv reload";

      # terraform
      tf = "tofu";
      tg = "terragrunt";

      # Jujutsu
      j = "jj";
      jst = "jj status";
      js = "jj show";

      # abandon
      ja = "jj abandon";
      jabs = "jj absorb";

      # bookmark
      jbs = "jj bookmark set";
      jbl = "jj bookmark list";
      jbt = "jj bookmark track";
      jbd = "jj bookmark delete";
      jbf = "jj bookmark forget";
      jbm = "jj bookmark move";
      jbr = "jj bookmark rename";

      # log
      jl = "jj log";
      jlr = "jj log -r";
      jla = "jj log -r all()";

      # new
      jn = "jj new";
      jnn = "jj new --no-edit";
      jna = "jj new -A";
      jnb = "jj new -B";
      jnna = "jj new --no-edit -A";
      jnnb = "jj new --no-edit -B";

      # git push
      jp = "jj git push";
      jpa = "jj git push --all";
      jpb = "jj git push --bookmark";
      jpc = "jj git push --change";
      jpd = "jj git push --deleted";

      # git fetch
      jf = "jj git fetch";
      jgcl = "jj git clone";

      # rebase
      jrb = "jj rebase";
      jrbr = "jj rebase -r";
      jrbs = "jj rebase -s";
      jrbd = "jj rebase -d";

      # resolve
      jrs = "jj resolve";
      jrsr = "jj resolve -r";
      jrsl = "jj resolve --list";

      # show
      jshs = "jj show --summary";
      jshg = "jj show --git";

      # squash
      jsq = "jj squash";

      # fix
      jfx = "jj fix";

      # describe
      jd = "jj describe";
      jdm = "jj describe -m";

      # diff
      jdf = "jj diff";
      jdfs = "jj diff --stat";
      jdfc = "jj diff --color-words";
      jdfg = "jj diff --git";

      # prev/next
      jpr = "jj prev";
      jnx = "jj next";

      # edit
      je = "jj edit";

      # split
      jsp = "jj split";

      # evolog
      jel = "jj evolog";

      # operation
      jol = "jj op log";

      # file
      jfa = "jj file annotate";
      jfl = "jj file list";
      jfc = "jj file chmod";
      jfs = "jj file show";

      # zellij
      zj = "zellij";
      zja = "zellij attach";
      zjac = "zellij attach -c";
      zjls = "zellij ls";
      zjka = "zellij ka";
      zjda = "zellij da";

      tmpd = "cd $(mktemp -d)";
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
    };

    plugins = [
      {
        name = "fifc";
        inherit (pkgs.fishPlugins.fifc) src;
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
}
