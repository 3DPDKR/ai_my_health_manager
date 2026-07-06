from __future__ import annotations

import re
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any


class HealthManagerError(ValueError):
    """An input error safe to return to an MCP client."""


EMERGENCY_SIGNALS: dict[str, tuple[str, ...]] = {
    "흉통": ("흉통", "가슴 통증", "가슴이 아파", "가슴을 짓누"),
    "호흡곤란": ("호흡곤란", "숨이 안 쉬", "숨을 못 쉬", "숨쉬기 힘", "숨이 차서"),
    "의식 이상": ("의식이 없", "의식을 잃", "깨워도 반응", "갑자기 쓰러"),
    "얼굴 처짐": ("얼굴 처짐", "얼굴이 처", "입꼬리가 내려"),
    "말 어눌함": ("말이 어눌", "발음이 이상", "말을 못 하"),
    "한쪽 힘 빠짐": ("한쪽 힘", "한쪽 팔이 안", "한쪽 다리가 안", "반신 마비"),
    "갑작스러운 심한 두통": ("갑작스러운 심한 두통", "살면서 가장 심한 두통", "벼락 두통"),
    "갑작스러운 시야 이상": ("갑자기 안 보여", "갑작스러운 시야", "시야가 갑자기"),
}

PHOTO_TYPE_LABELS: dict[str, str] = {
    "meal": "식단 사진",
    "medication": "약봉투 사진",
    "blood_pressure": "혈압계 화면",
    "prescription": "처방전 사진",
    "lab": "검사 결과지",
    "other": "기타 사진",
}

INPUT_MODE_LABELS: dict[str, str] = {
    "file": "파일 열기",
    "camera": "바로 찍기",
    "paste": "붙여넣기",
}


def check_emergency_signals(text: str) -> dict[str, Any]:
    normalized = _required_text(text)
    detected = [
        label
        for label, phrases in EMERGENCY_SIGNALS.items()
        if any(phrase in normalized for phrase in phrases)
    ]
    if detected:
        return {
            "emergency_possible": True,
            "detected_signals": detected,
            "message": (
                "응급 상황일 가능성을 배제할 수 없습니다. 대한민국에서는 즉시 119에 연락하거나 "
                "가까운 응급실의 도움을 받으세요. 혼자라면 주변 사람에게도 바로 알리세요."
            ),
            "automatic_contact": False,
            "disclaimer": "이 결과는 진단이 아니며 자동으로 전화하거나 신고하지 않습니다.",
        }
    return {
        "emergency_possible": False,
        "detected_signals": [],
        "message": "현재 입력에서 미리 정의된 응급 의심 표현은 발견되지 않았습니다.",
        "automatic_contact": False,
        "disclaimer": "증상이 심하거나 빠르게 악화되면 이 결과와 관계없이 의료 도움을 받으세요.",
    }


