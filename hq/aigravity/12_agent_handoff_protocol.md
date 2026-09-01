# AI 에이전트 간 계약 기반 Handoff 2.0 & 멀티 저장소 프로토콜

> **Phase 3: 실무 코드베이스 고도화 & 에이전트 Handoff 프로토콜**  
> **Key Objective**: HQ(기획/교육)와 DEV(플랫폼) 두 독립 저장소 간에 Git 관리 기반의 `handoff/` 0-Copy 프로토콜과 `0000.md ↔ result.md` 스펙 계약을 적용하여, AI 에이전트 간 비동기 분업과 마스터 배달원 토미(Tommy)의 릴레이 시스템을 완벽히 구축한다.

---

## 📖 1. 에이전트 간 분업과 Handoff 2.0 리뉴얼 서사

단일 AI 에이전트에게 전체 아키텍처와 모든 소스코드를 무분별하게 처리하게 하면 컨텍스트 윈도우 낭비와 환각(Hallucination)이 발생합니다.
디렉터 토미(Tommy)는 **HQ(기획/교육)**와 **DEV(플랫폼)** 저장소를 철저히 분리하고, **Handoff 2.0 프로토콜**을 발명하여 적용했습니다.

### 🔄 Handoff 1.0에서 Handoff 2.0으로의 진화
- **Handoff 1.0 (레거시 `.local/handoff/`)**: Git 비관리 영역에서 파일 복사 방식으로 전달하던 초기 방식.
- **Handoff 2.0 (공식 표준 `handoff/`)**: 
  - HQ 저장소 내에 `handoff/` 폴더를 두고 **Git 관리에 공식 편입**.
  - DEV 저장소는 WSL 심볼릭 링크(`ln -s /mnt/d/0002/hq/handoff /mnt/d/0002/platform/handoff`)로 바라보아 **복사 지연 제로(0-Copy Zero-Latency)** 실시간 연동 달성!

```text
[HQ Agent & 토미] ──► handoff/<number_slug>/0000.md (요청서 작성)
                           │
                           ▼ (WSL Symlink 0-Copy 연동)
[DEV Agent] ──► 구현 & test & PR ──► handoff/<number_slug>/result.md (결과서 제출)
```

---

## 🛠️ 2. Handoff 2.0 규격과 실전 마일스톤 명명 표준

### 📁 1) 패키지 폴더 명명 표준 (Folder Naming Standard)
- **구상/발행 초기**: `<number>/` (예: `0001/`, `0002/`)
- **요청 구체화 완료 시**: **`<number>_<descriptive_slug>/`** 확정
  - `0005_chatdox_landing_curriculum_links/` (Chatdox 랜딩 20개 챕터 링크)
  - `0009_dynamic_admin_pricing_management/` (운영자 동적 요금제 어드민)
  - `0012_admin_commerce_products_ui_polish/` (어드민 모바일 반응형 UI 정제)
  - `0013_product_domain_dynamic_theme_and_order_metadata/` (동적 카탈로그 도메인)
  - `0015_dynamic_terminal_mockup_and_gnb_footer_links/` (터미널 목업 & GNB 항해선)

### 📄 2) 0-Copy 파일 계약 규격 (`0000.md` ↔ `result.md`)
1. **요청서 (`0000.md`)**: 요청 ID, `PR Required` 여부(Yes/No), 콤팩트 스펙, 스크린샷 자산 참조, 검증 체크리스트 및 DEV 에이전트 전달 메시지 수록.
2. **결과서 (`result.md`)**: 구현 결과, 커밋/PR 링크, 통합 테스트 및 RuboCop 지표, **토미 감독님과 HQ 에이전트에 보내는 정다운 동료 소감 편지** 수록.

### 🖼️ 3) 스크린샷 자산 경량화 관리 수칙 (Git Asset Hygiene)
- 스캔 및 대용량 스크린샷 자산은 `.local/handoff/000X/` (.gitignore 영역)에 격리 배치.
- `handoff/` 패키지 내부에는 마크다운 계약서(`0000.md` & `result.md`)만 유지하여 **Git 저장소 용량 낭비를 100% 차단**.

### 🌿 4) 다단계 피처 브랜치 누적 & Revert 가용 체제 (`PR Required: Yes`)
- 대형 아키텍처 개편(Phase 1~3 등) 시, 메인(`main`) 브랜치를 오염시키지 않고 **단일 피처 브랜치(Draft PR) 상에 0013, 0014, 0015를 차곡차곡 누적 푸시**.
- 디렉터 토미의 시각 검증 완료 후 **1-Click 최종 머지** 또는 **100% 클린 Revert 가용성**을 완벽히 보장.

---

## 🔤 3. 핵심 용어 정리 (Core Terms)

> **💡 본질 개념 한눈에 파악하기**
> - **File-Based Agent Handoff Protocol (파일 기반 에이전트 핸드오프 프로토콜)**: 상호 메모리를 직접 공유하지 않는 독립된 AI 에이전트들이 파일 기반의 명확한 입출력 계약(`0000.md` ↔ `result.md`)을 통해 100% 안전하게 작업을 주고받는 협업 규약.
> - **Symlink Zero-Copy Sync (심볼릭링크 제로카피 동기화)**: HQ의 `handoff/`와 DEV 플랫폼 간 심볼릭링크를 구축하여 복사/복제 지연 시간 0(Zero Latency)으로 실시간 요청/결과를 공유하는 인프라 연동 기법.
> - **PR Required Guard (PR 필요성 가드)**: 1시간 미만 소규모 UI 수정(`PR Required: No`)과 대규모 구조 개편(`PR Required: Yes`)을 계약서상에 명시하여 개발 속도와 품질을 유연하게 제어하는 기법.
> - **Master Courier Role (마스터 배달원 역할)**: 디렉터 토미(Tommy)가 단순한 유저를 넘어 에이전트 간의 스펙 계약과 마음 담긴 편지를 주고받게 해주는 중앙 총괄 리더 서사.
