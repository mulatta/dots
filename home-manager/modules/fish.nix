{ pkgs, ... }:
{
  programs.fish = rec {
    enable = true;
    interactiveShellInit = ''
      # disable fish greeting
      set fish_greeting
      fish_config theme choose "Catppuccin Mocha"
      fish_add_path -p ~/.nix-profile/bin /nix/var/nix/profiles/default/bin
      set -a fish_complete_path ~/.nix-profile/share/fish/completions/ ~/.nix-profile/share/fish/vendor_completions.d/
      set hydro_color_pwd brcyan
      set hydro_color_git brmagenta
      set hydro_color_error brred
      set hydro_color_prompt brgreen
      set hydro_color_duration bryellow
      set hydro_multiline true

      set -gx PATH $HOME/.nix-profile/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin/usr/local/bin /usr/bin ~/.local/bin $PATH

      fzf_configure_bindings

      fish_vi_key_bindings
      set fish_cursor_default     block      blink
      set fish_cursor_insert      line       blink
      set fish_cursor_replace_one underscore blink
      set fish_cursor_visual      block

      # Correct cursor for ghostty when in VI mode.
      if string match -q -- '*ghostty*' $TERM
        set -g fish_vi_force_cursor 1
      end

      # jujutsu completion
      if command -v jj >/dev/null 2>&1
        jj util completion fish | source
      end
    '';

    shellAliases = {
      # Navigation
      "..." = "cd ../..";

      # Git commands
      g = "git";
      gs = "git status";
      gco = "git checkout";

      # Command replacements
      c = "clear";
      ss = "zellij -l welcome";
      cd = "z";
      cdi = "zi";
      cat = "bat";
      ls = "eza";
      l = "eza --group --header --group-directories-first --long --git --all --binary --all --icons always";
      tree = "eza --tree";
      sudo = "sudo -E -s";

      # Kubernetes
      k = "kubectl";
      kgp = "kubectl get pods";

      # Tailscale
      tsu = "tailscale up";
      tsd = "tailscale down";

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
      nv = "nvim";

      # Custom commands
      weather = "curl wttr.in/incheon?0pq";
      pfile = "fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'";
      gdub = "git fetch -p && git branch -vv | grep ': gone]' | awk '{print }' | xargs git branch -D $argv;";
      tldrf = ''${pkgs.tldr}/bin/tldr --list | fzf --preview "${pkgs.tldr}/bin/tldr {1} --color" --preview-window=right,70% | xargs tldr'';
      docker-compose = "podman-compose";

      jjs = "jj status";
    };

    shellAbbrs = shellAliases;

    functions = {
      mk = ''
        if test (count $argv) -eq 0
          echo "Usage: mk <directory_name>"
          return 1
        end
        mkdir -p $argv[1] && cd $argv[1]
      '';

      fish_greeting = "";

      hmg = ''
        set current_gen (home-manager generations | head -n 1 | awk '{print $7}')
        home-manager generations | awk '{print $7}' | tac | fzf --preview "echo {} | xargs -I % sh -c 'nvd --color=always diff $current_gen %' | xargs -I{} bash {}/activate"
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
    };
    plugins = [
      {
        name = "bass";
        inherit (pkgs.fishPlugins.bass) src;
      }
      {
        name = "fzf-fish";
        inherit (pkgs.fishPlugins.fzf-fish) src;
      }
      {
        name = "fifc";
        inherit (pkgs.fishPlugins.fifc) src;
      }
      {
        name = "gruvbox";
        inherit (pkgs.fishPlugins.gruvbox) src;
      }
      # {
      #   name = "kubectl-abbr";
      #   src = pkgs.fetchFromGitHub {
      #     owner = "lewisacidic";
      #     repo = "fish-kubectl-abbr";
      #     rev = "161450ab83da756c400459f4ba8e8861770d930c";
      #     sha256 = "sha256-iKNaD0E7IwiQZ+7pTrbPtrUcCJiTcVpb9ksVid1J6A0=";
      #   };
      # }
      {
        name = "git-abbr";
        inherit (pkgs.fishPlugins.git-abbr) src;
      }
    ];
  };

  catppuccin.fish.enable = true;
}
