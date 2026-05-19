# slack-manifest-cli

Manage Slack app manifests from raw YAML or JSON files.

## Config

Config path follows XDG:

```text
~/.config/slack-manifest/config.json
```

Example:

```json
{
  "token_command": "rbw get slack-manifest-deploy-token"
}
```

Per-manifest app IDs live in repo-local `slack-manifest-state.json`, not in raw Slack manifests.

```json
{
  "version": 1,
  "manifests": {
    "definitions/read.yaml": {
      "app_id": "A1234567890"
    }
  }
}
```

Priority: CLI flags > environment variables > `*_command` > direct config values.

Environment variables:

- `SLACK_MANIFEST_TOKEN`
- `SLACK_MANIFEST_APP_ID`
- `SLACK_MANIFEST_API_BASE`
- `SLACK_MANIFEST_TIMEOUT`

## Usage

```bash
slack-manifest validate definitions/read.yaml
slack-manifest adopt definitions/read.yaml A1234567890
slack-manifest diff definitions/read.yaml
slack-manifest apply definitions/read.yaml
slack-manifest --app-id A1234567890 export --output definitions/read.yaml --save
```

`apply` updates when app_id is known from CLI/config/state. Use `apply --create` or `create --save` only for new apps.
