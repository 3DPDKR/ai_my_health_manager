from __future__ import annotations


def dashboard_html() -> str:
    return """<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>AI My Health Manager</title>
  <style>
    :root {
      --bg: #f4f7f2;
      --panel: rgba(255, 255, 255, 0.88);
      --panel-strong: #ffffff;
      --line: rgba(25, 38, 28, 0.1);
      --text: #12311f;
      --muted: #5d6d60;
      --green: #17884c;
      --green-strong: #0f6c3b;
      --blue: #2264ff;
      --red: #d94b4b;
      --shadow: 0 18px 50px rgba(10, 40, 22, 0.12);
      --radius: 22px;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, Pretendard, "Apple SD Gothic Neo", "Noto Sans KR", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(23, 136, 76, 0.12), transparent 28%),
        radial-gradient(circle at 90% 10%, rgba(34, 100, 255, 0.12), transparent 24%),
        linear-gradient(180deg, #f7faf4 0%, #edf4ef 100%);
      min-height: 100vh;
    }

    .shell {
      max-width: 1240px;
      margin: 0 auto;
      padding: 24px;
    }

    .hero {
      display: grid;
      grid-template-columns: 1.3fr 0.9fr;
      gap: 18px;
      align-items: stretch;
    }

    .brand, .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      backdrop-filter: blur(18px);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }

    .brand {
      padding: 28px;
      position: relative;
      overflow: hidden;
    }

    .brand::after {
      content: "";
      position: absolute;
      inset: auto -90px -120px auto;
      width: 320px;
      height: 320px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(23, 136, 76, 0.18), transparent 68%);
      pointer-events: none;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 7px 12px;
      border-radius: 999px;
      background: rgba(23, 136, 76, 0.09);
      color: var(--green-strong);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: -0.01em;
    }

    h1 {
      margin: 16px 0 10px;
      font-size: clamp(32px, 4vw, 54px);
      line-height: 1.04;
      letter-spacing: -0.04em;
    }

    .lead {
      max-width: 58ch;
      font-size: 16px;
      line-height: 1.75;
      color: var(--muted);
      margin: 0 0 22px;
    }

    .hero-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }

    .button {
      border: 0;
      border-radius: 14px;
      padding: 13px 16px;
      font-weight: 700;
      cursor: pointer;
      transition: transform 0.18s ease, box-shadow 0.18s ease, background 0.18s ease;
      text-decoration: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }

    .button:hover { transform: translateY(-1px); }
    .button.primary {
      background: linear-gradient(135deg, var(--green), var(--green-strong));
      color: white;
      box-shadow: 0 14px 30px rgba(23, 136, 76, 0.24);
    }
    .button.secondary {
      background: white;
      color: var(--text);
      border: 1px solid var(--line);
    }

    .metric-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
      margin-top: 18px;
    }

    .metric {
      background: rgba(255, 255, 255, 0.8);
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 16px;
    }

    .metric .label {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 8px;
    }

    .metric .value {
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.04em;
    }

    .metric .sub {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }

    .panel {
      padding: 18px;
    }

    .panel h2 {
      margin: 0 0 14px;
      font-size: 18px;
      letter-spacing: -0.03em;
    }

    .input-card {
      background: var(--panel-strong);
      border: 1px solid var(--line);
      border-radius: 20px;
      padding: 16px;
      display: grid;
      gap: 12px;
    }

    .composer {
      display: grid;
      gap: 12px;
    }

    .textarea {
      width: 100%;
      min-height: 120px;
      resize: vertical;
      border-radius: 18px;
      border: 1px solid var(--line);
      padding: 15px 16px;
      font: inherit;
      color: var(--text);
      background: #fbfdfb;
      outline: none;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }

    .chip {
      border: 1px solid var(--line);
      background: white;
      color: var(--text);
      border-radius: 999px;
      padding: 10px 14px;
      font-size: 14px;
      font-weight: 700;
      cursor: pointer;
    }

    .chip.active {
      background: rgba(23, 136, 76, 0.1);
      border-color: rgba(23, 136, 76, 0.25);
      color: var(--green-strong);
    }

    .split {
      display: grid;
      grid-template-columns: minmax(0, 1.08fr) minmax(280px, 0.92fr);
      gap: 18px;
      margin-top: 18px;
    }

    .cards {
      display: grid;
      gap: 14px;
    }

    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 20px;
      padding: 18px;
      box-shadow: var(--shadow);
    }

    .card-header {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: center;
      margin-bottom: 12px;
    }

    .card-title {
      font-size: 17px;
      font-weight: 800;
      letter-spacing: -0.03em;
    }

    .card-badge {
      font-size: 12px;
      color: var(--green-strong);
      background: rgba(23, 136, 76, 0.1);
      padding: 7px 10px;
      border-radius: 999px;
      font-weight: 700;
      white-space: nowrap;
    }

    .summary-list {
      display: grid;
      gap: 12px;
    }

    .summary-item {
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: #fff;
    }

    .summary-item strong {
      display: block;
      margin-bottom: 6px;
    }

    .summary-item p {
      margin: 0;
      color: var(--muted);
      line-height: 1.65;
    }

    .grid-2 {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 14px;
    }

    .mini-card {
      border-radius: 18px;
      border: 1px solid var(--line);
      background: #fff;
      padding: 16px;
    }

    .mini-card .mini-label {
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 10px;
    }

    .mini-card .mini-value {
      font-size: 20px;
      font-weight: 800;
      letter-spacing: -0.03em;
    }

    .mini-card .mini-sub {
      margin-top: 8px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.55;
    }

    .timeline {
      display: grid;
      gap: 10px;
      margin-top: 8px;
    }

    .timeline-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 12px 0;
      border-bottom: 1px solid var(--line);
    }

    .timeline-row:last-child { border-bottom: 0; }
    .timeline-row span:first-child {
      font-weight: 700;
    }
    .timeline-row span:last-child {
      color: var(--muted);
      text-align: right;
    }

    .result-area {
      display: grid;
      gap: 14px;
    }

    .result-box {
      border-radius: 18px;
      border: 1px solid rgba(23, 136, 76, 0.2);
      background: linear-gradient(180deg, rgba(23, 136, 76, 0.08), rgba(255, 255, 255, 0.95));
      padding: 16px;
    }

    .result-box h3 {
      margin: 0 0 6px;
      font-size: 16px;
    }

    .result-box p {
      margin: 0;
      color: var(--muted);
      line-height: 1.7;
    }

    .tag-row {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .tag {
      padding: 8px 10px;
      border-radius: 999px;
      background: #fff;
      border: 1px solid var(--line);
      font-size: 12px;
      font-weight: 700;
      color: var(--text);
    }

    .bottom-nav {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 8px;
      margin-top: 18px;
      padding: 8px;
      border-radius: 22px;
      background: rgba(255, 255, 255, 0.82);
      border: 1px solid var(--line);
      box-shadow: var(--shadow);
    }

    .nav-item {
      padding: 12px 10px;
      border-radius: 16px;
      text-align: center;
      font-size: 13px;
      color: var(--muted);
      font-weight: 700;
      background: transparent;
    }

    .nav-item.active {
      background: rgba(23, 136, 76, 0.12);
      color: var(--green-strong);
    }

    @media (max-width: 980px) {
      .hero,
      .split {
        grid-template-columns: 1fr;
      }
    }

    @media (max-width: 720px) {
      .shell { padding: 14px; }
      .brand, .panel, .card { border-radius: 18px; }
      .metric-grid,
      .grid-2 {
        grid-template-columns: 1fr;
      }
      .bottom-nav {
        position: sticky;
        bottom: 10px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <article class="brand">
        <div class="eyebrow">AI My Health Manager</div>
        <h1>대화, 음성, 사진을 카드형 건강 기록으로 바꾸는 화면</h1>
        <p class="lead">
          사용자가 텍스트를 직접 정리하지 않아도, 말하기·사진 선택·붙여넣기 입력을 받아
          오늘의 혈압, 복약, 식단, 병원 일정, 진료 요약을 카드로 보여주는 반응형 화면입니다.
        </p>
        <div class="hero-actions">
          <a class="button primary" href="#composer">AI 입력 시작</a>
          <a class="button secondary" href="#results">분석 결과 보기</a>
        </div>
        <div class="metric-grid">
          <div class="metric">
            <div class="label">오늘 기록</div>
            <div class="value">4</div>
            <div class="sub">혈압 · 복약 · 식단 · 일정</div>
          </div>
          <div class="metric">
            <div class="label">응급 신호</div>
            <div class="value">0</div>
            <div class="sub">먼저 확인 후 안전하게 정리</div>
          </div>
          <div class="metric">
            <div class="label">다음 알림</div>
            <div class="value">18:30</div>
            <div class="sub">복약 알림 초안</div>
          </div>
          <div class="metric">
            <div class="label">다음 일정</div>
            <div class="value">08-07</div>
            <div class="sub">재진일 추천 초안</div>
          </div>
        </div>
      </article>

      <aside class="panel" id="composer">
        <h2>AI 입력</h2>
        <div class="input-card">
          <div class="composer">
            <textarea class="textarea" placeholder="무엇을 도와드릴까요? 예: 오늘 혈압이 132/86이야. 식사 사진도 같이 보낼게."></textarea>
            <div class="toolbar">
              <button class="chip active" type="button">파일 선택</button>
              <button class="chip" type="button">바로 찍기</button>
              <button class="chip" type="button">붙여넣기</button>
              <button class="chip" type="button">음성 입력</button>
            </div>
            <div class="hero-actions">
              <button class="button primary" type="button">전송하기</button>
              <button class="button secondary" type="button">초안 저장</button>
            </div>
          </div>
          <div class="tag-row">
            <span class="tag">사진 업로드</span>
            <span class="tag">카메라 촬영</span>
            <span class="tag">클립보드 붙여넣기</span>
            <span class="tag">음성 입력</span>
          </div>
        </div>
      </aside>
    </section>

    <section class="split" id="results">
      <div class="cards">
        <article class="card">
          <div class="card-header">
            <div class="card-title">오늘 요약</div>
            <div class="card-badge">안전 확인 완료</div>
          </div>
          <div class="summary-list">
            <div class="summary-item">
              <strong>식단 수분</strong>
              <p>점심 식사 사진에서 밥, 국, 반찬이 보였고 수분 섭취 기록도 함께 정리되었습니다.</p>
            </div>
            <div class="summary-item">
              <strong>혈압 기록</strong>
              <p>혈압계 화면에서 132/86mmHg 값이 읽혀 활력징후 카드로 정리됩니다.</p>
            </div>
            <div class="summary-item">
              <strong>복약 알림</strong>
              <p>식후 30분 기준으로 18:30 복약 알림 초안을 만들고, 사용자 확인 후 저장합니다.</p>
            </div>
          </div>
        </article>

        <article class="card">
          <div class="card-header">
            <div class="card-title">진료 브리핑</div>
            <div class="card-badge">의료진 공유용</div>
          </div>
          <div class="result-area">
            <div class="result-box">
              <h3>요약 문장</h3>
              <p>최근 혈압은 132/86, 저녁 약은 복용 완료, 식사 사진상 특별한 응급 표현은 없었습니다. 다음 진료 일정은 재진일 초안으로 계산 가능합니다.</p>
            </div>
            <div class="grid-2">
              <div class="mini-card">
                <div class="mini-label">식단 사진</div>
                <div class="mini-value">균형 잡힌 한 끼</div>
                <div class="mini-sub">밥, 국, 단백질 반찬, 채소를 카드로 정리</div>
              </div>
              <div class="mini-card">
                <div class="mini-label">사진 입력 경로</div>
                <div class="mini-value">파일 · 카메라 · 붙여넣기</div>
                <div class="mini-sub">같은 분석 흐름으로 받아 카드형 초안 생성</div>
              </div>
              <div class="mini-card">
                <div class="mini-label">카카오 캘린더 알림</div>
                <div class="mini-value">병원 · 복약 일정</div>
                <div class="mini-sub">확인된 일정은 캘린더 이벤트 초안으로 넘겨 외부 알림으로 연결</div>
              </div>
            </div>
          </div>
        </article>
      </div>

      <div class="cards">
        <article class="card">
          <div class="card-header">
            <div class="card-title">건강비서 패널</div>
            <div class="card-badge">모바일 대응</div>
          </div>
          <div class="timeline">
            <div class="timeline-row">
              <span>오전 혈압</span>
              <span>132 / 86</span>
            </div>
            <div class="timeline-row">
              <span>아침 약</span>
              <span>복용 완료</span>
            </div>
            <div class="timeline-row">
              <span>식단 사진</span>
              <span>카드로 정리됨</span>
            </div>
            <div class="timeline-row">
              <span>다음 일정</span>
              <span>재진 초안 계산</span>
            </div>
          </div>
        </article>

        <article class="card">
          <div class="card-header">
            <div class="card-title">도구 흐름</div>
            <div class="card-badge">MCP 연동</div>
          </div>
          <div class="summary-list">
            <div class="summary-item">
              <strong>1. 입력 받기</strong>
              <p>텍스트, 음성, 파일, 카메라, 붙여넣기 중 하나로 입력을 받습니다.</p>
            </div>
            <div class="summary-item">
              <strong>2. 초안 만들기</strong>
              <p>혈압, 식단, 복약, 일정, 증상, 문서 정보를 카드 데이터로 나눕니다.</p>
            </div>
            <div class="summary-item">
              <strong>3. 확인 후 저장</strong>
              <p>사용자 확인이 끝나기 전에는 확정 저장이나 일정 등록을 하지 않습니다.</p>
            </div>
          </div>
        </article>
      </div>
    </section>

    <nav class="bottom-nav" aria-label="하단 메뉴">
      <div class="nav-item active">홈</div>
      <div class="nav-item">건강비서</div>
      <div class="nav-item">기록</div>
      <div class="nav-item">설정</div>
    </nav>
  </main>
</body>
</html>
"""
