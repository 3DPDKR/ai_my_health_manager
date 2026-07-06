# PlayMCP 신규 MCP 서버 등록 입력안

아래 값만 그대로 입력하면 된다.

## 제작자 정보

- 팀프로필 이름: `강대현`

## 대표 이미지

- 업로드 필요
- 권장 크기: `600x600px` 이상
- 형식: `png`, `jpg`, `jpeg`, `gif`

## MCP 정보

- MCP 이름: `AI My Health Manager`
- MCP 식별자: `healthManager`
- MCP 설명:

```text
AI My Health Manager는 대화나 사진으로 받은 건강 정보를 기록 초안으로 정리하고, 응급 신호를 먼저 확인한 뒤 복약 알림, 병원 일정, 진료 요약까지 쉽게 이어주는 개인 건강관리 MCP 서버입니다. 누구나 카카오톡처럼 편하게 건강 기록을 관리할 수 있도록 돕습니다.
```

## 대화 예시

```text
오늘 혈압 132/86이야
```

```text
아침 약 먹는 시간 알려줘
```

```text
다음 진료일 계산해줘
```

## 인증 방식

- 인증 사용하지 않음

## MCP Endpoint

```text
https://ai-my-health-manager-prod.playmcp-endpoint.kakaocloud.io/mcp
```

## 등록 후 확인

- `정보 불러오기`를 눌러 Tool 5개가 표시되는지 확인
- 표시되어야 할 Tool:
  - `check_emergency_signals`
  - `draft_health_records`
  - `calculate_follow_up_date`
  - `build_medication_reminders`
  - `build_visit_brief`

## 주의

- 이 문서에는 `PlayMCP 상세 페이지 URL`을 적지 않는다.
- 상세 페이지 URL은 승인 후 생성되는 공개 주소다.
