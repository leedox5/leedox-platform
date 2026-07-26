# 다상품 콘텐츠 플랫폼 일반화 — 1단계 감사

- 관련 계획 문서: HQ `chatdox/multi_product_platform_plan.md`
- 브랜치: `feature/generic-content-platform`
- 범위: `app/`, `config/routes.rb`, `test/` 전수 조사(sitewide grep + 코드 확인). 커머스·결제 레이어(`Product`/`ProductOffer`/`Order`/`License`)는 이미 일반화가 검증돼 있어 제외.
- 목적: 2단계(설계)의 입력이 되는 실제 하드코딩 지점 인벤토리. 이 문서 자체는 아무것도 고치지 않는다.

## 요약

- 총 **34개** 지점 발견(카테고리 1: 12, 카테고리 2: 27개 히트 중 로직 관여 22개, 카테고리 3: 라우트 8개 + 헬퍼 사용처 다수, 카테고리 4: 3, 카테고리 5: 7 — 카테고리 간 중복 있음, 아래 "핵심 지점" 표가 실제 작업 단위 기준).
- **핵심 지점(새 상품 추가 시 반드시 고쳐야 함)**: 13곳. 대부분 "상품마다 완전히 새로 구현"이거나 "상품 코드가 늘어나면 매핑표에 줄 하나씩 추가해야" 하는 유형.
- **가장 중요한 발견**: "상품별 챕터 목록 + 완료 상태 조회"라는 동일한 문제가 이 코드베이스 안에 **최소 4번 독립적으로 재구현**돼 있다(아래 "패턴 A" 참고). 이게 이번 감사에서 가장 큰 단일 리스크다 — 2단계 설계가 통합해야 할 대상이 "2개 모델"이 아니라 "4개의 서로 다른 챕터-조회 구현"이라는 뜻.
- **비급한 지점**: 5곳(주석/문서화성 언급, 죽은 코드, 상품 특화가 의도적으로 맞는 기능).

## 교차 패턴 (카테고리를 가로지르는 발견)

### 패턴 A — "상품별 챕터 목록 + 완료 상태"가 4번 따로 구현됨

같은 문제("이 상품의 챕터가 몇 개고, 각각 제목이 뭐고, 몇 개가 완성/완료됐나")를 푸는 코드가 서로 전혀 모르는 채로 4곳에 있다:

1. `Curriculum`(`app/models/curriculum.rb`) — Chatdox, 하드코딩된 배열 20개
2. `Claudox`(`app/models/claudox.rb`) — Claudox, 파일시스템 스캔(`Dir.glob` + 마크다운 `#` 헤딩 파싱)
3. `ClaudoxProductsController`(`app/controllers/claudox_products_controller.rb:24-40`) — Claudox 마케팅 페이지 전용, **`Claudox` 모델을 아예 안 쓰고** `setup.md`를 정규식으로 파싱해서 챕터 제목을 또 뽑아냄(`chapter_written?`이 `UNWRITTEN_PLACEHOLDER` 텍스트 존재 여부로 "완성" 판정 — 위 1/2번과는 "완성"의 정의 자체가 다름)
4. `Admin::ContentProgressController`(`app/controllers/admin/content_progress_controller.rb:8,20-34`) — Chatdox는 `Curriculum.all` 재사용하지만, Claudox는 `88_progress.md`를 정규식(`CLAUDOX_ROW_PATTERN`)으로 파싱하는 **또 다른 별도 구현**

2단계에서 단일 제네릭 콘텐츠 모델을 설계할 때, 1/2번(모델)뿐 아니라 3/4번(각자 다른 데이터 소스·다른 "완성" 판정 기준)까지 같이 흡수하지 않으면 통합이 실제로는 안 된 것과 마찬가지다.

### 패턴 B — 라우트/헬퍼 네이밍이 상품마다 다른 스킴을 씀

