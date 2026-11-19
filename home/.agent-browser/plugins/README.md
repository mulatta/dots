# agent-browser plugins

## rbw

The shared agent-browser config registers `rbw` with `credential.read` and
launches `$HOME/.agent-browser/plugins/rbw.py`.

Uses the default rbw profile and an already unlocked vault. Pass the exact vault item name with `--item`. The HTTPS login URL must match an eligible stored URI.
Without `--url`, the first eligible URI in vault order is used.

```sh
rbw unlock
agent-browser auth login inu-lib --credential-provider rbw \
  --item '<vault item name>' --url https://lib.inu.ac.kr/login
```

Credentials pass directly to `auth login`; do not invoke credential resolution for display.

## transfer

Unlock the default vault with `rbw unlock`. The `neko-rustfs-client` item
holds the S3 access key as its username, the secret key as its password, and
`https://s3.mulatta.io` as its URI.

```sh
agent-browser --json plugin run transfer transfer.list --payload '{"area":"downloads"}'
agent-browser --json plugin run transfer transfer.pull --payload '{"name":"paper.pdf","output":"/absolute/path/paper.pdf"}'
agent-browser --json plugin run transfer transfer.push --payload '{"input":"/absolute/path/file.pdf","name":"file.pdf"}'
```

After a browser download completes, wait for the final filename to appear in
`transfer.list` before pulling. After a push, `browserPathReady: false` means
the worker still needs to publish the file to Chromium staging. Wait for the
worker before passing `browserPath` to `agent-browser upload`.

Local paths must be absolute and contain no symlink components. Transfers
are limited to 1 GiB and do not overwrite existing files.
