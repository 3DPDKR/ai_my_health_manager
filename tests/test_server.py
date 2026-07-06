from __future__ import annotations

import asyncio

import httpx

from ai_my_health_manager.server import app


def test_http_endpoints_and_reverse_proxy_host_header() -> None:
    async def exercise_app() -> tuple[httpx.Response, httpx.Response]:
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                health = await client.get("/healthz")
                initialize = await client.post(
                    "/mcp",
                    headers={
                        "Host": "ai-my-health-manager-prod.playmcp-endpoint.kakaocloud.io",
                        "Accept": "application/json, text/event-stream",
                    },
                    json={
                        "jsonrpc": "2.0",
                        "id": 1,
                        "method": "initialize",
                        "params": {
                            "protocolVersion": "2025-06-18",
                            "capabilities": {},
                            "clientInfo": {"name": "test-client", "version": "1.0"},
                        },
                    },
                )
        return health, initialize

    health, initialize = asyncio.run(exercise_app())

    assert health.status_code == 200
    assert health.json() == {
        "status": "ok",
        "service": "ai-my-health-manager",
        "version": "0.1.0",
    }
    assert initialize.status_code == 200
    assert initialize.json()["result"]["serverInfo"]["name"] == "AI My Health Manager"