Chatdox는 `/docs`, `/docs/:id`(헬퍼: `doc_path`), Claudox는 `/claudox/read`, `/claudox/read/:id`(헬퍼: `claudox_chapter_path`, `claudox_read_path`) — 경로 구조와 헬퍼 이름 규칙 자체가 상품마다 다르다. 그 결과 "챕터로 가는 링크"가 필요한 모든 곳(대시보드, 챕터 진도 컨트롤러 등)이 `product_code == "claudox" ? claudox_chapter_path(id) : doc_path(id)` 같은 3항 분기를 갖고 있다. 아래 3절에서 이 분기가 나타나는 지점을 전부 나열한다.

### 패턴 C — "챕터 완료 처리" 자체는 이미 잘 일반화돼 있음

`ChapterProgress`/`ChapterProgressesController`는 (2단계 이전 이번 시즌 라운드에서) 이미 `product_code` 컬럼 기반으로 일반화돼 있다 — `find_chapter`가 상품별 챕터 조회 로직(패턴 A의 1/2번)에 위임하는 구조라, **콘텐츠 조회 레이어만 통합되면 이쪽은 거의 그대로 따라온다.** 유일한 하드코딩은 `PRODUCT_CODES = %w[chatdox claudox]`(허용 상품 목록, 카테고리 2-①) 하나뿐.

---

## 1. `Curriculum`/`Claudox` 클래스 직접 참조 지점

| # | 파일:라인 | 무엇을 하는 코드인가 | 왜 새 상품 추가 시 고쳐야 하는가 |
|---|---|---|---|
| 1.1 | `app/models/curriculum.rb` (전체) | Chatdox 20챕터를 하드코딩 배열로 정의 | 새 상품은 이 클래스를 통째로 새로 만들거나(현재 패턴), 제네릭 모델이 대체해야 함 |
| 1.2 | `app/models/claudox.rb` (전체) | Claudox 챕터를 파일시스템 스캔으로 조회, `kind`(정규/부록) 구분까지 포함 | 위와 동일 — Chatdox와 완전히 다른 구현 |
| 1.3 | `app/controllers/docs_controller.rb:4,21,57,83,94` | `DOCS_PATH`, `find`, `last_updated_at`, `all`, `phases` 5회 호출 | Chatdox 전용 컨트롤러 자체가 `Curriculum`에 강결합 |
| 1.4 | `app/controllers/claudox_controller.rb:4,31,43,47` | `CLAUDOX_PATH`, `last_updated_at`, `all`, `phases` 4회 호출 | 위와 동일, Claudox 쪽 |
| 1.5 | `app/controllers/chapter_progresses_controller.rb:29-33` | `product_code`로 `Curriculum.find`/`Claudox.find` 분기 | 신규 상품마다 이 `if/else`에 분기 추가 필요(패턴 C 참고 — 그나마 한 곳뿐) |
| 1.6 | `app/controllers/dashboard_controller.rb:8` (`CHAPTER_SOURCES`) | `{"chatdox" => Curriculum, "claudox" => Claudox}` 매핑표 | 신규 상품마다 이 해시에 줄 추가 필요(카테고리 5와 중복 집계) |
| 1.7 | `app/controllers/admin/content_progress_controller.rb:8,18,20-34,23` | Chatdox는 `Curriculum.all`, Claudox는 `88_progress.md` 정규식 파싱(패턴 A-4) | 신규 상품마다 이 어드민 컨트롤러에 완전히 새로운 파싱 로직 필요 — 지금 구조에서 가장 확장 비용이 큰 지점 중 하나 |
| 1.8 | `app/controllers/refs_controller.rb:53,62` | 어드민 참조문서(결제 가이드 등)를 `Curriculum.find`/`.phases`로 Chatdox 챕터 번호에 매핑 | Chatdox 전용으로 설계됨(참조 문서 자체가 결제 구현 가이드라 Claudox엔 대응 개념 없음) — **핵심 아님**, 구조상 그대로 둬도 되는 의도적 비대칭 |
| 1.9 | `app/views/landing/_curriculum.html.erb:2-3` | 뷰가 `Curriculum.all`/`.phases`를 **직접 호출**(컨트롤러를 거치지 않음) | 신규 상품이 Chatdox 스타일 랜딩 섹션을 가지려면 이 패턴을 그대로 복붙해야 함 |
| 1.10 | `app/views/leedox_home/_proof.html.erb:24` | `Curriculum.all.first(4)`로 홈페이지 미리보기 4개 생성 | 같은 파일의 Claudox 쪽(1.11)과 구현 방식 자체가 다름 |
| 1.11 | `app/views/leedox_home/_proof.html.erb:34` | Claudox 쪽은 모델을 아예 안 쓰고 `[["01", "클로독스와의 첫만남"], ...]` **뷰에 하드코딩된 리터럴 배열** | 실제 콘텐츠가 바뀌어도 이 화면은 자동 갱신 안 됨(가장 눈에 띄는 "가짜 동기화" 사례) — 신규 상품은 이런 배열을 또 손으로 써야 함 |
| 1.12 | `app/models/chapter_progress.rb:20-22` (주석) | `Curriculum`/`Claudox` 비대칭성을 설명하는 주석 | 코드는 아니지만 설계 근거로 남아있어 2단계에서 참고할 만함 |

