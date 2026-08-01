# 6. Database & Migrations

> Rails의 데이터베이스 설계와 Migration 시스템을 이해합니다.
> Chatdox 플랫폼의 핵심 테이블을 직접 만들어봅니다.

---

## 📋 목표

1. **Migration** 개념 이해
2. **Schema** 설계 방법
3. **Chatdox 핵심 테이블** 생성
4. **Active Record** 로 데이터 조작
5. **Seeding**으로 초기 데이터 심기

---

## 1️⃣ Migration이란?

### 개념

```
Migration = 데이터베이스 변경 이력서

코드로 DB 스키마를 관리합니다.
- 테이블 추가/삭제
- 컬럼 추가/수정/삭제
- 인덱스 설정
```

### 왜 Migration을 사용하나?

| 방법 | 문제점 |
|------|--------|
| DB에 직접 수정 | 팀원과 공유 불가, 이력 없음 |
| SQL 파일 공유 | 순서 관리 어려움, 충돌 위험 |
| **Migration** | ✅ 코드로 관리, Git으로 공유, 순서 보장 |

---

## 2️⃣ Migration 기본 사용법

### 생성

```bash
# 모델 + Migration 동시 생성
rails generate model User email:string name:string

# Migration만 생성 (테이블 변경용)
rails generate migration AddPhoneToUsers phone:string
```

### 실행

```bash
rails db:migrate          # 미적용 Migration 실행
rails db:rollback         # 마지막 Migration 취소
rails db:migrate:status   # 적용 상태 확인
```

### 파일 구조

```
db/
├── migrate/
│   ├── 20260709000001_create_users.rb
│   ├── 20260709000002_create_subscriptions.rb
│   └── 20260709000003_add_phone_to_users.rb
└── schema.rb              # 현재 DB 상태 (자동 생성)
```

---

## 3️⃣ Chatdox 핵심 테이블 설계

### ERD (Entity Relationship Diagram)

```
users
  id, email, name, password_digest
  created_at, updated_at
    |
    | has_one
    ↓
subscriptions
  id, user_id, plan_type, status
  started_at, expires_at
  created_at, updated_at
```

---

## 4️⃣ users 테이블

### Migration 파일

```ruby
# db/migrate/20260709000001_create_users.rb

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string  :email,           null: false
      t.string  :name,            null: false
      t.string  :password_digest, null: false

      t.timestamps  # created_at, updated_at 자동 추가
    end

    add_index :users, :email, unique: true  # 이메일 중복 방지
  end
end
```

### 생성 명령어

```bash
rails generate model User email:string:index name:string password_digest:string
rails db:migrate
```

### User 모델

```ruby
# app/models/user.rb

class User < ApplicationRecord
  has_secure_password  # password_digest 자동 처리

  has_one :subscription, dependent: :destroy

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name,  presence: true
end
```

---

## 5️⃣ subscriptions 테이블

### Migration 파일

```ruby
# db/migrate/20260709000002_create_subscriptions.rb

class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user,      null: false, foreign_key: true
      t.string     :plan_type, null: false, default: "free"
      t.string     :status,    null: false, default: "active"
      t.datetime   :started_at
      t.datetime   :expires_at

      t.timestamps
    end
  end
end
```

### 생성 명령어

```bash
rails generate model Subscription user:references plan_type:string status:string started_at:datetime expires_at:datetime
rails db:migrate
```

### Subscription 모델

```ruby
# app/models/subscription.rb

class Subscription < ApplicationRecord
  belongs_to :user

  PLANS = %w[free basic premium].freeze

  validates :plan_type, inclusion: { in: PLANS }
  validates :status,    inclusion: { in: %w[active inactive cancelled] }

  def active?
    status == "active"
  end

  def premium?
    plan_type == "premium"
  end
end
```

---

## 6️⃣ 컬럼 추가 (Migration 변경)

기존 테이블에 컬럼을 추가할 때:

```bash
# Migration 파일 생성
rails generate migration AddAvatarToUsers avatar_url:string
```

