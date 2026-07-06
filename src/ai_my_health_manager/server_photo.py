from __future__ import annotations

import logging
from typing import Any, Callable

import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse
from starlette.routing import Mount, Route

from .config import settings
from .ui import dashboard_html
from .domain_photo import (
    HealthManagerError,
    build_medication_reminders as build_medication_reminders_domain,
    build_visit_brief as build_visit_brief_domain,
    calculate_follow_up_date as calculate_follow_up_date_domain,
    check_emergency_signals as check_emergency_signals_domain,
    draft_health_records as draft_health_records_domain,
    draft_photo_health_records as draft_photo_health_records_domain,
)

logging.basicConfig(level=settings.log_level)

SERVICE_NAME = "AI My Health Manager(AI 나의 건강관리사)"

mcp = FastMCP(
    "AI My Health Manager",
    instructions=(
        "건강 입력을 바로 확정하거나 진단하지 말고 응급 표현을 먼저 확인한 뒤 기록 초안을 제시하세요. "
        "모든 초안·일정·알림은 사용자의 확인을 받아야 합니다. 사진 입력은 파일 열기, 바로 찍기, 붙여넣기로 들어와도 "
        "OCR이나 사용자가 설명한 내용을 바탕으로 식단, 복약, 혈압계, 처방전, 검사 결과지 같은 건강 기록 초안으로 정리하세요. "
        "119, 병원, 보호자에게 자동 연락하지 않습니다."
    ),
    stateless_http=True,
    json_response=True,
    host=settings.host,
    port=settings.port,
)


def _annotations(title: str, *, idempotent: bool) -> ToolAnnotations:
    return ToolAnnotations(
        title=title,
        readOnlyHint=True,
        destructiveHint=False,
        openWorldHint=False,
        idempotentHint=idempotent,
    )


def _safe_call(function: Callable[..., dict[str, Any]], *args: Any, **kwargs: Any) -> dict[str, Any]:
    try:
        return {"ok": True, "data": function(*args, **kwargs)}
    except HealthManagerError as exc:
        return {"ok": False, "error": str(exc)}


@mcp.tool(
    title="Check Emergency Signals",
    description=(
        f"{SERVICE_NAME} tool. Review a health note for urgent symptoms or emergency cues first. "
        "Do not diagnose, treat, or contact anyone automatically."
    ),
    annotations=_annotations("Check Emergency Signals", idempotent=True),
)
def check_emergency_signals(text: str) -> dict[str, Any]:
    return _safe_call(check_emergency_signals_domain, text)


@mcp.tool(
    title="Draft Health Records",
    description=(
        f"{SERVICE_NAME} tool. Turn one natural-language health update into structured draft records. "
        "Wait for user confirmation before saving or scheduling anything."
    ),
    annotations=_annotations("Draft Health Records", idempotent=False),
)
def draft_health_records(text: str, recorded_at: str | None = None) -> dict[str, Any]:
    return _safe_call(draft_health_records_domain, text, recorded_at)


@mcp.tool(
    title="Draft Photo Health Records",
    description=(
        f"{SERVICE_NAME} tool. Turn a health-related photo description or OCR text into draft records. "
        "Use this for meal photos, medication photos, blood pressure screens, prescriptions, and lab results. "
        "It accepts images opened from a file, taken with a camera, or pasted from the clipboard."
    ),
    annotations=_annotations("Draft Photo Health Records", idempotent=False),
)
def draft_photo_health_records(
    photo_type: str,
    observed_text: str,
    input_mode: str = "paste",
    source_name: str | None = None,
    recorded_at: str | None = None,
) -> dict[str, Any]:
    return _safe_call(draft_photo_health_records_domain, photo_type, observed_text, input_mode, source_name, recorded_at)


@mcp.tool(
    title="Calculate Follow-Up Date",
    description=(
        f"{SERVICE_NAME} tool. Calculate the next visit date from a confirmed completion date and interval. "
        "Shift away from weekends or provided holidays."
    ),
    annotations=_annotations("Calculate Follow-Up Date", idempotent=True),
)
def calculate_follow_up_date(
    completed_date: str,
    interval_days: int,
    holidays: list[str] | None = None,
) -> dict[str, Any]:
    return _safe_call(calculate_follow_up_date_domain, completed_date, interval_days, holidays)


@mcp.tool(
    title="Build Medication Reminders",
    description=(
        f"{SERVICE_NAME} tool. Build reminder time drafts from confirmed prescription timing and meal times. "
        "Do not alter the prescription itself."
    ),
    annotations=_annotations("Build Medication Reminders", idempotent=True),
)
def build_medication_reminders(
    medication_name: str,
    meal_times: list[str],
    delay_minutes: int = 30,
) -> dict[str, Any]:
    return _safe_call(build_medication_reminders_domain, medication_name, meal_times, delay_minutes)


@mcp.tool(
    title="Build Visit Brief",
    description=(
        f"{SERVICE_NAME} tool. Summarize confirmed records into a short clinic-ready brief. "
        "Keep the output concise and factual."
    ),
    annotations=_annotations("Build Visit Brief", idempotent=True),
)
def build_visit_brief(records: list[dict[str, Any]]) -> dict[str, Any]:
    return _safe_call(build_visit_brief_domain, records)


async def health(_: Request) -> JSONResponse:
    return JSONResponse({"status": "ok", "service": "ai-my-health-manager", "version": "0.1.0"})


async def dashboard(_: Request) -> HTMLResponse:
    return HTMLResponse(dashboard_html())


mcp_http_app = mcp.streamable_http_app()
app = Starlette(
    routes=[
        Route("/healthz", health, methods=["GET"]),
        Route("/", dashboard, methods=["GET"]),
        Mount("/", app=mcp_http_app),
    ],
    lifespan=mcp_http_app.router.lifespan_context,
)


def main() -> None:
    uvicorn.run(app, host=settings.host, port=settings.port, log_level=settings.log_level.lower())


if __name__ == "__main__":
    main()
