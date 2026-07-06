# Kakao Cloud MCP Git 소스 빌드 가이드

GitHub의 `ai_my_health_manager`를 Kakao Cloud MCP 서버로 빌드·배포하는 절차다.

## 1. 등록 전 확인

저장소:

```text
https://github.com/3DPDKR/ai_my_health_manager
```

GitHub `main` 브랜치에 다음 파일이 있어야 한다.

- `Dockerfile`
- `pyproject.toml`
- `src/ai_my_health_manager/server.py`
- `src/ai_my_health_manager/domain.py`

저장소는 Public이므로 PAT는 필요하지 않다.

## 2. Git 소스 빌드 입력값

| 화면 항목 | 입력값 |
|---|---|
| MCP 서버 이름 | `ai-my-health-manager-prod` |
| 설명 | `대화를 건강 기록 초안으로 정리하고 응급 신호 확인, 복약 알림, 병원 일정과 진료 브리핑을 제공하는 안전 중심 MCP 서버` |
| Git URL | `https://github.com/3DPDKR/ai_my_health_manager.git` |
| 브랜치 / ref | `main` |
| Dockerfile 경로 | `Dockerfile` |
| PAT | 공란 |

### MCP 서버 이름

```text
ai-my-health-manager-prod
```

- 소문자 영문과 하이픈만 사용한다.
- 프로젝트명처럼 밑줄 `_`을 사용하면 안 된다.
- 개발 서버가 별도로 필요하면 `ai-my-health-manager-dev`를 사용한다.

### 설명

```text
대화를 건강 기록 초안으로 정리하고 응급 신호 확인, 복약 알림, 병원 일정과 진료 브리핑을 제공하는 안전 중심 MCP 서버
```

### Git URL

```text
https://github.com/3DPDKR/ai_my_health_manager.git
```

브라우저 주소와 달리 `.git`으로 끝나는 clone URL을 입력한다.

### 브랜치 / ref

```text
main
```

### Dockerfile 경로

```text
Dockerfile
```

저장소 루트 기준 경로다. `/Dockerfile` 또는 `./Dockerfile`로 입력하지 않는다.

### PAT

비워 둔다. Public 저장소에 GitHub 비밀번호나 Personal Access Token을 입력할 필요가 없다.

## 3. 등록하기

1. 위 표와 화면의 입력값을 대조한다.
2. PAT가 비어 있는지 확인한다.
3. `등록하기`를 한 번 누른다.
4. 서버 목록으로 이동해 배포 상태를 확인한다.

등록 전 체크리스트:

- [ ] 서버 이름에 대문자, 공백과 밑줄이 없다.
- [ ] Git URL이 `.git`으로 끝난다.
- [ ] 브랜치가 `main`이다.
- [ ] Dockerfile 경로가 정확히 `Dockerfile`이다.
- [ ] PAT가 비어 있다.
- [ ] GitHub에 실제 건강정보, `.env`, API 키와 토큰이 없다.

## 4. 배포 상태 확인

일반적인 상태 흐름:

```text
접수 → Building 또는 Starting → Active
```

`Active`가 되기 전에는 PlayMCP 등록을 진행하지 않는다.

Active 서버의 상세 화면에서 다음을 확인한다.

- Endpoint URL
- 서버 상태 `Active`
- 빌드·실행 로그
- 지원 Tools 목록

MCP Endpoint 예시:

```text
https://<발급된-호스트>/mcp
```

실제 주소는 Kakao Cloud 상세 화면에서 복사한다. `<발급된-호스트>` 문구를 그대로 사용하면 안 된다.

## 5. 상태 확인

MCP Endpoint와 같은 호스트의 `/healthz`를 브라우저에서 연다.

```text
https://<발급된-호스트>/healthz
```

정상 응답:

```json
{
  "status": "ok",
  "service": "ai-my-health-manager",
  "version": "0.1.0"
}
```

## 6. 빌드 실패 해결

### Git clone 실패

- Git URL과 `main` 브랜치를 다시 확인한다.
- 저장소가 Public인지 확인한다.
- Public 저장소의 PAT 칸을 비운다.

### Dockerfile을 찾을 수 없음

- 경로를 정확히 `Dockerfile`로 입력한다.
- GitHub 저장소 루트에 Dockerfile이 있는지 확인한다.

### Python 패키지 설치 실패

- 빌드 로그의 `pip install` 오류를 확인한다.
- GitHub에 `pyproject.toml`이 있는지 확인한다.

### 서버 시작 실패

컨테이너는 다음 명령으로 시작한다.

```text
python -m ai_my_health_manager.server
```

서버 설정:

```text
HOST=0.0.0.0
PORT=8000
```

### Active지만 PlayMCP 연결 실패

- Endpoint가 `/mcp`로 끝나는지 확인한다.
- `/mcp/mcp`처럼 경로를 중복하지 않는다.
- `/healthz`나 GitHub URL을 MCP Endpoint로 입력하지 않는다.

## 7. Active 후 PlayMCP 등록

1. Kakao Cloud 상세 화면에서 `/mcp` Endpoint를 복사한다.
2. `https://playmcp.kakao.com/console`에 접속한다.
3. `새로운 MCP 서버 등록`을 선택한다.
4. Kakao Cloud `/mcp` Endpoint를 입력한다.
5. `정보 불러오기`를 누른다.
6. 아래 5개 도구가 모두 표시되는지 확인한다.

```text
check_emergency_signals
draft_health_records
calculate_follow_up_date
build_medication_reminders
build_visit_brief
```

7. 처음에는 `등록 및 심사 요청`이 아니라 `임시 등록`을 선택한다.
8. 정상 입력, 응급 입력과 오류 입력을 테스트한다.
9. 검증 후 `등록 및 심사 요청`을 진행한다.
10. 승인 후 공개 상태를 `전체 공개`로 변경한다.

## 8. URL 용도 구분

PlayMCP 서버 등록에는 Kakao Cloud Endpoint를 사용한다.

```text
https://<Kakao-Cloud-호스트>/mcp
```

AGENTIC PLAYER 10 신청서에는 승인·전체 공개 후의 PlayMCP 상세 페이지를 사용한다.

```text
https://playmcp.kakao.com/mcp/<실제 서비스 ID>
```

두 주소를 서로 바꾸어 입력하면 안 된다.

