# 07. 인증 (Devise)

> 회원가입, 로그인, 세션 관리를 구현합니다.
> Devise 젬을 사용해 Rails 표준 인증 시스템을 구축합니다.
> 사용자가 안전하게 계정을 생성하고 로그인할 수 있는 기능을 만듭니다.

---

## 📋 목표

1. **인증(Authentication)** 개념 이해
2. **Devise 젬** 설치 & 설정
3. **User 모델** 생성
4. **회원가입 & 로그인** 구현
5. **세션 & 쿠키** 관리
6. **보안** 고려사항 적용

---

## 1️⃣ 인증이란?

### 개념

```
인증(Authentication) = "당신이 진짜 맞나요?"

  ❌ 인증 전
  사용자: "나는 홍길동이야"
  시스템: "그럼 증명해봐 (증거 필요)"

  ✅ 인증 후
  사용자: "여기 비밀번호 있어"
  시스템: "맞네! 로그인 성공"
```

### 인증 vs 인가 (중요!)

| 구분 | 설명 | 예시 |
|------|------|------|
| **인증** | 당신이 누인지 확인 | 로그인 (이메일 + 비밀번호) |
| **인가** | 당신이 무엇을 할 수 있는지 확인 | 어드민만 대시보드 접근 (다음 장) |

---

## 2️⃣ Devise란?

### 개념

```
Devise = Rails 인증 젬 (가장 인기 있음)

기능 제공:
  ✅ 회원가입
  ✅ 로그인/로그아웃
  ✅ 세션 관리 (쿠키 기반)
  ✅ 비밀번호 리셋
  ✅ 이메일 확인
  ✅ 잠금/차단 기능
```

### Devise vs 직접 구현

| 비교 | Devise | 직접 구현 |
|------|--------|----------|
| 개발 시간 | 빠름 (1시간) | 느림 (5시간+) |
| 보안 | 검증됨 (gem 프로덕션 검증) | 실수할 가능성 높음 |
| 유지보수 | 커뮤니티 지원 | 직접 관리 |
| 유연성 | 제한적 (커스터마이징 가능) | 완전 자유 |

**→ Devise 추천** (프로덕션 SaaS)

---

## 3️⃣ Devise 설치 & 설정

### Step 1: Devise 젬 추가

```bash
# Gemfile에 추가
bundle add devise
```

또는 직접 Gemfile 수정:

```ruby
# Gemfile
gem "devise"
```

그 다음:

```bash
bundle install
```

### Step 2: Devise 초기화

```bash
rails generate devise:install
```

**생성되는 파일:**

```
Running via Spring preloader in process 12345
      create  config/initializers/devise.rb
      create  config/locales/devise.en.yml
       ┌─────────────────────────────────────────┐
       │ Devise installation is complete.         │
       │ Run migrations before using devise.      │
       └─────────────────────────────────────────┘
```

**확인할 파일: `config/initializers/devise.rb`**

```ruby
# config/initializers/devise.rb (중요 부분)

Devise.setup do |config|
  # Mailer 설정 (이메일 기능)
  config.mailer_sender = 'please-change-me-at-config-initializers-devise@example.com'

  # ORM 설정 (ActiveRecord 사용)
  require 'devise/orm/active_record'

  # 모듈 설정 (기본값: 충분)
  # config.modules = [:database_authenticatable, :registerable, ...]
end
```

### Step 3: User 모델 생성

Devise에서 User 모델 자동 생성:

```bash
rails generate devise User
```

**생성되는 파일:**

```
      create  app/models/user.rb
      create  config/routes.rb (devise_for :users 추가)
      create  db/migrate/20240101120000_devise_create_users.rb
      create  app/views/devise/...
```

**생성된 User 모델:**

```ruby
# app/models/user.rb

class User < ApplicationRecord
  # Devise 모듈 (기능 추가)
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # associations (나중에 추가)
  has_many :subscriptions
end
```

**Devise 모듈 설명:**

