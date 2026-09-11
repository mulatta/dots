# merge-when-green

Push the current branch, open a PR, enable auto-merge and wait until CI is
green. Works with GitHub (`gh`) and Gitea (REST API, with `tea` for host discovery).

## Usage

```bash
merge-when-green              # create PR and wait for CI
merge-when-green --no-wait    # create PR, don't wait
merge-when-green -m "title"   # PR title/body from argument instead of $EDITOR
```

## Workflow

1. Rebases onto the default branch and runs `flake-fmt`. Formatting fixes are
   folded into your commits with `git-absorb`; if that fails, `lazygit` opens.
2. Pushes the branch (on the default branch, a `merge-when-green-$USER` branch
   is created) and creates a PR, or reuses an existing open one. The PR
   description is taken from your commit messages, editable via `$EDITOR`.
3. Enables auto-merge using rebase and polls check status. On failing checks it runs
   `nbo log` (nixbot CLI) to show failure logs, if installed.
4. After the merge, rebases your local branch onto the updated default branch.

## Requirements

- GitHub: `gh`, repository with auto-merge enabled
- Gitea: `tea` login for the origin host, `GITEA_TOKEN` with repository write
  access, and a repository that permits auto-merge
- Optional: `flake-fmt`, `git-absorb`, `lazygit`, `nbo`

The platform is detected from the origin URL. GitHub remotes use `gh`; other
hosts are matched exactly against the URL or SSH host in `tea logins list -o json`.
Unknown or ambiguous hosts stop with an error. SCP URLs such as
`gitea@git.mulatta.io:mulatta/blog.git` and `ssh://` URLs are supported.
The matching login supplies the HTTP API URL; SSH ports are not API ports.

Gitea uses `GITEA_TOKEN` for all REST requests. The `mwg` shell alias supplies
this token. PR discovery and commit statuses are paginated. Merge scheduling
errors exit nonzero, including with `--no-wait`. Waiting exits on merge, closure,
API errors, or failed commit statuses once all reported checks settle.
No checks means keep waiting; it does not mean permission to merge locally.
Gitea does not expose scheduling cancellation in the PR response, so a cancelled
schedule can require Ctrl-C. This polls commit statuses, not a separate Actions
runs API.

## Development and availability

Run `python3 -m unittest -v`, `ruff format --check .`, `ruff check .`, and
`mypy merge-when-green.py test_merge_when_green.py` from this directory.
Tests use temporary git repositories and a local HTTP server; they do not push
or change live pull requests.

Editing this source does not update an installed Nix profile. Build the package
from the dots flake, then invoke its output directly to try the new version.
Only a later explicit profile rebuild/switch updates the `mwg` command on PATH.
