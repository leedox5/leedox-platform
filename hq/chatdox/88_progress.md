# 진도표 — Chatdox 커리큘럼

`app/models/curriculum.rb`(DEV)의 20장 목차와 동기화 대상. 챕터가 추가/조정되면 이 표도 같이 갱신할 것. claudox/의 `88_progress.md`와 같은 규칙(번호를 1~20 챕터 범위 밖에 둬서 스토리 챕터와 구분하는 부록 파일)을 따른다.

## Phase 1. 기초 & 환경 (1~5장)

| # | 챕터 | 파일 | 상태 |
|---|------|------|:---:|
| 1 | 채독스 전체 구조 이해 | [01_overview.md](01_overview.md) | ✅ |
| 2 | Ruby on Rails 기초 | [02_rails_basics.md](02_rails_basics.md) | ✅ |
| 3 | 개발 환경 세팅 | [03_dev_setup.md](03_dev_setup.md) | ✅ |
| 4 | 랜딩페이지 구축 | [04_landing_page.md](04_landing_page.md) | ✅ |
| 5 | 프로젝트 구조 설계 | [05_project_structure.md](05_project_structure.md) | ✅ |

## Phase 2. 핵심 기능 구현 (6~16장)

| # | 챕터 | 파일 | 상태 |
|---|------|------|:---:|
| 6 | Database & Migrations | [06_database.md](06_database.md) | ✅ |
| 7 | Authentication (Devise) | [07_authentication.md](07_authentication.md) | ✅ |
| 8 | Authorization & 권한 관리 | [08_authorization.md](08_authorization.md) | ✅ |
| 9 | Payment (PortOne) | [09_payment.md](09_payment.md) | ✅ |
| 10 | 사용자 대시보드 | [10_dashboard.md](10_dashboard.md) | ✅ |
| 11 | 관리자 대시보드 | [11_admin.md](11_admin.md) | ✅ |
| 12 | Email & 알림 | [12_email.md](12_email.md) | ✅ |
| 13 | 파일 업로드 (Active Storage) | [13_file_upload.md](13_file_upload.md) | ✅ |
| 14 | API 설계 & JSON | [14_api.md](14_api.md) | 🟡 일반 내용 |
| 15 | 테스트 | [15_testing.md](15_testing.md) | ✅ |
| 16 | 성능 최적화 & 캐싱 | [16_performance.md](16_performance.md) | ✅ |

## Phase 3. 프로덕션 운영 (17~20장)

| # | 챕터 | 파일 | 상태 |
|---|------|------|:---:|
| 17 | 보안 & OWASP | [17_security.md](17_security.md) | ✅ |
| 18 | 배포 (Railway / Render) | [18_deployment.md](18_deployment.md) | ✅ |
| 19 | 모니터링 & 에러 추적 | [19_monitoring.md](19_monitoring.md) | 🟡 일반 내용 |
| 20 | 런칭 & 운영 | [20_launch.md](20_launch.md) | ✅ |

**전체 20장 작성 완료. 완료(✅): 18개(실전 사례 기반) · 🟡 일반 내용: 2개(14, 19 — 오픈 시점 100% 채움을 위해 먼저 일반적인 Rails 원칙으로 작성, 실제 API/모니터링 작업을 하게 되면 그 경험으로 보강 예정. 각 챕터 하단에 "일반 내용" 안내 문구 포함)**

**2026-08-06**: 16장이 🟡→✅로 전환됨 — 로컬 dev 서버가 `public/assets`의 예전 `assets:precompile` 산출물에 가려 최신 Tailwind 빌드를 못 내보내던 실제 사건(backlog 021)을 캐싱 절의 "실전 사례"로 반영. 인덱스·백그라운드 작업·페이지네이션 절은 아직 일반 원칙 그대로.

## 15장 제목/내용 관련 참고

기존 커리큘럼 제목이 "테스트 (RSpec)"로 돼 있으나, 이 프로젝트는 처음부터 지금까지 Rails 기본 Minitest(`bin/rails test`)를 쓰고 있다. 15장을 쓸 때는 RSpec이 아니라 Minitest 기준으로 작성하고, DEV의 `Curriculum` 모델 title도 같이 갱신 요청할 것.

*이 파일은 챕터가 추가되거나 상태가 바뀔 때마다 함께 갱신해야 최신 상태를 유지한다.*
