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

이 외의 협업 규칙(글쓰기 다듬기, 영어 교정, TOC 커버리지, 비선형 진행, 압축해서 기록 등)은 [`CLAUDE.md`](../CLAUDE.md)의 Standing rules와 [`memory_seed.md`](memory_seed.md)에 정리돼 있다.

---

*새 명령어가 정해질 때마다 이 표에도 한 줄씩 추가한다.*
