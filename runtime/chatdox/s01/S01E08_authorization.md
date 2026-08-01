# 08. 권한 (Authorization)

> 사용자의 역할에 따라 접근 권한을 제어합니다.
> Pundit 젬을 사용해 정책 기반 권한 관리를 구현합니다.
> 비로그인, Trial 사용자, 구독자별로 다른 페이지를 보여줍니다.

---

## 📋 목표

1. **인가(Authorization)** 개념 이해
2. **Pundit 젬** 설치 & 설정
3. **Policy 파일** 작성 (역할별 권한)
4. **문서 접근 제어** (1-5장 vs 6-20장)
5. **대시보드 보호** (로그인 필수)
6. **권한 확인** (컨트롤러/뷰)

---

## 1️⃣ 인증 vs 인가

### 개념

```
인증 (Authentication)  = "당신이 누세요?"
  → 로그인으로 증명
  → "test@example.com입니다"

인가 (Authorization)   = "당신이 무엇을 할 수 있어요?"
  → 역할로 제어
  → "admin만 대시보드 접근 가능"
```

### 실제 예시

```
상황: 사용자가 /docs/10 (10장) 접근 시도

1️⃣ 인증 확인
   user_signed_in? → true (로그인함)

2️⃣ 인가 확인
   can_view_chapter?(10) → false (구독자 아님)
   
결과: "이 페이지는 구독자만 볼 수 있습니다" 에러
```

---

## 2️⃣ 권한 정책

### Chatdox 3가지 역할

| 역할 | 상태 | 문서 접근 | 대시보드 | 결제 |
|------|------|---------|---------|------|
| **Guest** | 비로그인 | 1-2장만 | ❌ 불가 | ❌ |
| **User (Trial)** | 로그인 + 7일 이내 | 1-5장 | ✅ 가능 | 💳 필요 |
| **Subscriber** | 유료 구독 중 | 1-20장 전체 | ✅ 가능 | ✅ 관리 |
| **Admin** | 관리자 | 전체 | ✅ 전체 | ✅ 전체 |

### Policy 로직

```ruby
# app/policies/doc_policy.rb

class DocPolicy < ApplicationPolicy
  # Guest (비로그인)
  def view?
    return true if chapter_number <= 2  # 1-2장 공개
    false
  end
  
  # Trial User (로그인 + 7일)
  def view_as_trial?
    user.trial_active? && chapter_number <= 5
  end
  
  # Subscriber (유료)
  def view_as_subscriber?
    user.subscribed? && chapter_number <= 20
  end
  
  # Admin
  def view_as_admin?
    user.admin? # 전체 접근
  end
  
  # 종합: view? 메서드
  def view?
    return view_as_admin? if user&.admin?
    return view_as_subscriber? if user&.subscribed?
    return view_as_trial? if user&.trial_active?
    view?  # Guest
  end
end
```

---

## 3️⃣ Pundit 설치

### Step 1: Pundit 젬 추가

```bash
bundle add pundit
```

### Step 2: Pundit 초기화

```bash
rails generate pundit:install
```

**생성되는 파일:**

```
app/policies/
├── application_policy.rb  (기본 정책)
└── .keep
```

### Step 3: 컨트롤러에 Pundit 포함

**파일: `app/controllers/application_controller.rb`**

```ruby
class ApplicationController < ActionController::Base
  include Pundit::Authorization
  
  # 권한 없을 때 처리
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized
  
  private
  
  def user_not_authorized
    flash[:alert] = "이 작업을 할 권한이 없습니다."
    redirect_to root_path
  end
end
```

---

## 4️⃣ Policy 파일 작성

### 문서 접근 정책

**파일: `app/policies/doc_policy.rb`**

```ruby
class DocPolicy < ApplicationPolicy
  attr_reader :user, :doc
  
  def initialize(user, doc)
    @user = user
    @doc = doc
  end
  
  # 문서 번호 추출
  def chapter_number
    doc[:id].to_i  # "05" → 5
  end
  
  # 비로그인 (Guest): 1-2장만
  def view_as_guest?
    chapter_number <= 2
  end
  
  # Trial 사용자: 1-5장 + 7일 이내
  def view_as_trial?
    user&.trial_active? && chapter_number <= 5
  end
  
  # 구독자: 1-20장 전체
  def view_as_subscriber?
    user&.subscribed? && chapter_number <= 20
  end
  
  # 관리자: 전체 접근
  def view_as_admin?
    user&.admin?
  end
  
  # 최종 판단
  def view?
    return true if view_as_admin?
    return true if view_as_subscriber?
    return true if view_as_trial?
    return true if view_as_guest?
    false
  end
end
```

### 대시보드 접근 정책

**파일: `app/policies/dashboard_policy.rb`**

