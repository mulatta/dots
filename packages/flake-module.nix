{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    {
      packages = {
        inherit (pkgs)
          rsshub
          chartdb
          bulwark-webmail
          dbml-cli
          merge-when-green
          claude-code
          claude-md
          rbw-pinentry
          rhwp
          rhwp-studio
          email-sync
          msmtp-with-sent
          n8n-hooks
          jellyfin-plugin-sso-auth
          miniflux-sync
          ntfy-subscribe
          nostore-preload
          pim
          updater
          instagram-cli
          quarkdown
          sem-vcs
          slack-manifest-cli
          ;
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        inherit (pkgs)
          nostr-chat-bar
          radicle-desktop
          systemctl-macos
          ;
      };
    };
}
