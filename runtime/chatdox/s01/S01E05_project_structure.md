# 5. 프로젝트 구조 설계

> Rails 프로젝트의 폴더 구조를 이해하고,
> Chatdox 플랫폼의 핵심 구조를 설계합니다.
> "Convention over Configuration" 원칙에 따라
> Rails가 기대하는 구조를 따릅니다.

---

## 📋 목표

1. **Rails 기본 구조** 이해
2. **Chatdox 플랫폼** 폴더 설계
3. **핵심 Models** 정의
4. **요청 흐름** 이해 (Request → Response)

---

## 1️⃣ Rails 기본 구조

### 폴더별 역할

```
chatdox-platform/
├── app/                 # 핵심 애플리케이션 코드
│   ├── models/          # 데이터 모델 (User, Plan, Document)
│   ├── controllers/      # 요청 처리 (PagesController, DocsController)
│   ├── views/           # HTML 템플릿 (ERB)
│   ├── helpers/         # View 헬퍼 메서드
│   ├── assets/          # CSS, JS, 이미지
│   └── javascript/      # Rails 7+ JavaScript (importmap)
│
├── config/              # 환경 설정
│   ├── routes.rb        # URL 라우팅
│   ├── database.yml     # 데이터베이스 설정
│   └── environments/    # development, production 환경
│
├── db/                  # 데이터베이스
│   └── migrate/         # 스키마 변경 이력
│
├── public/              # 정적 파일 (이미지, 다운로드)
└── Gemfile              # Ruby Gem (라이브러리) 관리
```

---

## 2️⃣ Chatdox 플랫폼 구조

### 전체 구조도

```
app/
├── models/
│   ├── user.rb              # 사용자
│   ├── subscription.rb       # 구독
│   ├── curriculum.rb         # 커리큘럼 (Git Subtree)
│   └── document.rb           # 문서
│
├── controllers/
│   ├── pages_controller.rb   # 랜딩페이지, 홈
│   ├── docs_controller.rb    # 문서 뷰어
│   └── users_controller.rb   # 회원가입, 프로필
│
└── views/
    ├── layouts/
    │   └── application.html.erb   # 레이아웃 (Header, Footer)
    ├── pages/
    │   └── home.html.erb          # 홈페이지
    ├── docs/
    │   ├── index.html.erb         # 문서 목록
    │   └── show.html.erb          # 문서 상세
    └── users/
        ├── new.html.erb           # 가입 폼
        └── show.html.erb          # 프로필
```

---

## 3️⃣ 핵심 Models 설계

### User (사용자)

```ruby
# app/models/user.rb

class User < ApplicationRecord
  # 관계
  has_one :subscription
  
  # 검증
  validates :email, presence: true, uniqueness: true
  validates :password, presence: true, length: { minimum: 8 }
  
  # 컬럼: id, email, password_digest, name, created_at, updated_at
end
```

**역할:**
- 회원가입/로그인
- 구독 정보 관리

---

### Subscription (구독)

```ruby
# app/models/subscription.rb

class Subscription < ApplicationRecord
  belongs_to :user
  
  # 상태: free, basic, premium
  validates :plan_type, inclusion: { in: %w(free basic premium) }
  
  # 컬럼: id, user_id, plan_type, started_at, expires_at
end
```

**역할:**
- 사용자의 요금제 추적
- 접근 권한 제어

---

### Curriculum (커리큘럼)

```ruby
# app/models/curriculum.rb

class Curriculum < ApplicationRecord
  # Git Subtree로 docs/curriculum/ 폴더와 연동
  # 이 모델은 데이터 기반 기능용 (예: 시청 진도)
  
  validates :chapter_number, presence: true
  validates :title, presence: true
  
  # 컬럼: id, chapter_number, title, slug, created_at
end
```

**역할:**
- 커리큘럼 메타데이터 관리
- 학습 진도 추적

---

### Document (문서)

```ruby
# app/models/document.rb

class Document < ApplicationRecord
  # Redcarpet으로 Markdown 렌더링
  
  validates :title, presence: true
  validates :content, presence: true
  
  # 컬럼: id, title, content, category, created_at
end
```

**역할:**
- 우리가 생성하는 추가 문서 관리

---

## 4️⃣ Controllers & Routes

### 라우팅 설계

```ruby
# config/routes.rb

Rails.application.routes.draw do
  root "pages#home"                    # http://localhost:3000/
  
  get  "docs",        to: "docs#index"  # 문서 목록
  get  "docs/:id",    to: "docs#show"   # 문서 상세
  
  get  "signup",      to: "users#new"   # 회원가입
  post "users",       to: "users#create"
  
  get  "dashboard",   to: "dashboard#index"  # 사용자 대시보드
end
```

### PagesController (랜딩페이지)

```ruby
# app/controllers/pages_controller.rb

class PagesController < ApplicationController
  def home
    # 템플릿 자동 렌더링: views/pages/home.html.erb
  end
end
```

