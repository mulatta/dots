# taps nginx vhosts

Public-facing reverse-proxy and static-site vhosts on `taps`. This
directory is a NixOS module tree: `default.nix` wires the shared nginx
service settings, imports every per-vhost file, and injects shared
`_module.args` that vhosts consume.

## Layout

| File               | Role                                                                             |
| ------------------ | -------------------------------------------------------------------------------- |
| `default.nix`      | nginx core config, shared HTTP maps, catch-all 444 vhost, ACME defaults, imports |
| `lib/wg.nix`       | WireGuard peer-address helper (`wgHost`)                                         |
| `security-txt.nix` | RFC 9116 `security.txt`, WKD stub, `appWellKnownLocations` fragment              |
| `<service>.nix`    | One file per public hostname                                                     |

## Shared helpers (`_module.args`)

| Arg                      | Exposed by                   | What it is                                                                                                                  |
| ------------------------ | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `wgLib`                  | `default.nix` → `lib/wg.nix` | `wgLib.wgHost "malt"` → `{ ip, url }` where `url` is bracketed for IPv6                                                     |
| `securityTxtFile`        | `security-txt.nix`           | Nix-store path of the rendered security.txt; alias into vhosts                                                              |
| `openpgpkeyDir`          | `security-txt.nix`           | WKD stub directory (`policy` file + empty `hu/`); alias under `^~ /.well-known/openpgpkey/`                                 |
| `appWellKnownLocations`  | `security-txt.nix`           | Ready-to-merge `locations` attr: security.txt alias + regex 404 fallback for all other `/.well-known/*`                     |
| `securityHeadersConfig`  | `security-txt.nix`           | Pre-rendered `add_header` block (X-Frame-Options, X-Content-Type-Options, Referrer-Policy); concat into vhost `extraConfig` |
| `blockDottedPathsConfig` | `default.nix`                | Pre-rendered `if ($block_dotted) { return 404; }` block for app vhosts that should hide dot-prefixed paths                  |

## Shared HTTP maps (`default.nix` `appendHttpConfig`)

Both opt-in per vhost:

| Variable        | Truthy when…                                | How to opt in                                   |
| --------------- | ------------------------------------------- | ----------------------------------------------- |
| `$block_ai`     | UA matches the AI-crawler list              | `if ($block_ai) { return 403; }`                |
| `$block_dotted` | URI starts with `/.` except `/.well-known/` | `blockDottedPathsConfig` in vhost `extraConfig` |

## Adding a new vhost

### A. Simple localhost proxy

For services that bind to `127.0.0.1` and need nothing more than TLS +
reverse proxy. Examples: `atuin.nix`, `ntfy.nix`, `vaultwarden.nix`.

```nix
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:1234";
      proxyWebsockets = true;   # only if needed
    };
  };
}
```

### B. WG-proxied app (on another machine)

For services that run on `malt` (or any non-gateway peer) and taps
fronts them over WireGuard. Example: `nextcloud.nix`.

```nix
{ wgLib, ... }:
let
  malt = wgLib.wgHost "malt";
in
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    locations."/".proxyPass = "http://${malt.url}:1234";
  };
}
```

### C. SPA / proxied app with default-deny `.well-known`

Same as B, but the upstream is an SPA that would otherwise return
`index.html` for unknown `/.well-known/*` probes. Examples:
`vikunja.nix`, `nostr.nix`.

```nix
{ wgLib, appWellKnownLocations, securityHeadersConfig, ... }:
let
  malt = wgLib.wgHost "malt";
in
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    extraConfig = securityHeadersConfig + ''
      if ($block_dotted) { return 404; }
    '';
    locations = appWellKnownLocations // {
      "/" = {
        proxyPass = "http://${malt.url}:1234";
        proxyWebsockets = true;
      };
    };
  };
}
```

### D. Static content site

For Hugo/Zola output served from `/var/lib/radicle-ci/<site>/current`.
Examples: `blog.nix`, `mulatta-io.nix`.

```nix
{ securityTxtFile, openpgpkeyDir, ... }:
{
  services.nginx.virtualHosts."foo.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/lib/radicle-ci/foo/current";
    extraConfig = ''
      if ($block_dotted) { return 404; }
    '';
    locations."= /robots.txt".extraConfig = ''
      add_header Cache-Control "public, max-age=3600";
    '';
    locations."= /.well-known/security.txt" = {
      alias = "${securityTxtFile}";
      extraConfig = ''
        default_type "text/plain; charset=utf-8";
      '';
    };
    locations."^~ /.well-known/openpgpkey/" = {
      alias = "${openpgpkeyDir}/";
      extraConfig = ''
        default_type "application/octet-stream";
      '';
    };
    locations."/" = {
      tryFiles = "$uri $uri/ /index.html =404";
      extraConfig = ''
        if ($block_ai) { return 403; }
      '';
    };
  };
}
```

Finally, add the new file to the `imports` list in `default.nix`.

## Gotchas

1. **`locations` merge conflicts.** Mixing `locations = someAttr;` with
   `locations."x" = ...;` in the same module raises a nix merge
   conflict. When pulling in `appWellKnownLocations`, always spread it
   with `//`: `locations = appWellKnownLocations // { "/" = ...; };`.
2. **Location match precedence.** `= /path` (exact) > `^~ /prefix/`
   (non-regex prefix) > `~ regex` / `~* regex` > `/prefix` (prefix
   fallback). Use `^~` when a prefix block must shadow a later regex
   (e.g. WKD dir vs. `.well-known` default-deny).
3. **ACME HTTP-01.** `enableACME` wires `/.well-known/acme-challenge/`
   automatically; never add a conflicting location for that path.
4. **`$block_dotted` already allow-lists `/.well-known/`.** SPA
   fallbacks still need pattern C (per-vhost regex 404), because
   allow-listing only stops the shared map — it does not stop the
   upstream from answering.
5. **Nix-store secret leaks.** Never inline a secret into
   `services.nginx.virtualHosts.<h>.extraConfig` — it lands in the
   world-readable store. Use `alias` to a path produced by a
   secret-aware derivation, or fetch at runtime via `LoadCredential`.

## Renewal points

| What                   | When                             | Where                                                                                                                  |
| ---------------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `security.txt` Expires | Before `2027-04-22`              | `security-txt.nix` (`expires` binding). Bump, redeploy, update the Vikunja reminder.                                   |
| `ai-robots-txt` lock   | Quarterly or on crawler outbreak | `~/git/blog` and `~/git/homepage` — `nix flake update ai-robots-txt`                                                   |
| WKD key publication    | When a PGP key exists            | Drop the binary into `openpgpkeyDir`'s `hu/<z-base32-sha1(localpart)>`, then bump `Encryption:` in `security-txt.nix`. |
