{
  # cask is the public HTTPS entrypoint; expose the user-scoped relay only on
  # the authenticated Naru interface.
  networking.firewall.interfaces."tinc.naru".allowedTCPPorts = [ 4242 ];
}
