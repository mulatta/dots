# Miniflux provisioning module

This module extends the existing NixOS `services.miniflux` namespace with a
`services.miniflux.provision` subtree. It provides ensure-style provisioning for
Miniflux users, API keys, UI assets, and feeds after the Miniflux service and
database are available.

The module is intended for local infrastructure, not for upstream Miniflux
configuration generation or Terraform-style exact-state reconciliation. Miniflux
has no native declarative feed provisioning file, so the module uses a small DB
bootstrap step for the minimum state needed to authenticate to the API, then
performs non-destructive feed and asset reconciliation via the Miniflux API.

## Design goals

- Follow NixOS `ensureUsers`/`ensureDatabases` style semantics for durable
  application state.
- Bootstrap from an empty Miniflux database without manually creating API keys.
- Use an existing Miniflux API key when user/bootstrap management is not needed.
- Keep Miniflux feed history intact by updating existing feeds in place.
- Treat feed URLs as stable identities and never delete missing feeds.
- Keep secrets out of the Nix store by using runtime credential files.
- Keep RSSHub route/package customization outside this module.
- Support per-Miniflux-user provisioning units.

## Non-goals

- Owning the exact set of feeds present in a Miniflux account.
- Deleting feeds that were removed from the Nix configuration.
- Recreating feeds to apply changes.
- Managing RSSHub packages, routes, or credentials.
- Provisioning password-based Miniflux login credentials.
- Automatically overwriting an existing user's OIDC subject.
- Guessing the API endpoint from Miniflux `BASE_URL` or `LISTEN_ADDR`.

## Supported authentication modes

The provisioning API calls always authenticate with a Miniflux API token.

With `ensureUser = false`, the token must already exist in Miniflux. This mode
works with any Miniflux authentication backend because the module only performs
API reconciliation.

With `ensureUser = true`, the module bootstraps the Miniflux user and API key in
the database before calling the API. Automatic bootstrap supports OIDC-bound
users and API-only local users. It does not create or rotate password-based login
credentials.

For OIDC-bound users, the OIDC provider and Miniflux OIDC settings must be
configured separately. This module only ensures the Miniflux `openid_connect_id`
binding is present and safe.

## Proposed configuration

OIDC-bound user bootstrap:

```nix
services.miniflux = {
  enable = true;

  provision = {
    enable = true;
    apiEndpoint = "http://[fd00::1]:8080";

    users.seungwon = {
      enable = true;
      ensureUser = true;
      username = "seungwon";
      openidConnectIdFile = config.clan.core.vars.generators.miniflux-seungwon.files.oidc-sub.path;
      apiTokenFile = config.clan.core.vars.generators.miniflux-seungwon.files.api-token.path;
      apiKeyDescription = "nixos-provisioning";

      stylesheet = ./custom.css;
      javascript = ./custom.js;

      feeds.githubTrendingRust = {
        url = "http://127.0.0.1:1200/github/trending-readme/daily/rust?limit=20";
        category = "GitHub Trending";
      };
    };
  };
};
```

Existing API key mode:

```nix
services.miniflux.provision = {
  enable = true;
  apiEndpoint = "http://[fd00::1]:8080";

  users.seungwon = {
    ensureUser = false;
    apiTokenFile = config.clan.core.vars.generators.miniflux-seungwon.files.api-token.path;

    feeds.example = {
      url = "https://example.com/feed.xml";
      category = "Example";
    };
  };
};
```

`apiEndpoint` is the URL used by the provisioning job to access the Miniflux API.
It is not the public canonical `BASE_URL`. The caller must set it explicitly
because Miniflux `LISTEN_ADDR` may contain multiple addresses, IPv6 literals,
wildcard addresses, or Unix sockets.

## Runtime model

For each enabled `services.miniflux.provision.users.<name>`, the module creates:

```text
miniflux-provisioning-<name>.service
miniflux-provisioning-<name>.timer    # optional
```

The service runs after `miniflux.service`. It performs ensure-style
reconciliation:

1. DB bootstrap
   - ensure the Miniflux user exists when `ensureUser = true`
   - ensure the default `All` category exists
   - ensure the `integrations` row exists
   - ensure an API key with `apiKeyDescription` exists and has the declared token
2. API provisioning
   - sync stylesheet and custom JavaScript
   - create missing categories
   - create missing feeds
   - update existing feed settings in place
   - report orphan feeds without deleting them

The DB bootstrap is intentionally limited to user and API-key state. Feeds and
assets are reconciled through the public Miniflux API.

Provisioning output is written to the systemd journal, not to Nix evaluation or
`nixos-rebuild` output. Check run status, feed updates, and orphan/drift reports
with:

```sh
systemctl status miniflux-provisioning-<name>.service
journalctl -u miniflux-provisioning-<name>.service
```

The implementation logic lives in `packages/miniflux-sync`. The NixOS module
renders configuration, wires credentials, and creates systemd units; it should not
inline the API client or database bootstrap code.

## Bootstrap safety

