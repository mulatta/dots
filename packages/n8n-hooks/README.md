# n8n-hooks

CLI to invoke authenticated n8n webhooks. Supports storing email drafts,
read-only GitHub, Slack, RSS, Vikunja, and Linkwarden context access,
template-aware Vikunja task creation requests, and confirmed Linkwarden link
creation.

## Configuration

`$XDG_CONFIG_HOME/n8n-hooks/config.json`:

```json
{
  "hooks": {
    "store-draft": {
      "url": "https://n8n.example.test/webhook/mail-draft-store",
      "token_command": "rbw get n8n-hooks-token"
    },
    "github": {
      "url": "https://n8n.example.test/webhook/context-github",
      "token_command": "rbw get n8n-hooks-token"
    },
    "slack": {
      "url": "https://n8n.example.test/webhook/context-slack",
      "token_command": "rbw get n8n-hooks-token"
    },
    "rss": {
      "url": "https://n8n.example.test/webhook/context-rss",
      "token_command": "rbw get n8n-hooks-token"
    },
    "vikunja": {
      "url": "https://n8n.example.test/webhook/context-vikunja",
      "token_command": "rbw get n8n-hooks-token"
    },
    "vikunja-task-create": {
      "url": "https://n8n.example.test/webhook/vikunja-task-create",
      "token_command": "rbw get n8n-hooks-token"
    },
    "linkwarden": {
      "url": "https://n8n.example.test/webhook/context-linkwarden",
      "token_command": "rbw get n8n-hooks-token"
    },
    "linkwarden-link-create": {
      "url": "https://n8n.example.test/webhook/linkwarden-link-create",
      "token_command": "rbw get n8n-hooks-token"
    }
  }
}
```

Use `token` instead of `token_command` for a literal shared bearer token.

## Usage

```sh
n8n-hooks store-draft --to "a@b.com" --subject "Hi" --body-plain "Hello"
n8n-hooks github /repos/NixOS/nixpkgs/pulls/12345/files -q per_page=100
n8n-hooks slack replies C0123456789 1712345678.123456
n8n-hooks slack file-info F0123456789
n8n-hooks slack file-content F0123456789 --max-bytes 1048576
n8n-hooks slack file-download F0123456789 -o /var/lib/opencrow/tmp
n8n-hooks rss list-categories
n8n-hooks rss list-entries --starred --category-id 12
n8n-hooks rss show-entry 1234
n8n-hooks rss list-enclosures 1234
n8n-hooks vikunja list-projects
n8n-hooks vikunja list-tasks --filter 'done = false' --sort-by due_date --order-by asc
n8n-hooks vikunja show-task 1234
n8n-hooks vikunja-task-create --project Inbox --title "Reply to mail" \
  --template communication --context context.json --due 2026-05-20
n8n-hooks linkwarden search-links --query 'Nix source:rss'
n8n-hooks linkwarden-link-create --url https://example.com --name Example \
  --collection Engineering --description-file description.md \
  --tag source:rss --tag signal:noa-saved --tag kind:article --tag Nix
```

`vikunja-task-create` reads the selected Markdown+YAML template, validates the
context against the template schema, and sends the template defaults/schema plus
context to the `vikunja-task-create` n8n workflow.

## Adding a new hook

1. Create `n8n_hooks/hooks/<name>.py` with `register(subparsers)` and
   `run(args, config)`.
2. Import and register it from `n8n_hooks/cli.py`.
3. Add tests under `tests/`.
