# 다상품 콘텐츠 플랫폼 일반화 — 2단계 설계

- 입력: `docs/internal/content_platform_audit.md`(1단계 감사)
- 이번 라운드는 **설계만** — 이 문서는 앱 동작을 바꾸지 않는다. 코드 변경은 3단계(마이그레이션)/4단계(나머지 정리)에서 실행한다.
- 목표: `Curriculum`/`Claudox`(모델), `DocsController`/`ClaudoxController`(컨트롤러), `DocPolicy`의 하드코딩된 챕터 범위, 그리고 감사에서 드러난 `ClaudoxProductsController`/`Admin::ContentProgressController`의 독립 재구현까지 — "새 상품 = 콘텐츠 폴더 + `Product` row 등록만"으로 흡수되는 단일 구조를 설계한다.

## A. 단일 제네릭 콘텐츠 모델 — `ProductContent`

### A-1. 인터페이스(계약)

`Curriculum`/`Claudox`를 대체하는 건 "하나의 클래스"가 아니라 "하나의 인터페이스 + 그걸 만족하는 소스 구현체 여러 개"다. 요청서가 허용한 대로("완전히 데이터 기반을 강제하지 않아도 된다") 상품마다 소스가 달라도 되고, 이 계약만 지키면 된다.

```ruby
# 모든 소스 구현체가 만족해야 하는 계약(Ruby엔 강제 인터페이스가 없으므로 duck-type 문서화 + 테스트로 보증)
#
#   #chapters                 -> Array<Chapter>  (id 순 정렬, 존재하는 챕터 전부)
#   #find(id)                 -> Chapter | nil
#   #phases                   -> Array<Phase>    (Part/Phase 그룹핑 메타데이터)
#   #licensed_chapter_ranges  -> Array<Range>    (DocPolicy가 쓸 라이선스 허용 범위)
#   #guest_chapter_limit      -> Integer         (게스트 미리보기 상한, 기본 2)
#   #trial_chapter_limit      -> Integer         (Trial 미리보기 상한, 기본 5)
#   #images_path              -> Pathname        (이미지 서빙 base path)
#   #editorial_status(id)     -> 상품마다 다른 형태 허용(아래 A-3), 어드민 전용
#
# Chapter = { id:, slug:, title:, kind: (:chapter | :appendix), available: true/false }
# Phase   = { key:, label:, title:, description:, range: }
```

`ProductContent`는 구현체가 아니라 **레지스트리(디스패처)**다:

```ruby
class ProductContent
  def self.for(product_code)
    source_class = REGISTRY.fetch(product_code) { FilesystemSource }
    source_class.new(product_code)
  end
end
```

핵심은 `REGISTRY.fetch(product_code) { FilesystemSource }` — **등록이 안 된 상품코드는 자동으로 `FilesystemSource`를 쓴다.** 즉 신규 상품은 `REGISTRY`에 줄을 추가할 필요조차 없다(아래 A-2).

### A-2. 두 가지 소스 구현체

**`ProductContent::FilesystemSource`(신규 기본 구현, Claudox 방식을 일반화)**

