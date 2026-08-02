# CLAUDE.md

이 파일은 이 프로젝트에서 반복적으로 필요한 맥락(환경 특이사항, 작업 규칙, 아키텍처 결정, 겪은 실수와 교훈)을 담는다. 세션이 새로 열릴 때마다 가장 먼저 읽을 것.

**이 문서의 규칙이 실제로 적용되는 순간(예: request.md를 곧이곧대로 믿지 않고 추가로 grep한다, 마이그레이션 후 Railway 실행을 상기시킨다 등)에는 조용히 그냥 하지 말고, 대화에서 "CLAUDE.md 규칙에 따라 ~" 식으로 명시적으로 언급할 것.**

## 프로젝트 구조: DEV / HQ

- 이 저장소(`chatdox-platform`)는 **DEV** — 실제 코드가 사는 곳.
- 커리큘럼/handoff 저장소는 **HQ** (`chatdox-curriculum`). 이 WSL 환경에서는 `/mnt/d/RubyOnRails/chatdox-curriculum`에 마운트되어 있다.
- **이 저장소(chatdox-platform) 자체도 체크아웃이 두 곳이다 — 역할이 다르다.**
  - `~/dev/chatdox-platform`(WSL 네이티브) — **여기가 진짜 DEV**. Linux 환경에서 실제로 웹을 구동하며 개발이 이뤄지는 곳. 지금 이 세션이 작업하는 곳도 여기.
  - `/mnt/d/RubyOnRails/chatdox-platform`(Windows) — **HQ가 DEV 코드를 참조용으로 체크아웃해둔 것.** 작업하는 곳이 아니라 "커리큘럼 쓸 때 실제 코드가 어떻게 생겼는지 확인하는" 용도. 2026-07-16에 HQ 쪽 에이전트가 실수로 여기에 직접 커밋(`e43e689`, CLAUDE.md 피드백)해서 origin에 올라간 적이 있다 — 이건 정상 흐름이 아니라 사고였고, Tommy가 이것 자체를 "AI 실수" 콘텐츠 소재로 올릴 예정이다.
  - 둘 다 같은 origin(`github.com/leedox5/chatdox-platform`)을 보므로, 커밋 히스토리가 안 맞는 것 같으면 먼저 `git fetch origin`으로 이쪽이 뒤처진 건 아닌지 확인할 것. D: 드라이브 쪽은 참조 전용이라 원래 커밋이 발생할 일이 없는 곳이니, 직접 건드리지 않고 origin을 통해서만 간접적으로 주고받는다.
- **`script/`에 HQ 연동 스크립트 3개가 있다 — 이름이 서로 안 비슷하니 매번 `ls script/`로 전체를 확인하고 얘기할 것, 하나만 보고 "이 방향은 스크립트가 없다"고 단정하지 말 것(2026-07-16 실수).**
  - `sync_handoff.sh` — HQ→DEV, handoff 패키지(request/result/STATUS) 전체 미러.
  - `push_handoff_to_curriculum.sh` — DEV→HQ, handoff 패키지 하나를 HQ inbox로 push.
  - `sync_curriculum.sh` — HQ→DEV, handoff와 무관하게 **실제 런타임 콘텐츠**(커리큘럼 문서/claudox/service-desk 요청)를 HQ git 저장소에서 `git archive`로 스냅샷 떠서 `hq/`(git 추적됨, `.local/`이 아님) 아래로 미러. REQ 0022에서 git subtree pull을 대체한 것 — subtree는 HQ 저장소 전체(QA/, SETUP/ 등 안 쓰는 것까지)를 끌어오고 merge conflict가 잦아서, 실제 쓰는 3개 폴더만 골라 받는 방식으로 바꿨다.
- Handoff 작업 흐름:
  1. HQ가 `.local/handoff/inbox/<package>/request.md`를 만든다.
  2. DEV는 `script/sync_handoff.sh`(`--dry-run`으로 먼저 확인 후 `--mirror`)로 HQ의 `.local/handoff/`를 이 저장소의 `.local/handoff/`로 끌어온다. `--mirror`는 HQ에 없는 로컬 전용 폴더(`outbox/`)까지 지우는 진짜 미러링이므로 실행 전 `--dry-run` 결과를 반드시 확인한다. `outbox/`가 매번 삭제되는 건 정상이다 — HQ는 애초에 `outbox/`를 갖지 않고, 그 폴더는 push 전 임시 스테이징 용도라 pull 시점엔 이미 역할이 끝나 있어야 한다.
  3. 구현 후 결과물(`result.md` 등)을 `.local/handoff/outbox/<package>/`에 채워 넣고, `script/push_handoff_to_curriculum.sh --source .local/handoff/outbox/<package>`(`--dry-run`으로 먼저 확인)로 HQ의 `.local/handoff/inbox/<package>/`에 보낸다. `--source`는 반드시 패키지 하나의 경로여야 한다(outbox 루트 자체를 넘기면 이미 completed로 옮겨진 과거 패키지까지 되살아나 HQ 쪽에 스푸리어스 파일이 생긴다 — 스크립트가 이 실수를 막아준다).
  4. `.local/handoff/inbox/<package>/`에도 같은 `result.md`를 남겨서 로컬 전체 기록(request+result)을 유지한다.
