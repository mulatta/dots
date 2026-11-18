# agent-browser plugins

## rbw

The shared agent-browser config registers `rbw` with `credential.read` and
launches `$HOME/.agent-browser/plugins/rbw.py`.

Uses the default rbw profile and an already unlocked vault. Pass the exact vault item name with `--item`. The HTTPS login URL must match an eligible stored URI.
Without `--url`, the first eligible URI in vault order is used.

```sh
rbw unlock
agent-browser auth login inu --credential-provider rbw \
  --item '<vault item name>' --url https://lib.inu.ac.kr/login
```

Credentials pass directly to `auth login`; do not invoke credential resolution for display.