- `hq/<product_code>/`를 스캔(`Dir.glob`)해서 챕터 목록을 구성 — 지금 `Claudox` 모델 로직을 상품코드로 파라미터화한 것과 같다.
- Part/Phase 그룹핑, 라이선스 범위(`licensed_chapter_ranges`), 부록 범위, 비-챕터 파일 제외 목록(`97_commands.md` 같은) 같은 "상품마다 다를 수 있는 형태" 메타데이터는 **코드가 아니라 데이터**로 옮긴다 — `hq/<product_code>/content_meta.yml` 파일 하나로.

  ```yaml
  # hq/claudox/content_meta.yml (예시 — Claudox 마이그레이션 시 지금 Claudox::PHASES/CHAPTER_RANGE/APPENDIX_RANGE/NON_CHAPTER_FILES를 그대로 옮긴 값)
  phases:
    - key: part_1
      label: "Part 1"
      title: "입문"
      description: "관계 맺기와 기본 협업 규칙 — ..."
      range: 1..8
    - key: part_2
      ...
  chapter_range: 1..20
  appendix_range: 90..99
  non_chapter_files: [97_commands.md]
  guest_chapter_limit: 2   # 생략 시 기본값 2
  trial_chapter_limit: 5   # 생략 시 기본값 5
  ```

  이 파일은 `sync_curriculum.sh`가 다른 챕터 `.md` 파일과 똑같이 HQ에서 그대로 미러링한다 — **HQ가 콘텐츠 폴더에 이 파일 하나 추가하는 것만으로 새 상품의 구조(파트 구성, 게스트/Trial 미리보기 범위 등)를 정의**할 수 있다는 뜻이다. `content_meta.yml`이 없는 상품은 파트 그룹핑 없이 챕터를 그냥 나열하고, `guest_chapter_limit`/`trial_chapter_limit`은 기본값(2/5)을 쓴다 — 최소 설정으로도 동작해야 "코드 변경 없이 등록"이 실제로 성립한다.

**`ProductContent::ChatdoxLegacySource`(Chatdox 전용, 과도기 유지 — 아래 근거 참고)**

- Chatdox를 곧바로 `FilesystemSource`로 옮기지 못하는 이유를 **이번 라운드에서 직접 검증**했다: `Curriculum::CHAPTERS`의 하드코딩된 제목 20개 전부가 실제 마크다운 파일의 `#` 헤딩과 다르다(예: 01번은 헤딩이 `"1. 채독스 전체 구조 이해"`인데 하드코딩 제목은 `"채독스 전체 구조 이해"` — 번호 접두어 차이는 전부, 07/08/13번 등 일부는 표현 자체가 다름: `"Authentication (Devise)"` vs `"인증 (Devise)"`). 화면은 챕터 번호를 별도 UI 요소로 이미 보여주고 있어서(`Chapter <%= id %>`), 헤딩을 그대로 쓰면 번호가 중복 표시되거나 문구가 달라져 **콘텐츠·UX가 바뀐다** — 3단계가 지키기로 한 "동작 완전히 동일 유지" 원칙에 위배된다.
- 그래서 Chatdox는 `REGISTRY`에 명시적으로 등록해 `ChatdoxLegacySource`(지금의 `Curriculum::CHAPTERS` 배열을 그대로 감싸는 얇은 어댑터)를 계속 쓴다. 인터페이스는 동일하게 만족하므로 컨트롤러/정책 등 나머지 레이어는 Chatdox가 레거시 소스인지 몰라도 된다.
- **후속 옵션(4단계 이후, 이번 설계 범위 밖)**: HQ가 `hq/chatdox/*.md`의 헤딩에서 번호 접두어를 제거하고 문구를 지금 표시되는 제목과 맞춰주면, 그때 Chatdox도 `FilesystemSource`로 옮기고 `ChatdoxLegacySource`/`Curriculum`을 완전히 삭제할 수 있다. 지금은 콘텐츠 파일을 건드리는 결정이라 DEV 단독으로 정할 수 없어 옵션으로만 남긴다.

### A-3. "완성" 판정 — 통일하지 않고 목적별로 분리

감사에서 지적된 세 가지 서로 다른 기준을 검토한 결과, **하나로 합치지 않는다.** 이유:

