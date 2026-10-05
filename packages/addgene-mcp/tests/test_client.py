"""Exercise the Addgene API boundary without live credentials."""

import asyncio
from pathlib import Path
from typing import Any

import httpx
import pytest

from addgene_mcp.client import AddgeneClient, AddgeneError

TOKEN = "test-addgene-token"


@pytest.mark.parametrize("status", [401, 403, 404, 429, 500])
def test_api_error_has_no_fallback(status: int) -> None:
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(status, json={"detail": "Request rejected"})

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            with pytest.raises(AddgeneError) as error:
                await client.get_plasmid(52961)
            assert TOKEN not in str(error.value)

    asyncio.run(run())
    assert len(requests) == 1


def test_transport_failure_is_reported_without_fallback() -> None:
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        raise httpx.ConnectError("Connection refused", request=request)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            with pytest.raises(AddgeneError):
                await client.search_plasmids("CRISPR")

    asyncio.run(run())
    assert len(requests) == 1


@pytest.mark.parametrize("kind", ["plasmid", "viral-prep"])
def test_search_paths_and_repeated_filters(kind: str) -> None:
    payload = {
        "count": 1,
        "next": None,
        "previous": None,
        "results": [{"id": 52961, "name": "lentiCRISPR v2"}],
    }
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=payload)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            search = (
                client.search_plasmids
                if kind == "plasmid"
                else client.search_viral_preps
            )
            result = await search(
                "CRISPR",
                filters={"species": ["human", "mouse"]},
                page=2,
                page_size=10,
                sort_by="newest",
            )
            assert result == payload

    asyncio.run(run())
    assert len(requests) == 1
    request = requests[0]
    assert request.method == "GET"
    assert request.url.host == "api.developers.addgene.org"
    assert request.url.path == f"/catalog/{kind}/"
    assert request.headers["Authorization"] == f"Token {TOKEN}"
    assert request.url.params.get_list("species") == ["human", "mouse"]
    assert request.url.params["page"] == "2"
    assert request.url.params["page_size"] == "10"
    assert request.url.params["sort_by"] == "newest"
    assert request.url.params["q"] == "CRISPR"


SEQUENCE_CATEGORIES = (
    "public_user_full_sequences",
    "public_addgene_full_sequences",
    "public_user_partial_sequences",
    "public_addgene_partial_sequences",
)


@pytest.mark.parametrize("include_text", [False, True])
def test_sequence_categories_preserve_metadata_and_opt_in_text(
    include_text: bool,
) -> None:
    sequences = {
        category: [
            {
                "sequence_id": 100 + index,
                "description": "Verified sequence",
                "length": 8,
                "sequence": "ACGTACGT",
                "genbank_api_url": (
                    f"https://api.developers.addgene.org/download/genbank/{100 + index}/"
                ),
            }
        ]
        for index, category in enumerate(SEQUENCE_CATEGORIES)
    }
    payload = {"id": 52961, "name": "lentiCRISPR v2", "sequences": sequences}
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=payload)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            result = await client.get_plasmid(
                52961, include_sequences=True, include_sequence_text=include_text
            )
            for category in SEQUENCE_CATEGORIES:
                record = result["sequences"][category][0]
                expected = dict(sequences[category][0])
                if not include_text:
                    expected.pop("sequence")
                assert record == expected

    asyncio.run(run())
    assert len(requests) == 1
    assert requests[0].url.path == "/catalog/plasmid-with-sequences/52961/"


@pytest.mark.parametrize("kind", ["plasmid", "viral-prep"])
def test_detail_uses_canonical_path(kind: str) -> None:
    identifier: Any = 52961 if kind == "plasmid" else "52961-AAV9"
    payload = {"id": identifier, "name": "lentiCRISPR v2"}
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json=payload)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            detail = client.get_plasmid if kind == "plasmid" else client.get_viral_prep
            assert await detail(identifier) == payload

    asyncio.run(run())
    assert len(requests) == 1
    assert requests[0].url.path == f"/catalog/{kind}/{identifier}/"


@pytest.mark.parametrize("status", [403, 404])
def test_sequence_detail_error_does_not_fall_back(status: int) -> None:
    paths: list[str] = []

    def respond(request: httpx.Request) -> httpx.Response:
        paths.append(request.url.path)
        return httpx.Response(status, json={"detail": "Sequence unavailable"})

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            with pytest.raises(AddgeneError):
                await client.get_plasmid(52961, include_sequences=True)

    asyncio.run(run())
    assert paths == ["/catalog/plasmid-with-sequences/52961/"]


def test_genbank_redirect_strips_auth_and_writes_cache(tmp_path: Path) -> None:
    genbank = (
        b"LOCUS       example                    8 bp    DNA\n"
        b"ORIGIN\n        1 acgtacgt\n//\n"
    )
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.host == "api.developers.addgene.org":
            assert request.url.path == "/download/genbank/12345/"
            assert request.headers["Authorization"] == f"Token {TOKEN}"
            return httpx.Response(
                302,
                headers={"Location": "https://storage.example.org/sequences/12345.gb"},
            )
        assert request.url.host == "storage.example.org"
        assert "Authorization" not in request.headers
        return httpx.Response(200, content=genbank)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond), cache_dir=tmp_path
        ) as client:
            result = await client.download_genbank(12345)
            assert result["sequence_id"] == 12345
            path = Path(result["path"])
            assert path.is_relative_to(tmp_path)
            assert path.read_bytes() == genbank

    asyncio.run(run())
    assert len(requests) == 2


def test_failed_download_leaves_no_cached_file(tmp_path: Path) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"detail": "Sequence not found"})

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond), cache_dir=tmp_path
        ) as client:
            with pytest.raises(AddgeneError):
                await client.download_genbank(12345)

    asyncio.run(run())
    assert not [path for path in tmp_path.rglob("*") if path.is_file()]


@pytest.mark.parametrize("body", [b"not json", b"[]"])
def test_invalid_api_payload_is_reported(body: bytes) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, content=body)

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond)
        ) as client:
            with pytest.raises(AddgeneError):
                await client.get_plasmid(52961)

    asyncio.run(run())


@pytest.mark.parametrize(
    "location",
    [
        "http://storage.example.org/sequence.gb",
        "https://user:pass@storage.example.org/sequence.gb",
    ],
)
def test_unsafe_genbank_redirect_is_not_followed(tmp_path: Path, location: str) -> None:
    requests: list[httpx.Request] = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(302, headers={"Location": location})

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond), cache_dir=tmp_path
        ) as client:
            with pytest.raises(AddgeneError):
                await client.download_genbank(12345)

    asyncio.run(run())
    assert len(requests) == 1
    assert not [path for path in tmp_path.rglob("*") if path.is_file()]


def test_non_genbank_download_is_not_cached(tmp_path: Path) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, text="<html>Login required</html>")

    async def run() -> None:
        async with AddgeneClient(
            TOKEN, transport=httpx.MockTransport(respond), cache_dir=tmp_path
        ) as client:
            with pytest.raises(AddgeneError):
                await client.download_genbank(12345)

    asyncio.run(run())
    assert not [path for path in tmp_path.rglob("*") if path.is_file()]
