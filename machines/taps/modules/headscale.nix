# headscale: self-hosted Tailscale control plane.
#
# Purpose: give external Minecraft players a private overlay onto malt
# instead of exposing a public game port. taps runs the control plane;
# malt and the players join as nodes and reach each other over WireGuard
# (see machines/malt/modules/tailscale.nix). nginx terminates TLS for
# headscale.mulatta.io and proxies to the loopback listener below.
#
# DERP relay uses Tailscale's public derpmap by default. The control
# plane (identity, ACLs, key exchange) stays fully self-hosted; the
# public DERP only relays already-encrypted WireGuard packets when a
# direct path cannot be punched (malt is behind CGNAT). A self-hosted
# DERP can be added later if relay locality becomes a concern.
{ pkgs, ... }:
let
  domain = "headscale.mulatta.io";
  # 8080 is taken by stalwart-mail on this host; keep nginx/headscale.nix in sync.
  port = 8089;

  # Tailnet segmentation: players get the Minecraft port on malt and
  # nothing else; everything not explicitly accepted is denied.
  #
  # User-based (no ACL tags) since malt is a single dedicated node:
  # malt registers under the `mc-server` user, and the destination is
  # that user's node on port 25565. This avoids tag ownership setup.
  #
  # In headscale policy v2 a user reference is suffixed with `@`; a bare
  # name is parsed as an (undefined) host alias and headscale refuses to
  # start. So users are `mc-server@`, and group members below are `alice@`.
  #
  # Operational wiring (one-time, outside Nix):
  #   - `headscale users create mc-server` then register malt with a key
  #     from `headscale preauthkeys create --user mc-server`.
  #   - each player is a headscale user added to group:players below.
  aclPolicy = {
    groups."group:players" = [ ]; # add player users (e.g. "alice@") as onboarded
    acls = [
      {
        action = "accept";
        src = [ "group:players" ];
        dst = [ "mc-server@:25565" ];
      }
    ];
  };
in
{
  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    inherit port;
    settings = {
      server_url = "https://${domain}";

      # MagicDNS suffix. Must differ from server_url's host, so nodes
      # resolve each other as <hostname>.ts.mulatta.io on the tailnet
      # (e.g. players connect to malt.ts.mulatta.io:25565).
      dns = {
        magic_dns = true;
        base_domain = "ts.mulatta.io";
        # Only resolve the tailnet domain; do not push global nameservers onto
        # clients (we have none, and the module asserts global must be set when
        # this is true). Players keep their own resolver for everything else.
        override_local_dns = false;
      };

      # No upstream telemetry from a self-hosted control plane.
      logtail.enabled = false;

      # Restrict who may reach what on the tailnet (see aclPolicy above).
      policy = {
        mode = "file";
        path = pkgs.writeText "headscale-policy.json" (builtins.toJSON aclPolicy);
      };
    };
  };
}
