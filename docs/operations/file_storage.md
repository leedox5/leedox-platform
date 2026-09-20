# 파일 저장소 운영 가이드 (handoff 0058)

대표 이미지(ProductLine)와 Season 산출물(ContentAsset)은 Active Storage로 저장합니다. production은
**Railway Storage Bucket**(비공개 S3 호환 object storage)을 쓰고, 개발·test는 로컬 디스크를 씁니다.
이 문서는 production 연결·점검·장애 대응 절차입니다. **이 문서와 저장소 어디에도 인증 값은 적지 않습니다.**

## 1. 구조 한 장 요약

| 환경 | Active Storage service | 파일 위치 |
|---|---|---|
| development | `local` (Disk) | `storage/` |
| test | `test` (Disk) | `tmp/storage/` |
| production (`ACTIVE_STORAGE_SERVICE` 미설정) | `local` (Disk) — **재배포 시 사라지는 임시 디스크** | 컨테이너 `/rails/storage` |
| production (`ACTIVE_STORAGE_SERVICE=railway_bucket`) | `railway_bucket` (S3) | Railway Bucket |

- production이 임시 디스크(`local`)를 쓰는 동안에는 **업로드가 거부됩니다**(메시지: "파일 저장소가 아직 영속 저장소(버킷)로 설정되지 않아…"). 파일이 조용히 사라지는 사고를 막는 안전장치입니다. 부팅 로그에도 경고가 남습니다.
- 버킷은 **비공개**입니다. 앱이 게이트(공개 상태·라이선스)를 검사한 뒤 파일을 직접 내려주며, 브라우저에는 버킷 주소도 서명 URL도 나가지 않습니다(Active Storage 기본 라우트는 꺼져 있음). 그래서 저장소를 바꿔도 접근 권한 규칙은 그대로입니다.

## 2. production 연결 절차 (Product Owner)

### 2-1. web 서비스 변수 (이름 — 값은 Railway Bucket의 Credentials를 변수 참조로 연결)

| web 서비스 변수 | 설명 | 대신 인식하는 표준 이름(둘 중 하나만 있으면 됨) |
|---|---|---|
| `STORAGE_BUCKET_NAME` | Bucket 이름 | `AWS_S3_BUCKET_NAME` |
| `STORAGE_BUCKET_ENDPOINT` | S3 endpoint URL | `AWS_ENDPOINT_URL` |
| `STORAGE_BUCKET_REGION` | 리전(없으면 `auto`) | `AWS_DEFAULT_REGION`, `AWS_REGION` |
| `STORAGE_BUCKET_ACCESS_KEY_ID` | 액세스 키 ID | `AWS_ACCESS_KEY_ID` |
| `STORAGE_BUCKET_SECRET_ACCESS_KEY` | 시크릿 키 | `AWS_SECRET_ACCESS_KEY` |
| `STORAGE_BUCKET_FORCE_PATH_STYLE` | (선택) `true`면 path-style 주소 사용 | — |
| **`ACTIVE_STORAGE_SERVICE`** | **`railway_bucket`** — 이 변수가 저장소를 실제로 켭니다 | — |

`STORAGE_BUCKET_*`와 `AWS_*`가 둘 다 있으면 `STORAGE_BUCKET_*`가 우선합니다. Railway Bucket의 Credentials 화면이
보여주는 변수 이름에 맞춰 위 표의 왼쪽(또는 오른쪽) 이름으로 참조를 만들어 주세요.

### 2-2. 켜는 순서

1. Bucket 생성(완료) 후 위 인증 변수 5개를 web 서비스에 연결한다.
2. **마지막에** `ACTIVE_STORAGE_SERVICE=railway_bucket`을 설정한다(변수를 바꾸면 서비스가 자동 재시작됨).
   변수를 빠뜨린 채 서비스만 켜면 업로드/조회가 실패하므로 2-3의 점검으로 바로 확인한다.
3. 아래 2-3 점검이 PASS인지 확인한다.

### 2-3. 켠 직후 점검

```bash
railway ssh --service web -- bin/rails storage:check
```
서비스 종류·버킷 이름·endpoint·리전을 출력하고, 임시 객체를 **업로드 → 존재 확인 → 내려받아 checksum 비교 → 삭제 → 삭제 확인**합니다.
끝에 `RESULT: PASS`가 나와야 합니다(실패하면 종료 코드 1, 실패한 단계 표시). 이 명령은 DB나 실제 파일을 건드리지 않고,
`storage-check/` 경로의 임시 객체 1개만 만들었다 지웁니다. 인증 값은 출력하지 않습니다.

### 2-4. 실제 파일로 검증 (HQ 승인 후)

