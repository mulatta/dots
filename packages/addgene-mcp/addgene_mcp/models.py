"""Search filters from the Addgene public OpenAPI schema."""

from pydantic import BaseModel, ConfigDict


class PlasmidFilters(BaseModel):
    model_config = ConfigDict(extra="forbid")

    article_authors: str | None = None
    article_pmid: str | None = None
    article_published: bool | None = None
    article_so: str | None = None
    article_title: str | None = None
    backbone: str | None = None
    bacterial_resistance: list[str] | None = None
    catalog_item_id: str | None = None
    cloning_method: str | None = None
    experimental_use: str | None = None
    expression: list[str] | None = None
    gene_ids: str | None = None
    genes: str | None = None
    is_industry: bool | None = None
    material_code: str | None = None
    mutations: str | None = None
    name: str | None = None
    pi_id: str | None = None
    pis: str | None = None
    plasmid_type: list[str] | None = None
    promoters: list[str] | None = None
    purpose: str | None = None
    resistance_marker: list[str] | None = None
    species: list[str] | None = None
    tags: list[str] | None = None
    vector_types: list[str] | None = None


class ViralPrepFilters(BaseModel):
    model_config = ConfigDict(extra="forbid")

    catalog_item_id: str | None = None
    inserts: list[str] | None = None
    is_industry: bool | None = None
    material_code: str | None = None
    name: str | None = None
    plasmid_type: list[str] | None = None
    promoters: list[str] | None = None
    serotype: list[str] | None = None
    species: list[str] | None = None
    tags: list[str] | None = None
    use: list[str] | None = None
