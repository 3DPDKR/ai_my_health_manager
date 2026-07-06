from __future__ import annotations

import argparse
import asyncio

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


EXPECTED_TOOLS = {
    "check_emergency_signals",
    "draft_health_records",
    "draft_photo_health_records",
    "calculate_follow_up_date",
    "build_medication_reminders",
    "build_visit_brief",
}


async def verify(base_url: str) -> None:
    base_url = base_url.rstrip("/")
    async with httpx.AsyncClient(timeout=10) as client:
        health = await client.get(f"{base_url}/healthz")
        health.raise_for_status()
        payload = health.json()
        if payload.get("status") != "ok":
            raise RuntimeError(f"Unexpected health response: {payload}")

    async with streamablehttp_client(f"{base_url}/mcp") as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            result = await session.list_tools()

    tool_names = {tool.name for tool in result.tools}
    if tool_names != EXPECTED_TOOLS:
        missing = sorted(EXPECTED_TOOLS - tool_names)
        unexpected = sorted(tool_names - EXPECTED_TOOLS)
        raise RuntimeError(f"Tool mismatch: missing={missing}, unexpected={unexpected}")

    print(f"health: {payload}")
    print(f"tools ({len(tool_names)}): {', '.join(sorted(tool_names))}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Verify the AI My Health Manager HTTP and MCP endpoints.")
    parser.add_argument("base_url", nargs="?", default="http://127.0.0.1:8000")
    args = parser.parse_args()
    asyncio.run(verify(args.base_url))


if __name__ == "__main__":
    main()

