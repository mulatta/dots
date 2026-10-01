"""Check the exposed MCP contract without external credentials."""

import asyncio

from addgene_mcp.server import server


def test_tool_surface() -> None:
    async def run() -> None:
        tools = {tool.name: tool for tool in await server.list_tools()}
        assert set(tools) == {
            "search_plasmids",
            "get_plasmid",
            "download_genbank",
            "search_viral_preps",
            "get_viral_prep",
        }
        properties = tools["get_plasmid"].inputSchema["properties"]
        assert properties["include_sequences"]["default"] is False
        assert properties["include_sequence_text"]["default"] is False
        for tool in tools.values():
            assert "token" not in tool.inputSchema["properties"]

    asyncio.run(run())