- **존재(existence)** — "이 챕터 ID에 해당하는 콘텐츠 파일이 지금 있는가"는 기계적으로 파일 존재 여부로 판단 가능하고, 리더 화면(잠금 아이콘, 접근 가능 문서 카운트)이 실제로 필요로 하는 값이다. `Chapter#available`로 인터페이스에 포함시킨다(지금 `DocsController`의 `File.exist?` 기반 `available`, `Claudox.all`의 트리비얼한 `available: true`를 통일).
- **편집 완성도(editorial status)** — "파일은 있는데 아직 플레이스홀더인가"(`ClaudoxProductsController`의 `UNWRITTEN_PLACEHOLDER` 검사)나 "얼마나 다듬어졌나"(`Admin::ContentProgressController`가 파싱하는 `88_progress.md`의 %/✅⬜🟡)는 **리더에게 노출되는 값이 아니라 HQ/어드민 전용 저작 진행률 지표**다. 두 상품이 지금도 서로 다른 정밀도(Chatdox는 있음/없음 이진, Claudox는 %+3단계 상태)를 쓰고 있고, 이건 실제로 다른 정보다 — 억지로 하나의 스키마로 합치면 Claudox 쪽 정보가 손실된다.
- 그래서 `editorial_status(id)`는 인터페이스에 **자리는 만들어두되 반환 형태를 상품별로 허용**한다. `FilesystemSource`의 기본 구현은 플레이스홀더 텍스트 검사(지금 `ClaudoxProductsController`와 동일 로직을 흡수)로 이진 `:draft`/`:written`을 반환하고, `88_progress.md` 같은 더 정밀한 자체 트래커가 있는 상품은 그 파서를 `editorial_status`에 얹어 상세 값을 반환해도 된다. 설계 시점엔 어드민 진행률 화면(`Admin::ContentProgressController`)만 이 메서드를 쓸 것으로 예상했지만, 4단계에서 `ClaudoxProductsController`(리더 대상 마케팅 페이지)도 `editorial_status(id) == :written`로 "완성" 배지를 판정하도록 흡수되면서 이 값을 쓰는 두 번째 소비자가 됐다 — 여전히 대시보드·정책은 이 값에 의존하지 않는다.

## B. 라우트 / 컨트롤러

### B-1. 기존 URL·헬퍼 이름은 전혀 바꾸지 않는다

사용자 북마크·외부 링크·SEO에 영향을 주는 URL 변경은 이 프로젝트의 목적(내부 구조 정리)과 무관한 리스크라고 판단해서, **`/docs`, `/docs/:id`, `/claudox/read`, `/claudox/read/:id` 등 기존 경로와 `doc_path`/`claudox_chapter_path` 등 기존 헬퍼 이름을 그대로 유지**한다. 대신 그 경로들이 가리키는 컨트롤러를 하나로 합친다 — Rails 라우트의 `defaults:`로 상품코드를 주입하면 URL도 헬퍼 이름도 안 바꾸고 뒤에서 단일 컨트롤러로 합칠 수 있다.

```ruby
# 기존 상품 -- URL/헬퍼 이름 완전히 그대로, product_code만 defaults로 주입
get "/docs",               to: "product_content#index", defaults: { product_code: "chatdox" }
get "/docs/:id",           to: "product_content#show",  defaults: { product_code: "chatdox" }, as: :doc
get "/docs/images/*filename", to: "product_content#image", defaults: { product_code: "chatdox" }, as: :doc_image, format: false

get "/claudox/read",       to: "product_content#index", defaults: { product_code: "claudox" }, as: :claudox_read
get "/claudox/read/:id",   to: "product_content#show",  defaults: { product_code: "claudox" }, as: :claudox_chapter
get "/claudox/images/*filename", to: "product_content#image", defaults: { product_code: "claudox" }, as: :claudox_image, format: false

# 신규 상품(3번째 이후) -- 별도 라우트 추가 없이 이 패턴 하나로 전부 커버
get "/content/:product_code",              to: "product_content#index"
get "/content/:product_code/:id",          to: "product_content#show",  as: :product_chapter
get "/content/:product_code/images/*filename", to: "product_content#image", as: :product_content_image, format: false
```

`ProductContentController`는 `params[:product_code]`(defaults로 주입되든 URL 세그먼트로 오든 동일)로 `ProductContent.for(product_code)`를 얻어 지금 `DocsController`/`ClaudoxController#show`/`#index`/`#image`가 하던 일을 그대로 한다. **신규 상품은 이 라우트 3줄(index/show/image)이 이미 있으므로 라우트 추가가 필요 없다** — 나중에 그 상품이 `/docs`처럼 예쁜 전용 URL을 갖고 싶으면(선택) `defaults:` 줄 하나만 추가하면 된다.

