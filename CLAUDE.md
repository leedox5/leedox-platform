# CLAUDE.md

이 파일은 이 프로젝트에서 반복적으로 필요한 맥락(환경 특이사항, 작업 규칙, 아키텍처 결정, 겪은 실수와 교훈)을 담는다. 세션이 새로 열릴 때마다 가장 먼저 읽을 것.

**이 문서의 규칙이 실제로 적용되는 순간(예: request.md를 곧이곧대로 믿지 않고 추가로 grep한다, 마이그레이션 후 Railway 실행을 상기시킨다 등)에는 조용히 그냥 하지 말고, 대화에서 "CLAUDE.md 규칙에 따라 ~" 식으로 명시적으로 언급할 것.**

## 프로젝트 구조: DEV / HQ

- 이 저장소(`leedox-platform`)는 **DEV** — 실제 코드가 사는 곳.
- 커리큘럼/handoff 저장소는 **HQ** (`leedox-hq`). 경로는 환경마다 다르므로 고정값으로 가정하지 않는다(예: `/mnt/d/dev/leedox-hq`, 과거 환경 `/mnt/d/RubyOnRails/leedox-hq`).
- **이 저장소(leedox-platform) 자체도 체크아웃이 두 곳이다 — 역할이 다르다.**
  - **WSL 네이티브 클론(경로는 데스크탑마다 다르다)이 진짜 DEV** — Linux 환경에서 실제로 웹을 구동하며 개발이 이뤄지는 곳. 고정 경로를 가정하지 말고 현재 세션에서 `pwd`로 실제 작업 경로를 확인할 것. 데스크탑별 확인된 예: `/home/leedox/rails/leedox-platform`, `/home/leedox/dev/leedox-platform`(2026-08-03 확인). 지금 이 세션이 작업하는 곳도 이 WSL 네이티브 클론 중 하나다.
  - `/mnt/d/RubyOnRails/leedox-platform`(Windows) — **HQ가 DEV 코드를 참조용으로 체크아웃해둔 것.** 작업하는 곳이 아니라 "커리큘럼 쓸 때 실제 코드가 어떻게 생겼는지 확인하는" 용도. 2026-07-16에 HQ 쪽 에이전트가 실수로 여기에 직접 커밋(`e43e689`, CLAUDE.md 피드백)해서 origin에 올라간 적이 있다 — 이건 정상 흐름이 아니라 사고였고, Tommy가 이것 자체를 "AI 실수" 콘텐츠 소재로 올릴 예정이다.
  - 둘 다 같은 origin(`github.com/leedox5/leedox-platform`)을 보므로, 커밋 히스토리가 안 맞는 것 같으면 먼저 `git fetch origin`으로 이쪽이 뒤처진 건 아닌지 확인할 것. D: 드라이브 쪽은 참조 전용이라 원래 커밋이 발생할 일이 없는 곳이니, 직접 건드리지 않고 origin을 통해서만 간접적으로 주고받는다.
- **`script/`에 HQ 연동 스크립트 3개가 있다 — 이름이 서로 안 비슷하니 매번 `ls script/`로 전체를 확인하고 얘기할 것, 하나만 보고 "이 방향은 스크립트가 없다"고 단정하지 말 것(2026-07-16 실수).**
  - `sync_handoff.sh` — (Deprecated) `.local/handoff` 미러링용 레거시 스크립트.
  - `push_handoff_to_curriculum.sh` — (Deprecated) `.local/handoff` push용 레거시 스크립트.
  - `sync_curriculum.sh` — HQ→DEV, handoff와 무관하게 **실제 런타임 콘텐츠**(커리큘럼 문서/claudox/service-desk 요청)를 HQ git 저장소에서 `git archive`로 스냅샷 떠서 `hq/`(git 추적됨, `.local/`이 아님) 아래로 미러. REQ 0022에서 git subtree pull을 대체한 것 — subtree는 HQ 저장소 전체(QA/, SETUP/ 등 안 쓰는 것까지)를 끌어오고 merge conflict가 잦아서, 실제 쓰는 3개 폴더만 골라 받는 방식으로 바꿨다.
- Handoff 작업 흐름 (Handoff 2.0):
  1. HQ가 `handoff/<번호_슬러그>/0000.md`를 Source of Truth로 발행한다 (WSL Symlink 0-Copy 실시간 연동 및 Git 이력 영구 보존).
  2. DEV는 `handoff/<번호_슬러그>/0000.md`를 직접 읽는다.
  3. DEV는 같은 패키지 폴더(`handoff/<번호_슬러그>/`)에 `result.md`(리비전은 `result_rN.md`)만 작성한다.
  4. inbox/completed 이동, `STATUS.md` 작성, HQ 저장소 commit/push는 HQ(Tommy) 권한이다.