```ruby
class DashboardPolicy < ApplicationPolicy
  attr_reader :user
  
  def initialize(user, _record = nil)
    @user = user
  end
  
  # 로그인 필수
  def access?
    user.present?
  end
  
  # Trial 또는 Subscriber (내 정보만)
  def show_subscription?
    user.present? && (user.trial_active? || user.subscribed?)
  end
  
  # 관리자: 전체 접근
  def admin_access?
    user&.admin?
  end
end
```

---

## 5️⃣ 컨트롤러에서 권한 체크

### Docs 컨트롤러

**파일: `app/controllers/docs_controller.rb`**

```ruby
class DocsController < ApplicationController
  # before_action :authenticate_user!, only: [:show]  # 선택사항
  
  def index
    # 모든 챕터 리스트 표시 (접근 가능 여부만 표시)
    @chapters = chapters_with_availability
  end
  
  def show
    # 문서 객체 (임시)
    @doc = { id: params[:id] }
    
    # 권한 확인
    authorize @doc, policy_class: DocPolicy
    
    # 권한이 있으면 표시, 없으면 위에서 에러 발생
    @markdown_html = render_markdown(params[:id])
    @chapters = chapters_with_availability
  end
  
  private
  
  def chapters_with_availability
    CHAPTERS.map do |ch|
      file = DOCS_PATH.join("#{ch[:slug]}.md")
      policy = DocPolicy.new(current_user, ch)
      ch.merge(
        available: File.exist?(file),
        accessible: policy.view?  # 새로 추가!
      )
    end
  end
  
  def render_markdown(chapter_id)
    file = DOCS_PATH.join("#{chapter_id}.md")
    return "" unless File.exist?(file)
    
    markdown = File.read(file)
    MarkdownRenderer.new.render(markdown)
  end
end
```

### Dashboard 컨트롤러

**파일: `app/controllers/dashboard_controller.rb`**

```ruby
class DashboardController < ApplicationController
  before_action :authenticate_user!
  
  def index
    authorize :dashboard, policy_class: DashboardPolicy
    
    @user = current_user
    @subscription = @user.subscription
    @trial_days_remaining = @user.trial_days_remaining
    @trial_active = @user.trial_active?
  end
end
```

---

## 6️⃣ 뷰에서 권한 표시

### 문서 사이드바 (접근 불가 표시)

**파일: `app/views/docs/show.html.erb`**

```erb
<aside class="w-64 sticky top-0 bg-gray-50 p-4 h-screen overflow-y-auto">
  <h3 class="font-bold text-lg mb-4">챕터</h3>
  
  <ul class="space-y-2">
    <% @chapters.each do |chapter| %>
      <li>
        <% if chapter[:available] %>
          <% if chapter[:accessible] %>
            <!-- 접근 가능: 파란색 링크 -->
            <%= link_to chapter[:title],
              doc_path(chapter[:slug]),
              class: "text-blue-600 hover:underline"
            %>
          <% else %>
            <!-- 접근 불가: 회색 + 잠금 -->
            <span class="text-gray-400 cursor-not-allowed">
              🔒 <%= chapter[:title] %>
            </span>
            <span class="text-xs text-gray-500">구독 필요</span>
          <% end %>
        <% else %>
          <!-- 파일 없음: 회색 + 예정 -->
          <span class="text-gray-400">
            📝 <%= chapter[:title] %>
          </span>
          <span class="text-xs text-gray-500">예정</span>
        <% end %>
      </li>
    <% end %>
  </ul>
</aside>

<!-- 메인 콘텐츠 -->
<main class="flex-1 p-8">
  <div class="prose prose-lg">
    <%= raw @markdown_html %>
  </div>
</main>
```

### 권한 없을 때 에러 페이지

**파일: `app/views/shared/_unauthorized.html.erb`**

```erb
<div class="bg-red-50 border-l-4 border-red-500 p-6 rounded">
  <h2 class="text-red-800 font-bold text-lg mb-2">
    접근 권한이 없습니다
  </h2>
  
  <p class="text-red-700 mb-4">
    이 문서는 구독자만 볼 수 있습니다.
  </p>
  
  <% if current_user %>
    <% if current_user.trial_active? %>
      <p class="text-red-700 mb-4">
        👉 Trial 기간: <%= current_user.trial_days_remaining %>일 남음
      </p>
      <p class="text-red-700">
        전체 문서를 보려면
        <%= link_to "구독하기", pricing_path, class: "text-red-600 hover:underline font-bold" %>
      </p>
    <% else %>
      <p class="text-red-700">
        <%= link_to "지금 구독하기", pricing_path, class: "text-red-600 hover:underline font-bold" %>
      </p>
    <% end %>
  <% else %>
    <p class="text-red-700">
      먼저 <%= link_to "로그인", new_user_session_path, class: "text-red-600 hover:underline font-bold" %>
      해주세요. 7일 무료 Trial을 시작할 수 있습니다.
    </p>
  <% end %>
</div>
```

