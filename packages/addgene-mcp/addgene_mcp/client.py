"""HTTP access to the Addgene Developers API."""

import os
from pathlib import Path
from typing import Any, Self
from urllib.parse import quote

import httpx

API_URL = "https://api.developers.addgene.org"


class AddgeneError(Exception):
    """A sanitized upstream or input error."""


class AddgeneClient:
    def __init__(
        self,
        token: str,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        cache_dir: Path | None = None,
    ) -> None:
        if not token.strip():
            raise AddgeneError("ADDGENE_API_TOKEN is required")
        self._token = token
        self._http = httpx.AsyncClient(transport=transport, timeout=60)
        base = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
        if not base.is_absolute():
            base = Path.home() / ".cache"
        self._cache = cache_dir if cache_dir is not None else base / "addgene-mcp"

    async def __aenter__(self) -> Self:
        return self

    async def __aexit__(self, *args: object) -> None:
        await self._http.aclose()

    async def _request(
        self, url: str, *, params: list[tuple[str, str]] | None = None
    ) -> httpx.Response:
        headers = (
            {"Authorization": f"Token {self._token}"}
            if url.startswith(API_URL + "/")
            else {}
        )
        try:
            response = await self._http.get(
                url,
                params=tuple(params) if params is not None else None,
                headers=headers,
            )
        except httpx.HTTPError:
            raise AddgeneError("Addgene network request failed") from None
        if response.is_error:
            message = {
                401: "Invalid Addgene API token",
                403: "Addgene token lacks permission for this endpoint",
                404: "Addgene record not found",
                429: "Addgene rate limit exceeded; retry later",
            }.get(response.status_code, "Addgene upstream request failed")
            raise AddgeneError(f"{message} (HTTP {response.status_code})")
        return response

    async def _json(
        self, path: str, params: list[tuple[str, str]] | None = None
    ) -> dict[str, Any]:
        response = await self._request(API_URL + path, params=params)
        if response.status_code != 200:
            raise AddgeneError("Unexpected Addgene API response")
        try:
            data = response.json()
        except ValueError:
            raise AddgeneError("Invalid Addgene JSON response") from None
        if not isinstance(data, dict):
            raise AddgeneError("Expected Addgene JSON object")
        return data

    async def _search(
        self,
        kind: str,
        query: str | None,
        filters: dict[str, Any] | None,
        page: int,
        page_size: int,
        sort_by: str | None,
    ) -> dict[str, Any]:
        if page < 1 or page_size < 1:
            raise AddgeneError("page and page_size must be positive")
        if sort_by not in (None, "id", "newest", "relevance"):
            raise AddgeneError("Invalid sort_by")
        if sort_by == "relevance" and not query:
            raise AddgeneError("relevance requires query")
        params = [("page", str(page)), ("page_size", str(page_size))]
        if query:
            params.append(("q", query))
        if sort_by:
            params.append(("sort_by", sort_by))
        for key, value in (filters or {}).items():
            if key in {"q", "page", "page_size", "sort_by"}:
                raise AddgeneError(f"Use explicit argument for {key}")
            if value is not None:
                for item in value if isinstance(value, list) else [value]:
                    params.append(
                        (
                            key,
                            str(item).lower() if isinstance(item, bool) else str(item),
                        )
                    )
        return await self._json(f"/catalog/{kind}/", params)

    async def search_plasmids(
        self,
        query: str | None = None,
        *,
        filters: dict[str, Any] | None = None,
        page: int = 1,
        page_size: int = 20,
        sort_by: str | None = None,
    ) -> dict[str, Any]:
        return await self._search("plasmid", query, filters, page, page_size, sort_by)

    async def search_viral_preps(
        self,
        query: str | None = None,
        *,
        filters: dict[str, Any] | None = None,
        page: int = 1,
        page_size: int = 20,
        sort_by: str | None = None,
    ) -> dict[str, Any]:
        return await self._search(
            "viral-prep", query, filters, page, page_size, sort_by
        )

    async def get_plasmid(
        self,
        plasmid_id: int,
        include_sequences: bool = False,
        include_sequence_text: bool = False,
    ) -> dict[str, Any]:
        if plasmid_id < 1:
            raise AddgeneError("plasmid_id must be positive")
        if include_sequence_text and not include_sequences:
            raise AddgeneError("include_sequence_text requires include_sequences")
        kind = "plasmid-with-sequences" if include_sequences else "plasmid"
        data = await self._json(f"/catalog/{kind}/{plasmid_id}/")
        if include_sequences and not include_sequence_text:
            for records in data.get("sequences", {}).values():
                for record in records:
                    record.pop("sequence", None)
        return data

    async def get_viral_prep(self, viral_prep_id: str) -> dict[str, Any]:
        if not viral_prep_id or "/" in viral_prep_id or viral_prep_id in {".", ".."}:
            raise AddgeneError("Invalid viral_prep_id")
        return await self._json(f"/catalog/viral-prep/{quote(viral_prep_id, safe='')}/")

    async def download_genbank(self, sequence_id: int) -> dict[str, Any]:
        if sequence_id < 1:
            raise AddgeneError("sequence_id must be positive")
        url = httpx.URL(f"{API_URL}/download/genbank/{sequence_id}/")
        for _ in range(6):
            response = await self._request(str(url))
            if not response.is_redirect:
                break
            location = response.headers.get("location")
            if not location:
                raise AddgeneError("GenBank redirect missing Location")
            url = url.join(location)
            if url.scheme != "https" or url.userinfo:
                raise AddgeneError("Unsafe GenBank redirect")
        else:
            raise AddgeneError("Too many GenBank redirects")
        if response.status_code != 200 or not response.content.lstrip().startswith(
            b"LOCUS"
        ):
            raise AddgeneError("Invalid GenBank response")
        folder = self._cache / "genbank"
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"{sequence_id}.gb"
        path.write_bytes(response.content)
        return {"sequence_id": sequence_id, "path": str(path), "format": "genbank"}