### B-2. 내부 링크 생성은 제네릭 헬퍼로 통일 (분기 제거)

지금 `dashboard_helper.rb`의 `chapter_link_path`/`chapter_index_path`가 `product_code == "claudox" ? claudox_chapter_path(id) : doc_path(id)` 식으로 분기하는 이유는 "레거시 이름 헬퍼가 상품마다 다르다"는 것뿐이다. **앱이 스스로 생성하는 내부 링크는 전부 신규 제네릭 헬퍼(`product_chapter_path(product_code, id)`)로 통일**하고, 레거시 이름 헬퍼(`doc_path`/`claudox_chapter_path`)는 "외부에서 들어오는 요청을 여전히 받아주는 진입점"으로만 남긴다(둘 다 결국 같은 챕터로 이어지므로 사용자 경험은 동일 — 대시보드에서 챕터를 클릭하면 URL 표시가 `/docs/05`에서 `/content/chatdox/05`로 바뀌는 정도이고, 콘텐츠·기능은 동일).

이렇게 하면 `chapter_link_path`/`chapter_index_path` 헬퍼 자체가 필요 없어져서 삭제된다(감사 2.12/3.1), `ChapterProgressesController#redirect_path`(3.2)와 `Admin::ContentProgressController`의 경로 분기(3.3)도 같은 방식으로 제거된다.

## C. `DocPolicy` 챕터 범위 일반화

```ruby
class DocPolicy < ApplicationPolicy
  def view_as_license?
    Entitlements::ProductAccess.allowed?(user: user, product_code: product_code) &&
      content_source.licensed_chapter_ranges.any? { |range| range.cover?(chapter_number) }
  end

  def view_as_guest?
    chapter_number <= content_source.guest_chapter_limit
  end

  def view_as_trial?
    user&.trial_active? && chapter_number <= content_source.trial_chapter_limit
  end

  private

  def content_source
    ProductContent.for(product_code)
  end
end
```

`LICENSED_CHAPTER_RANGES = [1..20, 90..99]` 하드코딩(감사 4.1)이 `content_source.licensed_chapter_ranges`(= A절의 `content_meta.yml`에서 온 값)로 대체된다. 게스트/Trial 상한(감사 4.2, 지금 전역 상수 `<=2`/`<=5`)도 같은 방식으로 상품별 오버라이드가 가능해지지만, `content_meta.yml`에 값이 없으면 지금과 똑같은 기본값(2/5)을 쓰므로 **Chatdox·Claudox 둘 다 동작 변화가 없다** — `guest_chapter_limit`/`trial_chapter_limit`을 명시한 상품만 다른 값을 가질 수 있다.

`product_code` 기본값 `"chatdox"`(감사 2.2/2.3, `DocPolicy#product_code`·`User#can_view_chapter?`)는 이번 설계에서 없애지 않는다 — 호출부 전수 재검증이 필요한 별도 작업이라 4단계로 넘긴다(D절).

## D. 핵심 지점 → 단계 매핑

감사 문서의 "핵심 13곳"(중복 지점 통합 기준)을 전부 아래 표에 배정했다 — 누락 없음.

