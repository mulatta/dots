# Terraform Infrastructure

Infrastructure-as-Code for mulatta.io services.

## Modules

| Module     | Purpose                   | Secrets Used                                                         |
| ---------- | ------------------------- | -------------------------------------------------------------------- |
| vultr      | VPS provisioning          | `VULTR_API`                                                          |
| cloudflare | DNS A records, R2 buckets | Cloudflare token from clan vars                                      |
| aws        | SES SMTP relay            | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLOUDFLARE_API_TOKEN` |

## Secrets Management

### Terraform-only secrets (`secrets.yaml`)

Secrets used exclusively by Terraform are stored in `terraform/secrets.yaml` (SOPS encrypted):

- `VULTR_API` - Vultr API key for VPS management
- `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` - Cloudflare R2 for Terraform state backend
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` - AWS (SES, IAM)
- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` - Cloudflare (shared, also in Terraform)

## Dependency Order

```
1. vultr      → Creates VPS, outputs IP
2. cloudflare → Creates A records (reads vultr state for IP)
3. aws        → Creates SES domain, DKIM records in Cloudflare
4. NixOS      → Deploys services (reads cloudflare-api token from clan vars, SES credentials)
```

## Usage

```bash
# Apply infrastructure
cd terraform/vultr && terragrunt apply
cd terraform/cloudflare && terragrunt apply
cd terraform/aws && terragrunt apply

# Copy SES SMTP credentials to NixOS secrets (see aws/README.md)

# Deploy NixOS
clan machines update cask
```

## Reserved IP

The production Reserved IP is attached to cask and supplies the stable address
consumed by Cloudflare remote state. Preserve `prevent_destroy` and import an
existing address before adding this module to fresh Terraform state.

## Remote State

Terraform state is stored in S3 (`mulatta-dots-tfstate` bucket) with DynamoDB locking.

The `cloudflare` module reads `vultr` state to get the VPS IP for DNS A records.
This is a one-way dependency (not circular).

## Cloudflare scope (design note)

Cloudflare is used as a **DNS registrar only**. Every A record in
`cloudflare/dns.tf` sets `proxied = false`, and that is intentional:

- Mail (SMTP/IMAP), Nostr relay (strfry), Radicle p2p, `cache.mulatta.io`,
  and the internal step-ca PKI all use protocols or trust chains that are
  incompatible with Cloudflare's HTTP proxy.
- TLS is terminated at origin with Let's Encrypt (`nixosModules/acme.nix`),
  which keeps a single consistent chain across all services and avoids
  routing traffic metadata through Cloudflare.

Consequences for Terraform:

- `cloudflare_bot_management` and related managed robots.txt / AI scraper
  controls are not used here. Cloudflare's Free plan rejects those API
  calls on a DNS-only zone (`10405 Method not allowed for this
authentication scheme`), and enabling them would require switching
  records to `proxied = true` — a design reversal.
- AI crawler defense is handled at origin: the homepage robots.txt is
  generated from the pinned `ai-robots-txt/ai.robots.txt` upstream, and
  `machines/cask/modules/nginx/mulatta-io.nix` hard-blocks known
  AI user agents with a 403.

Revisit this note if Cloudflare's Free-plan Terraform support for AI bot
protection ships and the self-host trust boundaries shift.

## Provider reproducibility

Nix is the single authority for OpenTofu and provider versions. The Terraform
shell supplies `opentofu.withPlugins`; update `flake.lock` to update providers.
Do not add duplicate provider version pins or commit `.terraform.lock.hcl`.
Generated lock files describe the local Nix-built packages, not a portable set
of registry archives.

Use the declared shell for every Terragrunt command, including automation:

```sh
nix develop .#terraform -c terragrunt --working-dir terraform/cloudflare init
nix develop .#terraform -c terragrunt --working-dir terraform/cloudflare plan
```

The shell selects the Nix-packaged `tofu` and disables Terragrunt's automatic
and explicit provider cache. These settings do not depend on loading `.envrc`.
A Nix-generated guard verifies the exact packaged executable before initialization
or provider/state operations. It rejects `TG_TF_PATH` overrides, inherited
`TF_PLUGIN_CACHE_DIR`, `TF_CLI_CONFIG_FILE`, `TF_DATA_DIR`, or `TG_DOWNLOAD_DIR`,
and changed cache controls.
These are operational checks, not a security boundary against a user who can
modify the environment or invoke OpenTofu directly.

Each unit uses `.terragrunt-cache/<Nix-package-basename>/` for its execution
cache. The basename identifies the complete `opentofu.withPlugins` package, so
changing OpenTofu or a provider selects a fresh cache. Both `.terraform/` and
`.terraform.lock.hcl` stay inside that cache; source-directory lock files and
provider metadata are excluded from copying, and locks are not copied back.

Terragrunt auto-init initializes a fresh cache before the first plan. Subsequent
plans reuse it without reinitializing unless Terragrunt detects another reason
to initialize, such as changed modules or backend configuration. Initialization
can require credentials and network access. No hook deletes provider metadata.

An init hook rejects automatic initialization triggered by `apply`. If its cache
is missing or environment changed, create and review a new plan first. Keep
saved plans outside the disposable cache using an absolute `-out` path. Old
cache directories can be removed when no active operation needs them; never
remove remote state.

Keep the same flake revision, platform, and initialized provider selection from
saved-plan creation through apply. Do not update Nix inputs or reinitialize with
a different environment between them. Store plans with restricted permissions;
they can contain secrets. Only apply a reviewed plan with explicit approval.