| 모듈 | 기능 |
|------|------|
| `database_authenticatable` | 비밀번호 해싱 & 로그인 |
| `registerable` | 회원가입 가능 |
| `recoverable` | 비밀번호 리셋 |
| `rememberable` | "로그인 상태 유지" |
| `validatable` | 이메일/비밀번호 검증 |

### Step 4: 마이그레이션 실행

```bash
rails db:migrate
```

**생성되는 테이블: users**

```ruby
# schema.rb (자동 생성됨)

create_table :users do |t|
  # 기본 devise 컬럼
  t.string :email, null: false, default: ""
  t.string :encrypted_password, null: false, default: ""
  t.string :reset_password_token
  t.datetime :reset_password_sent_at
  t.datetime :remember_created_at
  
  # 타임스탐프
  t.timestamps
end

# 인덱스
add_index :users, :email, unique: true
add_index :users, :reset_password_token, unique: true
```

---

## 4️⃣ 회원가입 & 로그인 페이지

### Devise가 제공하는 뷰

```bash
# Devise 기본 뷰를 프로젝트에 복사 (커스터마이징용)
rails generate devise:views users
```

**생성되는 뷰:**

```
app/views/devise/
├── registrations/
│   ├── edit.html.erb       (계정 수정)
│   ├── new.html.erb        (회원가입)
│   └── _form.html.erb      (폼 공유)
├── sessions/
│   └── new.html.erb        (로그인)
└── passwords/
    ├── edit.html.erb       (비밀번호 변경)
    └── new.html.erb        (비밀번호 리셋)
```

### 회원가입 페이지 (기본 스타일링)

```erb
<!-- app/views/devise/registrations/new.html.erb -->

<div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
  <div class="bg-white rounded-lg shadow-lg p-8 w-full max-w-md">
    <h1 class="text-3xl font-bold text-center mb-6 text-gray-800">
      회원가입
    </h1>

    <%= form_with(model: resource, local: true) do |form| %>
      <% if resource.errors.any? %>
        <div class="mb-4 p-4 bg-red-50 border border-red-200 rounded">
          <h2 class="text-red-800 font-bold mb-2">
            <%= resource.errors.count %>개 오류 발생:
          </h2>
          <ul class="list-disc list-inside text-red-700">
            <% resource.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <!-- 이메일 입력 -->
      <div class="mb-4">
        <label class="block text-gray-700 font-bold mb-2">
          이메일
        </label>
        <%= form.email_field :email,
          class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500",
          autofocus: true,
          autocomplete: "email",
          required: true
        %>
      </div>

      <!-- 비밀번호 입력 -->
      <div class="mb-4">
        <label class="block text-gray-700 font-bold mb-2">
          비밀번호 (6자 이상)
        </label>
        <%= form.password_field :password,
          class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500",
          autocomplete: "new-password",
          required: true
        %>
      </div>

      <!-- 비밀번호 확인 -->
      <div class="mb-6">
        <label class="block text-gray-700 font-bold mb-2">
          비밀번호 확인
        </label>
        <%= form.password_field :password_confirmation,
          class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500",
          autocomplete: "new-password",
          required: true
        %>
      </div>

      <!-- 회원가입 버튼 -->
      <div class="mb-4">
        <%= form.submit "회원가입",
          class: "w-full bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded-lg transition"
        %>
      </div>
    <% end %>

    <!-- 로그인 링크 -->
    <p class="text-center text-gray-600 text-sm">
      이미 계정이 있나요?
      <%= link_to "로그인", new_user_session_path, class: "text-blue-500 hover:underline font-bold" %>
    </p>
  </div>
</div>
```

### 로그인 페이지