| 감사 지점 | 처리 | 단계 |
|---|---|---|
| `Curriculum` 모델(1.1) | `ChatdoxLegacySource`로 감싸 유지(A-2) | 3단계 |
| `Claudox` 모델(1.2) | `FilesystemSource` + `content_meta.yml`로 이관(A-2) | 3단계 |
| `DocsController`(1.3) | `ProductContentController`로 흡수(B-1) | 3단계 |
| `ClaudoxController`(1.4) | 〃 | 3단계 |
| `ChapterProgressesController` 분기(1.5/2.14/3.2) | `ProductContent.for`/제네릭 헬퍼로 자동 해소(패턴 C) | 3단계 |
| `DashboardController::CHAPTER_SOURCES`(1.6/2.9/5.1) | `ProductContent.for(product.code)` 호출로 대체, 해시 삭제 | 3단계 |
| `Admin::ContentProgressController`(1.7/3.3/5.4) | Chatdox/Claudox 각각의 파서를 `editorial_status`(A-3)로 흡수 | 3단계 |
| `landing/_curriculum.html.erb`(1.9) | `ProductContent.for("chatdox")` 호출로 교체 | 3단계 |
| `leedox_home/_proof.html.erb`(1.10, 동적 Chatdox 4개) | 위와 동일 패턴으로 자동 해소 | 3단계 |
| `leedox_home/_proof.html.erb`(1.11, 하드코딩된 Claudox 배열 — "가짜 동기화") | **이번 설계 범위에 포함**(아래 근거) — `ProductContent.for("claudox").chapters.first(4)`로 교체 | 3단계 |
| `ChapterProgress::PRODUCT_CODES`(2.1) | `Product.pluck(:code)` 동적 조회로 대체 | 4단계 |
| `DocPolicy` 챕터 범위(2.2/4.1/4.2/4.3) | C절 | 3단계 |
| `User#can_view_chapter?` 기본값(2.3) | 호출부 재검증 후 기본값 제거 여부 결정 | 4단계 |
| `PagesController` 매핑표(2.5/5.2) + `BillingController#product_landing_path_for`(2.6/5.3) | `Product`에 `tagline`/`landing_page_path` 컬럼 추가, 두 코드 지점 모두 DB 조회로 대체(중복 통합) | 4단계 |
| `BillingOrdersController` 기본값 ×3(2.8) | `"chatdox"` 묵시적 기본값 제거, 명시적 파라미터 요구로 전환 | 4단계 |
| 라우트/헬퍼 비대칭(카테고리 3 전체, 2.12/3.1) | B절 | 3단계 |

**표에 별도 행이 없지만 놓친 건 아닌 지점**: `chapter_progress.rb:20-22`의 주석(1.12)은 코드가 아니라 `Curriculum`/`Claudox` 비대칭을 설명하는 문서화성 텍스트라 — 1.1/1.2가 A절대로 이관되면 이 주석도 자연히 낡은 설명이 되므로, 3단계에서 해당 코드를 옮길 때 같이 지우거나 갱신하면 된다(별도 작업 아님). `claudox.rb`/`docs_controller.rb`가 응답 해시에 `product_code`를 직접 박아넣는 지점(2.15)도 마찬가지로 — `FilesystemSource`/`ChatdoxLegacySource`가 자기 생성자에 받은 `product_code`로 챕터를 만들게 되면 이 하드코딩은 A절 이관과 함께 자동으로 없어진다.

**비급함으로 분류돼 이번 설계에서 다루지 않는 지점**(감사 문서와 동일 판단 유지): `RefsController`(1.8, 의도적 Chatdox 전용), `DashboardPolicy#show_subscription?`(2.4, 죽은 코드 — 삭제는 하되 이 프로젝트 범위는 아님), `billing_checkout_path_for`의 chatdox 예외(2.7, 의도적 하위호환), GitHub Lab 관련 두 지점(2.10/2.11, 의도적 Chatdox 전용 기능), `subscription_badge`류(2.13, 어드민 레거시).

### `_proof.html.erb`(1.11) 포함 근거

제외해도 되는 선택지였지만 포함시켰다 — A절 소스 통합이 끝나면 `ProductContent.for("claudox").chapters.first(4)` 한 줄로 옆의 Chatdox 코드(1.10)와 완전히 대칭이 되는데, 이 한 줄을 안 바꾸면 통합된 시스템 안에 "여전히 수동으로 손봐야 하는 구석"이 하나 남는 셈이라 프로젝트 취지에 안 맞는다고 판단했다. 지금 시점에 하드코딩된 제목과 실제 콘텐츠 사이에 드리프트가 있는지는 확인하지 않았지만(이번 라운드는 코드 변경 없음), 3단계에서 이 한 줄을 바꾸기 직전에 실제 렌더링을 대조해서 드리프트가 있으면 그 자체가 부수 발견거리다.

