{
  config,
  pkgs,
  self,
  ...
}:
let
  dotfiles = "${self}/home";
  skillz = self.inputs.skillz;
  skillzPkgs = skillz.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  clan.core.vars.generators.opencrow-stalwart-dav = {
    files.stalwart-seungwon-password.secret = true;
    prompts.stalwart-seungwon-password = {
      description = "Stalwart/Kanidm password for seungwon DAV access to stalwart.mulatta.io — used for CalDAV and CardDAV syncing";
      type = "hidden";
    };
    script = ''
      cp "$prompts/stalwart-seungwon-password" "$out/stalwart-seungwon-password"
    '';
  };

  services.opencrow.rbwEntries."mulatta.io --field password" = "stalwart-seungwon-password";

  services.opencrow.credentialFiles."stalwart-seungwon-password" =
    config.clan.core.vars.generators.opencrow-stalwart-dav.files.stalwart-seungwon-password.path;

  services.opencrow.skills.todo = ./skills/todo;
  services.opencrow.skills.contacts = ./skills/contacts;
  services.opencrow.skills.calendar-cli = "${skillz}/calendar-cli/skills";

  services.opencrow.extraPackages = [
    (pkgs.runCommand "vdirsyncer-hooks" { } ''
      mkdir -p $out/bin
      cp ${dotfiles}/bin/vdirsyncer-post-hook $out/bin/
      cp ${dotfiles}/bin/vdirsyncer-pre-deletion-hook $out/bin/
      chmod +x $out/bin/*
    '')
    skillzPkgs.calendar-cli
    pkgs.todoman
    pkgs.vdirsyncer
  ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/vdirsyncer 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/vdirsyncer/config - - - - ${dotfiles}/.config/vdirsyncer/config"
    "d /var/lib/opencrow/.config/todoman 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/todoman/config.py - - - - ${dotfiles}/.config/todoman/config.py"
    "L+ /var/lib/opencrow/.config/todoman/__init__.py - - - - ${dotfiles}/.config/todoman/__init__.py"
    "d /var/lib/opencrow/.local/share/vdirsyncer 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.local/share/vdirsyncer/status 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.local/share/calendars 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.local/share/contacts 0750 opencrow opencrow -"
  ];
}