```erb
<!-- app/views/devise/sessions/new.html.erb -->

<div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
  <div class="bg-white rounded-lg shadow-lg p-8 w-full max-w-md">
    <h1 class="text-3xl font-bold text-center mb-6 text-gray-800">
      로그인
    </h1>

    <%= form_with(model: resource, local: true, url: user_session_path) do |form| %>
      <!-- 에러 메시지 -->
      <% if resource.errors.any? %>
        <div class="mb-4 p-4 bg-red-50 border border-red-200 rounded">
          <p class="text-red-800">
            <strong>로그인 실패:</strong>
            이메일 또는 비밀번호가 올바르지 않습니다.
          </p>
        </div>
      <% end %>

      <!-- 이메일 입력 -->
      <div class="mb-4">
        <label class="block text-gray-700 font-bold mb-2">
          이메일
        </label>
        <%= form.email_field :email,
          class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500",
          autofocus: true,
          required: true
        %>
      </div>

      <!-- 비밀번호 입력 -->
      <div class="mb-4">
        <label class="block text-gray-700 font-bold mb-2">
          비밀번호
        </label>
        <%= form.password_field :password,
          class: "w-full px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-500",
          required: true
        %>
      </div>

      <!-- "로그인 상태 유지" 체크박스 -->
      <div class="mb-6">
        <%= form.check_box :remember_me, class: "mr-2" %>
        <label class="text-gray-600">
          로그인 상태 유지
        </label>
      </div>

      <!-- 로그인 버튼 -->
      <div class="mb-4">
        <%= form.submit "로그인",
          class: "w-full bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded-lg transition"
        %>
      </div>
    <% end %>

    <!-- 회원가입/비밀번호 리셋 링크 -->
    <p class="text-center text-gray-600 text-sm mb-2">
      계정이 없나요?
      <%= link_to "회원가입", new_user_registration_path, class: "text-blue-500 hover:underline font-bold" %>
    </p>
    <p class="text-center text-gray-600 text-sm">
      비밀번호를 잊었나요?
      <%= link_to "비밀번호 리셋", new_user_password_path, class: "text-blue-500 hover:underline font-bold" %>
    </p>
  </div>
</div>
```

---

## 5️⃣ 컨트롤러에서 사용자 정보 접근

### 현재 사용자 (current_user)

```ruby
# app/controllers/application_controller.rb

class ApplicationController < ActionController::Base
  before_action :authenticate_user!  # 모든 요청에서 로그인 필수
end
```

### 컨트롤러에서 사용

```ruby
# app/controllers/dashboard_controller.rb

class DashboardController < ApplicationController
  def index
    # 현재 로그인한 사용자
    @user = current_user
    @email = current_user.email
    
    # 사용자 정보 확인
    puts "로그인 사용자: #{current_user.email}"
  end
end
```

### 뷰에서 사용

```erb
<!-- app/views/layouts/application.html.erb -->

<header class="bg-white shadow">
  <div class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
    <h1 class="text-2xl font-bold">채독스</h1>
    
    <nav>
      <% if user_signed_in? %>
        <!-- 로그인한 경우 -->
        <span class="mr-4 text-gray-600">
          <%= current_user.email %>
        </span>
        <%= link_to "로그아웃", destroy_user_session_path, method: :delete, class: "btn btn-red" %>
      <% else %>
        <!-- 로그인 전 -->
        <%= link_to "로그인", new_user_session_path, class: "btn btn-blue" %>
        <%= link_to "회원가입", new_user_registration_path, class: "btn btn-green" %>
      <% end %>
    </nav>
  </div>
</header>
```

---

## 6️⃣ 라우트 확인

### Devise가 자동 생성하는 라우트

```ruby
# config/routes.rb

Rails.application.routes.draw do
  devise_for :users  # 자동으로 생성됨!
  
  root "pages#home"
  get "/docs", to: "docs#index"
  get "/docs/:id", to: "docs#show", as: "doc"
end
```

**생성되는 라우트:**

```bash
# 터미널에서 확인
rails routes | grep devise
```

**결과:**

```
             new_user_session      GET    /users/sign_in
         user_session              POST   /users/sign_in
         destroy_user_session      DELETE /users/sign_out
       new_user_password           GET    /users/password/new
       user_password               POST   /users/password
       new_user_registration       GET    /users/sign_up
       user_registration           POST   /users
   edit_user_registration          GET    /users/edit
       user_registration           PATCH  /users
       user_registration           PUT    /users
       destroy_user_registration   DELETE /users
```

---

## 7️⃣ 보안 (중요!)

### 비밀번호 보안

**Devise 기본 보안:**