## 3단계 마이그레이션 순서 제안

1. `ProductContent` 인터페이스 + `FilesystemSource` + `content_meta.yml` 로더를 **기존 코드와 나란히** 추가(아직 아무 컨트롤러도 안 바꿈). 신규 코드 경로 자체 테스트만 먼저 통과시킨다.
2. Claudox를 `FilesystemSource`로 전환(`Claudox::PHASES`/`CHAPTER_RANGE`/`APPENDIX_RANGE`/`NON_CHAPTER_FILES`를 `hq/claudox/content_meta.yml`로 이관) — Claudox가 원래 파일시스템 스캔 방식이라 가장 리스크가 낮은 첫 이관 대상.
3. Chatdox는 `ChatdoxLegacySource`로 어댑터만 씌운다(내용은 안 바꿈, 헤딩-제목 불일치 문제 있음 — A-2 참고).
4. `ProductContentController` + B절 라우트 도입, `DocsController`/`ClaudoxController` 삭제. 기존 URL·헬퍼 이름 유지되는지 회귀 테스트로 검증.
5. `DocPolicy`를 C절 설계로 전환.
6. 나머지 호출부(대시보드, 어드민 진행률, 랜딩 페이지 2곳, 챕터 진도 컨트롤러) 순서대로 이관 — 각 이관마다 회귀 테스트.
7. `Curriculum`/`Claudox`(구 모델 파일) 삭제 — 이 시점에 남은 유일한 참조가 `ChatdoxLegacySource` 내부뿐이어야 한다.
8. 전체 회귀 테스트 + (가능하면) 실제 화면 텍스트 대조로 "동작 완전히 동일" 최종 확인.

## 미결정 사항

- Chatdox를 언젠가 `FilesystemSource`로 완전 이관할지는 HQ가 `hq/chatdox/*.md` 헤딩을 표시용 제목과 맞게 정리해줄 의향이 있는지에 달려 있다 — 이번 설계 범위 밖의 콘텐츠 편집 결정이라 옵션으로만 남겨둔다.
- `sync_curriculum.sh`가 `sync_one "docs" ...`/`sync_one "claudox" ...`를 여전히 하드코딩하고 있다는 걸 이번 설계 중 발견했다(감사 문서의 sitewide grep 범위(`app/`, `config/routes.rb`, `test/`) 밖이라 감사엔 안 실렸음). `content_meta.yml`이 상품 구조를 데이터화해도, HQ 콘텐츠가 DEV로 넘어오는 이 스크립트 자체는 여전히 상품코드마다 한 줄이 필요하다 — **5단계에서 실제 3번째 상품(`aistart`)을 등록하며 이걸 직접 확인했다**: `sync_one "aistart" ...` 한 줄을 추가해야만 콘텐츠가 넘어왔고, 이게 "새 상품 등록" 전체 과정에서 유일하게 남는 코드 변경 지점이었다(그 외엔 `Commerce::CatalogBootstrap`의 상품 데이터 등록뿐, 콘텐츠 조회 파이프라인 자체는 무변경). 이 문서 전반의 "코드 변경 없이 등록"이라는 표현은 정확히는 "콘텐츠 조회 파이프라인 코드는 무변경"을 뜻하며, `sync_curriculum.sh`는 그 예외다. 스크립트 자체를 `Product.pluck(:code)` 기반으로 완전 일반화할지는 backlog 006으로 별도 보류.
- 어드민 진행률 화면(`Admin::ContentProgressController`)이 `editorial_status`로 흡수된 뒤에도, Chatdox 쪽 저작 진행률을 지금처럼 "파일 존재 여부"로만 볼지, Claudox처럼 더 정밀한 트래커를 도입할지는 콘텐츠 운영 정책 문제라 이 설계에서 결정하지 않는다.