```ruby
# db/migrate/20260709000004_add_avatar_to_users.rb

class AddAvatarToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :avatar_url, :string
  end
end
```

```bash
rails db:migrate
```

---

## 7️⃣ Active Record CRUD

### Create (생성)

```ruby
# Rails Console에서
user = User.create!(
  email: "test@chatdox.com",
  name: "테스터",
  password: "password123"
)
```

### Read (조회)

```ruby
User.all                          # 전체 조회
User.find(1)                      # ID로 조회
User.find_by(email: "test@...")   # 조건 조회
User.where(name: "테스터")         # 복수 조회
```

### Update (수정)

```ruby
user = User.find(1)
user.update!(name: "새이름")
```

### Delete (삭제)

```ruby
user = User.find(1)
user.destroy
```

---

## 8️⃣ Schema 확인

Migration 실행 후 `db/schema.rb`가 자동 업데이트됩니다:

```ruby
# db/schema.rb (자동 생성, 수동 수정 금지)

ActiveRecord::Schema[8.1].define(version: 2026_07_09_000002) do
  create_table "users", force: :cascade do |t|
    t.string   "email",           null: false
    t.string   "name",            null: false
    t.string   "password_digest", null: false
    t.datetime "created_at",      null: false
    t.datetime "updated_at",      null: false
    t.index    ["email"],         unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer  "user_id",    null: false
    t.string   "plan_type",  default: "free"
    t.string   "status",     default: "active"
    t.datetime "started_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index    ["user_id"]
  end
end
```

---

## 9️⃣ Seeding — 초기 데이터 심기

### Migration과 Seeding의 차이

Migration이 데이터베이스의 **그릇을 만드는 작업**(테이블/컬럼/인덱스)이라면, Seeding은 그 그릇에 **서비스가 정상 동작하기 위해 필요한 초기 데이터를 채우는 작업**이다.

| 구분 | 역할 | 예 |
|------|------|------|
| **Migration** | 구조 생성/변경 | `products` 테이블 생성 |
| **Seeding** | 초기 데이터 입력 | Chatdox 상품 1개, 오퍼 4개 등록 |

시딩 코드는 `db/seeds.rb`에 작성하고, 다음 명령으로 실행한다.

```bash
bin/rails db:seed
```

### 실전 예시 — Chatdox 상품 카탈로그 시딩

Chatdox는 판매할 상품(Product)과 기간별 가격 옵션(ProductOffer)을 서비스 시작 전에 반드시 심어둬야 한다. `db/seeds.rb`는 이렇게 한 줄이다.

```ruby
# db/seeds.rb
Commerce::CatalogBootstrap.call!
```

실제 로직은 `app/services/commerce/catalog_bootstrap.rb`에 있다.

```ruby
module Commerce
  class CatalogBootstrap
    PRODUCTS = {
      "chatdox" => "Chatdox",
      "claudox" => "Claudox"
    }.freeze

    CHATDOX_OFFERS = [
      { code: "chatdox-1m-v1", version: 1, duration_months: 1,
        supply_amount: 7_000, vat_amount: 700, total_amount: 7_700, discount_bps: 0 },
      { code: "chatdox-3m-v1", version: 1, duration_months: 3,
        supply_amount: 21_000, vat_amount: 2_100, total_amount: 23_100, discount_bps: 0 },
      # ... 6개월, 12개월 오퍼도 동일한 형태로 이어짐
    ].freeze

    def self.call!
      ApplicationRecord.transaction do
        products = PRODUCTS.to_h do |code, name|
          product = Product.find_or_create_by!(code: code) do |record|
            record.name = name
            record.active = true
            record.sale_enabled = false   # 시딩은 "등록"만, 판매 스위치는 별도!
          end
          [ code, product ]
        end

        CHATDOX_OFFERS.each do |attributes|
          ProductOffer.find_or_create_by!(code: attributes.fetch(:code)) do |offer|
            offer.assign_attributes(
              attributes.merge(product: products.fetch("chatdox"), currency: "KRW", active: true)
            )
          end
        end

        products
      end
    end
  end
end
```

