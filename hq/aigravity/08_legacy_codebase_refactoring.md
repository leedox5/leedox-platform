# 실무 레거시 코드 파악과 안전한 DB/API 리팩토링

> **Phase 3: 실무 코드베이스 고도화 & 멀티 에이전트**  
> **Key Objective**: 수만 줄 규모의 실무 레거시 시스템을 에이전트가 안전하게 파악하도록 하고, DB 스키마 무결성을 보존하면서 백엔드 API를 리팩토링하는 기법을 배운다.

---

## 📖 1. 레거시 시스템 탐색 전략 (Scanning Legacy Code)

에이전트에게 "우리 프로젝트 분석해 줘"라고 하면 전체 코드를 읽다가 토큰 한도를 초과합니다. 15년 차 디렉터 토미의 **DB-First 탐색 방식**을 적용합니다.

1. **DB 스키마 & 엔티티 탐색**: `db/schema.rb`, `models/`, DDL SQL 스크립트 선 확인.
2. **핵심 도메인 서비스 스캔**: 비즈니스 로직이 집중된 `services/`, `controllers/` 탐색.
3. **의존성 체크**: `Gemfile`, `pom.xml`, `build.gradle` 등의 라이브러리 버전 확인.

---

## 🔤 3. 핵심 용어 정리 (Core Terms)

> **Core English Definition**: *Legacy Refactoring (레거시 리팩토링)*
> - **Simple Definition**: Improving existing codebase structure without changing its external behavior.
> - **Practical Meaning**: 기존 시스템의 버그나 비효율성을 개선하되, 기존 DB 스키마나 작동 중인 API 서비스에 장애를 일으키지 않는 안전한 코드 개선 과정.

> **Core English Definition**: *Schema Integrity (스키마 무결성)*
> - **Simple Definition**: Ensuring database constraints, tables, and data relationships remain valid and unbroken.
> - **Practical Meaning**: AI 에이전트가 코드를 고치면서 DB 컬럼명이나 외래키 관계를 멋대로 변경하지 않도록 에이전트에 엄격한 스키마 제약을 거는 기술.

---

## 🛠️ 3. 실습 과제: 안전한 리팩토링 요청하기

### 실습 1: DB 스키마 보존 규칙 프롬프트
```bash
# 프롬프트 예시
"@agents.md 지침을 준수해 줘. DB 스키마 무결성을 손대지 않는 선에서 서비스 레이어의 중복 로직을 안전하게 리팩토링해 줘."
```

---

## 🔗 다음 에피소드 안내
- **09 (정규)**: [멀티 에이전트 병렬 구동: DB 스키마 & API 동시 개발](/content/aigravity/09)




