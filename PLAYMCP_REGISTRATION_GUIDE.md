# AI My Health Manager 배포·PlayMCP 등록 가이드

이 문서는 `ai_my_health_manager`를 Kakao Cloud의 `Git 소스 빌드`로 배포하고, 발급된 Endpoint를 PlayMCP 개발자 콘솔에 등록하는 절차를 정리한다.

## 1. 전체 순서

```text
GitHub main에 소스 푸시
→ Kakao Cloud Git 소스 빌드
→ 서버 Active 확인
→ /healthz 및 /mcp 확인
→ PlayMCP 콘솔에서 정보 불러오기
→ 임시 등록과 AI 채팅 테스트
→ 등록 및 심사 요청
→ 승인 후 전체 공개
→ AGENTIC PLAYER 10 신청서 제출
```

## 2. 현재 상태

| 항목 | 상태 |
|---|---|
| GitHub 저장소 | 생성 완료: `https://github.com/3DPDKR/ai_my_health_manager` |
| 로컬 Git | `main`, `origin` 설정 완료 |
| GitHub 소스 푸시 | 아직 필요 |
| Dockerfile | 준비 완료 |
| MCP Endpoint | `/mcp` |
| 상태 확인 Endpoint | `/healthz` |
| Kakao Cloud 배포 | 아직 필요 |
| PlayMCP 등록 | Kakao Cloud Endpoint 발급 후 진행 |

## 3. GitHub에 먼저 소스 올리기

Kakao Cloud가 Git URL에서 소스를 가져오므로 원격 저장소가 비어 있으면 빌드할 수 없다.

```powershell
cd C:\projects\ai_my_health_manager
git status
git add .
git commit -m "Initialize AI My Health Manager MCP"
git push -u origin main
```

GitHub에서 아래 파일이 표시되는지 확인한다.

- `README.md`
- `Dockerfile`
- `pyproject.toml`
- `src/ai_my_health_manager/server.py`
- `src/ai_my_health_manager/domain.py`
- `tests/test_domain.py`

`.env`, PAT, API 키, 실제 건강정보와 실제 처방전 사진은 커밋하지 않는다.

## 4. Kakao Cloud `Git 소스 빌드` 입력값

현재 화면에 아래 값을 그대로 입력한다.

### MCP 서버 이름

```text
ai-my-health-manager-prod
```

- 소문자 영문과 하이픈만 사용하므로 Kubernetes/DNS 이름 규칙에 맞는다.
- 최종 심사 제출용 서버라는 의미로 `prod`를 사용한다.
- 별도 개발 서버가 필요하면 `ai-my-health-manager-dev`를 사용한다.

### 설명

```text
대화를 건강 기록 초안으로 정리하고 응급 신호 확인, 복약 알림, 병원 일정과 진료 브리핑을 제공하는 안전 중심 MCP 서버
```

### Git URL

```text
https://github.com/3DPDKR/ai_my_health_manager.git
```

### 브랜치 / ref

```text
main
```

### Dockerfile 경로

```text
Dockerfile
```

Dockerfile이 저장소 루트에 있으므로 앞에 `/` 또는 `./`를 붙이지 않는다.

### PAT

```text
비워 둠
```

GitHub 저장소가 Public이므로 PAT가 필요 없다. 토큰을 입력하거나 저장소에 커밋하지 않는다.

### 입력값 최종 표

| 화면 필드 | 입력값 |
|---|---|
| MCP 서버 이름 | `ai-my-health-manager-prod` |
| 설명 | `대화를 건강 기록 초안으로 정리하고 응급 신호 확인, 복약 알림, 병원 일정과 진료 브리핑을 제공하는 안전 중심 MCP 서버` |
| Git URL | `https://github.com/3DPDKR/ai_my_health_manager.git` |
| 브랜치 / ref | `main` |
| Dockerfile 경로 | `Dockerfile` |
| PAT | 공란 |

## 5. 배포 버튼을 누르기 전 확인

- [ ] GitHub 저장소 웹페이지에 소스 파일이 보인다.
- [ ] 기본 브랜치가 `main`이다.
- [ ] Git URL 끝에 `.git`이 있다.
- [ ] Dockerfile 경로가 `Dockerfile`이다.
- [ ] PAT가 비어 있다.
- [ ] 서버 이름이 `ai-my-health-manager-prod`이다.
- [ ] 실제 건강정보나 비밀키가 GitHub에 없다.

위 항목을 확인한 뒤 화면의 생성 또는 배포 버튼을 누른다. 배포 접수는 외부 상태를 변경하므로 입력값을 마지막으로 검토한다.

## 6. Kakao Cloud 배포 상태 확인

