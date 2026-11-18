# RustFS on citra

The machine module uses nixpkgs RustFS 1.0.4 and its NixOS service module.
The RustFS overlay backports the build dependencies from
[NixOS/nixpkgs#584912](https://github.com/NixOS/nixpkgs/pull/584912).
The fix is merged into nixos-unstable; a full input update is deferred to avoid
changing unrelated production services during this deployment. Remove the
overlay once the pinned package includes the upstream fix.
Console, OIDC callbacks and the S3 API share `https://s3.mulatta.io`.
The Console UI lives under `/rustfs/console/`; S3 clients use the origin as
their endpoint with path-style bucket addressing.

Cloudflare DNS points directly to cask (DNS-only). Cask terminates HTTPS
with its shared public certificate and proxies the unchanged Host and URI
over Naru to citra's IPv4 address on port 9001. The backend firewall permits
only cask's Naru address. Port 9000 remains loopback-only. Headscale is not
part of this service's access path.

## Kanidm

The confidential client `rustfs` uses PKCE and the issuer
`https://idm.mulatta.io/oauth2/openid/rustfs`. Its redirect URI is exactly
`https://s3.mulatta.io/rustfs/admin/v3/oidc/callback/kanidm`.

| Kanidm group    | Access                                                                            |
| --------------- | --------------------------------------------------------------------------------- |
| `rustfs_users`  | May log in; `readwrite` policy grants access to all S3 buckets                    |
| `rustfs_admins` | Adds the `consoleAdmin` policy; also needs membership in `rustfs_users` to log in |

Initially only `seungwon` belongs to both groups. Policies arrive as the
`rustfs_policy` array claim. Both RustFS claim selectors read that claim, so
ordinary Kanidm group names cannot become storage policy names.

The shared Clan generator `kanidm-rustfs-oidc` provides the same client secret
to Kanidm on cask and RustFS on citra. The `rustfs` generator provides separate
root credentials. systemd reads both runtime environment files; secrets are
not embedded in Nix settings or the store. Secret generation and deployment
are separate from configuration evaluation; ungenerated Clan paths evaluate
to `/no-such-path` until the normal Clan generation workflow runs.

For a future deployment, provision cask's Kanidm client and groups before
starting RustFS on citra, then verify Console login and STS
`AssumeRoleWithWebIdentity` using an ID token for this client. Configuration
evaluation alone does not verify a live login.

## Policy ownership

The policy documents for `readwrite` and `consoleAdmin` are RustFS built-ins.
Nix declares the Kanidm group-to-policy-name mapping, not those policy bodies.
No custom IAM policy or bucket policy is currently provisioned.

For bucket-specific access, manage custom policy documents and buckets in a
separate Terraform unit after selecting and validating a RustFS-compatible
provider. Keep OIDC group mappings in Kanidm and use the same custom policy
names there. S3 API compatibility alone does not imply AWS IAM API compatibility.
Keep this unit's state in the existing external backend, not the RustFS
instance it manages.

## Storage

Persistent data is owned by `rustfs` under `/var/lib/rustfs`, mode `0700`.
Terraform manages the `neko-transfer` bucket on this single-node deployment.

OIDC settings were checked against the pinned server tag
[`1.0.4`](https://github.com/rustfs/rustfs/tree/1.0.4/crates/iam/src/oidc) and
Console tag [`v0.1.37`](https://github.com/rustfs/console/tree/v0.1.37).

### Neko staging transfer

The citra worker reads its `citra` S3 key from the Clan var
`neko-rustfs-transfer/env`. RustFS grants it the `transfer-worker` policy.
The client reads its `rhesus` S3 key from the `neko-rustfs-client` rbw
item. RustFS grants it the `transfer-client` policy.

The export timer copies completed top-level staging downloads to
`neko-transfer/downloads/`. The import timer copies objects from
`neko-transfer/uploads/` to local staging for Chromium. Both run as the
existing `transfer` user and use the loopback S3 endpoint. They skip hidden
names, Chromium partial downloads, rclone partial files, and names already
present at the destination. The export considers sources up to seven days old.
The import only considers sources up to one day old so expired local uploads
are not staged again. Use unique names.
The timers copy files, so staging and RustFS each retain a copy. Local
staging expires through systemd-tmpfiles after one day based on mtime.
Terraform configures seven-day object expiration for the RustFS bucket.

The citra credential needs bucket listing scoped to both prefixes, object
write and read-back for `downloads/*`, and object read for `uploads/*`.
