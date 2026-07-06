from __future__ import annotations

from ai_my_health_manager.domain_photo import draft_photo_health_records


def test_photo_health_input_is_split_into_drafts() -> None:
    result = draft_photo_health_records(
        "meal",
        "사진에서 밥 한 공기와 국, 샐러드가 보이고 저녁 식사 기록처럼 보인다",
        "2026-07-06T19:10:00+09:00",
    )
    assert result["photo_type"] == "meal"
    assert result["photo_type_label"] == "식단 사진"
    assert result["requires_user_confirmation"] is True
    assert result["persisted"] is False
    assert result["draft_count"] >= 1
