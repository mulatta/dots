# Rustic

Configures one host-specific Rustic repository per client and archives registered `clan.core.state` folders in one scheduled job. ZFS clients read those paths from one temporary snapshot; other filesystems are backed up live. Repository credentials, pruning, and checks remain service-owned.

```nix
rustic-r2 = {
  module.name = "rustic";
  module.input = "self";
  roles.client.settings.bucket = "backup";
  roles.client.tags.backup = { };
  roles.client.extraModules = [ ../nixosModules/rustic ];
};
```

Each client uses its machine name as an OpenDAL S3 prefix in configured R2 bucket. Backups run daily at 04:00, pruning runs Sunday at 05:00, and repository checks run monthly at 06:30 unless role settings override those defaults.

The module registers Rustic as a Clan backup provider. `clan backups list` reports full Rustic snapshot IDs, `clan backups create` starts the aggregate system job, and `clan backups restore` restores only folders registered through `clan.core.state`.
