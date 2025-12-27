# GitLab Personal Access Token

**URL:** https://gitlab.com/-/user_settings/personal_access_tokens

## Steps
1. Token name: `terraform`
2. Expiration: 90 days (max 365 days)
3. Select scopes below
4. Create token

## Required Scopes
| Scope | Description |
|-------|-------------|
| api | Full API access |
| read_user | Read user info |
| read_repository | Read repos |
| write_repository | Write repos |

## Update secrets
```bash
sops terraform/secrets.yaml
# Update GITLAB_TOKEN
```
