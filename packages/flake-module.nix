{ inputs, ... }:
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
        claude-code = pkgs.callPackage ../packages/claude-code {
          claude-code = inputs.llm-agents.packages.${system}.claude-code;
        };
        inherit (pkgs)
          rsshub
          chartdb
          bulwark-webmail
          merge-when-green
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
