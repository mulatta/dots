{
  self,
  inputs,
  ...
}:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      system,
      ...
    }:
    let
      mkHomeConfig =
        {
          extraModules ? [ ],
        }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./profiles/base.nix
            {
              _module.args.self = self;
              _module.args.inputs = self.inputs;
              _module.args.system = system;
              imports = extraModules ++ [
                inputs.sops-nix.homeManagerModules.sops
                inputs.nix-index-database.homeModules.nix-index
                { programs.nix-index-database.comma.enable = true; }
              ];
            }
          ];
        };

      profileMap = {
        "rhesus" = "macos";
        "psi" = "base";
        "malt" = "base";
      };

      dotfilesDir = "$HOME/dots";

      runtimeInputs = with pkgs; [
        coreutils
        findutils
        hostname
        stow
        inputs.home-manager.packages.${system}.home-manager
      ];
    in
    {
      apps.hm = {
        type = "app";
        program = lib.getExe config.packages.hm;
      };

      apps.bootstrap = {
        type = "app";
        program = lib.getExe config.packages.bootstrap;
      };

      apps.default = config.apps.bootstrap;

      # Expose hm script as package for installation in profile
      packages.hm =
        let
          profileMapBash = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (host: profile: ''profiles["${host}"]="${profile}"'') profileMap
          );
        in
        pkgs.writeShellApplication {
          name = "hm";
          inherit runtimeInputs;
          text = ''
            set -euo pipefail

            DOTFILES_DIR="${dotfilesDir}"

            # Determine profile based on hostname
            declare -A profiles
            ${profileMapBash}

            HOSTNAME=$(hostname -s)
            PROFILE="''${profiles[$HOSTNAME]:-base}"

            # Handle 'profile' subcommand
            if [[ "''${1:-}" == "profile" ]]; then
              echo "$PROFILE"
              exit 0
            fi

            # Stow dotfiles before home-manager switch
            if [[ "''${1:-}" == "switch" ]] && [[ -d "$DOTFILES_DIR/home" ]]; then
              echo "==> Stowing dotfiles..."
              stow -d "$DOTFILES_DIR" -t "$HOME" --restow home
            fi

            # Run home-manager with determined profile
            echo "==> Running home-manager with profile: $PROFILE"
            home-manager --flake "$DOTFILES_DIR#$PROFILE" "$@"
          '';
        };

      packages.bootstrap = pkgs.writeShellApplication {
        name = "bootstrap-dotfiles";
        runtimeInputs = runtimeInputs ++ [ pkgs.git ];
        text = ''
          set -euo pipefail

          DOTFILES_DIR="${dotfilesDir}"

          echo "==> Cloning dotfiles..."
          if [[ ! -d "$DOTFILES_DIR" ]]; then
            git clone "https://github.com/mulatta/dots.git" "$DOTFILES_DIR"
          else
            echo "    Already exists, pulling latest..."
            git -C "$DOTFILES_DIR" pull --rebase || true
          fi

          echo "==> Stowing dotfiles..."
          stow -d "$DOTFILES_DIR" -t "$HOME" --restow home

          echo "==> Activating home-manager..."
          nix run "$DOTFILES_DIR#hm" -- switch

          echo "==> Done! You may need to restart your shell."
        '';
      };

      legacyPackages.homeConfigurations =
        let
          profiles = {
            base = mkHomeConfig { };
          }
          // lib.optionalAttrs (system == "aarch64-darwin") {
            macos = mkHomeConfig { extraModules = [ ./profiles/macos.nix ]; };
          }
          // lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
            desktop = mkHomeConfig { extraModules = [ ./profiles/desktop.nix ]; };
          };

          filteredProfileMap = lib.filterAttrs (_host: p: profiles ? ${p}) profileMap;
        in
        profiles // lib.mapAttrs (_: p: profiles.${p}) filteredProfileMap;
    };
}
