{ self, lib, ... }:
{
  # Read a public clan var (trimmed), or null if not generated yet. Wraps the
  # stable getPublicValue; some generators emit a trailing newline, so trim
  # before it lands in /etc/hosts or resolver entries.
  flake.lib.readVarFile =
    machine: generator: file:
    let
      value = self.inputs.clan-core.lib.getPublicValue {
        flake = self;
        inherit machine generator file;
        default = null;
      };
    in
    if value == null then null else lib.strings.trim value;

  # Shared WireGuard /64 prefix from the taps controller. Callers build their
  # own address as "${wgPrefix}:${suffix}", so only this read is centralized.
  flake.lib.wgPrefix = self.inputs.clan-core.lib.getPublicValue {
    flake = self;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
}