```ruby
# app/models/user.rb

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # validates :password, length: { minimum: 6 }  # 자동 (기본값)
  # validates :email, uniqueness: true           # 자동
end
```

Devise는 다음을 자동으로 처리:
- ✅ 비밀번호 암호화 (bcrypt)
- ✅ 이메일 중복 방지
- ✅ 최소 길이 검증 (6자)
- ✅ SQL Injection 방지

### 로그인 필수 페이지

```ruby
# app/controllers/dashboard_controller.rb

class DashboardController < ApplicationController
  before_action :authenticate_user!  # 로그인 필수
  
  def index
    # 로그인한 사용자만 접근 가능
  end
end
```

### CSRF 보안

Devise는 Rails의 기본 CSRF 방어 자동 활용:

```erb
<!-- Rails 폼은 자동으로 CSRF 토큰 포함 -->
<%= form_with(model: resource, local: true) do |form| %>
  <!-- hidden CSRF 토큰 자동 포함됨 -->
<% end %>
```

---

## 8️⃣ 비밀번호 리셋 (이메일)

### Devise 설정

```ruby
# config/initializers/devise.rb

Devise.setup do |config|
  # 이메일 발신자 설정
  config.mailer_sender = 'noreply@chatdox.com'
  
  # 비밀번호 리셋 토큰 만료 시간 (기본: 6시간)
  config.reset_password_within = 6.hours
end
```

### 비밀번호 리셋 프로세스

```
1. 사용자: /users/password/new 방문
2. 입력: 이메일 주소
3. Devise: 리셋 링크 이메일 발송
4. 사용자: 이메일의 링크 클릭
5. Devise: 새 비밀번호 입력 페이지
6. 저장: 비밀번호 업데이트
```

### 개발 환경에서 이메일 테스트

```ruby
# config/environments/development.rb

Rails.application.configure do
  # 이메일 방식: 콘솔 출력
  config.action_mailer.delivery_method = :letter_opener
  
  # 이메일 미리보기
  config.action_mailer.preview_path = "#{Rails.root}/lib/mailers/previews"
end
```

설치:

```bash
bundle add letter_opener
```

---

## 9️⃣ 검증 (테스트)

### 회원가입 테스트

```ruby
# test/integration/devise_test.rb

require "test_helper"

class DeviseTest < ActionDispatch::IntegrationTest
  test "회원가입 성공" do
    # 회원가입 페이지 방문
    get new_user_registration_path
    assert_response :success
    
    # 폼 데이터 제출
    post user_registration_path, params: {
      user: {
        email: "user@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }
    
    # 리다이렉트 확인
    assert_redirected_to root_path
    
    # 사용자 생성 확인
    assert_equal 1, User.count
    assert_equal "user@example.com", User.last.email
  end
  
  test "로그인 성공" do
    # 사용자 생성
    user = User.create!(
      email: "user@example.com",
      password: "password123"
    )
    
    # 로그인
    post user_session_path, params: {
      user: {
        email: "user@example.com",
        password: "password123"
      }
    }
    
    # 리다이렉트 확인
    assert_redirected_to root_path
    
    # 세션에 사용자 ID 저장 확인
    assert_equal user.id, session[:user_id]
  end
end
```

### Rails 콘솔에서 테스트

```bash
rails console

# 사용자 생성
user = User.create(email: 'test@example.com', password: 'password123')
# => #<User id: 1, email: "test@example.com", ...>

# 사용자 확인
User.find_by(email: 'test@example.com')
# => #<User id: 1, ...>

# 비밀번호 검증
user.valid_password?('password123')
# => true

user.valid_password?('wrong')
# => false
```

---

## 💡 실전 사례 — 기본 언어를 한국어로 바꿨더니 벌어진 일

Devise 기본 문구(로그인 성공/실패, 비밀번호 리셋 메일 제목 등)는 전부 영어입니다. 이걸 한국어로 바꾸려고 Rails 앱의 기본 로케일을 한국어로 지정했는데, 그 순간 예상치 못한 곳이 깨질 뻔했습니다.

```ruby
# config/application.rb — 원래 있던 설정
config.i18n.default_locale = :ko
config.i18n.fallbacks = true   # 문제의 원인
```

