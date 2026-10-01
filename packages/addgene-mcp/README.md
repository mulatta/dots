# Addgene MCP

A read-only MCP server for the Addgene Developers API. Requires Python 3.13 or
newer. Uses `mcp.server.fastmcp.FastMCP` from the official `mcp` Python SDK, not the
standalone `fastmcp` package.

## Run

Build the package from the repository root:

```sh
nix build .#addgene-mcp
```

Provide your Addgene API token through `ADDGENE_API_TOKEN` in the server process's
runtime environment. Use your MCP client's secret mechanism or a runtime secret
loader. Do not put tokens in source files, Nix expressions, command arguments, or
logs. The server uses this token; it does not issue tokens or expose an
authentication tool.

Launch `addgene-mcp` (or `./result/bin/addgene-mcp` after the build). The server
communicates over **stdio**. Configure your MCP client to launch that command and
supply the token in its environment. No HTTP listener is required.

Example client configuration, with the token supplied separately by the client's
runtime environment:

```json
{
  "mcpServers": {
    "addgene": {
      "command": "addgene-mcp",
      "args": []
    }
  }
}
```

## Tools

| Tool                 | Purpose                                                                                                                                   |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `search_plasmids`    | Search plasmids with an optional query and typed filters.                                                                                 |
| `get_plasmid`        | Fetch one plasmid by `plasmid_id`. `include_sequences` and `include_sequence_text` both default to `false`; enable them only when needed. |
| `download_genbank`   | Download one sequence by `sequence_id`, save its GenBank file in the XDG cache, and return its local path.                                |
| `search_viral_preps` | Search viral preparations.                                                                                                                |
| `get_viral_prep`     | Fetch one viral preparation.                                                                                                              |

Use the MCP tool schemas for the supported filter names and argument types.
Sequence downloads use `$XDG_CACHE_HOME`, or `$HOME/.cache` when it is unset. The
returned path belongs to the server host; a remote client cannot assume that path
exists on its own filesystem. This is the only tool that writes a local data file.

There is no bulk-download tool, token-management tool, or API mutation tool.

Search defaults to page 1 with 20 results. HTTP requests time out after 60 seconds.
GenBank downloads follow up to six HTTPS responses and trust the redirect targets
provided by Addgene; there is no fixed storage-host allowlist. Authentication is
sent only to the Addgene API origin, never external storage hosts. Downloads
replace the cached file for that sequence ID. Presigned redirect URLs are not
returned or persisted. Sequence permission failures never fall back to metadata.

## Permissions

These are Addgene token permissions, not OAuth scopes. The server authenticates
API requests with `Authorization: Token <key>`.

| Operation                                   | Required token permission                                                    |
| ------------------------------------------- | ---------------------------------------------------------------------------- |
| Plasmid search and detail without sequences | `catalog:retrieve` or `catalog:retrieve-with-sequences`                      |
| Plasmid detail with sequences               | `catalog:retrieve-with-sequences`                                            |
| GenBank download                            | `catalog:retrieve-with-sequences` or `bulk-download:plasmids-with-sequences` |
| Viral-preparation search and detail         | `catalog:retrieve`                                                           |

Request only the permissions needed for your tools. Accepting a token with
`bulk-download:plasmids-with-sequences` for a single GenBank download does not
expose a bulk-download tool. A valid token does not guarantee access to every
record or sequence.

## Development

The Nix package runs formatting, lint, strict type checking, and tests during its
build. To run the same checks in the package environment:

```sh
cd packages/addgene-mcp
nix develop ../..#addgene-mcp -c ruff format --check .
nix develop ../..#addgene-mcp -c ruff check .
nix develop ../..#addgene-mcp -c mypy addgene_mcp tests
nix develop ../..#addgene-mcp -c pytest tests/
```
