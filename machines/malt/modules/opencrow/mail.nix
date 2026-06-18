{ config, pkgs, ... }:
{
  services.opencrow.skills.email = ./skills/email;
  services.opencrow.extraPackages = [ pkgs.mblaze ];

  # JMAP credentials for noa to read the shared seungwon INBOX from
  # stalwart on taps and perform a one-shot handoff for messages marked
  # with $flagged. The value is noa's kanidm POSIX password; Stalwart
  # authenticates protocol clients through kanidm.
  clan.core.vars.generators.opencrow-jmap = {
    files."password" = {
      secret = true;
    };
    prompts."password" = {
      description = "noa kanidm POSIX password (stalwart JMAP handoff)";
      type = "hidden";
    };
    script = ''
      cp "$prompts/password" "$out/password"
    '';
  };

  # Pin container UID/GID so the host opencrow group lines up with the
  # user inside the container. The flagged Maildir bind mount relies on
  # this match for read access through the group bit.
  containers.opencrow.config.users.users.opencrow.uid = 2000;
  containers.opencrow.config.users.groups.opencrow.gid = 2000;

  # Expose only the user-selected mail handoff. Sync implementations
  # populate this Maildir on the host; OpenCrow consumes it read-only.
  containers.opencrow.bindMounts = {
    "/var/mail/flagged" = {
      hostPath = "/var/lib/noa-maildir/Flagged";
      isReadOnly = true;
    };
  };

  # noa-mail owns the flagged-mail handoff Maildir on the host; the JMAP
  # service runs as this user.
  users.users.noa-mail = {
    isSystemUser = true;
    description = "Owner of the Noa flagged-mail handoff on malt";
    group = "noa-mail";
    extraGroups = [ "opencrow" ];
    home = "/var/lib/noa-maildir";
    createHome = false;
  };
  users.groups.noa-mail = { };

  # Host-side opencrow group with a fixed GID so the container user can
  # be made a member of the same group.
  users.groups.opencrow.gid = 2000;

  # Mode 2750 grants noa-mail write access and opencrow read/traverse
  # access. The setgid bit keeps new sync output readable by the agent
  # without a separate chgrp step in the common case.
  systemd.tmpfiles.rules = [
    "d /var/lib/noa-maildir 2750 noa-mail opencrow -"
    "d /var/lib/noa-maildir/Flagged 2750 noa-mail opencrow -"
    "d /var/lib/noa-maildir/Flagged/cur 2750 noa-mail opencrow -"
    "d /var/lib/noa-maildir/Flagged/new 2750 noa-mail opencrow -"
    "d /var/lib/noa-maildir/Flagged/tmp 2750 noa-mail opencrow -"
    "d /var/lib/opencrow 0750 2000 opencrow -"
    "d /var/lib/opencrow/sessions 0750 2000 opencrow -"
    "p /var/lib/opencrow/sessions/trigger.pipe 0660 noa-mail opencrow -"
  ];

  systemd.services.noa-jmap-handoff = {
    description = "Copy seungwon flagged mail to Noa via JMAP";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "noa-mail";
      Group = "noa-mail";
      ExecStart = "${pkgs.callPackage ../../pkgs/noa-jmap-handoff { }}";
      LoadCredential = "jmap-password:${config.clan.core.vars.generators.opencrow-jmap.files.password.path}";
    };
    environment = {
      JMAP_SESSION_URL = "https://stalwart.mulatta.io/.well-known/jmap";
      JMAP_API_URL = "https://stalwart.mulatta.io/jmap/";
      JMAP_DOWNLOAD_URL = "https://stalwart.mulatta.io/jmap/download/{accountId}/{blobId}/{name}?accept={type}";
      JMAP_USERNAME = "noa";
      JMAP_ACCOUNT_NAME = "seungwon";
      JMAP_MAILBOX_PATH = "INBOX";
      JMAP_MAILDIR = "/var/lib/noa-maildir/Flagged";
      JMAP_TRIGGER_PIPE = "/var/lib/opencrow/sessions/trigger.pipe";
    };
  };

  # A later JMAP EventSource or push webhook could trigger the same oneshot
  # for lower latency; keep this timer as the safety net.
  systemd.timers.noa-jmap-handoff = {
    description = "Periodically hand off seungwon flagged mail to Noa";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      Unit = "noa-jmap-handoff.service";
    };
  };
}