- **"완료(completed)" 판정과 STATUS.md는 HQ의 권한이다.** DEV가 임의로 STATUS.md를 지어내지 말 것. "HQ에서 completed 처리했다"는 말을 들으면 직접 작성하지 말고 `script/sync_handoff.sh --mirror`로 HQ의 실제 사본을 가져올 것.
- `.local/`은 `.gitignore`에 포함되어 커밋되지 않는다 — handoff 패키지, STATUS.md, 참고 정책 문서 등은 전부 로컬 전용이고, git 이력에는 실제 코드/테스트/마이그레이션만 남는다.
- **이 handoff 워크플로우 자체가 아직 시험 운영(trial) 단계다(2026-07-16 Tommy 확인).** 고정된 프로세스로 여기지 말고, 실제로 작업하면서 걸리는 지점이 보이면 매번 그냥 넘어가지 말고 개선 아이디어를 제안할 것. 지금까지 눈에 띈 것:
  - **스크린샷 주석과 서면 request_rN.md 사이에 정보가 누락될 수 있다.** `/chatdox` R2에서 실제로 겪음(Tommy가 스크린샷에 표시한 것 하나가 서면 스펙에서 빠졌다가 R3에서 확정됨). 서면 요청서를 작성할 때 스크린샷의 모든 표시 항목을 명시적으로 나열하면 이런 누락을 줄일 수 있다.
- **DEV→HQ 콘텐츠 제안 채널 승인됨(2026-07-16, HQ/Tommy 확인).** `leedox_dev_content_loop_r1`(`push_handoff_to_curriculum.sh`로 보낸 첫 제안)을 HQ가 검토해서 채널 자체와 소재 3건 전부 승인했다 — `.local/handoff/completed/leedox_dev_content_loop_r1/STATUS.md`(HQ 쪽, 이 WSL 마운트로 `/mnt/d/RubyOnRails/chatdox-curriculum/.local/handoff/completed/`에서 직접 읽을 수 있음)에 결정 근거가 있다. 앞으로도 작업 중 "이건 claudox/ 콘텐츠 소재가 될 만하다" 싶은 순간이 있으면 같은 방식(원재료 요약 + 어울릴 챕터 추측까지만, 산문은 HQ 몫)으로 `leedox_dev_content_*` 이름 규칙을 따라 계속 올릴 것 — 이번 건에서 부수적으로, `push_handoff_to_curriculum.sh`/`sync_handoff.sh` 두 스크립트를 HQ가 "존재하지 않는다"고 잘못 기록했던 것도 이번에 같이 바로잡혔다(HQ의 `service-desk/requests/0023.md` Job 0011 참고).

## 환경 특이사항

- 이 WSL 네이티브 클론에는 headless 브라우저/스크린샷 도구와 sudo가 없다. 스크린샷이 필요한 검증 요청이 오면 먼저 사용자에게 처리 방법을 물어볼 것 — 많은 경우 curl 기반 HTML/텍스트 검증으로 대체 가능하다.
  - 단, "모바일에서 줄바꿈되는지/한 줄에 들어가는지" 같은 실제 픽셀 렌더링 문제는 curl/HTML 비교로 **코드가 의도대로 반영됐는지**만 확인 가능하고, 실제로 맞는지는 확인 불가능하다. `/chatdox` 정합성 작업(2026-07-16, R1~R3)에서 매 라운드 이 한계에 부딪혔고, 결국 Tommy의 실기기 확인 → 후속 라운드 피드백으로 마무리되는 패턴이 반복됐다. 이런 모바일 CSS 핏 이슈를 받으면 "한 번에 완벽히 맞힌다"를 목표로 하지 말고, 처음부터 "최선의 반응형 처리 + 코드 레벨 검증 + Tommy 실기기 확인이 마지막 단계"라는 흐름을 미리 안내하는 게 낫다.
- DB는 SQLite. `bin/rails db:migrate`는 development 환경에만 적용된다 — 테스트가 새 스키마를 보게 하려면 `RAILS_ENV=test bin/rails db:schema:load`를 별도로 실행해야 한다.
- **`git push`로는 코드만 Railway에 자동 배포되고, 마이그레이션은 자동 실행되지 않는다.** 스키마 변경이 있는 작업 뒤에는 배포 후 `railway run bin/rails db:migrate`가 별도로 필요하다는 것을 항상 상기시킬 것(2026-07-16 하루에만 User#name 필드, Subscription 테이블 drop, GitHub access 테이블 drop 세 건 모두 이 문제가 있었다).

## 작업 규칙 (Tommy와의 협업 패턴)

- **모든 작업이 handoff를 타지는 않는다(2026-07-16 Tommy 확인).** 정식 handoff(`request.md`)는 규모가 있거나 HQ 쪽에도 기록이 남아야 하는 작업용이고, 간단한 건 그냥 대화로 바로 요청한다. 대화로 온 요청은 `.local/handoff/`에 억지로 request.md/result.md를 지어내지 말고, 필요하면 커밋 메시지와 이 대화 자체가 기록이 된다 — 정식 handoff 패턴(아래 두 줄)은 실제로 `.local/handoff/inbox/`에 request.md가 있을 때만 적용.
- 작업 요청은 `.local/handoff/inbox/<package>/request.md`로 온다. 문서 맨 끝 "Platform 실행 문구" 섹션이 실제 지시사항.
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
