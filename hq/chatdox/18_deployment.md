# 18. 배포 (Railway / Render)

> 로컬에서 완성한 Chatdox 플랫폼을 인터넷에 공개합니다.
> Railway를 사용해 Rails 앱을 배포하고,
> 환경 변수와 데이터베이스를 프로덕션 환경에 맞게 설정합니다.

---

## 📋 목표

1. **Railway** 배포 환경 이해
2. **환경 변수** 설정
3. **PostgreSQL** 프로덕션 DB 연결
4. **배포 & 검증**

---

## 1️⃣ Railway란?

### 개념

```
Railway = 클라우드 호스팅 플랫폼

GitHub 저장소를 연결하면:
  1. 코드 자동 감지 (Rails, Node, Python 등)
  2. 빌드 & 배포 자동 실행
  3. git push 할 때마다 자동 재배포
```

### Railway 핵심 구성요소

| 구성요소 | 설명 | 예시 |
|---------|------|------|
| **Project** | 앱 전체 묶음 | chatdox-platform |
| **Service** | 앱 하나 (GitHub 연결) | Rails 앱 |
| **Database** | 관리형 DB | PostgreSQL |
| **Variables** | 환경 변수 저장소 | SECRET_KEY_BASE |
| **Domain** | 외부 접근 URL | chatdox.up.railway.app |

### 왜 Railway인가?

| 서비스 | 특징 | 요금 |
|--------|------|------|
| **Railway** | Rails 자동 감지, PostgreSQL 통합, 간단 설정 | 월 $5 크레딧 (무료 시작) |
| Render | 무료 플랜, 슬립 모드 문제 (15분 비활성 시 절전) | 무료 (느림) |
| Fly.io | Docker 기반, 학습 곡선 있음 | 무료 |
| Heroku | 유명하지만 2022년 무료 플랜 폐지 | 유료만 |

**→ Chatdox는 Railway 사용** (Rails 자동 감지, PostgreSQL 통합 간편)

### Railway 요금 이해

```
Hobby Plan: 월 $5 고정
  - 포함: $5 크레딧
  - Rails 앱 + PostgreSQL 합산 사용량
  - 소규모 프로젝트는 $5 이내로 운영 가능

사용량 예시 (소규모):
  - Rails 앱: ~$2/월
  - PostgreSQL: ~$1/월
  - 합계: ~$3/월 → $5 크레딧 내 처리
```

---

## 2️⃣ 배포 전 준비

### 로컬 확인

```bash
# 현재 상태 확인
rails s  # localhost:3000 정상 동작 확인

# Git 상태 깨끗한지 확인
git status  # nothing to commit
```

### Gemfile 확인

```ruby
# Gemfile

# 프로덕션 DB는 PostgreSQL
gem "pg", "~> 1.1"  # 없으면 추가

# 프로덕션 자산 압축
gem "bootsnap", require: false
```

```bash
bundle install
```

### database.yml 확인

```yaml
# config/database.yml

default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  <<: *default
  database: db/development.sqlite3

# 프로덕션은 환경 변수 DATABASE_URL 사용
production:
  adapter: postgresql
  url: <%= ENV["DATABASE_URL"] %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

### Procfile 생성

```bash
# 프로젝트 루트에 Procfile 생성
echo "web: bundle exec puma -C config/puma.rb" > Procfile
```

---

## 3️⃣ Railway 배포

### 1단계: Railway 가입 & 프로젝트 생성

```
1. railway.app 접속
2. GitHub 계정으로 로그인
3. "New Project" 클릭
4. "Deploy from GitHub repo" 선택
5. chatdox-platform 저장소 선택
```

### 2단계: PostgreSQL 추가

```
Railway 대시보드에서:
1. "+ New" 클릭
2. "Database" → "Add PostgreSQL" 선택
3. 자동으로 DATABASE_URL 환경 변수 설정됨
```

### 3단계: 환경 변수 설정

**Railway가 자동으로 설정하는 변수 (8개):**

```
DATABASE_URL     = (PostgreSQL 연결 정보 자동 생성)
RAILS_ENV        = production
SECRET_KEY_BASE  = (자동 생성)
RAILS_LOG_TO_STDOUT = true
... (기타 4개 자동 설정)
```

**수동으로 추가해야 할 변수:**

Railway 대시보드 → web Service → Variables 탭 → "Add Variable" 버튼:

```
RAILS_MASTER_KEY = (config/master.key 파일 내용 복사)
```

**RAILS_MASTER_KEY 확인하는 방법:**

```bash
# 로컬 터미널에서
cat config/master.key
# 출력된 내용을 복사해서 Railway Variables에 붙여넣기
```

### 4단계: Deploy 버튼 클릭

```
Railway 대시보드 → web Service:
1. 화면 우측 상단에 Purple "Deploy" 버튼 확인
2. 클릭하면 배포 시작
3. "Deployments" 탭에서 상태 모니터링

