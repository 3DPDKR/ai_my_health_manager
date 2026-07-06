from __future__ import annotations

import logging
from typing import Any, Callable

import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

from .config import settings
from .domain import (
    HealthManagerError,
    build_medication_reminders as build_medication_reminders_domain,
    build_visit_brief as build_visit_brief_domain,
    calculate_follow_up_date as calculate_follow_up_date_domain,
    check_emergency_signals as check_emergency_signals_domain,
    draft_health_records as draft_health_records_domain,
)

logging.basicConfig(level=settings.log_level)

mcp = FastMCP(
    "AI My Health Manager",
    instructions=(
        "건강 입력을 바로 확정하거나 진단하지 말고 응급 표현을 먼저 확인한 뒤 기록 초안을 제시하세요. "
        "모든 초안·일정·알림은 사용자의 확인을 받아야 합니다. 119, 병원, 보호자에게 자동 연락하지 않습니다."
    ),
    stateless_http=True,
    json_response=True,
    host=settings.host,
    port=settings.port,
)


def _safe_call(function: Callable[..., dict[str, Any]], *args: Any, **kwargs: Any) -> dict[str, Any]:
    try:
        return {"ok": True, "data": function(*args, **kwargs)}
    except HealthManagerError as exc:
        return {"ok": False, "error": str(exc)}


@mcp.tool()
def check_emergency_signals(text: str) -> dict[str, Any]:
    """건강 입력에서 응급 의심 표현을 먼저 확인합니다. 진단하거나 자동 연락하지 않습니다."""
    return _safe_call(check_emergency_signals_domain, text)


@mcp.tool()
def draft_health_records(text: str, recorded_at: str | None = None) -> dict[str, Any]:
    """자연어 건강 입력을 저장되지 않은 여러 확인 초안으로 분리합니다. recorded_at은 시간대가 포함된 ISO 8601 형식입니다."""
    return _safe_call(draft_health_records_domain, text, recorded_at)


@mcp.tool()
def calculate_follow_up_date(
    completed_date: str,
    interval_days: int,
    holidays: list[str] | None = None,
) -> dict[str, Any]:
    """실제 방문 완료일에서 다음 일정을 계산하고 주말 또는 제공된 휴일이면 이전 평일로 조정합니다."""
    return _safe_call(calculate_follow_up_date_domain, completed_date, interval_days, holidays)


@mcp.tool()
def build_medication_reminders(
    medication_name: str,
    meal_times: list[str],
    delay_minutes: int = 30,
) -> dict[str, Any]:
    """사용자가 확인한 처방의 식후 지연 시간으로 알림 시각 초안을 계산합니다. 복용법을 제안하거나 변경하지 않습니다."""
    return _safe_call(build_medication_reminders_domain, medication_name, meal_times, delay_minutes)


@mcp.tool()
def build_visit_brief(records: list[dict[str, Any]]) -> dict[str, Any]:
    """확인된 건강 기록을 병원 방문 시 검토할 짧은 범주별 브리핑으로 정리합니다."""
    return _safe_call(build_visit_brief_domain, records)


async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok", "service": "ai-my-health-manager", "version": "0.1.0"})


mcp_http_app = mcp.streamable_http_app()
app = Starlette(
    routes=[
        Route("/healthz", health, methods=["GET"]),
        Mount("/", app=mcp_http_app),
    ],
    lifespan=mcp_http_app.router.lifespan_context,
)


def main() -> None:
    uvicorn.run(app, host=settings.host, port=settings.port, log_level=settings.log_level.lower())


if __name__ == "__main__":
    main()

