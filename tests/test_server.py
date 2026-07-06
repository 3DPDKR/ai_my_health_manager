from __future__ import annotations

import asyncio

import httpx

from ai_my_health_manager.server import app


def test_health_endpoint_and_application_lifespan() -> None:
    async def exercise_app() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with app.router.lifespan_context(app):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                return await client.get("/healthz")

    response = asyncio.run(exercise_app())

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "service": "ai-my-health-manager",
        "version": "0.1.0",
    }