배포 프로세스 (자동 실행):
  ✅ GitHub 코드 다운로드
  ✅ bundle install 실행
  ✅ assets:precompile 실행
  ✅ Puma 서버 시작
  ⏳ rails db:migrate는 아직 실행 안 됨 (다음 단계에서)
```

---

## 4️⃣ 배포 후 작업 (필수!)

### ⚠️ DB Migration 실행 (필수)

**왜 필수인가?**
- Deploy 버튼은 앱만 시작하고 DB 테이블 생성은 안 함
- Migration을 실행해야 users, subscriptions 등 테이블이 생성됨
- 이 단계를 건너뛰면 `/docs` 페이지 정상 작동 확인 불가

**방법 1: Railway 대시보드 Console 사용 (권장)**

```
Railway 대시보드 → web Service → Console 탭
1. "Create new command" 클릭
2. 입력: rails db:migrate
3. "Run" 클릭
4. 로그에서 완료 확인
```

**방법 2: Railway CLI 사용**

```bash
# 로컬 터미널에서
railway run rails db:migrate
```

### 도메인 확인

```
Railway 대시보드 → web Service → Settings → Networking
1. "Public Networking" 섹션에서 자동 도메인 확인
   예: web-production-50f0e.up.railway.app
2. (선택) "+ Custom Domain" 버튼으로 커스텀 도메인 연결
```

**도메인으로 접속:**
```
https://web-production-50f0e.up.railway.app
또는
https://web-production-50f0e.up.railway.app/docs
```

### ⚠️ 최초 관리자(Admin) 계정 설정 (필수)

**왜 당황하게 되는가?**

```
배포 직후 DB는 완전히 비어있다 (유저 0명)
  ↓
서비스를 만든 사람이 제일 먼저 회원가입한다
  ↓
회원가입은 기본적으로 일반 유저(role: user)로 생성된다
  ↓
관리자 대시보드나 서비스데스크 같은 admin 전용 기능이 필요해지는 순간
  → 방금 가입한 "1번 유저"인데도 접근이 막힌다
```

즉 배포 흐름 어디에도 "관리자를 자동으로 만들어주는" 단계가 없습니다 — 회원가입 폼만으로는 admin이 될 수 없고, 최초 1명은 반드시 수동으로 승격시켜야 합니다.

**어드민 판정 방식**

`User` 모델은 `role`이라는 enum 컬럼으로 admin 여부를 구분합니다.

```ruby
# app/models/user.rb
enum :role, { user: 0, admin: 1 }
```

**Railway 프로덕션에서 승격시키는 방법**

Railway 대시보드 → web Service → Console 탭에서 `rails console`을 실행하거나, 로컬에서 Railway CLI로 접속합니다.

```bash
# 로컬 터미널에서 (Railway CLI 설치 + railway login + railway link 선행 필요)
railway run bin/rails console
```

콘솔 진입 후:

```ruby
# 이메일로 찾는 방법 (권장 — "몇 번째로 가입했는지" 착각할 위험이 없다)
User.find_by(email: "본인이 가입한 이메일").update!(role: :admin)

# 정말로 배포 후 첫 가입자라고 확신할 때만 (ID 기준)
User.find(1).update!(role: :admin)
```

**주의**

- 이 작업은 배포마다, 그리고 관리자를 새로 추가할 때마다 반복해야 하는 수동 절차입니다 — 시딩 스크립트나 초대 코드로 자동화하는 것은 이 프로젝트의 범위 밖입니다(운영 정책이 확정되면 별도 검토).
- `railway run`은 로컬에서 실행되지만 프로덕션 `DATABASE_URL` 등 환경 변수를 그대로 물려받으므로, **실제 프로덕션 DB가 바뀝니다** — 테스트 계정이 아니라 정확한 이메일인지 반드시 확인 후 실행합니다.

### ⚠️ 이메일 발송 설정 (필수) — 비밀번호 재설정 등

**왜 필요한가?**

```
배포 직후엔 회원가입/로그인은 잘 된다
  ↓