def draft_health_records(text: str, recorded_at: str | None = None) -> dict[str, Any]:
    value = _required_text(text)
    if len(value) > 2_000:
        raise HealthManagerError("입력은 2,000자 이하로 작성해주세요.")
    timestamp = _parse_datetime(recorded_at).isoformat() if recorded_at else datetime.now().astimezone().isoformat()
    emergency = check_emergency_signals(value)
    drafts: list[dict[str, Any]] = []

    vital_fields: dict[str, Any] = {}
    blood_pressure = re.search(r"(?:혈압\s*)?(\d{2,3})\s*(?:/|에)\s*(\d{2,3})", value)
    if blood_pressure and ("혈압" in value or "/" in blood_pressure.group(0)):
        vital_fields["systolic_mmHg"] = int(blood_pressure.group(1))
        vital_fields["diastolic_mmHg"] = int(blood_pressure.group(2))
    _capture_number(value, vital_fields, "pulse_bpm", r"(?:맥박|심박)\s*(?:은|이|수)?\s*(\d{2,3})")
    _capture_number(value, vital_fields, "glucose_mg_dL", r"(?:혈당)\s*(?:은|이)?\s*(\d{2,3})")
    _capture_number(value, vital_fields, "temperature_c", r"(?:체온)\s*(?:은|이)?\s*(\d{2}(?:\.\d)?)", float)
    _capture_number(value, vital_fields, "spo2_percent", r"(?:산소포화도|산소 포화도)\s*(?:는|은|이)?\s*(\d{2,3})")
    if vital_fields:
        drafts.append(_draft("활력징후", "측정값 기록", vital_fields, timestamp, 0.92))

    body_fields: dict[str, Any] = {}
    _capture_number(value, body_fields, "weight_kg", r"(?:체중|몸무게)\s*(?:는|은|이)?\s*(\d{2,3}(?:\.\d)?)", float)
    _capture_number(value, body_fields, "height_cm", r"(?:키)\s*(?:는|은|가)?\s*(\d{2,3}(?:\.\d)?)", float)
    _capture_number(value, body_fields, "waist_cm", r"(?:허리둘레|허리 둘레)\s*(?:는|은|가)?\s*(\d{2,3}(?:\.\d)?)", float)
    if body_fields:
        drafts.append(_draft("신체", "신체 측정 기록", body_fields, timestamp, 0.9))

    if any(keyword in value for keyword in ("약", "복용", "투약")):
        status = "복용 완료" if any(keyword in value for keyword in ("먹었", "복용했", "투약했")) else "확인 필요"
        drafts.append(
            _draft(
                "복약",
                "복약 기록",
                {"status": status, "original_text": value},
                timestamp,
                0.72,
            )
        )

    symptom_keywords = (
        "통증", "두통", "어지", "기침", "열이", "메스꺼", "구토", "설사", "호흡", "가려", "붓기", "불편"
    )
    found_symptoms = [keyword for keyword in symptom_keywords if keyword in value]
    if found_symptoms:
        drafts.append(
            _draft(
                "증상",
                "증상 기록",
                {"matched_terms": found_symptoms, "original_text": value},
                timestamp,
                0.68,
            )
        )

    if any(keyword in value for keyword in ("식사", "식단", "아침", "점심", "저녁", "간식", "물 마", "수분")):
        drafts.append(_draft("식단·수분", "식사 또는 수분 기록", {"original_text": value}, timestamp, 0.62))

    activity_fields: dict[str, Any] = {}
    _capture_number(value, activity_fields, "steps", r"(\d{1,6})\s*걸음")
    _capture_number(value, activity_fields, "sleep_hours", r"(?:수면|잠)\s*(?:은|을|이)?\s*(\d{1,2}(?:\.\d)?)\s*시간", float)
    if activity_fields or any(keyword in value for keyword in ("운동", "러닝", "근력", "스트레칭")):
        if not activity_fields:
            activity_fields["original_text"] = value
        drafts.append(_draft("운동·수면", "활동 기록", activity_fields, timestamp, 0.78))

    if any(keyword in value for keyword in ("병원", "진료", "재진", "검사 예약", "예약")):
        drafts.append(_draft("병원 일정", "병원 일정 후보", {"original_text": value}, timestamp, 0.64))

    if any(keyword in value for keyword in ("처방전", "진단서", "검사표", "결과지", "퇴원 안내")):
        drafts.append(_draft("검사·문서", "의료 문서 기록", {"original_text": value}, timestamp, 0.7))

    if not drafts:
        drafts.append(_draft("확인 필요", "분류 확인 필요", {"original_text": value}, timestamp, 0.3))

    return {
        "emergency_check": emergency,
        "draft_count": len(drafts),
        "drafts": drafts,
        "requires_user_confirmation": True,
        "persisted": False,
        "next_step": "각 초안의 값과 분류를 사용자에게 보여주고 명시적으로 확인받으세요.",
    }


