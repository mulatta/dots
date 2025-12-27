# Cloudflare API Token

**URL:** https://dash.cloudflare.com/profile/api-tokens

## Steps
1. Edit existing token or create new
2. Set **TTL** (recommended: 90 days)
3. Copy token

## Required Permissions
| Permission | Access |
|------------|--------|
| Zone:Zone | Read |
| Zone:DNS | Edit |
| Account:Cloudflare R2 | Edit |

## Update secrets
```bash
sops terraform/secrets.yaml
# Update CLOUDFLARE_API_TOKEN
```