그런데 누군가 비밀번호를 잊어버린다
  ↓
"비밀번호를 잊으셨나요?" 화면에서 이메일을 입력한다
  ↓
화면엔 "이메일을 확인해 주세요"라고 성공 메시지가 뜬다
  ↓
그런데 메일함엔 아무것도 안 온다
```

Rails(정확히는 이 프로젝트가 쓰는 Devise 인증 라이브러리)는 이메일 발송 "기능" 자체는 이미 갖고 있습니다. 다만 "어느 서버를 통해 실제로 메일을 내보낼지"는 직접 설정해줘야 합니다. 이 설정이 없으면 코드는 정상적으로 동작한 것처럼 보이지만(에러도 안 남) 실제로는 메일이 한 통도 안 나갑니다 — 그래서 실제 고객이 겪기 전까지 몇 주고 몇 달이고 아무도 모르고 지나갈 수 있는 종류의 문제입니다.

**이 단계는 AI 에이전트가 대신 해줄 수 없습니다.** 도메인을 실제로 소유한 사람만 그 도메인의 DNS 설정을 바꿀 수 있고, 이메일 발송 서비스의 API 키도 계정 소유자만 발급받을 수 있기 때문입니다. 여기서부터는 직접 콘솔을 열고 손으로 진행합니다.

**왜 Gmail 같은 개인 계정으로 자동 발송하면 안 되는가?**

개인 이메일 계정은 자동화된 대량 발송에 최적화돼 있지 않습니다. 스팸으로 분류되기 쉽고, 발송 계정이 막힐 위험도 있습니다. Resend 같은 "트랜잭션 이메일" 전문 서비스를 쓰면 도착률이 높고 설정도 비교적 간단합니다.

**1단계: Resend 가입 + 도메인 등록**

```
1. resend.com 접속 후 가입
2. 왼쪽 메뉴 Domains → "Add Domain"
3. 본인이 실제로 소유한 도메인 입력 (예: leedox.kr)
```

> `up.railway.app` 같은, Railway가 제공하는 기본 도메인으로는 이 단계를 진행할 수 없습니다. DNS를 직접 관리할 수 있는 진짜 소유 도메인이 필요합니다.

![Resend Domains 목록 화면](/docs/images/18_resend_domains.png)

**2단계: DNS 레코드 추가 — 도메인 인증**

도메인을 추가하면 Resend가 아래와 비슷한 형태의 레코드 목록을 보여줍니다. 이걸 도메인을 구매한 곳(가비아, 후이즈, Cloudflare 등)의 DNS 관리 화면에 그대로 옮겨 적습니다.

| 타입 | 호스트 | 값 (예시 — 실제 값은 Resend 화면 그대로 복사) |
|---|---|---|
| TXT | @ | `v=spf1 include:amazonses.com ~all` |
| CNAME | resend._domainkey | `resend._domainkey.resend.com` |
| TXT | _dmarc | `v=DMARC1; p=none;` |

![DNS 레코드 추가 화면](/docs/images/18_resend_dns_records.png)

레코드를 추가하고 몇 분에서 몇 시간 정도 기다리면(DNS는 전세계에 전파되는 데 시간이 걸립니다) Resend 화면의 도메인 상태가 "Verified"로 바뀝니다. 아직 "Pending"이어도 당황하지 말고 기다립니다.

**3단계: API 키 발급**

```
Resend 대시보드 → API Keys → "Create API Key"
이름 예: chatdox-production
```

발급된 키는 `re_`로 시작하는 긴 문자열입니다. **이 값은 발급 시점에 딱 한 번만 화면에 보입니다** — 바로 안전한 곳에 복사해둡니다(비밀번호 관리자 등). 나중에 다시 보려고 하면 볼 수 없고, 새로 발급해야 합니다.

![API Key 발급 화면](/docs/images/18_resend_api_key.png)

**4단계: Railway에 환경변수 등록**

Railway 대시보드 → web Service → Variables 탭에서 두 개를 추가합니다.

```
RESEND_API_KEY = re_xxxxxxxxxxxxxxxxxxxx   (3단계에서 발급받은 값)
MAILER_SENDER  = noreply@leedox.kr          (2단계에서 인증한 도메인 기준 발신 주소)
```

**5단계: 실제로 확인하기**

배포된 사이트에서 "비밀번호를 잊으셨나요?" 화면에 실제로 받을 수 있는 이메일 주소를 입력해서 재설정을 요청해봅니다. 몇 분 안에 메일이 도착하면 성공입니다. 메일 안의 링크를 눌러서 실제로 새 비밀번호까지 설정되는지 끝까지 확인합니다.

**주의**

- Variables를 저장했다고 항상 바로 반영되는 건 아닙니다. Deployments 탭에서 저장 직후에 새 배포가 자동으로 돌았는지 확인하고, 안 돌았으면 수동으로 "Redeploy"를 눌러줍니다.
- 발신 주소(`MAILER_SENDER`)는 반드시 2단계에서 인증한 도메인과 일치해야 합니다. 다른 도메인 주소를 쓰면 발송 자체가 거부됩니다.

---

## 5️⃣ 배포 체크리스트

### 배포 전
- [ ] `git status` clean 확인
- [ ] `rails s` 로컬 정상 동작 확인
- [ ] `Gemfile`에 `pg` gem 추가
- [ ] `config/database.yml` 프로덕션 설정 확인
- [ ] `Procfile` 생성
- [ ] GitHub에 최신 코드 push

### Railway 설정
- [ ] Railway 프로젝트 생성
- [ ] GitHub 저장소 연결
- [ ] PostgreSQL 추가 (자동 변수 설정 확인)
- [ ] RAILS_MASTER_KEY 환경 변수 추가
- [ ] Deploy 버튼 클릭
- [ ] Deployments 탭에서 빌드 완료 확인

### 배포 후 검증 (필수)
- [ ] **Console 탭에서 `rails db:migrate` 실행**
- [ ] 사이트 접속 (생성된 도메인)
- [ ] `/docs` 페이지 접속 확인
- [ ] 01-06 챕터 파란색 링크, 07-20 회색 링크 확인
- [ ] 에러 로그 확인 (Deployments → Logs 탭)
- [ ] **회원가입 후 `rails console`에서 첫 관리자 계정 승격** (`role: :admin`)
- [ ] **Resend 도메인 인증 + `RESEND_API_KEY`/`MAILER_SENDER` 등록 후 비밀번호 재설정 이메일 실제 수신 확인**

---

## 6️⃣ 자주 발생하는 에러

### Assets precompile 실패

```bash
# config/environments/production.rb 확인
config.assets.compile = true  # 임시 해결 (개발 단계)
```

### master.key 없음 에러

```
ActionDispatch::Http::MissingKeyError
```

```
해결: RAILS_MASTER_KEY 환경 변수에 config/master.key 내용 입력
(config/master.key는 .gitignore에 포함되어 있어 GitHub에 없음)
```

### Database migration 안 됨

```bash
# Railway 콘솔에서 직접 실행
railway run rails db:migrate RAILS_ENV=production
```

---

## 7️⃣ 배포 후 운영

### 코드 업데이트 배포

```bash
# 로컬에서 개발 후
git add .
git commit -m "feat: ..."
git push origin main
# → Railway 자동 감지 & 재배포 (약 2~3분)
```

### 로그 모니터링

```
Railway 대시보드 → Deployments → Logs
실시간 로그 확인 가능
```

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **환경 변수로 비밀 관리** | SECRET_KEY_BASE, DB URL은 코드에 절대 포함 금지 |
| **master.key는 Git 제외** | .gitignore에 포함 (기본값), Railway 환경 변수로 전달 |
| **DB는 PostgreSQL** | 프로덕션에서 SQLite 사용 금지 |
| **Git push = 배포** | Railway가 자동으로 처리 |

---

## 📚 다음 단계

✅ 배포 완료!

다음에는:
- **19장: 모니터링 & 에러 추적** - Sentry, 로그 관리
- **20장: 런칭 & 운영** - 도메인, SEO, 분석
