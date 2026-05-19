# Bulwark Webmail NixOS module

Bulwark Webmail is a Next.js JMAP webmail client for Stalwart Mail Server. This module runs the native Nix package as a systemd service and keeps mutable application state in `/var/lib/bulwark-webmail`.

## Basic service

```nix
{
  services.bulwark-webmail = {
    enable = true;
    jmapServerUrl = "https://mail.example.com";
    sessionSecretFile = config.sops.secrets.bulwark-webmail-session-secret.path;
    settingsSync.enable = true;
  };
}
```

`sessionSecretFile` is required for remember-me sessions, settings sync, and server-side SSO. Generate it with at least 32 bytes of entropy, for example `openssl rand -base64 32`.

## nginx reverse proxy

```nix
{
  services.bulwark-webmail = {
    enable = true;
    jmapServerUrl = "https://mail.example.com";
    sessionSecretFile = config.sops.secrets.bulwark-webmail-session-secret.path;

    nginx = {
      enable = true;
      hostName = "webmail.example.com";
      enableACME = true;
      forceSSL = true;
    };
  };
}
```

## Subpath deployment

Next.js bakes `basePath` into the build output. Changing this option rebuilds the package.

```nix
{
  services.bulwark-webmail = {
    enable = true;
    basePath = "/webmail";
    nginx = {
      enable = true;
      hostName = "mail.example.com";
    };
  };
}
```

## Kanidm SSO

Kanidm support is a convenience wrapper around Bulwark's generic OIDC support. No separate Bulwark authentication backend is used. Bulwark obtains an OIDC access token and then presents it to Stalwart as a JMAP Bearer token, so Stalwart must be configured to trust the Kanidm issuer, audience, and relevant claims.

```nix
{
  services.bulwark-webmail = {
    enable = true;
    jmapServerUrl = "https://mail.example.com";
    sessionSecretFile = config.sops.secrets.bulwark-webmail-session-secret.path;

    kanidm = {
      enable = true;
      origin = "https://idm.example.com";
      clientId = "bulwark-webmail";
      clientSecretFile = config.sops.secrets.bulwark-webmail-kanidm-client-secret.path;
      oauthOnly = true;
      autoSso = true;
    };
  };
}
```

The module derives:

```text
OAUTH_ISSUER_URL=https://idm.example.com/oauth2/openid/bulwark-webmail
```

Register callback URLs in Kanidm for every served locale that users can reach:

```text
https://webmail.example.com/en/auth/callback
https://webmail.example.com/ko/auth/callback
```

When `basePath = "/webmail"`, include the prefix:

```text
https://mail.example.com/webmail/en/auth/callback
```

## Generic OAuth2 / OIDC

Use `oauth` when the issuer is not Kanidm, or when Stalwart itself is the OAuth issuer.

```nix
{
  services.bulwark-webmail = {
    enable = true;
    jmapServerUrl = "https://mail.example.com";
    sessionSecretFile = config.sops.secrets.bulwark-webmail-session-secret.path;

    oauth = {
      enable = true;
      only = true;
      autoSso = true;
      clientId = "bulwark-webmail";
      issuerUrl = "https://idp.example.com/oauth2/openid/bulwark-webmail";
      clientSecretFile = config.sops.secrets.bulwark-webmail-oauth-client-secret.path;
      scopes = "openid email profile";
    };
  };
}
```

Leave `issuerUrl = null` to let Bulwark discover OAuth metadata from `jmapServerUrl`. If `jmapServerUrl` points at a same-origin JMAP proxy, set `issuerUrl` to the public Stalwart origin instead, for example `https://mail.example.com`.

## Mutable state

The service creates these directories:

```text
/var/lib/bulwark-webmail/settings
/var/lib/bulwark-webmail/admin
/var/lib/bulwark-webmail/telemetry
/var/lib/bulwark-webmail/version-check
```

Telemetry and upstream version checks are disabled by default in the module. Enable explicitly:

```nix
{
  services.bulwark-webmail.telemetry.enable = true;
  services.bulwark-webmail.updateCheck.enable = true;
}
```

## Known limits

- The module cannot verify that Kanidm and Stalwart trust is configured correctly.
- Calendar, sharing, and file features depend heavily on the deployed Stalwart version.
- `basePath` is build-time, not runtime.
- Admin password bootstrap currently uses `environment.ADMIN_PASSWORD`; upstream does not support `ADMIN_PASSWORD_FILE` yet.

## Test

The flake exposes a Linux NixOS VM test:

```bash
nix build .#checks.x86_64-linux.bulwark-webmail --no-link -L
```

The test verifies service startup, health endpoint, state directories, and Kanidm/OIDC credential wiring.