## 2. `"chatdox"`/`"claudox"` 문자열 리터럴(로직 관여만, 문구·마케팅 텍스트 제외)

| # | 파일:라인 | 무엇을 하는 코드인가 | 왜 고쳐야 하는가 |
|---|---|---|---|
| 2.1 | `app/models/chapter_progress.rb:4` (`PRODUCT_CODES`) | 진도 기록이 허용되는 상품코드 화이트리스트 | 신규 상품 추가 시 이 배열에 안 넣으면 진도 저장 자체가 검증 실패로 거부됨 — **놓치기 쉬운 핵심 지점** |
| 2.2 | `app/policies/doc_policy.rb:13-17` (`product_code` 메서드) | 레코드에 `product_code`가 없으면 기본값 `"chatdox"`로 간주 | 새 조회 경로를 추가할 때 이 기본값 가정이 조용히 틀릴 수 있음 |
| 2.3 | `app/models/user.rb:42` (`can_view_chapter?` 기본 인자) | `product_code: "chatdox"` 기본값 | 호출부가 기본값에 의존하면 신규 상품에서 의도치 않게 Chatdox로 새는 경로가 될 수 있음 |
| 2.4 | `app/policies/dashboard_policy.rb:6-8` (`show_subscription?`) | `user.licensed_for?("chatdox")`만 체크 | **비급함** — 실제로는 앱 어디서도 호출되지 않는 죽은 코드(grep 확인). 2단계에서 되살릴 필요 없음, 삭제 후보로만 기록 |
| 2.5 | `app/controllers/pages_controller.rb:6-17` (`PRODUCT_TAGLINES`, `PRODUCT_DETAIL_PATH_HELPERS`) | `/pricing` 요약 카드용 상품코드→문구/경로 매핑 | 신규 상품마다 두 해시에 줄 추가 필요(계획 문서가 명시적으로 지목한 지점) |
| 2.6 | `app/controllers/billing_controller.rb:56-61`(`product_landing_path_for`) | 상품코드→마케팅 랜딩 경로 `case`문 | 2.5와 **개념적으로 완전히 같은 일**(상품코드→마케팅 페이지 경로)을 별도로 재구현 — 통합 후보 |
| 2.7 | `app/controllers/application_controller.rb:22`(`billing_checkout_path_for`) | `"chatdox"`만 세그먼트 없는 구 URL로 리다이렉트, 나머지는 `/billing/checkout/:product_code` | 의도적 하위호환 예외(과거 북마크 보존) — **핵심 아님**, 그대로 둬도 됨. 다만 신규 상품 라우팅 설계 시 이 예외가 왜 있는지는 인지 필요 |
| 2.8 | `app/controllers/billing_orders_controller.rb:18,91,104` | `product_code || "chatdox"` 기본값 3회 | 2.3과 같은 유형의 "묵시적 기본 상품" 가정 |
| 2.9 | `app/controllers/dashboard_controller.rb:8`(`CHAPTER_SOURCES` 키) | 1.6과 동일 지점, 문자열 리터럴 관점에서 중복 집계 | — |
| 2.10 | `app/views/dashboard/show.html.erb:105`(`product.code == "chatdox"`) | GitHub Lab 카드를 Chatdox 블록에만 렌더링 | **의도적 상품 특화**(GitHub Lab 자체가 Chatdox 전용 기능) — 콘텐츠 조회 일반화와 무관, 그대로 둬도 됨 |
| 2.11 | `app/controllers/admin/commerce/github_access_controller.rb:25` | `License.for_product("chatdox")`로 GitHub Lab 접근 가능 유저만 조회 | 2.10과 같은 이유로 의도적 — **핵심 아님** |
| 2.12 | `app/helpers/dashboard_helper.rb:27-33`(`chapter_link_path`/`chapter_index_path`) | `product_code == "claudox"` 3항 분기로 라우트 헬퍼 전환(패턴 B) | 신규 상품마다 분기 추가 필요 — 3절과 직결 |
| 2.13 | `app/helpers/dashboard_helper.rb:36,48`(`subscription_badge`/`subscription_period_text`) | Chatdox 전용 헬퍼(어드민 유저 목록에서만 씀) | R2 라운드에서 의도적으로 유지된 레거시 — 어드민 화면 정리와 함께 재검토 후보(비급함) |
| 2.14 | `app/controllers/chapter_progresses_controller.rb:29,32,45` | `product_code` 문자열 비교로 3곳에서 분기(조회/기본값/리다이렉트 경로) | 패턴 C 참고 — 상품별 조회·경로 로직이 통합되면 이 컨트롤러는 거의 자동으로 따라옴 |
| 2.15 | `app/models/claudox.rb:66`, `app/controllers/docs_controller.rb:21,60,85` | 응답 해시에 `product_code: "chatdox"`/`"claudox"` 하드코딩 삽입 | 모델/컨트롤러가 자기 상품코드를 스스로 알아야 하는 지금 구조의 근본 원인 |
| 2.16 | `app/services/commerce/catalog_bootstrap.rb:4-5,43,51` | 상품 시딩 데이터(이름, 오퍼 연결) | **커머스 레이어, 조사 범위 밖**(참고로만 기재) — 이미 `PRODUCTS` 해시에 줄 추가하는 패턴이라 확장 자체는 쉬움 |
| 2.17 | `app/services/commerce/release_preflight.rb:20-23` | 배포 전 점검에서 `"chatdox"` 상품 오퍼 개수 확인 | **커머스 레이어, 조사 범위 밖** |

