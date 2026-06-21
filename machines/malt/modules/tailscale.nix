# malt joins the headscale tailnet (control plane on taps). Joined once by
# hand, not via a stored key: headscale keys are single-use/expiring (no
# reproducibility) and a clan-vars prompt would deadlock the first deploy
# (the key can only be minted once headscale is already up). Registration
# persists in /var/lib/tailscale, so it is a one-time step:
#   malt$ tailscale up --login-server=https://headscale.mulatta.io \
#           --auth-key=<key> --accept-dns=false   # accept-dns=false: keep own resolver
{ ... }:
{
  services.tailscale.enable = true;
}
