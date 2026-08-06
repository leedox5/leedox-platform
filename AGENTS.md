# AGENTS.md

이 저장소에서 작업하는 코딩 에이전트를 위한 가이드다. Claude Code이고 작업이
`handoff-agy/<번호_슬러그>/` 패키지나 DEV/HQ 저장소 구조와 관련 있다면 **`CLAUDE.md`를 먼저
읽을 것** — 그 워크플로우는 여기가 아니라 거기 문서화돼 있다(중복해서 따로
관리하면 둘이 어긋난다). 이 파일은 그 워크플로우와 무관하게 어떤 에이전트든
필요한 아키텍처/컨벤션 지도다.

## 이 저장소가 뭔가

Rails 8.1 앱(Ruby 3.4)이 작은 다상품 콘텐츠 플랫폼을 서비스한다 — 3개 상품
(Chatdox, Claudox, 무료 입문 상품 `aistart`)이 하나의 콘텐츠 파이프라인을
공유하고, 유료 두 상품엔 커머스/결제 레이어가 붙어 있다. 개발/테스트는 SQLite,
프로덕션은 Postgres(Railway). Tailwind + Turbo/Stimulus + importmap, Node 빌드 없음.

## 핵심 추상화: `ProductContent`

콘텐츠 관련 코드를 건드리기 전에 반드시 이해해야 하는 부분이다.
`app/models/product_content.rb`는 레지스트리/디스패처다:

```ruby
ProductContent.for(product_code) # -> 소스 객체
```

등록 안 된 `product_code`는 자동으로 `ProductContent::FilesystemSource`를 쓴다 —
`hq/<product_code>/*.md`를 관례대로 스캔하고, 선택적으로 `hq/<product_code>/content_meta.yml`
에서 phases/범위/한도/theme을 읽는다. **"새 상품 = 콘텐츠 폴더 + `Product` DB row,
코드 변경 0"이 문자 그대로 성립하는 이유가 바로 이거다.** Chatdox만 예외로
`ProductContent::ChatdoxLegacySource`에 등록돼 있다 — 하드코딩된 챕터 제목이
마크다운 헤딩과 안전하게 바꿔 쓸 만큼 일치하지 않기 때문(그 클래스의 코멘트에
실제 차이가 적혀 있음).

모든 소스 클래스(현재든 미래든)는 `app/models/product_content.rb` 상단에 문서화된
인터페이스를 만족해야 한다 — `#chapters`, `#find(id)`, `#phases`,
`#licensed_chapter_ranges`, `#guest_chapter_limit`/`#trial_chapter_limit`, `#theme`
등. `ProductContentController`가 모든 상품의 `index`/`show`/`image` 액션을
전부 처리하는 단일 컨트롤러고, `app/views/product_content/*`가 단일 템플릿
세트다. 레거시 URL(`/docs`, `/claudox/read` 등)은 여전히 동작하고 원래 라우트
헬퍼 이름도 그대로다 — 별도 컨트롤러가 아니라 `config/routes.rb`의
`defaults: { product_code: ... }`로 연결돼 있을 뿐이다.

`DocPolicy`(Pundit)와 `ChapterProgress`(진도 추적)도 챕터 접근권한/한도를
`ProductContent.for(product_code)`에서 읽는다 — 상품별 로직을 하드코딩하지
않는다. `Product#free_access?`는 상품을 영구 무료로 표시한다(라이선스 불필요,
`ProductOffer` row 없음) — 지금은 `aistart`만 해당.

## 커머스/결제

`app/services/commerce/*` — 주문 생성, 체크아웃, 라이선스 스케줄링, 환불,
결제사와의 정합 확인(reconciliation). `Commerce::CatalogBootstrap`이 신규
환경에 어떤 상품/오퍼가 있어야 하는지의 단일 소스다(`db/seeds.rb`가 호출하고,
테스트 setup도 `Commerce::CatalogBootstrap.call!`로 호출). 결제는 PortOne을
거치고(`app/services/payments/`, `billing_controller.rb`에서 연결), 결제사
설정이 안 돼 있으면 무통장입금 경로로 폴백한다.

## 코드/테스트 작성 전에 알아둘 컨벤션

- **모킹을 쓰지 않는다.** 이 테스트 스위트는 Mocha/RSpec-mocks/Minitest::Mock을
  어디서도 쓰지 않는다 — 실제 모델, 실제 라우트, 실제(임시) 파일로 검증한다.
  이 관례를 따를 것 — 첫 모킹을 들여오지 말 것.
- **병렬 테스트 안전성.** `test_helper.rb`가 CPU 코어 수만큼 병렬 실행한다.
  테스트에서 공유 디렉터리인 `hq/<product>/`에 실제 파일을 쓰지 말 것 — 동시에
  실행 중인 다른 워커가 그 디렉터리를 그 순간 glob하고 있을 수 있다. 파일시스템에
  의존하는 테스트는 `Dir.mktmpdir`을 쓰거나(`test/models/product_content/content_meta_test.rb`
  참고), 완전히 별도의 합성 상품 폴더를 만들어 `teardown`에서 정리할 것
  (`test/integration/synthetic_product_content_test.rb` 참고).
- **Tailwind 클래스 문자열은 소스 어딘가에 완전한 리터럴로 있어야 한다.**
  `"bg-#{accent}-600"` 같은 문자열 보간은 Tailwind 정적 스캐너가 인식 못 해서
  스타일이 조용히 안 먹는다. 상품별 accent 색상은 전부
  `app/helpers/content_theme_helper.rb`의 `ACCENT_CLASSES` 룩업을 거친다 —
  나올 수 있는 클래스가 전부 완전한 문자열로 적혀 있다. 새로 동적으로 보이는
  클래스가 필요하면 이 패턴을 따를 것.
- **`hq/` 아래를 직접 고치지 말 것.** 그 콘텐츠는 별도 저장소에서
  `script/sync_curriculum.sh`로 미러링돼 들어오고, 다음 동기화 때 덮어써진다.
  `hq/` 아래 `content_meta.yml`에 새 필드가 필요하면, 실제 콘텐츠를 관리하는
  저장소에도 동일하게 반영돼야 다음 동기화 때 안 사라진다 — 알아서 처리됐다고
  가정하지 말고 이 점을 명시적으로 알릴 것.
- **커밋 메시지**는 Claude Code가 변경했다면 `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
  로 끝맺는다.

## 명령어

```bash
bin/rails test      # 전체 테스트
bin/rails test path/to/file_test.rb           # 파일 하나만
bin/rails test path/to/file_test.rb -n "/pattern/"  # 패턴으로 필터링

bin/rubocop         # 스타일
bin/brakeman        # 보안 정적 분석
bin/bundler-audit   # gem 취약점 스캔
bin/ci              # setup + rubocop + 보안 스캔 2개
```

마이그레이션 후 `test` DB는 `development`와 별도로 갱신해야 한다:
`RAILS_ENV=test bin/rails db:schema:load`.

## 설계 의도가 담긴 문서

- `docs/internal/content_platform_audit.md` / `content_platform_design.md` —
  `ProductContent` 추상화가 나온 감사·설계 문서. 콘텐츠 파이프라인의 무언가가
  우연이 아니라 의도된 것인지 확인하려면 먼저 이걸 읽을 것.
- `CLAUDE.md` — DEV/HQ 저장소 관계, `.local/handoff/` 워크플로우, Railway 배포
  주의사항, 그리고 이 저장소에서 실제로 겪고 고친 실수 목록.
