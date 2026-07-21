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
          archify-cli
          rsshub
          bulwark-webmail
          merge-when-green
          claude-md
          rbw-pinentry
          rhwp
          email-sync
          msmtp-with-sent
          n8n-hooks
          jellyfin-plugin-sso-auth
          miniflux-sync
          ntfy-subscribe
          pim
          updater
          jj-forklift
          instagram-cli
          instant-deploy
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
