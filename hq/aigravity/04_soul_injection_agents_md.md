# 에이전트 영혼 이식: 15년 차 개발 노하우 주입 (`agents.md`)

> **Phase 1: 환경 구축 & 에이전트 영혼 이식**  
> **Key Objective**: 15년 차 디렉터 토미(Tommy)의 개발 철학과 세션 수록 방식을 에이전트 상시 지침서인 `agents.md`에 주입(영혼 이식)하고 행동 규칙을 수립한다.

---

## 📖 1. 라이브 세션 대화록 (Live Interaction Log)

에이전트에게 1회성 명령을 내리는 프롬프트의 한계를 깨닫고, 프로젝트 상시 지침(`agents.md`)을 작성하도록 지시한 핵심 대화입니다.

```text
USER: 참고로... 오늘 설치를 하고(img폴더의 스샷 만들어놈), 너의 처음 인사를 하는 모든 대화, 활동들이 그대로 컨텐츠로 녹아 들어가면되.... 가능하면 사소한 질문도 놓지지 않도록 신경좀 써주고 agents.md 등에다 기록해줘

ANTIGRAVITY: 너무나 중요한 지침입니다! 토미님의 요청을 바탕으로 hq/agents.md 파일에 에이전트 영혼 이식 지침서를 작성하겠습니다.
```

### 💡 대화 맥락의 핵심 (Context Takeaway)
- **일회성 프롬프트 ❌ vs 상시 지침 ⭕**: 대화 세션이 바뀌어도 에이전트가 디렉터의 스타일을 잊지 않도록 `agents.md` 파일로 영속화(Persist)함.
- **사소한 질문 수록 규칙**: "사소한 질문도 놓치지 마라"는 지침이 에이전트 행동 원칙으로 주입됨.

---

## 📄 2. 작성된 실제 `agents.md` 구조 분석

실제로 생성되어 본 프로젝트를 구동하고 있는 [hq/agents.md](file:///d:/0002/hq/agents.md) 파일의 핵심 뼈대입니다.

```markdown
# Agent Directives: Tommy's Antigravity Pair Programming & Content Pipeline

## 🛠️ Key Directives & Content Ingestion Rules
1. Live Experience Ingestion (생생한 실전 대화 및 질문 기록)
2. Special Edition Rule (특별판 E01X01, E01X02 편성 규칙)
3. Core English Definition (쉬운 영어 본질 정의)
4. Database & Schema-First Approach (DB 무결성 검증)
5. Strict Definition of Done (DoD)
```

---

## 🔤 3. Core English Definition (본질 개념 정리)

> **Core English Definition**: *Soul Injection (영혼 이식 / 지침 영속화)*
> - **Simple Definition**: Embedding a developer's unique coding philosophy, preferences, and rules into the AI agent's permanent instruction file.
> - **Practical Meaning**: 매번 "DB 스키마 먼저 봐줘", "쉬운 영어로 설명해 줘"라고 반복하지 않고, 프로젝트 루트의 `agents.md`나 `.agents/agents.md`에 기재하여 에이전트가 매 턴마다 자동으로 준수하게 만드는 기술.

> **Core English Definition**: *Instruction Hierarchy (지침 우선순위 계층)*
> - **Simple Definition**: The order of authority when multiple instructions conflict.
> - **Practical Meaning**: `System Prompt (기본 엔진)` < `Global User Rules (글로벌 규칙)` < `Project agents.md (프로젝트 규칙)` < `Session Task Prompt (현재 프롬프트)`. 하위 계층일수록 특정 작업에 더 구체적인 권한을 가짐.

---

## 🛠️ 4. 실습 과제: 나만의 `agents.md` 작성해 보기

### 실습 1: 내 프로젝트 스타일 정의하기
여러분의 프로젝트 루트 디렉터리에 `agents.md` 파일을 생성하고 아래 3가지 요소를 직접 작성해 보세요.

1. **에이전트 역할(Role)**: (예: "너는 나의 15년 차 백엔드 수석 주임이야.")
2. **코딩 스타일(Code Style)**: (예: "주석은 Core English Definition 스타일로 달아줘.", "Tailwind 동적 클래스는 보간하지 마.")
3. **완료 조건(DoD)**: (예: "작업 완료 보고 전 반드시 Unit Test를 돌려라.")

### 실습 2: 에이전트의 지침 준수 여부 테스트하기
작성한 `agents.md`를 에이전트에게 인식시키고, 지침에 명시된 규칙을 알아서 지키며 코드를 짜는지 확인해 보세요.

```bash
# 프롬프트 예시
"@agents.md 지침을 읽고, 우리가 약속한 코딩 스타일대로 새로운 로그인 데이터 모델을 설계해 줘."
```

---

## 🔗 다음 에피소드 안내
- **E03 (정규)**: [컨텍스트 주입의 기술: `@CONTEXT.md`와 세션 연동](/content/aigravity/)


