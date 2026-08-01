# 2. Ruby on Rails 8.1 기초

> Rails가 처음이라도 괜찮습니다. 이 챕터에서는 채독스 구현에 꼭 필요한
> 핵심 개념만 빠르게 정리합니다. 전부 외울 필요 없이, 흐름을 이해하는 것이 목표입니다.

---

## 📌 Rails란?

Ruby on Rails(이하 Rails)는 **Ruby 언어로 만들어진 웹 프레임워크**입니다.

> "Convention over Configuration" (설정보다 관례)

Rails의 핵심 철학입니다. 개발자가 일일이 설정하지 않아도, Rails의 규칙을 따르면 코드가 자동으로 연결됩니다. 덕분에 **빠르게 기능을 만들 수 있습니다.**

---

## 🧩 MVC 패턴 심화

챕터 1에서 MVC 흐름을 봤습니다. 여기서는 각 역할을 코드와 함께 이해합니다.

### Model — 데이터 담당

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_many :subscriptions
  validates :email, presence: true, uniqueness: true
end
```

- 데이터베이스 테이블과 1:1 대응
- 데이터 유효성 검사 (validates)
- 다른 모델과의 관계 정의 (has_many, belongs_to)

---

### Controller — 처리 담당

```ruby
# app/controllers/docs_controller.rb
class DocsController < ApplicationController
  def show
    @document = Document.find(params[:id])
  end
end
```

- 요청을 받아 Model에서 데이터를 가져옴
- View에 데이터(`@변수`)를 전달
- 인증, 권한 확인도 여기서 처리

---

### View — 화면 담당

```erb
<!-- app/views/docs/show.html.erb -->
<h1><%= @document.title %></h1>
<div class="content">
  <%= @document.content %>
</div>
```

- ERB(Embedded Ruby) 형식: HTML 안에 Ruby 코드 삽입
- `<%= %>` : 출력 있음 | `<% %>` : 출력 없음 (조건문, 반복문)

---

## 🛤️ 라우팅 (Routes)

URL과 Controller를 연결하는 설정입니다.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "pages#home"           # 메인 페이지
  resources :docs, only: [:index, :show]  # /docs, /docs/:id
  devise_for :users           # 인증 관련 URL 자동 생성
end
```

### RESTful 라우트 규칙

| HTTP 메서드 | URL | Controller#Action | 용도 |
|------------|-----|-------------------|------|
| GET | /docs | docs#index | 목록 |
| GET | /docs/:id | docs#show | 상세 |
| GET | /docs/new | docs#new | 작성 폼 |
| POST | /docs | docs#create | 생성 |
| GET | /docs/:id/edit | docs#edit | 수정 폼 |
| PATCH | /docs/:id | docs#update | 수정 |
| DELETE | /docs/:id | docs#destroy | 삭제 |

---

## 💎 Gem (라이브러리)

Rails 생태계에서는 외부 라이브러리를 **Gem**이라고 합니다.

```ruby
# Gemfile
gem "devise"       # 사용자 인증
gem "tailwindcss-rails"  # Tailwind CSS
gem "net/http"      # 결제 API 직접 연동 시 사용 가능
gem "redcarpet"    # 마크다운 렌더링
```

```bash
bundle install  # Gemfile에 정의된 Gem 설치
```

---

## 🗄️ 데이터베이스 & 마이그레이션

Rails에서 DB 구조 변경은 **마이그레이션 파일**로 관리합니다.

```ruby
# db/migrate/20260101000000_create_documents.rb
class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.string  :title,        null: false
      t.text    :content
      t.integer :order_number
      t.string  :access_level, default: "paid"
      t.timestamps
    end
  end
end
```

```bash
rails db:migrate    # 마이그레이션 실행 (DB에 반영)
rails db:rollback   # 마지막 마이그레이션 되돌리기
```

> 💡 **마이그레이션 = DB 변경 이력** — Git 커밋처럼 누적 관리됩니다.

---

## ⚡ Rails 주요 명령어

```bash
# 프로젝트 생성
rails new chatdox --css tailwind --database sqlite3

# 서버 실행
rails server  (또는 rails s)

# 콘솔 (데이터 직접 조작)
rails console  (또는 rails c)

# 코드 자동 생성
rails generate model Document title:string content:text
rails generate controller Docs index show

# 데이터베이스
rails db:migrate     # 마이그레이션 실행
rails db:seed        # 초기 데이터 삽입
rails db:reset       # DB 초기화 후 재생성

# 테스트
rails test
```

---

## 🔑 Active Record (ORM)

Rails는 SQL을 직접 쓰지 않고 **Ruby 코드로 DB를 조작**합니다.

```ruby
# 생성
Document.create(title: "챕터 1", content: "내용...", order_number: 1)

# 조회
Document.all                          # 전체
Document.find(1)                      # ID로 찾기
Document.where(access_level: "free")  # 조건 검색
Document.order(:order_number)         # 정렬

# 수정
doc = Document.find(1)
doc.update(title: "새 제목")

# 삭제
doc.destroy
```

---

## 🔐 인증 흐름 (Devise 미리보기)

Devise gem을 사용하면 인증 기능이 자동으로 만들어집니다.

```bash
rails generate devise User  # User 모델에 인증 기능 추가
```

생성되는 기능:
- `/users/sign_up` — 회원가입
- `/users/sign_in` — 로그인
- `/users/sign_out` — 로그아웃
- `/users/password/new` — 비밀번호 재설정

Controller에서 인증 확인:
```ruby
class DocsController < ApplicationController
  before_action :authenticate_user!  # 로그인 필수

  def show
    @document = Document.find(params[:id])
  end
end
```

---

## ✅ 챕터 2 체크리스트

- [ ] MVC 각각의 역할을 코드와 함께 설명할 수 있다
- [ ] `config/routes.rb`가 무엇을 하는지 안다
- [ ] Gemfile에 라이브러리를 추가하는 방법을 안다
- [ ] `rails db:migrate`가 무엇인지 안다
- [ ] Active Record로 데이터를 조회하는 코드를 이해한다

---

## ➡️ 다음 챕터

**[3. 개발 환경 세팅 →](/docs/3)**

> 이제 개념은 충분합니다. 다음 챕터에서 실제로 컴퓨터에 개발 환경을 구축합니다.
