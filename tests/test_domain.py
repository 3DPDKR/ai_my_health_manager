from __future__ import annotations

import pytest

from ai_my_health_manager.domain import (
    HealthManagerError,
    build_medication_reminders,
    build_visit_brief,
    calculate_follow_up_date,
    check_emergency_signals,
    draft_health_records,
)


def test_emergency_signal_is_detected() -> None:
    result = check_emergency_signals("갑자기 말이 어눌하고 한쪽 힘이 빠져요")
    assert result["emergency_possible"] is True
    assert "말 어눌함" in result["detected_signals"]
    assert "한쪽 힘 빠짐" in result["detected_signals"]
    assert result["automatic_contact"] is False


def test_health_input_is_split_into_drafts() -> None:
    result = draft_health_records(
        "오늘 혈압 132/86이고 저녁 약을 먹었어. 다음 병원 예약도 있어.",
        "2026-07-06T20:30:00+09:00",
    )
    categories = {draft["category"] for draft in result["drafts"]}
    assert {"활력징후", "복약", "병원 일정"}.issubset(categories)
    assert result["requires_user_confirmation"] is True
    assert result["persisted"] is False


def test_follow_up_moves_weekend_to_friday() -> None:
    result = calculate_follow_up_date("2026-07-09", 30)
    assert result["calculated_date"] == "2026-08-08"
    assert result["recommended_date"] == "2026-08-07"
    assert result["adjusted_to_previous_business_day"] is True


def test_follow_up_respects_supplied_holiday() -> None:
    result = calculate_follow_up_date("2026-07-01", 9, ["2026-07-10"])
    assert result["recommended_date"] == "2026-07-09"


def test_medication_reminder_uses_confirmed_delay_only() -> None:
    result = build_medication_reminders("처방약", ["08:00", "18:30"], 30)
    assert [item["reminder_time"] for item in result["reminders"]] == ["08:30", "19:00"]
    assert result["requires_user_confirmation"] is True


def test_invalid_meal_time_is_rejected() -> None:
    with pytest.raises(HealthManagerError, match="HH:MM"):
        build_medication_reminders("처방약", ["25:00"])


def test_visit_brief_groups_records_without_diagnosis() -> None:
    result = build_visit_brief(
        [
            {"category": "활력징후", "recorded_at": "2026-07-06 08:00", "summary": "혈압 132/86"},
            {"category": "복약", "recorded_at": "2026-07-06 08:30", "summary": "아침 약 복용 완료"},
        ]
    )
    assert result["record_count"] == 2
    assert result["category_counts"] == {"활력징후": 1, "복약": 1}
    assert result["requires_user_confirmation"] is True


