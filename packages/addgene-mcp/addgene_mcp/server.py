"""Thin stdio MCP adapters for Addgene."""

import os
from typing import Any

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from .client import AddgeneClient
from .models import PlasmidFilters, ViralPrepFilters

server = FastMCP("addgene-mcp")
READ_ONLY = ToolAnnotations(
    readOnlyHint=True, destructiveHint=False, openWorldHint=True
)


def client() -> AddgeneClient:
    return AddgeneClient(os.environ.get("ADDGENE_API_TOKEN", ""))


@server.tool(annotations=READ_ONLY)
async def search_plasmids(
    query: str | None = None,
    filters: PlasmidFilters | None = None,
    page: int = 1,
    page_size: int = 20,
    sort_by: str | None = None,
) -> dict[str, Any]:
    """Search plasmids. Requires catalog:retrieve or catalog:retrieve-with-sequences.

    Filters use Addgene names: genes, species, promoters, mutations, tags,
    article_pmid, bacterial_resistance, backbone, pi_id, is_industry.
    Array values become repeated query keys. sort_by: id, newest, relevance.
    """
    async with client() as api:
        return await api.search_plasmids(
            query,
            filters=filters.model_dump(exclude_none=True) if filters else None,
            page=page,
            page_size=page_size,
            sort_by=sort_by,
        )


@server.tool(annotations=READ_ONLY)
async def get_plasmid(
    plasmid_id: int,
    include_sequences: bool = False,
    include_sequence_text: bool = False,
) -> dict[str, Any]:
    """Get plasmid detail. Sequences require catalog:retrieve-with-sequences.

    Sequence metadata excludes bases unless include_sequence_text is true.
    Permission failures never fall back to metadata-only results.
    """
    async with client() as api:
        return await api.get_plasmid(
            plasmid_id, include_sequences, include_sequence_text
        )


@server.tool(
    annotations=ToolAnnotations(
        readOnlyHint=False, destructiveHint=False, openWorldHint=True
    )
)
async def download_genbank(sequence_id: int) -> dict[str, Any]:
    """Save GenBank to server XDG cache and return local path, not file contents.

    Requires catalog:retrieve-with-sequences or bulk-download:plasmids-with-sequences.
    Use sequence_id from plasmid sequences, not plasmid ID or insert genbank_ids.
    """
    async with client() as api:
        return await api.download_genbank(sequence_id)


@server.tool(annotations=READ_ONLY)
async def search_viral_preps(
    query: str | None = None,
    filters: ViralPrepFilters | None = None,
    page: int = 1,
    page_size: int = 20,
    sort_by: str | None = None,
) -> dict[str, Any]:
    """Search viral preps; requires catalog:retrieve.

    Filters: name, catalog_item_id, material_code, inserts, serotype, species,
    promoters, tags, use, plasmid_type, is_industry. Lists use repeated keys.
    """
    async with client() as api:
        return await api.search_viral_preps(
            query,
            filters=filters.model_dump(exclude_none=True) if filters else None,
            page=page,
            page_size=page_size,
            sort_by=sort_by,
        )


@server.tool(annotations=READ_ONLY)
async def get_viral_prep(viral_prep_id: str) -> dict[str, Any]:
    """Get viral prep by string ID (e.g. 44361-AAV1); requires catalog:retrieve."""
    async with client() as api:
        return await api.get_viral_prep(viral_prep_id)


def main() -> None:
    if not os.environ.get("ADDGENE_API_TOKEN", "").strip():
        raise SystemExit("ADDGENE_API_TOKEN is required")
    server.run(transport="stdio")
