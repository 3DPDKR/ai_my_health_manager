# Build and Rebuild Guide

이 문서는 `ai_my_health_manager`를 GitHub에 올린 뒤, PlayMCP용 Git 소스 빌드와 재검증을 다시 돌릴 때 참고하는 문서다.

## 현재 기준

- GitHub 저장소: `https://github.com/3DPDKR/ai_my_health_manager.git`
- 브랜치: `main`
- Dockerfile: `Dockerfile`
- 실행 모듈: `ai_my_health_manager.server_photo`
- MCP Endpoint: `https://ai-my-health-manager-prod.playmcp-endpoint.kakaocloud.io/mcp`

## 로컬 재빌드

```powershell
cd C:\projects\ai_my_health_manager
.\.venv\Scripts\python.exe -m pytest -q
.\.venv\Scripts\python.exe .\scripts\verify_mcp.py http://127.0.0.1:8000
```

## Docker 재빌드

```powershell
docker build --platform linux/amd64 -t ai-my-health-manager:v0.1.0 .
docker run --rm -p 8000:8000 ai-my-health-manager:v0.1.0
```

## PlayMCP 재등록

1. GitHub `main` 브랜치 최신 커밋을 푸시한다.
2. PlayMCP 콘솔에서 Git 소스 빌드를 다시 실행한다.
3. `정보 불러오기`를 눌러 Tool이 보이는지 확인한다.
4. 다음 Tool이 모두 보여야 한다.

```text
check_emergency_signals
draft_health_records
draft_photo_health_records
calculate_follow_up_date
build_medication_reminders
build_visit_brief
```

## 수정 포인트

이 프로젝트는 다음 파일만 바꾸면 다시 빌드할 수 있게 구성했다.

- `src/ai_my_health_manager/server_photo.py`
- `src/ai_my_health_manager/domain_photo.py`
- `tests/test_server_photo.py`
- `tests/test_photo_domain.py`
- `scripts/verify_mcp.py`

사진 입력은 다음 세 가지 경로를 같은 도구로 받는다.

- `file` - 파일 열기
- `camera` - 바로 찍기
- `paste` - 붙여넣기

## 주의

- 브라우저에서 `/mcp`를 직접 열면 `text/event-stream` 오류가 보일 수 있다. MCP 클라이언트로 확인한다.
- 실제 배포 후에는 `/healthz`와 `tools/list`가 모두 성공해야 한다.
