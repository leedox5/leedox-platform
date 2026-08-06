# 컨텍스트 주입의 기술: `@CONTEXT.md`와 세션 연동

> **Phase 2: 컨텍스트 주입 & 토큰 경제학**  
> **Key Objective**: 휘발되기 쉬운 대화 세션의 맥락을 프로젝트 청사진인 `CONTEXT.md` 파일로 승화하고, 새로운 세션에서도 `@CONTEXT.md` 주입을 통해 단 1초 만에 프로젝트 맥락을 100% 동기화하는 기법을 마스터한다.

---

## 📖 1. 라이브 세션 대화록 (Live Interaction Log)

대화 창(Web/App) 안에서 나누는 세션은 창을 닫으면 소멸합니다. 토미님과 Antigravity는 이 맥락을 로컬 파일로 저장하여 연속성을 확보했습니다.

```text
USER: 이 자료는 어디까지나 Draft이고... 우선 이 대화를 그대로 가져오기 보다는 너의 아이디어를 보태서 CONTEXT.md 를 작성해줘

ANTIGRAVITY: hq/CONTEXT.md 파일과 hq/docs/implementation_plan.md 파일 작성을 완료했습니다!

USER: 이 구현계획서는 로컬에 저장은 안되어 있네? docs 폴더를 만들고 여기서 저장해 줘

ANTIGRAVITY: hq/docs/implementation_plan.md 경로에 로컬 파일로 저장 완료했습니다!
```

### 💡 대화 맥락의 핵심 (Context Takeaway)
- **세션의 청사진화**: 대화 세션이 길어지거나 종료되어도 `CONTEXT.md`와 `docs/implementation_plan.md`가 남아있다면 에이전트는 이전까지 합의된 모든 아키텍처와 시나리오를 즉시 복원함.

---

## 📄 2. `CONTEXT.md`를 활용한 세션 연동 메커니즘

```
 [휘발성 대화 세션] ──► [CONTEXT.md 생성] ──► [새로운 대화 세션 시작]
                                                      │
                                          "@CONTEXT.md 읽고 진행해"
                                                      │
                                                      ▼
                                         [100% 맥락 복원 및 즉시 작업]
```

### `@CONTEXT.md` 주입 시 3가지 이점
1. **토큰 절약**: 매번 긴 이전 대화 내용을 복사-붙여넣기 할 필요 없이 파일 1개 참조로 끝남.
2. **환각(Hallucination) 방지**: 정돈된 Markdown 청사진을 참조하므로 모호한 지침으로 인한 헛소리 방지.
3. **팀원 공유 및 버전 관리**: Git 레포지토리에 저장되어 팀원 및 다른 에이전트와 동일 맥락 공유.

---

## 🔤 3. Core English Definition (본질 개념 정리)

> **Core English Definition**: *Context Window (맥락 윈도우 / 대화 기억 용량)*
> - **Simple Definition**: The total amount of text and code an AI agent can read and process at a single time.
> - **Practical Meaning**: 에이전트가 한 번에 기억할 수 있는 메모리 크기. 세션이 길어질수록 예전 대화는 잊혀지므로, 핵심 요약을 `CONTEXT.md`로 외부 파일화하는 것이 필수적임.

> **Core English Definition**: *Context Injection (@-Mention Prompting)*
> - **Simple Definition**: Feeding a specific file's content directly into the AI's current prompt context using symbol references like `@filename`.
> - **Practical Meaning**: 프롬프트 창에 `@CONTEXT.md`를 언급하여 에이전트가 해당 파일의 최신 내용을 즉시 읽고 판단 근거로 삼게 만드는 맥락 주입 기법.

---

## 🛠️ 4. 실습 과제: 새로운 세션에서 맥락 1초 복원하기

### 실습 1: `CONTEXT.md` 청사진 작성하기
프로젝트 루트에 `CONTEXT.md`를 만들고 (1) 프로젝트 목표, (2) 현재 진행 중인 마일스톤, (3) 주요 아키텍처를 요약해 기재하세요.

### 실습 2: `@CONTEXT.md` 주입 프롬프트 실행하기
새로운 채팅 창을 열고 아래와 같이 프롬프트를 입력하여 에이전트가 완벽히 이전 맥락을 복원하는지 확인하세요.

```bash
# 새로운 세션에서의 첫 프롬프트 예시
"안녕! @CONTEXT.md 파일을 가장 먼저 읽고 현재 우리가 진행해야 할 다음 에피소드 작업 목록을 제시해 줘."
```

---

## 🔗 다음 에피소드 안내
- **E04 (정규)**: [토큰 경제학과 비용 최적화: 무료 플랜부터 Pro까지](/content/aigravity/)