Miniflux stores API tokens in plaintext in the `api_keys.token` column and looks
up users with `api_keys.token = $1`. This makes deterministic bootstrap possible:
the token can be generated by clan vars or another secret manager before the
first deployment, then inserted into Miniflux by the provisioning service.

The bootstrap helper must use parameterized database queries. Shell heredocs with
interpolated SQL are forbidden because usernames, OIDC subjects, and tokens are
runtime values.

OIDC binding policy when an OIDC subject is declared:

```text
user missing                            -> create with username + OIDC subject
user exists and openid_connect_id empty -> set the declared OIDC subject
user exists and openid_connect_id same  -> continue
user exists and openid_connect_id differs -> fail hard
```

When no OIDC subject is declared, `ensureUser = true` creates or updates only the
API provisioning state for an API-only local user. It must not create a password
hash.

The last case prevents accidentally binding an existing Miniflux account to a
different OIDC identity.

## Secret model

Use separate secret files per consumer.

```text
RSSHub service:
  GITHUB_ACCESS_TOKEN

Miniflux provisioning user:
  MINIFLUX_TOKEN / api token file
  optional OIDC subject file
```

The RSSHub GitHub PAT belongs to `services.rsshub` and must not be exposed to
Miniflux provisioning jobs. Miniflux API tokens belong to individual Miniflux
users and must not be exposed to RSSHub.

Prefer `apiTokenFile` plus systemd `LoadCredential` over an `EnvironmentFile`.
The wrapper can export `MINIFLUX_TOKEN` from `$CREDENTIALS_DIRECTORY` before
running `miniflux-sync`.

## Feed identity and history preservation

Miniflux feed history is preserved only when existing feeds are updated in place.
This module treats feed URL as the identity used to find an existing feed. It is
not exact-state reconciliation: it must never delete missing feeds or recreate
feeds to apply changes.

Preserved state includes read, starred, and shared entries because Miniflux stores
that state on entries, and refreshing/updating an existing feed does not update
entry `status`, `starred`, or `share_code`.

Changing a feed URL creates a new feed. The old feed becomes an orphan and keeps
its history until manually removed. To preserve state while changing a URL,
change it manually in Miniflux first, update the Nix declaration to the same URL,
and avoid running provisioning between those two steps.

Removing a feed from the Nix declaration only stops managing it. It does not hide
or delete the feed from Miniflux. Retiring, hiding, archiving, or deleting a feed
is intentionally left to manual Miniflux operation.

Deleting a feed in Miniflux is destructive because entries belong to the feed and
are deleted with it. Re-adding the same URL later creates a new feed and does not
restore the old read, starred, or shared entry state.

## Assertions

The module should assert:

- `services.miniflux.provision.enable -> services.miniflux.enable`
- `services.miniflux.provision.enable -> services.miniflux.provision.apiEndpoint != null`
- any enabled `ensureUser = true` user -> `services.miniflux.config.DATABASE_URL != null`
- at least one enabled provisioning user exists
- provisioning user attr names match `^[A-Za-z0-9_-]+$`
- each enabled user sets `apiTokenFile`
- each `ensureUser = true` user sets `username`
- for OIDC bootstrap, each `ensureUser = true` user sets exactly one of
  `openidConnectId` or `openidConnectIdFile`
- feed URLs are unique per user
- each feed sets a non-empty `category`
- `openidConnectId` and `openidConnectIdFile` are not both set

The module should warn when `scraperRules` is set without `crawler = true`.

## Feed option shape

Feeds are declared as an attrset to provide stable local names:

```nix
feeds.<name> = {
  url = "...";
  category = "...";
  title = null;
  description = null;
  siteUrl = null;
  crawler = null;
  scraperRules = null;
  rewriteRules = null;
  urlRewriteRules = null;
  blocklistRules = null;
  keeplistRules = null;
  blockFilterEntryRules = null;
  keepFilterEntryRules = null;
  disabled = null;
  ignoreEntryUpdates = null;
  ignoreHttpCache = null;
  allowSelfSignedCertificates = null;
  fetchViaProxy = null;
  hideGlobally = null;
  noMediaPlayer = null;
  disableHttp2 = null;
  userAgent = null;
  proxyUrl = null;
  cookieFile = null;
  usernameFile = null;
  passwordFile = null;
};
```

Nix options use camelCase. The generated manifest uses the Miniflux API field
names expected by `miniflux-sync`.

## Implementation notes

- Keep `miniflux-sync` as a package under `packages/miniflux-sync` so the API
  reconciliation and DB bootstrap logic can be tested independently.
- Use Nix-generated shell wrappers only for systemd glue such as credential
  loading, environment setup, and runtime manifest materialization.
- Generate a JSON manifest with `pkgs.writeText` and `builtins.toJSON` to avoid an extra format-conversion derivation.
- Omit `null` fields from generated feed entries.
- Read secret files at runtime, not during evaluation.
- Run the provisioning service as the `miniflux` system user when using the
  local PostgreSQL database and peer authentication.
- Keep the DB bootstrap helper small and covered by tests.
- Extend `miniflux-sync` with regression coverage for updating feed settings
  without losing read/starred state.
