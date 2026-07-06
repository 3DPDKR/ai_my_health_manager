from __future__ import annotations

import asyncio

import httpx

from ai_my_health_manager.server_photo import app, mcp


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


def test_playmcp_tool_metadata_is_exposed() -> None:
    tools = mcp._tool_manager.list_tools()

    assert {tool.name for tool in tools} == {
        "check_emergency_signals",
        "draft_health_records",
        "draft_photo_health_records",
        "calculate_follow_up_date",
        "build_medication_reminders",
        "build_visit_brief",
    }

    for tool in tools:
        assert "AI My Health Manager(AI 나의 건강관리사)" in tool.description
        assert tool.annotations is not None
        assert tool.annotations.title is not None
        assert tool.annotations.readOnlyHint is not None
        assert tool.annotations.destructiveHint is not None
        assert tool.annotations.openWorldHint is not None
        assert tool.annotations.idempotentHint is not None


def test_root_dashboard_renders_cards() -> None:
    async def exercise() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.get("/")

    response = asyncio.run(exercise())
    assert response.status_code == 200
    assert "AI My Health Manager" in response.text
    assert "파일 선택" in response.text
    assert "바로 찍기" in response.text
    assert "붙여넣기" in response.text
