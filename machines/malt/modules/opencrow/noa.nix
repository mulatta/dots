{ lib, ... }:
{
  imports = [
    ./biorefs.nix
    ./calendar.nix
    ./geo.nix
    ./mail.nix
    ./miniflux.nix
    ./n8n.nix
    ./nostr.nix
    ./paperless.nix
    ./rbw.nix
  ];

  config = {
    containers.opencrow.config.systemd.tmpfiles.rules = lib.mkBefore [
      "d /var/lib/opencrow/.config 0750 opencrow opencrow -"
      "d /var/lib/opencrow/.cache 0750 opencrow opencrow -"
      "d /var/lib/opencrow/.local 0750 opencrow opencrow -"
      "d /var/lib/opencrow/.local/share 0750 opencrow opencrow -"
      "L+ /var/lib/opencrow/AGENTS.md - - - - ${./agents/noa/AGENTS.md}"
      # vdirsyncer hooks commit local calendar/contact changes under this user.
      ''f /var/lib/opencrow/.gitconfig 0644 opencrow opencrow - [user]\n\tname = Noa\n\temail = noa@mulatta.io''
    ];

    services.opencrow = {
      enable = true;

      environment = {
        OPENCROW_LOG_LEVEL = "debug";
        OPENCROW_SOUL_FILE = "${./agents/noa/soul.md}";
      };
    };
  };
}
