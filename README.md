# chatdox-platform

Collaboration signature: LEEDOX x Codidox.

[LEEDOX](https://leedox.up.railway.app)를 구동하는 Rails 앱 — AI 협업 콘텐츠·강의를
제공하는 작은 다상품 플랫폼이다. 지금은 하나의 공유 콘텐츠 파이프라인으로 3개 상품을
서비스한다:

- **Chatdox** (`/docs`) — AI와 함께 기획부터 배포까지 실제 SaaS 하나를 완성하는 과정.
- **Claudox** (`/claudox/read`) — Claude와 매일 협업한 실제 기록을 담은 서사형 콘텐츠.
- **AI, 오늘부터 시작** (`/content/aistart`) — 로그인 없이 볼 수 있는 무료 5화짜리 입문 가이드.

새 상품을 등록하는 데 컨트롤러/뷰 코드는 필요 없다 — `hq/<product_code>/` 폴더에
마크다운 챕터(+ 선택적으로 `content_meta.yml`)를 두고 `Product` row 하나만 만들면
된다. 동작 방식은 `app/models/product_content.rb`를 참고.

## 스택

- Ruby 3.4 / Rails 8.1, Puma, Propshaft
- 개발/테스트는 SQLite, 프로덕션은 Postgres(Railway가 `DATABASE_URL`을 설정)
- Solid Queue / Solid Cache / Solid Cable(Redis 없음)
- Tailwind CSS(`tailwindcss-rails`), Turbo + Stimulus, importmap(Node/npm 빌드 없음)
- Devise(인증) + Pundit(인가)
- 마크다운 렌더링은 Redcarpet
- 결제는 PortOne, 안 되면 무통장입금으로 폴백

## 시작하기

```bash
bin/setup        # bundle install, db:prepare, 로그/tmp 정리 후 bin/dev 실행
```

`bin/setup --skip-server`는 서버 기동만 빼고 전부 실행한다. `bin/dev`(`foreman` +
`Procfile.dev`)가 Rails 서버와 `tailwindcss:watch`를 같이 띄운다.

결제 관련 기능을 쓰려면 `.env`(gitignore됨)가 필요하다 — `app/services/commerce/`와
`app/controllers/billing_controller.rb`의 `ENV.fetch(...)` 호출을 보면 어떤 값을
읽는지 알 수 있다(PortOne 키, `LEEDOX_COMMERCE_ENABLED`, `BANK_TRANSFER_ACCOUNT_INFO`
등). 이 설정이 하나도 없어도 앱은 정상 구동되고 콘텐츠도 그대로 볼 수 있다 —
결제 화면만 실패 대신 "아직 준비 중" 화면으로 대체된다.

## 콘텐츠

`hq/`(`hq/chatdox/`, `hq/claudox/`, `hq/aistart/`) 아래 챕터 콘텐츠는 이 저장소에서
직접 작성하는 게 아니다 — 별도 커리큘럼 저장소에서 `script/sync_curriculum.sh`로
미러링해온다. `hq/` 아래 파일을 직접 고쳐도 다음 동기화 때 덮어써진다. DEV/HQ 구조와
handoff 워크플로우 전체는 `CLAUDE.md`를 참고.

## 테스트 & 검사

```bash
bin/rails test      # 전체 테스트, CPU 코어 수만큼 병렬 실행
bin/rubocop         # 스타일(rails-omakase 설정)
bin/brakeman        # 정적 보안 스캔
bin/bundler-audit   # gem 취약점 스캔
bin/ci              # setup + rubocop + 보안 스캔 2개를 순서대로 실행
```

마이그레이션은 `development` DB에만 자동 반영된다. 스키마를 바꿨다면 test DB는
따로 갱신해야 한다:

```bash
RAILS_ENV=test bin/rails db:schema:load
```

## 배포

Railway에 배포된다. `main`에 push하면 자동으로 빌드/배포되지만, Railway가 대기 중인
마이그레이션까지 자동으로 실행해주지는 **않는다** — 스키마 변경이 `main`에 반영되면,
새 빌드가 뜬 뒤에 마이그레이션을 직접 실행해야 한다:

```bash
railway ssh -- bin/rails db:migrate
```

(`railway run bin/rails db:migrate`는 여기서 안 된다 — 이 명령은 로컬에서 실행되는
방식이라 Railway 내부 Postgres 호스트명을 못 찾는다. `railway ssh`는 실제로 배포된
컨테이너 안에서 실행되니 접근 가능하다.)

## 더 볼 문서

- `AGENTS.md` — 이 저장소에서 작업하는 코딩 에이전트를 위한 아키텍처/컨벤션 가이드.
- `CLAUDE.md` — DEV/HQ 저장소 구조, 커리큘럼 저장소와의 handoff 워크플로우, 환경별
  주의사항(직접 겪고 정리한 것들).
- `docs/internal/` — 다상품 콘텐츠 플랫폼 설계 문서
  (`content_platform_audit.md`, `content_platform_design.md`).
