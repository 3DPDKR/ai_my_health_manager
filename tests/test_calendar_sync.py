from __future__ import annotations

from ai_my_health_manager.domain_photo import (
    build_medication_reminders,
    calculate_follow_up_date,
)


def test_follow_up_date_exposes_kakao_calendar_alert() -> None:
    result = calculate_follow_up_date("2026-07-09", 30)

    assert result["external_alert"]["channel"] == "kakao_calendar"
    assert result["external_alert"]["alert_type"] == "hospital_visit"
    assert result["external_alert"]["action"] == "create_or_update_event"


def test_medication_reminder_exposes_kakao_calendar_alert() -> None:
    result = build_medication_reminders("처방약", ["08:00", "18:30"], 30)

    assert result["external_alert"]["channel"] == "kakao_calendar"
    assert result["external_alert"]["alert_type"] == "medication_schedule"
    assert result["external_alert"]["action"] == "create_or_update_event"
    assert result["external_alert"]["event_times"] == ["08:30", "19:00"]
