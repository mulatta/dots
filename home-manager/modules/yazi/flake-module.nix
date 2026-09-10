{
  perSystem =
    { pkgs, lib, ... }:
    let
      plugins =
        let
          selected = with pkgs.yaziPlugins; {
            inherit
              chmod
              full-border
              toggle-pane
              diff
              rsync
              miller
              starship
              glow
              git
              piper
              ;
          };
        in
        pkgs.runCommand "yazi-plugins" { } ''
          mkdir -p $out/share/yazi/plugins
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: package: ''
              ln -s ${package} $out/share/yazi/plugins/${name}.yazi
            '') selected
          )}
        '';
      previewTools = pkgs.buildEnv {
        name = "yazi-preview-tools";
        paths = with pkgs; [
          imagemagick
          ffmpegthumbnailer
          unar
          poppler
          glow
        ];
      };
    in
    {
      packages = {
        yazi-plugins = plugins;
        yazi-preview-tools = previewTools;
        # Standalone Yazi for `nix run`, separate from Home Manager.
        yazi = pkgs.callPackage ./yazi-standalone.nix {
          yazi-plugins = plugins;
          yazi-preview-tools = previewTools;
          yazi = pkgs.yazi;
        };
      };
    };
}
