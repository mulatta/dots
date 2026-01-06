# Terraform Infrastructure

Infrastructure-as-Code for mulatta.io services.

## Modules

| Module     | Purpose                   | Secrets Used                                                         |
| ---------- | ------------------------- | -------------------------------------------------------------------- |
| vultr      | VPS provisioning          | `VULTR_API`                                                          |
| cloudflare | DNS A records, R2 buckets | Cloudflare token from clan vars                                      |
| github     | Repository management     | `GITHUB_TOKEN`                                                       |
| aws        | SES SMTP relay            | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLOUDFLARE_API_TOKEN` |

## Secrets Management

### Terraform-only secrets (`secrets.yaml`)

Secrets used exclusively by Terraform are stored in `terraform/secrets.yaml` (SOPS encrypted):

- `VULTR_API` - Vultr API key for VPS management
- `GITHUB_TOKEN` - GitHub API token for repo management
- `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY` - Cloudflare R2 for Terraform state backend
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` - AWS (SES, IAM)
- `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID` - Cloudflare (shared, also in Terraform)

### Shared secrets (clan.core.vars)

Secrets shared between Terraform and NixOS are managed by clan.core.vars:

- `cloudflare-api/token` - Cloudflare API token
  - Terraform reads from: `vars/per-machine/taps/cloudflare-api/token/secret`
  - NixOS reads via: `config.clan.core.vars.generators.cloudflare-api.files."token".path`

## Dependency Order

```
1. vultr      → Creates VPS, outputs IP
2. cloudflare → Creates A records (reads vultr state for IP)
3. aws        → Creates SES domain, DKIM records in Cloudflare
4. NixOS      → Deploys services (reads cloudflare-api token from clan vars, SES credentials)
```

## Usage

```bash
# Generate shared secrets (first time only)
CLAN_NO_COMMIT=1 clan vars generate taps

# Apply infrastructure
cd terraform/vultr && terragrunt apply
cd terraform/cloudflare && terragrunt apply
cd terraform/aws && terragrunt apply

# Copy SES SMTP credentials to NixOS secrets (see aws/README.md)

# Deploy NixOS
clan machines update taps
```

## Remote State

Terraform state is stored in S3 (`mulatta-dots-tfstate` bucket) with DynamoDB locking.

The `cloudflare` module reads `vultr` state to get the VPS IP for DNS A records.
This is a one-way dependency (not circular).