- **권한 경계:** DEV는 `handoff/<번호_슬러그>/` 패키지 내 `result*.md` 외 HQ 저장소 파일을 수정하지 않는다. HQ 저장소 commit/push도 하지 않는다.
- 기존 `.local/handoff` 기록은 보존 대상이다. 새 절차 도입을 이유로 자동 이동/삭제하지 않는다.
- **`handoff-agy`라는 이름은 존재하지 않는다.** 실제 심링크는 저장소 루트의 `handoff`(→ HQ의 `handoff` 디렉터리) 하나뿐이다(`ls -la`로 실제 이름 확인 가능). 과거 한 세션에서 "Handoff 2.0 process renewal"이라는 커밋(`c486b39`)이 문서 전체를 `handoff-agy/`로 잘못 고쳐놓았던 적이 있다(2026-08-11 발견, 실제 심링크 rename은 없었던 것으로 보임) — 문서에서 `handoff-agy`가 다시 보이면 오탈자이니 `handoff`로 고칠 것.
- **이 handoff 워크플로우 자체가 아직 시험 운영(trial) 단계다(2026-07-16 Tommy 확인).** 고정된 프로세스로 여기지 말고, 실제로 작업하면서 걸리는 지점이 보이면 매번 그냥 넘어가지 말고 개선 아이디어를 제안할 것. 지금까지 눈에 띈 것:
  - **스크린샷 주석과 서면 request_rN.md 사이에 정보가 누락될 수 있다.** `/chatdox` R2에서 실제로 겪음(Tommy가 스크린샷에 표시한 것 하나가 서면 스펙에서 빠졌다가 R3에서 확정됨). 서면 요청서를 작성할 때 스크린샷의 모든 표시 항목을 명시적으로 나열하면 이런 누락을 줄일 수 있다.
- **DEV→HQ 콘텐츠 제안 채널 승인됨(2026-07-16, HQ/Tommy 확인).** `leedox_dev_content_loop_r1`(당시 레거시 `.local/handoff` 절차로 전달)을 HQ가 검토해서 채널 자체와 소재 3건 전부 승인했다. 이후 handoff 운영은 `handoff/` Git 패키지 중심 2.0 체계로 전환되었다.

## 환경 특이사항

- 이 WSL 네이티브 클론에는 headless 브라우저/스크린샷 도구와 sudo가 없다. 스크린샷이 필요한 검증 요청이 오면 먼저 사용자에게 처리 방법을 물어볼 것 — 많은 경우 curl 기반 HTML/텍스트 검증으로 대체 가능하다.
  - 단, "모바일에서 줄바꿈되는지/한 줄에 들어가는지" 같은 실제 픽셀 렌더링 문제는 curl/HTML 비교로 **코드가 의도대로 반영됐는지**만 확인 가능하고, 실제로 맞는지는 확인 불가능하다. `/chatdox` 정합성 작업(2026-07-16, R1~R3)에서 매 라운드 이 한계에 부딪혔고, 결국 Tommy의 실기기 확인 → 후속 라운드 피드백으로 마무리되는 패턴이 반복됐다. 이런 모바일 CSS 핏 이슈를 받으면 "한 번에 완벽히 맞힌다"를 목표로 하지 말고, 처음부터 "최선의 반응형 처리 + 코드 레벨 검증 + Tommy 실기기 확인이 마지막 단계"라는 흐름을 미리 안내하는 게 낫다.