## 3. `/docs`, `/claudox/read` 라우트 및 헬퍼

**라우트 정의** (`config/routes.rb:18-24`):

| 상품 | 목록 | 상세 | 이미지 |
|---|---|---|---|
| Chatdox | `GET /docs` → `docs#index` | `GET /docs/:id` → `docs#show` (`doc_path`) | `GET /docs/images/*filename` (`doc_image_path`) |
| Claudox | `GET /claudox/read` → `claudox#index` (`claudox_read_path`) | `GET /claudox/read/:id` → `claudox#show` (`claudox_chapter_path`) | `GET /claudox/images/*filename` (`claudox_image_path`) |

경로 세그먼트(`/docs` vs `/claudox/read`)와 헬퍼 이름 규칙(`doc_*` vs `claudox_*`) 둘 다 상품마다 다르다 — 제네릭 라우트(예: `/content/:product_code/:id`) 하나로 통합하려면 기존 URL(사용자 북마크·외부 링크)과의 하위호환도 함께 설계해야 한다.

**이 비대칭 때문에 분기가 생기는 지점**(3항 연산자 또는 `case`로 `doc_path` vs `claudox_chapter_path` 선택):

| # | 파일:라인 |
|---|---|
| 3.1 | `app/helpers/dashboard_helper.rb:27-33` (`chapter_link_path`, `chapter_index_path`) |
| 3.2 | `app/controllers/chapter_progresses_controller.rb:45` (`redirect_path`) |
| 3.3 | `app/controllers/admin/content_progress_controller.rb:13,32` (경로만 다르게 생성, 분기는 위치가 다를 뿐 결과적으로 동일 문제) |

## 4. `DocPolicy` 상품별 분기

