# CI broker for radicle repos.
# Subscribes to rad node events and runs `.radicle/native.yaml` from any repo
# whose default branch is updated by the mulatta delegate. The native adapter
# executes the workflow under systemd hardening (PrivateTmp, ProtectSystem=strict, ...).
#
# Extensions on top of the upstream nixpkgs module:
#   - nix + rsync on the adapter PATH so flake-based sites can build and deploy
#     from the workflow script.
#   - nginx joined to the radicle group so it can read built artifacts served
#     from /var/lib/radicle-ci/<site>/current.
#   - pre-created per-site state dirs (mode 0750, radicle:radicle) that nginx
#     can traverse via group membership.
{ pkgs, ... }:
{
  services.radicle.ci = {
    adapters.native.instances.native = {
      runtimePackages = with pkgs; [
        bash
        coreutils
        curl
        gawk
        gitMinimal
        gnused
        wget
        nix
        rsync
      ];
    };

    broker = {
      enable = true;
      settings.triggers = [
        {
          adapter = "native";
          filters = [
            {
              And = [
                { HasFile = ".radicle/native.yaml"; }
                { Node = "z6MkkGbVHDVLst7JZgrH8iTCK6YGg4GJKAuEoPEcrokykNkk"; }
                "DefaultBranch"
              ];
            }
          ];
        }
      ];
    };
  };

  users.users.nginx.extraGroups = [ "radicle" ];

  systemd.tmpfiles.rules = [
    "d /var/lib/radicle-ci/blog 0750 radicle radicle -"
    "d /var/lib/radicle-ci/cv 0750 radicle radicle -"
    "d /var/lib/radicle-ci/homepage 0750 radicle radicle -"
  ];
}
