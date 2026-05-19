# Paperless infrastructure

OpenCrow can access Paperless through the configured token-auth endpoint.

Environment:

- `PAPERLESS_URL`: internal Paperless URL

Credentials:

- Paperless API token is exposed via the rbw shim as `rbw get paperless-api-token`.

Use only existing Paperless API capabilities. Do not import documents, create n8n workflows, or encode custom Paperless business rules in this skill.