1. 관리자 화면에서 **테스트 제품의 테스트 편**에 작은 파일과 대표 이미지를 올린다(실제 제품에 올리지 않는다).
2. 고객 화면 다운로드·대표 이미지가 정상인지 확인하고, 파일의 checksum이 원본과 같은지 대조한다.
3. **새 배포(또는 서비스 재시작) 후** 같은 파일이 그대로인지 확인한다:
   ```bash
   railway ssh --service web -- bin/rails storage:audit
   railway ssh --service web -- env CHECKSUM=1 bin/rails storage:audit
   ```
4. 검증이 끝나면 테스트 파일을 관리자 화면의 삭제 버튼으로 지운다(버킷 객체도 즉시 삭제됨).

## 3. 정기 점검 (운영자)

```bash
railway ssh --service web -- bin/rails storage:audit               # 파일 존재 확인
railway ssh --service web -- env CHECKSUM=1 bin/rails storage:audit   # + 내용(checksum) 검증, 파일이 많으면 오래 걸림
```

| 출력 | 뜻 | 조치 |
|---|---|---|
| `missing files: N` + 목록 | DB에는 기록이 있는데 저장소에 파일이 없음. 종료 코드 1 | 해당 파일을 관리자 화면에서 다시 올리거나(교체), 원본 보관본으로 복구. 고객에게는 404로 보임 |
| `checksum mismatches: N` | 저장된 파일 내용이 기록과 다름(손상). 종료 코드 1 | 원본으로 교체 업로드 |
| `orphan objects: N` + 키 목록 | 저장소에 있지만 DB 기록이 없는 객체(삭제 실패 등의 잔여물) | 자동 삭제하지 않음. 확인 후 필요하면 버킷에서 직접 정리 |

`storage:audit`은 읽기 전용입니다(아무것도 삭제·수정하지 않음).

## 4. 장애 시 동작과 대응

| 상황 | 고객 화면 | 관리자 화면 | 조치 |
|---|---|---|---|
| 저장소(버킷) 일시 장애·인증 오류 | 다운로드·이미지가 **503**("잠시 후 다시 시도")과 `Retry-After` | 업로드 시 "저장소에 일시적인 문제" 메시지, **아무것도 저장되지 않음**(기존 파일 그대로) | `storage:check`로 원인 확인, 변수·Bucket 상태 점검 |
| 저장소에서 파일이 사라짐 | **404**("파일을 찾을 수 없습니다") | 다운로드 404 | `storage:audit`로 목록 확인 후 재업로드 |
| 삭제 중 저장소 장애 | 영향 없음 | 삭제는 성공 처리, 로그에 `[storage] blob purge failed` | `storage:audit`의 orphan 목록으로 잔여물 확인 |

업로드는 **DB 저장과 같은 트랜잭션 안에서** 저장소에 올립니다. 올리기가 실패하면 DB 변경도 함께 취소되므로 "기록만 있고
파일은 없는" 상태가 생기지 않습니다. 파일 삭제(교체·삭제 시 이전 파일)는 작업 큐를 거치지 않고 즉시 실행합니다(큐 DB는
재배포 때 초기화되므로 큐에 의존하면 삭제가 유실돼 버킷에 잔여물이 남을 수 있음).

## 5. 롤백

`ACTIVE_STORAGE_SERVICE` 변수를 지우면(재시작 후) production은 다시 임시 디스크(`local`)로 돌아가고 **업로드가 거부**됩니다.
**주의:** 버킷을 쓰는 동안 올린 파일은 버킷에만 있으므로, 롤백하면 그 파일의 DB 기록은 남지만 앱이 파일을 못 읽어
404가 됩니다(파일 자체는 버킷에 남아 있어 다시 켜면 복구됨). 파일을 올린 뒤에는 롤백하지 말고 변수/버킷 문제를 고치는 쪽을 권합니다.

## 6. 키 교체

Railway에서 Bucket 인증 정보를 새로 발급하고 web 서비스 변수 참조를 갱신하면 서비스가 재시작됩니다. 이후
`bin/rails storage:check`가 PASS인지 확인합니다. 저장소 코드·이 문서에는 키가 없으므로 코드 변경은 필요 없습니다.

## 7. 개발자 메모

- 설정: `config/storage.yml`의 `railway_bucket`, `config/environments/production.rb`의 `ACTIVE_STORAGE_SERVICE`.
- 임시 디스크 업로드 거부: `StoragePersistence`. 장애 분류: `StorageFailures`. 점검 도구: `StorageVerifier`(`lib/tasks/storage.rake`).
- 업로드를 커밋 전에 실행: `UploadsBeforeCommit`(모델에 `has_one_attached` 다음 줄에 include).
- 테스트는 메모리 안의 가짜 S3 버킷(`test/support/fake_bucket.rb`)으로 실제 Active Storage S3 코드 경로를 검증합니다. 실제 Railway
  Bucket에 대한 검증은 위 2-3, 2-4 절차로 production에서만 가능합니다.
