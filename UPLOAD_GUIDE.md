# GitHub·Docker·PlayMCP 업로드 및 등록 가이드

## 1. 배포 원본

- GitHub: `https://github.com/3DPDKR/ai_my_health_manager`
- Clone: `https://github.com/3DPDKR/ai_my_health_manager.git`
- 공개 범위: Public
- 기본 브랜치: `main`
- Dockerfile: `Dockerfile`

## 2. GitHub 업로드

```powershell
cd C:\projects\ai_my_health_manager
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[dev]"
pytest

git init
git add .
git commit -m "Initialize AI My Health Manager MCP"
git branch -M main
git remote add origin https://github.com/3DPDKR/ai_my_health_manager.git
git push -u origin main
```

이미 `origin`이 있으면 다시 추가하지 않는다.

```powershell
git remote -v
git status
git branch --show-current
```

커밋 금지:

- `.env`
- API 키와 인증 토큰
- `DATA_GO_KR_SERVICE_KEY`
- 데이터베이스 접속 문자열
- PlayMCP·레지스트리 비밀번호
- 실제 건강정보와 사진

`.env.example`에는 변수 이름만 둔다. Public 저장소이므로 Git PAT는 입력하지 않는다.

## 3. Docker 점검

PlayMCP in KC 컨테이너는 `linux/amd64`여야 한다.

```powershell
docker build --platform linux/amd64 -t ai-my-health-manager:v0.1.0 .
docker run --rm -p 8000:8000 ai-my-health-manager:v0.1.0
docker image inspect ai-my-health-manager:v0.1.0 --format '{{.Architecture}}/{{.Os}}'
```

확인 결과는 `amd64/linux`여야 한다. 운영에는 `latest`가 아닌 고정 태그를 사용한다.

## 4. PlayMCP in KC 접속

1. `https://playmcp.kakaocloud.io`에 접속한다.
2. PlayMCP에 가입된 카카오 계정으로 로그인한다.
3. `My MCP Servers` 화면을 확인한다.
4. `+ 새 MCP 서버 등록`을 누른다.
5. `Git 소스 빌드`를 선택한다.

## 5. Git 소스 빌드 입력

| 항목 | 개발 서버 입력값 |
|---|---|
| MCP 서버 이름 | `ai-my-health-manager-dev` |
| 설명 | `사진과 대화를 건강 기록·식단·복약·병원 일정으로 정리하는 개발용 MCP 서버` |
| Git URL | `https://github.com/3DPDKR/ai_my_health_manager.git` |
| 브랜치/ref | `main` |
| Dockerfile 경로 | `Dockerfile` |
| PAT | 공란 |

제출 서버 이름은 `ai-my-health-manager-prod`를 사용한다.

입력 규칙:

- 서버명은 영문 소문자, 숫자, 하이픈을 사용한다.
- PlayMCP in KC의 이름과 설명은 PlayMCP 공개 정보와 별개다.
- Git URL의 저장소에 Dockerfile이 있어야 한다.
- Dockerfile 경로는 저장소 루트 기준 상대경로다.
- PAT는 HTTPS private 저장소에서만 입력한다.

## 6. 서버 활성화

1. 입력값을 확인하고 `등록하기`를 누른다.
2. `Starting` 상태에서 기다린다.
3. 수십 초에서 수 분 후 `Active`로 바뀌는지 확인한다.
4. Active 서버 카드를 눌러 상세 화면을 연다.

Active 실패 점검:

- Git URL과 main 브랜치
- Dockerfile 경로
- Python 의존성 설치
- `0.0.0.0:$PORT` 수신
- `/mcp` Streamable HTTP endpoint
- 컨테이너 시작 명령
- `linux/amd64` 호환
- 필수 환경변수

## 7. Endpoint 확인

상세 화면의 `Endpoint URL`을 복사한다.

```text
https://<server-name>.playmcp-endpoint.kakaocloud.io/mcp
```

확인 항목:

- Status `Active`
- Endpoint URL 끝의 `/mcp`
- Endpoint name과 Namespace
- Description
- 지원 Tools 목록과 설명

지원 Tools가 비거나 누락되면 PlayMCP 등록 전에 서버를 수정한다.

`중지`는 일시 중지이며 `삭제`는 복구할 수 없다. 서버는 계정당 최대 2개이므로 개발용과 제출용으로 각각 사용한다.

## 8. PlayMCP 개발자 콘솔 등록

1. `https://playmcp.kakao.com/console`에 접속한다.
2. `새로운 MCP 서버 등록`을 선택한다.
3. PlayMCP in KC Endpoint URL을 입력한다.
4. `정보 불러오기`를 실행한다.
5. 초기화와 `tools/list` 결과를 확인한다.
6. 개발 단계에서는 `임시 등록`을 선택한다.
7. AI 채팅에서 도구를 테스트한다.

테스트:

- 기대한 Tool Selection
- 정확한 Argument Binding
- 사진이 도구에 전달되는 형태
- 도구의 순차·병렬 호출
- 데이터 없음·잘못된 입력·타임아웃
- 출처·기준일·확인 상태 반환
- 건강정보·인증정보 로그 미노출

## 9. 제출 서버와 심사

```text
개발 서버 검증
→ GitHub main에 최종 push
→ ai-my-health-manager-prod 등록
→ Active와 Endpoint 확인
→ PlayMCP 등록 및 최종 테스트
→ 등록 및 심사 요청
→ 승인 확인
→ 전체 공개
→ Player 예선 참여
```

- GitHub push만으로 서버가 자동 갱신된다고 가정하지 않는다.
- 배포한 Git commit ID와 이미지 버전을 기록한다.
- 안전한 비밀 환경변수 주입이 확인되지 않으면 키를 저장소에 넣지 않고 해당 API 연동을 보류한다.
- 심사와 공개 투표 기간에는 제출 서버를 중지하지 않는다.
- Player 예선 제출은 1회만 가능하다.

## 10. 최종 체크리스트

- [ ] 테스트 성공
- [ ] 비밀정보·건강정보 미포함
- [ ] GitHub main 최신
- [ ] Docker `linux/amd64`
- [ ] 개발 서버 `Starting → Active`
- [ ] Endpoint `/mcp`
- [ ] 지원 Tools 확인
- [ ] PlayMCP 임시 등록 테스트
- [ ] 제출 서버 Active
- [ ] 등록 및 심사 요청
- [ ] 승인 후 전체 공개
- [ ] Player 예선 제출