- **개발/테스트 DB는 SQLite, 프로덕션 primary DB는 Postgres다.** `config/database.yml`은 모든 환경에 `adapter: sqlite3`를 적어두고 있지만, 프로덕션에서는 Rails가 `DATABASE_URL` 환경변수를 primary 연결에 우선 적용해서 실제로는 Railway의 Postgres(`postgres.railway.internal`)를 쓴다 — 파일만 읽고 "프로덕션도 SQLite"라고 판단하면 틀린다(2026-08-06 `railway run`으로 `ActiveRecord::Base.configurations`를 직접 조회해 확인). Solid Cache/Queue/Cable(cache/queue/cable 세 역할)은 `DATABASE_URL`의 영향을 안 받아서 프로덕션에서도 여전히 SQLite 파일(`storage/production_*.sqlite3`)이다. `bin/rails db:migrate`는 (로컬) development 환경에만 적용된다 — 테스트가 새 스키마를 보게 하려면 `RAILS_ENV=test bin/rails db:schema:load`를 별도로 실행해야 하고, 프로덕션 Postgres에 반영하려면 배포 후 `railway ssh --service web -- bin/rails db:migrate`가 별도로 필요하다(아래 항목 참고).
- **`git push`로는 코드만 Railway에 자동 배포되고, 마이그레이션은 자동 실행되지 않는다.** 스키마 변경이 있는 작업 뒤에는 배포 후 마이그레이션이 별도로 필요하다는 것을 항상 상기시킬 것(2026-07-16 하루에만 User#name 필드, Subscription 테이블 drop, GitHub access 테이블 drop 세 건 모두 이 문제가 있었다). **`railway run bin/rails db:migrate`는 로컬에서 실패한다** — `postgres.railway.internal` DNS가 Railway 네트워크 안에서만 풀리기 때문. 대신 `railway ssh --service web -- bin/rails db:migrate`(서비스가 여러 개면 `--service web` 필수, 안 붙이면 "Multiple services found" 에러)를 쓸 것 — 0045 R2에서 실제로 이 방식으로 프로덕션 마이그레이션을 성공시켰다.

## 작업 규칙 (Tommy와의 협업 패턴)

- **모든 작업이 handoff를 타지는 않는다(2026-07-16 Tommy 확인).** 정식 handoff가 필요한 경우 현재 기준 문서는 `handoff/<번호_슬러그>/0000.md`다. 간단한 건 대화로 바로 요청할 수 있다.
- handoff 작업 시 DEV는 활성 패키지의 `0000.md`를 기준으로 수행하고, 같은 폴더의 `result*.md`만 작성한다(다른 HQ 파일 수정 금지).
- 구현 후에는 거의 항상 커밋 + push, 그리고 `result.md`로 (조사 결과 / 실제 채택한 설계와 제안 대비 달라진 점 + 이유 / 변경·삭제 파일 / 테스트 결과 / 미결정 사항) 보고하는 게 표준 패턴이다.
- **request.md의 "현재 코드 확인 완료, 재조사 불필요"를 그대로 믿지 말 것.** 실제로 매 작업마다 request.md가 나열하지 않은 관련 참조가 더 있었다(예: Toss/Subscription 제거 때 admin 컨트롤러 4곳 + `Commerce::Reconciliation`/`EventLogger`, GitHub access 단순화 때 `event_recorder.rb`/`task_factory.rb` + `Commerce::Reconciliation`). 삭제·리팩터링 대상 클래스/모델명으로 항상 sitewide grep을 먼저 돌려 숨은 참조를 확인한다.
- "코드량을 최대한 줄이는 것"처럼 명시적 단순화 목표가 있는 작업에서는, 요청서의 제안 설계보다 더 간단한 방법이 보이면 조정해도 되는 재량이 주어진다 — 다만 `result.md`에 무엇을 왜 다르게 했는지 반드시 남긴다.
- 커밋 메시지는 `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`로 끝맺는 관례를 따른다.

## 알게 된 실수와 교훈

- **`git add path1 path2 path3`에서 어느 한 pathspec이라도 안 맞으면(예: 이미 `git rm`으로 지워진 경로를 또 add하려는 경우) 명령 전체가 에러로 실패하고, 나머지 경로들도 스테이징이 안 된다.** 그 상태로 바로 `git commit`을 하면 의도한 파일 중 일부만(혹은 엉뚱한 파일만) 커밋되는데도 에러 메시지를 놓치면 눈치채기 어렵다. 여러 경로를 한 번에 `git add`한 뒤에는 커밋 전에 `git status`/`git diff --cached --stat`으로 실제 스테이징된 게 의도와 맞는지 반드시 확인할 것. (2026-07-16, `markdown_renderer.rb`를 `git rm -f`로 지운 뒤 같은 커밋에 다른 파일 3개를 묶으려다 이 문제로 실제로 잘못된 커밋을 만들었다 — force-push 없이 새 커밋으로 바로잡음.)
- **`has_one` 연관 + `dependent: :restrict_with_error` 상태에서 `owner.build_association(...)`을 이미 연관이 존재하는데 다시 호출하면 `ActiveRecord::RecordNotSaved`가 발생한다** (Rails가 기존 레코드를 "교체"하려다 restrict에 막힘). 존재 여부를 먼저 확인하고, 필요하면 `Model.new(user: owner, ...)`으로 직접 생성해 이 replace 시맨틱 자체를 피할 것. (2026-07-16, GitHub access 단순화 작업 중 수동 curl 검증으로 발견. 흥미롭게도 동일 시나리오의 자동 통합 테스트(`assert_no_difference`)는 이 예외를 잡아내지 못했고 원인은 못 밝혔다 — `bin/rails test` 통과만으로 안심하지 말고 실제 화면 조작을 흉내 낸 수동 검증을 병행할 것.)
- 라우트 헬퍼 이름은 `namespace :admin { namespace :commerce { ... as: :foo } }`이면 `admin_commerce_foo_path`가 된다(네임스페이스 접두사가 지정한 이름 앞에 붙는다) — `foo_admin_commerce_path`처럼 순서를 반대로 짐작해서 쓰면 뷰 렌더링 시점에야 `NoMethodError`로 드러난다. `bin/rails routes`로 실제 이름을 확인하고 쓸 것.
- 마이그레이션에서 테이블을 drop할 때는 그 테이블을 참조하는 FK부터 `remove_foreign_key`로 먼저 제거하고, 여러 테이블이 서로 참조하면 참조받는 쪽이 없어지기 전에 참조하는 쪽부터 순서대로 drop한다(예: `events → tasks → grants`). `drop_table`에 컬럼 정의 블록을 넣어두면 롤백 시 원래 스키마로 복원되는 reversible 마이그레이션이 된다.

## 참고 문서

- `.local/claudox/chatdox_golive_simplification_2026-07-16.md` — Chatdox GoLive 단순화 작업 전체의 배경과 의사결정 근거. Toss/Subscription 제거, GitHub access MVP 단순화, 법무 문서 정합화 같은 관련 작업들이 이 문서를 공통 참조로 삼는다.
