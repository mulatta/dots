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
      # Home-manager configuration builder
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
                inputs.stylix.homeModules.stylix
                inputs.catppuccin.homeModules.catppuccin
              ];
            }
          ];
        };

      # Hostname → profile mapping
      profileMap = {
        "seungwon@rhesus" = "macos";
        "seungwon@psi" = "base";
        "seungwon@malt" = "base";
      };

      runtimeInputs = with pkgs; [
        jujutsu
        uutils-coreutils-noprefix
        findutils
        hostname
        inputs.home-manager.packages.${system}.home-manager
      ];
    in
    {
      apps.bootstrap = {
        type = "app";
        program =
          let
            script = pkgs.writeShellApplication {
              name = "bootstrap-dotfiles";
              runtimeInputs = runtimeInputs ++ [ pkgs.bash ];
              text = ''
                DOTFILES_DIR="$HOME/dots"

                echo "==> Cloning dotfiles..."
                if [[ ! -d "$DOTFILES_DIR" ]]; then
                  jj git clone "https://github.com/mulatta/dots.git" "$DOTFILES_DIR"
                else
                  echo "    Already exists, fetching and updating..."
                  cd "$DOTFILES_DIR"
                  jj git fetch --quiet
                  jj new main@origin --no-edit --quiet
                fi

                echo "==> Activating home-manager..."
                home-manager switch --flake "$DOTFILES_DIR" -b bak

                echo "==> Done! You may need to restart your shell."
              '';
            };
          in
          "${script}/bin/bootstrap-dotfiles";
      };
      apps.default = config.apps.bootstrap;

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

          # Filter profileMap to only include entries with existing profiles
          filteredProfileMap = lib.filterAttrs (_: p: profiles ? ${p}) profileMap;
        in
        profiles // lib.mapAttrs (_: p: profiles.${p}) filteredProfileMap;
    };
}
