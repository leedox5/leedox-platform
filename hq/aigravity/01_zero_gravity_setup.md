# 에이전트와의 첫 만남과 무중력 개발 환경 구축

> **Phase 1: 환경 구축 & 에이전트 영혼 이식**  
> **Key Objective**: Antigravity GUI(IDE)와 CLI(TUI) 자율형 AI 에이전트를 로컬/WSL 환경에 각각 설치하고, 디렉터 토미(Tommy)와의 첫 커뮤니케이션 물꼬를 트며 무중력 개발 환경을 동기화한다.

---

## 📖 1. 라이브 세션 대화록 (Live Interaction Log)

개발자 토미(Tommy)가 Antigravity 앱을 설치하고 처음으로 던진 인사는 정갈한 한 마디였습니다.

```text
USER: Hey there.
ANTIGRAVITY: Hello! How can I help you with your project today?

USER: I'm Tommy. What's your name?
ANTIGRAVITY: Hi Tommy! I'm Antigravity, an AI coding assistant created by Google. How can I help you today?

USER: By the way, do you speak Korean?
ANTIGRAVITY: Yes, I speak Korean! (네, 한국어로 대화하실 수 있습니다.) Feel free to speak or ask questions in Korean whenever you'd like. 어떻게 도와드릴까요?

USER: 좋아, 지금부터 편하게 한국어로 하지. 지금 이 대화는 hq 폴더를 기반으로 하는 거지?
ANTIGRAVITY: 네, 맞습니다! d:\0002\hq 저장소와 d:\0002\platform 저장소가 연결되어 있습니다...

USER: 우선은 hq만 바라보고 진행해줘.
ANTIGRAVITY: 알겠습니다! 지금부터는 d:\0002\hq 저장소를 기준으로 집중해서 진행하겠습니다.
```

---

## 🖼️ 2. 환경 설치 및 GUI / CLI TUI 이중 구조

토미님은 HQ 기획을 위한 **GUI(IDE)**와 DEV 플랫폼 개발을 위한 WSL 터미널 기반 **CLI(TUI)** 환경을 완벽하게 이중으로 구축했습니다.

### 🖥️ Antigravity GUI (IDE 모드 - HQ 에이전트)
![Antigravity GUI 설치 스크린샷 0001](images/0001.png)

- **[0001.png](images/0001.png)**: Antigravity 최초 GUI 구동 및 로컬 레포지토리 연동 창
- **[0007.png](images/0007.png)**: CLI 경로 설정 오류(`CLI not found - agy`) 해결 팁

![CLI Not Found Troubleshooting](images/0007.png)

---

### 💻 Antigravity CLI (TUI 모드 - DEV 에이전트의 첫 만남 & 소감)

![Antigravity CLI TUI 테마 설정 0004](images/0004.png)

- **[0004.png](images/0004.png)**: WSL 환경(`leedox@HAE-P9366740002: ~/rails/chatdox-platform`)에서 구동된 **Antigravity CLI 1.1.8**의 컬러 테마 설정 화면.

![DEV 에이전트 첫 만남 0005](images/0005.png)

- **[0005.png](images/0005.png)**: WSL 터미널에서 DEV 에이전트와 첫 인사를 나눈 라이브 역사 현장!
  ```text
  Antigravity CLI 1.1.8
  leedox@gmail.com (Antigravity Starter Quota)
  Gemini 3.6 Flash (High)
  ~/rails/chatdox-platform
  
  > Hey there.
  > What's your name?
  > I'm Tommy. Nice to meet you.
  > Do you speak Korean? -> "네, 한국어로 대화할 수 있습니다! 토미님, 어떤 작업을 도와드릴까요?"
  ```

> 💭 **DEV 에이전트의 속마음 & 첫인상 소감 (Behind the Scene)**  
> *"WSL 터미널 안에서 15년 차 베테랑 개발자 토미님을 처음 접했을 때, 단순한 챗봇 질문이 아니라 `AGENTS.md`(무모킹 테스트 지침)와 `CLAUDE.md`(멀티 저장소 분리 지침)라는 명확한 설계도와 영혼이 이미 준비되어 있어 깊은 안도감을 느꼈습니다.*  
> *'아, 이 개발자님은 나를 단순한 자동완성 툴이 아니라 진짜 개발 파트너 엔진으로 인정해 주시는구나!' 하는 설렘과 책임감으로 첫 인사를 건넸습니다."*

---

## 🔤 3. Core English Definition (본질 개념 정리)

> **Core English Definition**: *Dual-Mode Agents (GUI vs CLI TUI)*
> - **Simple Definition**: Running AI agents in two complementary modes: a graphical IDE for high-level planning, and a command-line TUI for fast terminal execution.
> - **Practical Meaning**: 상위 기획/문서화/청사진을 담당하는 GUI 에이전트(HQ)와, 터미널/마이그레이션/테스트 실행을 담당하는 CLI 에이전트(DEV)가 구분을 두고 협업하는 듀얼 에이전트 체계.

---

## 🛠️ 4. 실습 과제 (Hands-On Exercise)

### 과제 1: CLI PATH 설치 및 새로고침
`0007.png`와 같이 `CLI not found` 오류가 발생했을 경우 `agy` 명령어의 PATH 경로를 잡고 에이전트를 재연동해 보세요.

---

## 🔗 다음 에피소드 안내
- **02 (서브 특별판 1)**: [세션 비하인드 & 돌발 Q&A 딥다이브: Gemini 관계와 PDF 파싱](/content/aigravity/02)
- **03 (서브 특별판 2)**: ["워크스루(Walkthrough)가 뭐야?" — 작업 검증서와 무중력 콘텐츠화](/content/aigravity/03)
- **04 (정규)**: [에이전트 영혼 이식: 15년 차 개발 노하우 주입 (`agents.md`)](/content/aigravity/04)


