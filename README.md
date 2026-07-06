# AI My Health Manager

대화를 건강 기록 초안으로 정리하고 응급 신호 확인, 복약 알림, 병원 일정과 진료 브리핑을 제공하는 안전 중심 MCP 서버입니다.

## 핵심 원칙

- 건강 입력을 진단하거나 바로 확정하지 않습니다.
- 모든 기록, 일정과 알림은 사용자 확인이 필요합니다.
- 응급 의심 표현을 먼저 확인하지만 자동 전화·신고는 하지 않습니다.
- 현재 MVP는 사용자 입력을 영구 저장하지 않습니다.

## MCP 도구

| 도구 | 역할 |
|---|---|
| `check_emergency_signals` | 응급 의심 표현 확인 |
| `draft_health_records` | 자연어를 확인 전 건강 기록 초안으로 분리 |
| `calculate_follow_up_date` | 방문 완료일 기준 다음 일정 계산 |
| `build_medication_reminders` | 확인된 복용 기준으로 알림 시각 계산 |
| `build_visit_brief` | 건강 기록을 진료용 브리핑으로 정리 |
| `draft_photo_health_records` | 사진 입력을 파일, 카메라, 붙여넣기 경로로 받아 건강 기록 초안으로 정리 |

## 로컬 실행

웹 화면은 `http://localhost:8000/`에서 열 수 있고, MCP는 `/mcp`를 사용한다.

```powershell
cd C:\projects\ai_my_health_manager
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
pytest
python -m ai_my_health_manager.server_photo
```

- MCP: `http://localhost:8000/mcp`
- Health: `http://localhost:8000/healthz`

다른 터미널에서 실제 HTTP와 MCP 도구 목록을 검증할 수 있습니다.

```powershell
python .\scripts\verify_mcp.py
```

배포된 서버는 기본 URL을 인자로 전달합니다.

```powershell
python .\scripts\verify_mcp.py https://<발급된-호스트>
```

## Docker

```powershell
docker build --platform linux/amd64 -t ai-my-health-manager:v0.1.0 .
docker run --rm -p 8000:8000 ai-my-health-manager:v0.1.0
```

## 문서

- [PlayMCP 배포·등록 가이드](PLAYMCP_REGISTRATION_GUIDE.md)
- [프로그램 개발 가이드](PROGRAM_GUIDE.md)
- [공모전 참가 가이드](CONTEST_GUIDE.md)
- [GitHub·Docker·PlayMCP 업로드 가이드](UPLOAD_GUIDE.md)
- [AGENTIC PLAYER 10 신청 문안](apply.md)

## 주의

이 프로젝트는 의료기기가 아니며 의료진의 진단·치료를 대신하지 않습니다. 증상이 심하거나 빠르게 악화되면 119 또는 의료기관의 도움을 받으세요.

복약과 병원 일정의 외부 알림은 카카오 캘린더 연동 패키지로 만들어 사용합니다.