`fallbacks = true`는 내부적으로 `I18n::Locale::Fallbacks.new(I18n.default_locale)`로 해석됩니다. 즉 "번역이 없으면 기본 로케일로 대체하라"는 뜻인데, 기본 로케일 자체가 `:ko`가 되어버리면 **한국어 번역이 없을 때 한국어로 대체하라**는, 자기 자신을 가리키는 의미 없는 설정이 되어버립니다. 그 결과 `devise.ko.yml`에 없는 키(예: 일반 폼 검증 메시지)를 만나면 "Translation missing"이 화면에 그대로 노출될 뻔했습니다.

```ruby
# config/application.rb — 수정 후
config.i18n.default_locale = :ko
config.i18n.fallbacks = [:en]   # 명시적으로 영어를 폴백으로 지정
```

`fallbacks`를 `true`(암묵적 자기참조) 대신 배열로 명시하면, 한국어 번역이 없는 키는 영어로라도 안전하게 대체됩니다.

> 💡 실전 교훈: `default_locale`을 바꾸는 건 그 로케일 파일 하나만의 문제가 아닙니다. `fallbacks` 같은 다른 i18n 설정이 `default_locale`을 암묵적으로 참조하고 있다면, 함께 재검토해야 합니다.

---

## 🔟 체크리스트

### 준비
- [ ] `bundle add devise` 실행
- [ ] `rails generate devise:install` 실행
- [ ] `config/initializers/devise.rb` 확인

### User 모델
- [ ] `rails generate devise User` 실행
- [ ] `rails db:migrate` 실행
- [ ] `app/models/user.rb` 확인 (devise 모듈 포함)

### 뷰
- [ ] `rails generate devise:views users` 실행 (선택)
- [ ] `app/views/devise/sessions/new.html.erb` 스타일링
- [ ] `app/views/devise/registrations/new.html.erb` 스타일링

### 컨트롤러
- [ ] `current_user` 사용 확인
- [ ] `user_signed_in?` 사용 확인
- [ ] `authenticate_user!` 추가

### 레이아웃
- [ ] 헤더에 로그인/로그아웃 링크 추가
- [ ] 현재 사용자 이메일 표시
- [ ] 네비게이션 바 업데이트

### 테스트
- [ ] 회원가입 페이지 접속 확인
- [ ] 회원가입 성공 확인
- [ ] 로그인 페이지 접속 확인
- [ ] 로그인 성공 확인
- [ ] 로그인한 상태에서 대시보드 접근 확인

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **Devise 사용** | 프로덕션 SaaS는 검증된 gem 사용 |
| **비밀번호 암호화** | 절대 평문 저장 금지 (Devise 자동) |
| **이메일 검증** | 사용자 존재 여부 확인 (다음 단계) |
| **세션 관리** | 쿠키로 자동 관리 (Devise 자동) |
| **로그인 필수** | `before_action :authenticate_user!` |

---

## 📚 다음 단계

✅ 인증 완료! (회원가입, 로그인, 세션)

다음에는:
- **08장: 인가 (Authorization)** - 역할 관리 (Admin, User, etc.)
- **09장: 결제 (Payment)** - Toss Payments / PortOne 선택형 결제 시스템
- **10장: 대시보드** - 사용자 전용 페이지

---

## 🚀 실습 과제

### 1. Devise 설치 (지금 바로)

```bash
bundle add devise
rails generate devise:install
rails generate devise User
rails db:migrate
```

**확인:**

```bash
rails s
# http://localhost:3000/users/sign_up 방문
```

### 2. 회원가입 & 로그인 테스트

```
1. /users/sign_up 방문
2. test@example.com / password123 입력
3. 회원가입 버튼 클릭
4. 자동 로그인 확인
5. 로그아웃 클릭
6. /users/sign_in 방문
7. 다시 로그인
```

### 3. current_user 사용

```erb
<!-- app/views/layouts/application.html.erb -->
<%= current_user.email %>
```

조회:
- 로그인하면 이메일 표시
- 로그아웃하면 "로그인하세요" 표시