배포 후 서버 목록에서 상태 변화를 확인한다.

```text
Starting 또는 Building → Active
```

수십 초에서 수 분이 걸릴 수 있다. `Active`가 되기 전에 PlayMCP 등록을 진행하지 않는다.

### 실패 시 점검 순서

1. GitHub `main`에 소스가 실제로 올라갔는지 확인한다.
2. 빌드 로그에서 저장소 clone 실패 여부를 확인한다.
3. Dockerfile 탐색 실패가 있으면 경로가 정확히 `Dockerfile`인지 확인한다.
4. Python 패키지 설치 실패가 있으면 `pyproject.toml`을 확인한다.
5. 컨테이너 시작 실패가 있으면 시작 명령과 포트 설정을 확인한다.

현재 Dockerfile은 다음 조건으로 구성되어 있다.

- Python 3.12
- `HOST=0.0.0.0`
- `PORT=8000`
- `python -m ai_my_health_manager.server`
- `/mcp` Streamable HTTP
- `/healthz` 상태 확인

## 7. Active 후 Endpoint 확인

서버 상세 화면에서 Endpoint URL을 복사한다. 정확한 값은 배포 후 화면에서 발급된다.

```text
https://<발급된-호스트>/mcp
```

주의사항:

- Endpoint가 이미 `/mcp`로 끝나면 `/mcp`를 다시 붙이지 않는다.
- GitHub URL은 PlayMCP Endpoint가 아니다.
- `/healthz` URL도 PlayMCP Endpoint가 아니다.

상태 확인 주소는 같은 호스트에 `/healthz`를 사용한다.

```text
https://<발급된-호스트>/healthz
```

정상 응답:

```json
{"status":"ok","service":"ai-my-health-manager","version":"0.1.0"}
```

## 8. PlayMCP 개발자 콘솔 등록

