# GitHub Fine-grained PAT

**URL:** https://github.com/settings/personal-access-tokens/new

## Steps
1. Token name: `terraform`
2. Expiration: 90 days (recommended)
3. Repository access: All repositories
4. Set permissions below
5. Generate token

## Required Permissions
| Permission | Access |
|------------|--------|
| Administration | Read and write |
| Contents | Read and write |
| Metadata | Read-only (default) |
| Pull requests | Read and write |
| Workflows | Read and write |
| Secrets | Read and write |
| Variables | Read and write |

## Update secrets
```bash
sops terraform/secrets.yaml
# Update GITHUB_TOKEN
```
