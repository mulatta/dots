# Vultr API Key

**URL:** https://my.vultr.com/settings/#settingsapi

## Steps
1. Personal Access Token section
2. Add new key or regenerate existing
3. Set expiration (recommended: 90 days)
4. Copy key (shown only once)

## Update secrets
```bash
sops terraform/secrets.yaml
# Update VULTR_API
```
