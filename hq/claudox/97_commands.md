# 명령어 모음

Tommy가 짧게 던지는 말들을 Claudox가 어떻게 해석하는지 정리한 참고 문서.

| 명령어 | 의미 |
|---|---|
| `SYNC` | 대기 중인 변경사항을 add → commit → push까지 한 번에 진행한다. 다시 묻지 않는다. |
| 숫자만 (예: `01`, `3`, `19`) | `claudox/NN_slug.md` — 해당 번호의 챕터 파일을 가리킨다. |
| `S01 E01`~`S01 E20` | `docs/NN_....md` — Chatdox 커리큘럼(기술 문서 20장) 챕터. |
| `S02 E01`~`S02 E20` | `claudox/NN_slug.md` — Claudox 서사(협업 스토리 20장) 챕터. 숫자만 표기와 같은 파일을 가리킨다. |
| `GO` | 방금 제안한 작업을 그대로 진행하라는 일반 승인 표현. `SYNC`처럼 고정된 동작은 아니고, 직전 맥락에 달려 있다. |
| `HQ` | `leedox-hq`(이 저장소, 2026-08-03 이전 이름 chatdox-curriculum) — 기획·문서·의사결정이 이뤄지는 쪽. |
| `DEV` | `leedox-platform`(2026-08-03 이전 이름 chatdox-platform) — 실제 코드 구현이 이뤄지는 쪽. |
| `NNNN START` (예: `0050 START`) | 해당 번호로 handoff를 발행하거나, 대기 중인 그 패키지 작업을 시작하라는 뜻. `leedox-handoff` 스킬이 절차를 이끈다. |

## 스킬

2026-08-22부터 handoff 절차는 **`leedox-handoff` 스킬**로 굳혀져 있다(18장 참고). "handoff 발행", "DEV에 넘겨줘", "결과 확인해줘" 같은 말에 자동으로 걸리며, 번호·타임스탬프 실측, 전제 확인 문형, 실행 경계, 뷰어 상태별 기대 결과, 검증·`STATUS.md` 작성까지의 순서를 담고 있다. 스킬은 계정에 저장되므로 이 저장소를 clone해도 따라오지 않는다 — 다른 환경에서 필요하면 18장과 `CLAUDE.md`의 handoff 절을 근거로 다시 만들면 된다.

---

이 외의 협업 규칙(글쓰기 다듬기, 영어 교정, TOC 커버리지, 비선형 진행, 압축해서 기록 등)은 [`CLAUDE.md`](../CLAUDE.md)의 Standing rules와 [`memory_seed.md`](memory_seed.md)에 정리돼 있다.

---

*새 명령어가 정해질 때마다 이 표에도 한 줄씩 추가한다.*