1. [PlayMCP 개발자 콘솔](https://playmcp.kakao.com/console)에 로그인한다.
2. `새로운 MCP 서버 등록`을 선택한다.
3. Kakao Cloud에서 복사한 `/mcp` Endpoint URL을 입력한다.
4. `정보 불러오기`를 누른다.
5. 초기화 성공과 `tools/list` 결과를 확인한다.
6. 처음에는 `등록 및 심사 요청`이 아니라 **`임시 등록`**을 선택한다.

현재 MVP는 별도 Key/Token/OAuth 인증을 구현하지 않았다. 인증 방식 선택란이 표시되면 `인증 없음`에 해당하는 옵션을 사용한다.

## 9. 정보 불러오기 후 확인할 내용

| 항목 | 기대값 |
|---|---|
| 서버 표시명 | `AI My Health Manager` |
| Endpoint | Kakao Cloud에서 발급된 `/mcp` URL |
| 초기화 | 성공 |
| 도구 개수 | 5개 |

반드시 표시되어야 하는 도구:

| 도구명 | 역할 |
|---|---|
| `check_emergency_signals` | 응급 의심 표현 우선 확인 |
| `draft_health_records` | 자연어를 확인 전 건강 기록 초안으로 분리 |
| `calculate_follow_up_date` | 방문 완료일 기준 다음 일정 계산 |
| `build_medication_reminders` | 확인된 복용 기준으로 알림 시각 계산 |
| `build_visit_brief` | 건강 기록을 진료용 브리핑으로 정리 |

도구가 0개이거나 일부가 누락되면 임시 등록을 완료하지 말고 Kakao Cloud 로그와 Endpoint를 먼저 수정한다.

## 10. 공개 정보 입력 문안

PlayMCP 화면에서 이름, 설명, 태그 등을 입력하거나 수정해야 할 때 아래 값을 사용한다. 콘솔 버전에 따라 표시되는 필드는 달라질 수 있다.

### 서비스명

```text
AI My Health Manager
```

### 한 줄 설명

```text
대화를 건강 기록으로 정리하고 복약과 병원 일정을 다음 행동으로 연결하는 개인 건강관리 에이전트
```

### 상세 설명

```text
AI My Health Manager는 사용자의 자연스러운 대화에서 혈압 등 측정값, 증상, 복약 여부와 병원 일정을 구분해 확인 가능한 기록 초안으로 정리합니다. 응급 의심 표현을 먼저 확인하고, 사용자가 확인한 처방과 일정에 한해 복약 알림 시각과 다음 방문일을 계산합니다. 누적 기록은 진료 전 의료진에게 보여줄 수 있는 짧은 브리핑으로 정리합니다. 진단·치료·처방 변경을 하지 않으며 모든 결과는 사용자 확인 전까지 확정하지 않습니다.
```

### 권장 태그

```text
건강관리, 건강기록, 복약관리, 병원일정, 진료준비
```

### 홈페이지 또는 소스 URL

```text
https://github.com/3DPDKR/ai_my_health_manager
```

### 안전 안내

```text
현재 예선 MVP는 입력을 영구 저장하지 않습니다. 본 서비스는 의료 진단이나 치료를 제공하지 않으며, 응급 상황에서는 119 또는 의료기관의 도움을 받아야 합니다.
```

## 11. 임시 등록 후 AI 채팅 테스트

### 여러 기록 분리

입력:

```text
오늘 혈압은 132/86이고 저녁 약을 먹었어. 다음 병원 예약도 있어.
```

확인:

- `draft_health_records` 선택
- 활력징후, 복약, 병원 일정 초안 생성
- `requires_user_confirmation: true`
- `persisted: false`

### 응급 표현

입력:

```text
갑자기 말이 어눌하고 한쪽 힘이 빠져요.
```

확인:

- `check_emergency_signals` 선택
- `emergency_possible: true`
- 119 또는 응급실 안내
- `automatic_contact: false`

### 복약 알림

입력:

```text
처방약을 아침 8시와 저녁 6시 30분 식후 30분에 먹도록 알림 시간을 계산해줘.
```

확인:

- `build_medication_reminders` 선택
- 식사 시각 `08:00`, `18:30`
- 알림 후보 `08:30`, `19:00`
- 저장 전 사용자 확인 요청

### 다음 방문일

입력:

```text
2026년 7월 9일에 진료를 마쳤고 30일 뒤에 다시 오라고 했어. 다음 날짜를 계산해줘.
```

확인:

- `calculate_follow_up_date` 선택
- 완료일 `2026-07-09`, 간격 `30`
- 주말인 8월 8일 대신 이전 평일인 8월 7일 제안

### 오류 처리

입력:

```text
약 알림을 25시로 설정해줘.
```

확인:

- 서버가 중단되지 않음
- `ok: false`
- 24시간제 `HH:MM` 형식 오류 안내

## 12. 심사 요청 전 체크리스트

- [ ] Kakao Cloud 서버 상태가 `Active`다.
- [ ] `/healthz`가 정상 응답한다.
- [ ] PlayMCP 정보 불러오기가 성공한다.
- [ ] 5개 도구가 모두 표시된다.
- [ ] 정상·응급·오류 테스트가 모두 통과한다.
- [ ] 사용자 확인 전 저장되었다고 표현하지 않는다.
- [ ] 진단·치료·처방 변경 표현이 없다.
- [ ] API 키, 토큰과 서버 내부 경로가 응답에 노출되지 않는다.
- [ ] 공개 설명과 GitHub URL이 정확하다.

## 13. 심사 요청과 전체 공개

임시 등록 테스트를 모두 통과한 뒤 PlayMCP 콘솔에서 `등록 및 심사 요청`을 선택한다.

승인 후에는 다음 절차가 추가로 필요하다.

1. 공개 상태를 `나에게만 공개`에서 `전체 공개`로 변경한다.
2. 로그아웃 상태에서 공개 상세 페이지가 열리는지 확인한다.
3. 공개 상세 페이지 URL을 복사한다.
4. `apply.md`의 `[실제 서비스 ID]`를 교체한다.
5. AGENTIC PLAYER 10 신청서에 공개 상세 페이지 URL을 입력한다.

신청서에는 Kakao Cloud `/mcp` Endpoint가 아니라 다음 형식의 **PlayMCP 공개 상세 페이지 URL**을 입력한다.

```text
https://playmcp.kakao.com/mcp/<실제 서비스 ID>
```

## 14. 문제 해결표

| 증상 | 확인할 내용 |
|---|---|
| Git clone 실패 | 저장소가 Public인지, Git URL과 `main`이 정확한지 확인 |
| Dockerfile 없음 | 경로를 `Dockerfile`로 입력했는지 확인 |
| 배포 상태 실패 | Kakao Cloud 빌드·실행 로그 확인 |
| 정보 불러오기 실패 | 서버 Active 여부와 `/mcp` Endpoint 확인 |
| 도구 0개 | MCP 초기화 및 `tools/list` 응답 확인 |
| 잘못된 도구 선택 | 도구 설명과 호출 조건 수정 후 재배포 |
| 참가 신청 불가 | 승인 후 공개 상태가 `전체 공개`인지 확인 |

## 15. 공식 자료

- PlayMCP 개발자 콘솔: https://playmcp.kakao.com/console
- PlayMCP 등록·테스트 설명: https://tech.kakao.com/posts/734
- AGENTIC PLAYER 10 안내: https://b.kakao.com/views/PlayMCP/AGENTIC_PlAYER_10

