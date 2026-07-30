# S01E06: 멀티 에이전트 병렬 구동: DB 스키마 & API 동시 개발

> **Phase 3: 실무 코드베이스 고도화 & 멀티 에이전트**  
> **Key Objective**: 복수의 서브에이전트(Subagents)를 호출하여 DB 스키마 마이그레이션과 REST API 컨트롤러 작성을 병렬로 동시 지휘하는 동시성 개발을 마스터한다.

---

## 📖 1. 멀티 에이전트 지휘 (Multi-Agent Orchestration)

단일 에이전트에게 2개 이상의 대형 작업을 시키면 병목이 발생합니다. Antigravity의 `invoke_subagent` 도구를 사용하여 서브에이전트 A에게는 DB 작업, 서브에이전트 B에게는 API 컨트롤러 작성을 동시 위임합니다.

```text
               ┌──► Subagent A (DB Schema Migration Worker)
Main Agent ────┤
 (Director)    └──► Subagent B (API Controller & DTO Worker)
```

---

## 🔤 2. Core English Definition (본질 개념 정리)

> **Core English Definition**: *Subagent Parallelism (서브에이전트 병렬 처리)*
> - **Simple Definition**: Spawning multiple isolated AI workers to perform different subtasks concurrently.
> - **Practical Meaning**: 디렉터가 당구장에서 테니스 스핀을 계산하듯, 독립된 컨텍스트를 가진 서브 에이전트 여럿에게 작업을 분판하고 Inbox 알림으로 비동기 검토하는 기술.

---

## 🛠️ 3. 실습 과제: 서브에이전트 병렬 지휘

```bash
# 프롬프트 예시
"서브에이전트 A를 생성해서 DB 마이그레이션 파일을 만들고, 서브에이전트 B를 생성해서 결제 API 컨트롤러를 동시에 병렬로 작성하게 해줘."
```

---

## 🔗 다음 에피소드 안내
- **S01E07 (정규)**: [자율 디버깅과 자동화 테스트: 에러 발생 시 자율 수정 루프](file:///d:/0002/hq/aigravity/S01E07_autonomous_debugging_testing.md)
