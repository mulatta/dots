{ self, lib, ... }:
{
  # Read a public clan var for a machine, trimmed of trailing whitespace, or
  # null when the value has not been generated yet. Wraps clanLib.getPublicValue
  # (the stable accessor) rather than reaching into clan's on-disk layout; some
  # generators write their value with a trailing newline (e.g. `echo ... > $out`),
  # so trim before the result is spliced into /etc/hosts or resolver entries.
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
}