def draft_photo_health_records(
    photo_type: str,
    observed_text: str,
    input_mode: str = "paste",
    source_name: str | None = None,
    recorded_at: str | None = None,
) -> dict[str, Any]:
    photo_kind = _required_text(photo_type).strip().lower()
    if photo_kind not in PHOTO_TYPE_LABELS:
        raise HealthManagerError(
            "photo_type은 meal, medication, blood_pressure, prescription, lab, other 중 하나여야 합니다."
        )
    input_kind = _required_text(input_mode).strip().lower()
    if input_kind not in INPUT_MODE_LABELS:
        if recorded_at is None and source_name is None:
            try:
                _parse_datetime(input_kind)
            except HealthManagerError:
                raise HealthManagerError("input_mode는 file, camera, paste 중 하나여야 합니다.")
            recorded_at = input_kind
            input_kind = "paste"
        else:
            raise HealthManagerError("input_mode는 file, camera, paste 중 하나여야 합니다.")

    value = _required_text(observed_text)
    if len(value) > 2_000:
        raise HealthManagerError("사진 설명은 2,000자 이하로 작성해주세요.")

    timestamp = _parse_datetime(recorded_at).isoformat() if recorded_at else datetime.now().astimezone().isoformat()
    emergency = check_emergency_signals(value)
    label = PHOTO_TYPE_LABELS[photo_kind]
    drafts: list[dict[str, Any]] = []

    if photo_kind == "blood_pressure":
        vital_fields: dict[str, Any] = {}
        blood_pressure = re.search(r"(\d{2,3})\s*(?:/|에)\s*(\d{2,3})", value)
        if blood_pressure:
            vital_fields["systolic_mmHg"] = int(blood_pressure.group(1))
            vital_fields["diastolic_mmHg"] = int(blood_pressure.group(2))
        _capture_number(value, vital_fields, "pulse_bpm", r"(?:맥박|심박)\s*(?:은|이|수)?\s*(\d{2,3})")
        _capture_number(value, vital_fields, "spo2_percent", r"(?:산소포화도|산소 포화도)\s*(?:는|은|이)?\s*(\d{2,3})")
        if vital_fields:
            drafts.append(_draft("활력징후", label, vital_fields, timestamp, 0.96))
    elif photo_kind == "medication":
        drafts.append(_draft("복약", label, {"observed_text": value}, timestamp, 0.84))
    elif photo_kind == "meal":
        drafts.append(_draft("식단·수분", label, {"observed_text": value}, timestamp, 0.8))
    elif photo_kind == "prescription":
        drafts.append(_draft("처방·문서", label, {"observed_text": value}, timestamp, 0.82))
    elif photo_kind == "lab":
        drafts.append(_draft("검사·문서", label, {"observed_text": value}, timestamp, 0.82))
    else:
        drafts.append(_draft("확인 필요", label, {"observed_text": value}, timestamp, 0.55))

    if photo_kind != "blood_pressure":
        if any(keyword in value for keyword in ("혈압", "/", "mmHg")):
            blood_pressure = re.search(r"(\d{2,3})\s*(?:/|에)\s*(\d{2,3})", value)
            if blood_pressure:
                drafts.append(
                    _draft(
                        "활력징후",
                        "사진에서 읽은 혈압",
                        {
                            "systolic_mmHg": int(blood_pressure.group(1)),
                            "diastolic_mmHg": int(blood_pressure.group(2)),
                            "source": label,
                        },
                        timestamp,
                        0.78,
                    )
                )

    return {
        "photo_type": photo_kind,
        "photo_type_label": label,
        "input_mode": input_kind,
        "input_mode_label": INPUT_MODE_LABELS[input_kind],
        "source_name": source_name.strip() if source_name else None,
        "emergency_check": emergency,
        "draft_count": len(drafts),
        "drafts": drafts,
        "requires_user_confirmation": True,
        "persisted": False,
        "next_step": "사진에서 읽은 내용과 분류를 사용자에게 보여주고 명시적으로 확인받으세요.",
    }


def calculate_follow_up_date(
    completed_date: str,
    interval_days: int,
    holidays: list[str] | None = None,
) -> dict[str, Any]:
    try:
        completed = date.fromisoformat(completed_date)
    except ValueError as exc:
        raise HealthManagerError("완료일은 YYYY-MM-DD 형식이어야 합니다.") from exc
    if not 1 <= interval_days <= 3_650:
        raise HealthManagerError("간격은 1~3,650일 사이여야 합니다.")
    holiday_dates: set[date] = set()
    for item in holidays or []:
        try:
            holiday_dates.add(date.fromisoformat(item))
        except ValueError as exc:
            raise HealthManagerError("휴일은 YYYY-MM-DD 형식이어야 합니다.") from exc

    original = completed + timedelta(days=interval_days)
    adjusted = original
    while adjusted.weekday() >= 5 or adjusted in holiday_dates:
        adjusted -= timedelta(days=1)
    return {
        "completed_date": completed.isoformat(),
        "interval_days": interval_days,
        "calculated_date": original.isoformat(),
        "recommended_date": adjusted.isoformat(),
        "adjusted_to_previous_business_day": adjusted != original,
        "requires_user_confirmation": True,
        "notice": "제공된 휴일만 반영합니다. 병원 운영일과 실제 예약 가능 여부를 확인하세요.",
        "external_alert": {
            "channel": "kakao_calendar",
            "alert_type": "hospital_visit",
            "title": "병원 일정",
            "all_day": True,
            "event_date": adjusted.isoformat(),
            "summary": "병원 재진 일정",
            "action": "create_or_update_event",
        },
    }