### DocsController (문서 뷰어)

```ruby
# app/controllers/docs_controller.rb

class DocsController < ApplicationController
  def index
    @chapters = [
      { id: "01", title: "아키텍처 개요" },
      { id: "02", title: "Rails 기초" },
      { id: "03", title: "개발 환경 설정" },
      { id: "04", title: "랜딩페이지 구축" }
    ]
  end
  
  def show
    @chapter_id = params[:id]
    file_path = "docs/curriculum/docs/#{@chapter_id}_*.md"
    @markdown_content = File.read(file_path) rescue "파일을 찾을 수 없습니다"
    @markdown_html = render_markdown(@markdown_content)
  end
end
```

---

## 5️⃣ Views 구조

### Layout (공통 레이아웃)

```erb
<!-- app/views/layouts/application.html.erb -->

<!DOCTYPE html>
<html>
  <head>
    <title>Chatdox</title>
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application" %>
    <%= javascript_importmap_tags %>
  </head>

  <body>
    <%= render "shared/header" %>
    <main class="min-h-screen">
      <%= yield %>
    </main>
    <%= render "shared/footer" %>
  </body>
</html>
```

### Docs Show View

```erb
<!-- app/views/docs/show.html.erb -->

<div class="flex gap-4">
  <!-- 사이드바 -->
  <aside class="w-64 sticky top-0">
    <div class="p-4">
      <h3 class="font-bold mb-4">📚 커리큘럼</h3>
      <ul class="space-y-2">
        <% @chapters.each do |ch| %>
          <li>
            <%= link_to ch[:title], docs_path(ch[:id]),
                class: "text-blue-600 hover:underline" %>
          </li>
        <% end %>
      </ul>
    </div>
  </aside>

  <!-- 콘텐츠 -->
  <article class="flex-1 max-w-4xl">
    <div class="prose prose-sm">
      <%= @markdown_html %>
    </div>
  </article>
</div>
```

---

## 6️⃣ 요청 흐름 예시

### 사용자가 `/docs/04` 접속

```
1. 브라우저 요청
   GET /docs/04

2. Rails Router
   config/routes.rb 에서 매칭
   → docs_controller#show (id=04)

3. DocsController
   def show
     @chapter_id = "04"
     @markdown_content = File.read("docs/04_landing_page.md")
     @markdown_html = render_markdown(@markdown_content)
   end

4. View 렌더링
   app/views/docs/show.html.erb
   → @markdown_html 표시
   → Layout 감싸기
   → HTML 완성

5. 브라우저에 응답
   ✅ 완성된 HTML 페이지
```

---

## 7️⃣ 실전 체크리스트

새 기능을 추가할 때:

### Model 단계
- [ ] `rails generate model FeatureName` 실행?
- [ ] Validation 추가?
- [ ] Association (has_many, belongs_to) 설정?

### Migration 단계
- [ ] `rails db:migrate` 실행?
- [ ] 데이터베이스 컬럼 확인?

### Controller 단계
- [ ] `rails generate controller FeatureName` 실행?
- [ ] Action 메서드 정의? (index, show, new, create, edit, update, destroy)
- [ ] 필요한 instance variable 할당?

### Routes 단계
- [ ] `config/routes.rb` 에 라우트 추가?
- [ ] `rails routes` 로 확인?

### View 단계
- [ ] `app/views/feature_name/` 폴더 생성?
- [ ] 각 action용 ERB 파일 생성?
- [ ] Link/Form 태그 정확?

### 테스트 단계
- [ ] `rails s` 로 서버 실행?
- [ ] 브라우저에서 동작 확인?
- [ ] Rails 로그 에러 확인?

---

## 8️⃣ Rails 명령어 정리

```bash
# Model 생성
rails generate model User email:string password_digest:string

# Controller 생성
rails generate controller Docs index show

# Migration 실행
rails db:migrate

# 라우트 확인
rails routes

# 서버 실행
rails s

# Console 실행 (Rails 명령줄)
rails console
# irb> User.all
# irb> User.create(email: "test@example.com")
```

---

## 🎯 핵심 원칙

| 원칙 | 의미 |
|------|------|
| **Convention Over Configuration** | 설정보다 관례를 따르기 (폴더명, 파일명, 컬럼명) |
| **DRY (Don't Repeat Yourself)** | 코드 반복 최소화 (Layout, Helper, Partial) |
| **Separation of Concerns** | Model, View, Controller 역할 분리 |
| **RESTful Routing** | CRUD 작업을 URL로 명확하게 표현 |

---

## 📚 다음 단계

✅ 이제 폴더 구조를 이해했습니다!

다음에는:
- **06장: Database & Migrations** - 스키마 설계
- **07장: Authentication with Devise** - 회원가입/로그인
- **08장: Payment Integration** - 결제 시스템