---

## 7️⃣ User 모델 업데이트

**파일: `app/models/user.rb`**

```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  
  has_one :subscription
  
  # 역할 (enum)
  enum role: { user: 0, admin: 1 }
  
  # Trial 관련
  def trial_started_at
    created_at
  end
  
  def trial_remaining_seconds
    ((trial_started_at + 7.days) - Time.current).to_i
  end
  
  def trial_days_remaining
    (trial_remaining_seconds / 86400.0).ceil
  end
  
  def trial_active?
    trial_remaining_seconds > 0
  end
  
  # Subscription 관련
  def subscribed?
    subscription&.active?
  end
  
  # 권한 확인
  def can_view_chapter?(chapter_num)
    return true if admin?
    return true if subscribed?
    return true if trial_active? && chapter_num <= 5
    chapter_num <= 2  # Guest: 1-2장
  end
end
```

---

## 8️⃣ 라우트 설정

**파일: `config/routes.rb`**

```ruby
Rails.application.routes.draw do
  devise_for :users
  
  root "pages#home"
  
  get "/docs", to: "docs#index"
  get "/docs/:id", to: "docs#show", as: "doc"
  
  get "/dashboard", to: "dashboard#index"
  
  # Admin (추후)
  namespace :admin do
    root "dashboard#index"
  end
end
```

---

## 9️⃣ 테스트

### Rails 콘솔에서

```bash
rails c

# 사용자 생성
user1 = User.create(email: "trial@example.com", password: "password123", role: :user)
user2 = User.create(email: "admin@example.com", password: "password123", role: :admin)

# 권한 확인
policy = DocPolicy.new(user1, { id: "10" })
policy.view?  # false (1-5장만 가능)

policy = DocPolicy.new(user2, { id: "10" })
policy.view?  # true (Admin은 전체)
```

### 브라우저에서

```
1️⃣ 비로그인
   /docs/05 → 접근 불가 (1-2장만 보임)

2️⃣ 로그인 (Trial)
   /docs/05 → 접근 가능 (1-5장)
   /docs/10 → 접근 불가 (구독 필요)

3️⃣ 구독자
   /docs/20 → 접근 가능 (전체)

4️⃣ Admin
   /docs/어디든 → 전체 접근 가능
```

---

## 🔟 체크리스트

### Pundit 설치
- [ ] `bundle add pundit` 실행
- [ ] `rails generate pundit:install` 실행
- [ ] `app/controllers/application_controller.rb` 업데이트

### Policy 파일
- [ ] `app/policies/doc_policy.rb` 작성
- [ ] `app/policies/dashboard_policy.rb` 작성
- [ ] 권한 로직 확인

### User 모델
- [ ] `role` enum 추가
- [ ] `trial_active?` 메서드 추가
- [ ] `can_view_chapter?` 메서드 추가

### 컨트롤러
- [ ] `DocsController#show`에서 `authorize` 호출
- [ ] `DashboardController`에서 `authorize` 호출
- [ ] Rescue 처리 (`user_not_authorized`)

### 뷰
- [ ] 사이드바에서 `accessible` 확인
- [ ] 접근 불가 시 에러 메시지 표시
- [ ] Trial/Subscriber별 다른 UI

### 테스트
- [ ] 비로그인: 1-2장만 보임
- [ ] Trial: 1-5장 + 일수 표시
- [ ] Subscriber: 1-20장 전체
- [ ] Admin: 전체 접근

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| **Policy 중앙화** | 모든 권한 로직은 Policy 파일에 |
| **Pundit 사용** | 수동 if문 대신 authorize 메서드 |
| **명확한 에러** | 권한 없을 때 사용자 친화적 메시지 |
| **Guest도 고려** | 비로그인 사용자도 1-2장 보기 |
| **Trial 기간 표시** | 남은 날짜를 UI에 표시 |

---

## 📚 다음 단계

✅ 권한 관리 완료! (Role 기반 접근 제어)

다음에는:
- **09장: 결제 (Payment)** - Toss Payments / PortOne 선택형 월간 구독
- **10장: 대시보드** - 사용자 전용 페이지
- **11장: 가격 페이지** - 구독 CTA

---

## 🚀 실습 과제

### 1. Pundit 설치 (지금 바로)

```bash
bundle add pundit
rails generate pundit:install
```

### 2. Policy 파일 작성

```
app/policies/doc_policy.rb
app/policies/dashboard_policy.rb
```

### 3. 권한 확인

```bash
rails c
user = User.create(email: 'test@example.com', password: 'password123')
policy = DocPolicy.new(user, { id: "05" })
puts policy.view?  # true (Trial 중이면)
```

### 4. 권한 없을 때 테스트

```
1. /docs/15 접속 (구독 필요)
2. "접근 권한이 없습니다" 메시지 확인
3. "구독하기" 링크 확인
```
