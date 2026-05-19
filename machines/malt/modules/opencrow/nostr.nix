{
  config,
  pkgs,
  ...
}:
{
  clan.core.vars.generators.opencrow = {
    files.nostr-private-key.secret = true;
    files.nostr-public-key.secret = false;

    runtimeInputs = with pkgs; [ nak ];

    script = ''
      sk=$(nak key generate)
      pk=$(nak key public "$sk")
      echo -n "$sk" > "$out/nostr-private-key"
      echo -n "$pk" > "$out/nostr-public-key"
    '';
  };

  services.opencrow.credentialFiles."nostr-private-key" =
    config.clan.core.vars.generators.opencrow.files.nostr-private-key.path;

  services.opencrow.environment = {
    OPENCROW_NOSTR_NAME = "noa";
    OPENCROW_NOSTR_DISPLAY_NAME = "Noa";
    OPENCROW_NOSTR_ABOUT = "agent";
  };
}