def build_medication_reminders(
    medication_name: str,
    meal_times: list[str],
    delay_minutes: int = 30,
) -> dict[str, Any]:
    name = medication_name.strip()
    if not name or len(name) > 100:
        raise HealthManagerError("약 이름은 1~100자로 입력해주세요.")
    if not 0 <= delay_minutes <= 360:
        raise HealthManagerError("식후 지연 시간은 0~360분 사이여야 합니다.")
    if not 1 <= len(meal_times) <= 6:
        raise HealthManagerError("식사 시각은 1~6개를 입력해주세요.")

    reminders = []
    for meal_time in meal_times:
        try:
            meal = datetime.strptime(meal_time, "%H:%M")
        except ValueError as exc:
            raise HealthManagerError("식사 시각은 24시간제 HH:MM 형식이어야 합니다.") from exc
        reminder = meal + timedelta(minutes=delay_minutes)
        reminders.append({"meal_time": meal_time, "reminder_time": reminder.strftime("%H:%M")})
    return {
        "medication_name": name,
        "delay_minutes": delay_minutes,
        "reminders": reminders,
        "requires_user_confirmation": True,
        "notice": "처방전에 적힌 복용법을 사용자가 확인한 경우에만 알림을 저장하세요. 복용법을 새로 제안하지 않습니다.",
        "external_alert": {
            "channel": "kakao_calendar",
            "alert_type": "medication_schedule",
            "title": f"{name} 복약 알림",
            "recurrence": "daily",
            "event_times": [item["reminder_time"] for item in reminders],
            "summary": f"{name} 복약 알림",
            "action": "create_or_update_event",
        },
    }


def build_visit_brief(records: list[dict[str, Any]]) -> dict[str, Any]:
    if not records:
        raise HealthManagerError("요약할 기록이 없습니다.")
    if len(records) > 100:
        raise HealthManagerError("한 번에 최대 100개 기록을 요약할 수 있습니다.")

    grouped: dict[str, list[str]] = defaultdict(list)
    emergency_terms: set[str] = set()
    for record in records:
        category = str(record.get("category", "기타")).strip() or "기타"
        recorded_at = str(record.get("recorded_at", "시간 미상")).strip() or "시간 미상"
        summary = str(record.get("summary", record.get("title", "내용 미상"))).strip() or "내용 미상"
        grouped[category].append(f"{recorded_at}: {summary}"[:300])
        check = check_emergency_signals(summary)
        emergency_terms.update(check["detected_signals"])

    sections = [
        {"category": category, "count": len(items), "items": items[:10]}
        for category, items in sorted(grouped.items())
    ]
    category_counts = Counter(str(record.get("category", "기타")) for record in records)
    return {
        "record_count": len(records),
        "category_counts": dict(category_counts),
        "sections": sections,
        "emergency_signals_found": sorted(emergency_terms),
        "requires_user_confirmation": True,
        "notice": "원본 기록과 비교해 틀린 내용이 없는지 확인한 뒤 의료진에게 보여주세요. 이 브리핑은 진단서가 아닙니다.",
    }


def _required_text(text: str) -> str:
    value = text.strip()
    if not value:
        raise HealthManagerError("내용을 입력해주세요.")
    return value


def _parse_datetime(value: str) -> datetime:
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HealthManagerError("기록 시각은 ISO 8601 형식이어야 합니다.") from exc
    if parsed.tzinfo is None:
        raise HealthManagerError("기록 시각에는 시간대가 포함되어야 합니다.")
    return parsed


def _capture_number(
    text: str,
    target: dict[str, Any],
    key: str,
    pattern: str,
    converter: type[int] | type[float] = int,
) -> None:
    match = re.search(pattern, text)
    if match:
        target[key] = converter(match.group(1))


def _draft(
    category: str,
    title: str,
    fields: dict[str, Any],
    recorded_at: str,
    confidence: float,
) -> dict[str, Any]:
    return {
        "category": category,
        "title": title,
        "fields": fields,
        "recorded_at": recorded_at,
        "confidence": confidence,
        "confirmed": False,
    }