| # | 파일:라인 | 무엇을 하는가 | 왜 핵심인가 |
|---|---|---|---|
| 4.1 | `app/policies/doc_policy.rb:2-6`(`LICENSED_CHAPTER_RANGES`) | `[1..20, 90..99]` — Claudox의 정규+부록 범위가 정책에 하드코딩 | 계획 문서가 명시적으로 지목한 지점("상품 메타데이터 기반으로 바꾼다"). 신규 상품이 다른 챕터 범위(예: 10장, 또는 부록 없음)를 쓰면 이 배열이 안 맞음 |
| 4.2 | `app/policies/doc_policy.rb:19-25`(`view_as_guest?`/`view_as_trial?`) | 게스트 `<=2`, Trial `<=5` — 상품 무관 전역 상수로 적용 | 두 상품이 우연히 같은 1..20 범위를 쓰기 때문에 지금은 문제가 안 되지만, 실제로는 "상품마다 다를 수 있는 값"이 상수로 박혀 있는 것 — 4.1과 같이 메타데이터화 대상 |
| 4.3 | `app/policies/doc_policy.rb:13-17`(`product_code` 기본값) | 2.2와 동일 지점 | — |

## 5. 대시보드 / 가격 페이지 / 네비게이션 / 어드민 매핑표

| # | 파일:라인 | 매핑 내용 | 비고 |
|---|---|---|---|
| 5.1 | `app/controllers/dashboard_controller.rb:8`(`CHAPTER_SOURCES`) | 상품코드 → 챕터 소스 클래스 | 1.6/2.9와 동일 지점 |
| 5.2 | `app/controllers/pages_controller.rb:6-17`(`PRODUCT_TAGLINES`, `PRODUCT_DETAIL_PATH_HELPERS`) | 상품코드 → 가격 카드 문구/상세 경로 | 2.5와 동일 지점 |
| 5.3 | `app/controllers/billing_controller.rb:56-61`(`product_landing_path_for`) | 상품코드 → 마케팅 랜딩 경로 | 2.6과 동일 지점, 5.2와 통합 후보 |
| 5.4 | `app/controllers/admin/content_progress_controller.rb` 전체 | 어드민 콘텐츠 진행률 화면의 상품별 파싱 로직 | 패턴 A-4, 1.7과 동일 지점 |
| 5.5 | `app/helpers/navigation_helper.rb` | **확인 결과 해당 없음** — `primary_navigation_items`는 이미 `/pricing`, `/dashboard`, `/mypage` 같은 상품-무관 경로만 반환. 상품별 분기 없음 | 조사했으나 문제 없음, 완전성을 위해 기록 |
| 5.6 | `app/views/shared/_product_pricing.html.erb` | **확인 결과 해당 없음** — `product_code:` 로컬 하나로 `Product.find_by`부터 전부 DB 기반, 하드코딩 없음 | 이미 일반화된 참고 사례로 기록(2단계에서 이 패턴을 본보기로 삼을 만함) |
| 5.7 | `app/services/entitlements/product_access.rb` | **확인 결과 해당 없음** — `product_code`를 순수 파라미터로만 다룸 | 커머스 레이어 중 콘텐츠 레이어와 접점 있는 곳이라 참고로 확인, 문제 없음 |

---

## 2단계로 넘기는 제안 (설계 방향 확정 아님, 이번 라운드 관찰만)

- 패턴 A(4중 구현)를 하나로 합치는 게 이 프로젝트에서 단연 가장 리스크가 큰 작업. `Curriculum`/`Claudox`를 대체할 제네릭 모델이 `ClaudoxProductsController`(마케팅 페이지)와 `Admin::ContentProgressController`(진행률 어드민)가 필요로 하는 데이터도 같이 만족해야, 실질적으로 "통합"이라 부를 수 있다.
- 패턴 B(라우트/헬퍼 비대칭)는 URL 하위호환을 지키면서 어떻게 단일화할지가 설계의 핵심 결정 포인트 중 하나가 될 것.
- 2.5/2.6(가격 카드 문구·경로 매핑, 5.2/5.3과 동일)은 이미 서로 다른 컨트롤러에 중복 구현돼 있어, 콘텐츠 레이어 통합과 별개로 먼저 합쳐도 되는 낮은 리스크 작업으로 보인다.
