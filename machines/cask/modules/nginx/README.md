# cask nginx vhosts

Public-facing reverse-proxy and static-site vhosts on `cask`. This
directory contains shared edge policy and routes owned by nginx itself.
Service modules keep their own vhosts beside service lifecycle configuration.
`default.nix` owns cask listeners, the shared public certificate, firewall, and
shared HTTP maps. Generic `.n` access policy lives in `nixosModules/nginx.nix`.

## Layout

| File               | Role                                                                                               |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| `default.nix`      | nginx core config, listeners, shared HTTP maps and certificate, catch-all vhost, firewall, imports |
| `mulatta-io.nix`   | apex vhost and `www` redirect                                                                      |
| `nip05.nix`        | apex NIP-05 response                                                                               |
| `security-txt.nix` | RFC 9116 `security.txt`, WKD stub, and shared well-known locations                                 |
| `<route>.nix`      | Static, redirect, or cross-host ingress owned by nginx                                             |

Local services declare their routes in the sibling `../<service>.nix` module.

## Shared HTTP map (`default.nix` `appendHttpConfig`)

Vhosts opt in explicitly:

| Variable        | Truthy when…                                | How to opt in                        |
| --------------- | ------------------------------------------- | ------------------------------------ |
| `$block_dotted` | URI starts with `/.` except `/.well-known/` | `if ($block_dotted) { return 404; }` |

## Adding a new vhost

### A. Simple localhost proxy

For services that bind to `127.0.0.1`, put the vhost in the sibling service
module beside its lifecycle configuration. Examples: `../atuin.nix`,
`../ntfy.nix`, `../vaultwarden.nix`.

```nix
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:1234";
      proxyWebsockets = true;   # only if needed
    };
  };
}
```

### B. Naru-proxied app (on another machine)

For services that run on `malt` (or any non-gateway peer) and cask
fronts them over Naru. Example: `nextcloud.nix`.

```nix
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    locations."/".proxyPass = "http://malt.n:1234";
  };
}
```

### C. SPA / proxied app with default-deny `.well-known`

Keep service-specific routes in the owner module. `security-txt.nix` adds the
shared security endpoint and well-known fallback to participating vhosts.
Security headers stay explicit because applications such as Jellyfin require
different frame policies.

```nix
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;

    extraConfig = ''
      add_header X-Frame-Options "DENY" always;
      if ($block_dotted) { return 404; }
    '';
    locations."/" = {
      proxyPass = "http://malt.n:1234";
      proxyWebsockets = true;
    };
  };
}
```

Add nginx-owned route files to `default.nix`. Sibling service modules are
already imported by `machines/cask/configuration.nix`; do not import them from
nginx as well.

## Gotchas

1. **`locations` merge conflicts.** Shared well-known routes are merged from
   `security-txt.nix`; do not redefine the same location in a service module.
2. **Location match precedence.** `= /path` (exact) > `^~ /prefix/`
   (non-regex prefix) > `~ regex` / `~* regex` > `/prefix` (prefix
   fallback). Use `^~` when a prefix block must shadow a later regex
   (e.g. WKD dir vs. `.well-known` default-deny).
3. **Ingress policy.** `default.nix` gives every vhost loopback, Naru, and
   public listeners plus HTTP/3. Each public owner must explicitly set
   `useACMEHost = "mulatta.io"` and `forceSSL = true`; `_` and `ca.x` keep
   explicit TLS behavior. Generic `.n` vhosts allow only Naru source ranges
   through `nixosModules/nginx.nix`.
4. **QUIC firewall parity.** HTTP/3 needs UDP 443 in both the NixOS firewall and
   the Vultr firewall. Keep those rules with the shared nginx policy.
5. **Shared certificate.** Every public vhost name becomes an HTTP-01 SAN on
   `mulatta.io`. After Knot becomes public authority, replace this with its
   RFC2136 wildcard certificate.
6. **`$block_dotted` already allow-lists `/.well-known/`.** Add shared
   well-known fallbacks in `security-txt.nix` for SPA vhosts.
7. **Nix-store secret leaks.** Never inline a secret into
   `services.nginx.virtualHosts.<h>.extraConfig` — it lands in the
   world-readable store. Use `alias` to a path produced by a
   secret-aware derivation, or fetch at runtime via `LoadCredential`.

## Renewal points

| What                   | When                  | Where                                                                                                                  |
| ---------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `security.txt` Expires | Before `2027-04-22`   | `security-txt.nix` (`expires` binding). Bump, redeploy, update the Vikunja reminder.                                   |
| WKD key publication    | When a PGP key exists | Drop the binary into `openpgpkeyDir`'s `hu/<z-base32-sha1(localpart)>`, then bump `Encryption:` in `security-txt.nix`. |
