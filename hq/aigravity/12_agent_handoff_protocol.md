# AI 에이전트 간 계약 기반 Handoff & 멀티 저장소 프로토콜

> **Phase 3: 실무 코드베이스 고도화 & 에이전트 Handoff 프로토콜**  
> **Key Objective**: HQ(콘텐츠 기획)와 DEV(플랫폼 개발) 두 독립 저장소 간에 `inbox/outbox` 파일 기반 프로토콜과 `result.md` 스펙 계약을 적용하여, AI 에이전트 간 비동기 분업 시스템을 구축한다.

---

## 📖 1. 에이전트 간 분업의 필요성

단일 AI 에이전트에게 전체 아키텍처와 모든 소스코드를 처리하게 하면 컨텍스트 윈도우 낭비와 오염이 발생합니다.
토미 디렉터는 **HQ(기획/교육)**와 **DEV(플랫폼)** 저장소를 철저히 분리하고, 에이전트 간 간접 파일 통신 방식(Handoff)을 도입했습니다.

```text
[HQ Agent] ──► `.local/handoff/inbox/<task>/request.md`
                       │
                       ▼
[DEV Agent] ──► 구현 & test ──► `.local/handoff/inbox/<task>/result.md`
```

---

## 🛠️ 2. Handoff 계약 규칙 (`request.md` ↔ `result.md`)

1. **요청서 (`request.md`)**: 요청 ID, PR 필요 여부(`PR Required`), 구체적 스펙, 검증 체크리스트 전달.
2. **결과서 (`result.md`)**: 상태(Completed), 변경된 파일 목록, `bin/rails test` 결과, PR URL 공유.

---

## 🔤 3. 핵심 용어 정리 (Core Terms)

> **Core English Definition**: *File-Based Agent Handoff Protocol*  
> - **Simple Definition**: A structured file-contract mechanism (`request.md` and `result.md`) allowing autonomous AI agents in different repositories to collaborate asynchronously without shared memory or hallucinations.  
> - **Practical Meaning**: 상호 메모리를 직접 공유하지 않는 독립된 AI 에이전트들이 파일 기반의 명확한 입출력 계약(Contract)을 통해 100% 안전하게 작업을 주고받는 협업 규약.




