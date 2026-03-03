{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      packages = {
        inherit (pkgs)
          sieve-sync
          merge-when-green
          claude-code
          claude-md
          rbw-pinentry
          gh-radicle
          email-sync
          ntfy-subscribe
          updater
          instagram-cli
          radicle-desktop
          skim
          ;
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        inherit (pkgs) systemctl-macos;
      }
      // lib.optionalAttrs (system == "aarch64-darwin") {
        inherit (pkgs) meetily;
      };
    };
}