### 멱등성(Idempotency) — 왜 `find_or_create_by!`인가

운영용 시딩 코드는 **여러 번 실행돼도 안전**해야 한다. 이걸 멱등성(Idempotency)이라고 부른다.

```ruby
# ❌ 위험: 실행할 때마다 중복 생성됨
Product.create!(code: "chatdox", name: "Chatdox")

# ✅ 안전: 이미 있으면 그대로 두고, 없으면 생성
Product.find_or_create_by!(code: "chatdox") do |record|
  record.name = "Chatdox"
end
```

`CatalogBootstrap`이 전부 `find_or_create_by!`로 짜여있는 이유가 이거다 — 배포 파이프라인이나 관리자가 실수로 `db:seed`를 두 번 돌려도 상품이 2개, 4개로 불어나지 않는다.

### 실전 팁 — 운영 환경에서 처음 시딩하기

새로 배포한 운영 환경(Railway 등)엔 이 초기 데이터가 아예 없는 경우가 있다. 이럴 땐 서버 콘솔에서 직접 한 번 실행해줘야 한다.

> Railway 대시보드 → `web` 서비스 → **Console** 탭 →
> ```
> bin/rails db:seed
> ```

`find_or_create_by!` 기반이라 몇 번을 눌러도 안전하다. 다만 시딩이 만드는 건 "데이터의 존재"일 뿐, `sale_enabled` 같은 운영 스위치는 그대로 꺼진 채로 생성된다는 점은 기억해두자 — 판매를 실제로 켜는 건 별도의 관리자 조작(11장 참고)이다.

### 운영 시딩과 개발용 샘플 데이터 구분

개발 중 화면 테스트용으로 대량의 가짜 데이터를 만들고 싶을 수 있다. 이런 건 반드시 환경을 구분해서 운영 DB에 섞이지 않게 한다.

```ruby
# db/seeds.rb
Commerce::CatalogBootstrap.call!   # 모든 환경에 필요한 필수 데이터

if Rails.env.development?
  10.times do |i|
    User.create!(email: "user#{i}@example.com", password: "password")
  end
end
```

---

## 🔟 실전 체크리스트

### 새 테이블 추가 시
- [ ] `rails generate model ModelName ...` 실행
- [ ] Migration 파일 내용 확인 (null: false, default 등)
- [ ] `rails db:migrate` 실행
- [ ] `db/schema.rb` 변경 확인
- [ ] Model validation 추가

### 기존 테이블 변경 시
- [ ] `rails generate migration DescriptiveName ...` 실행
- [ ] Migration 파일 확인
- [ ] `rails db:migrate` 실행
- [ ] **절대 schema.rb 직접 수정 금지!**

### 새 환경에 시딩할 때
- [ ] `db/seeds.rb`의 시딩 코드가 `find_or_create_by!` 등으로 멱등성을 갖추고 있는지 확인
- [ ] `bin/rails db:seed` 실행(운영 콘솔 포함, 여러 번 실행해도 안전한지 재확인)
- [ ] 개발용 샘플 데이터가 `Rails.env.development?` 등으로 운영과 분리돼 있는지 확인
- [ ] 시딩은 "데이터 등록"까지다 — 판매/노출 같은 운영 스위치는 시딩과 별개로 켜야 한다

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **Migration으로만 변경** | DB를 직접 수정하지 않는다 |
| **null: false 기본값** | 필수 컬럼은 null 허용 안 함 |
| **인덱스 설정** | 자주 조회하는 컬럼에 index 추가 |
| **schema.rb는 자동** | 수동 수정 절대 금지 |
| **시딩은 멱등성 있게** | `find_or_create_by!`로 몇 번을 실행해도 안전하게 |

---

## 📚 다음 단계

✅ 이제 데이터베이스 설계를 이해했습니다!

다음에는:
- **07장: Authentication with Devise** - 회원가입/로그인
- **08장: Authorization** - 접근 권한 제어
