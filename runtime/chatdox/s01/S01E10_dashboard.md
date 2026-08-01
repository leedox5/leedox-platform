# 10. 사용자 대시보드

> 로그인한 사용자가 자신의 구독 상태와 학습 현황을 한눈에 확인하는 대시보드를 구현합니다.
> 7~9장에서 만든 Devise 인증, Pundit 권한, Subscription 모델을 하나의 화면으로 연결합니다.
> 컨트롤러는 데이터를 준비하고, 뷰는 표시만 담당하도록 구성합니다.

---

## 📋 목표

1. 로그인 사용자만 접근할 수 있는 대시보드 만들기
2. 체험판과 유료 구독 상태를 사용자에게 명확히 표시하기
3. 전체 챕터 수와 완료한 챕터 수로 학습 진도 계산하기
4. 최근 학습 문서와 다음 추천 문서 보여주기
5. 결제, 문서, 계정 설정으로 이동하는 빠른 링크 만들기
6. 권한과 사용자별 데이터 격리를 테스트하기

---

## 1️⃣ 대시보드가 하는 일

대시보드는 로그인 후 가장 먼저 도착하는 사용자 전용 페이지입니다. 단순히 숫자를 모아 놓는 대신, 사용자가 현재 상태를 이해하고 다음 행동을 선택할 수 있어야 합니다.

```
[로그인]
   ↓
[사용자 대시보드]
   ├── 현재 이용 상태: Trial / Subscriber / Admin
   ├── 구독 정보: 다음 결제일 또는 체험 종료일
   ├── 학습 진도: 완료 챕터 / 전체 챕터
   ├── 최근 학습: 마지막으로 본 챕터
   └── 다음 행동: 이어서 학습 / 구독 / 결제 관리
```

### 역할별 핵심 CTA

| 사용자 상태 | 보여줄 정보 | 핵심 버튼 |
|------|------|------|
| 체험판 | 체험 남은 기간, 접근 가능한 챕터 | 구독 시작 |
| 구독자 | 다음 결제일, 전체 학습 진도 | 이어서 학습 |
| 결제 지연 | 결제 실패 안내 | 결제 수단 확인 |
| 관리자 | 전체 문서 접근 가능 표시 | 관리자 대시보드 |

> 대시보드에 표시한 상태는 권한의 근거가 아닙니다. 실제 문서 접근은 8장의 `DocPolicy`가 계속 검사해야 합니다.

---

## 2️⃣ 라우트와 진입점 만들기

### 라우트 설정

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :users

  resource :dashboard, only: :show
  resources :docs, only: %i[index show]

  get  "billing/checkout", to: "billing#checkout", as: :billing_checkout
  post "billing/success",  to: "billing#success",  as: :billing_success
  get  "billing/cancel",   to: "billing#cancel",   as: :billing_cancel

  root "pages#home"
end
```

`resource :dashboard`는 사용자마다 대시보드가 하나뿐이므로 단수형 리소스를 사용합니다.

```text
GET /dashboard → DashboardsController#show
```

### 로그인 후 대시보드로 이동

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  protected

  def after_sign_in_path_for(_resource)
    dashboard_path
  end
end
```

이 설정은 로그인 성공 직후의 이동 경로만 바꿉니다. 비로그인 사용자가 `/dashboard`에 직접 접근하는 경우는 컨트롤러의 `authenticate_user!`가 처리합니다.

---

## 3️⃣ 학습 진도 데이터 모델

구독 상태는 9장의 `subscriptions` 테이블에 이미 저장되어 있습니다. 챕터별 완료 여부는 별도의 `chapter_progresses` 테이블로 관리합니다.

### 모델과 마이그레이션 생성

```bash
bin/rails generate model ChapterProgress user:references chapter_id:string completed_at:datetime
bin/rails db:migrate
```

생성된 마이그레이션에 사용자별 챕터 중복 기록을 막는 인덱스를 추가합니다.

```ruby
# db/migrate/xxxx_create_chapter_progresses.rb
class CreateChapterProgresses < ActiveRecord::Migration[8.0]
  def change
    create_table :chapter_progresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :chapter_id, null: false
      t.datetime :completed_at

      t.timestamps
    end

    add_index :chapter_progresses,
              %i[user_id chapter_id],
              unique: true
  end
end
```

> 프로젝트의 Rails 버전에 따라 `[8.0]`은 생성기가 만든 버전을 그대로 사용하세요.

### 모델 관계와 검증

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_one :subscription, dependent: :destroy
  has_many :chapter_progresses, dependent: :destroy
end
```

```ruby
# app/models/chapter_progress.rb
class ChapterProgress < ApplicationRecord
  belongs_to :user

  validates :chapter_id,
            presence: true,
            uniqueness: { scope: :user_id },
            format: { with: /\A(0[1-9]|1[0-9]|20)\z/ }

  scope :completed, -> { where.not(completed_at: nil) }

  def completed?
    completed_at.present?
  end
end
```

`chapter_id`는 문서 목록에서 사용하는 `"01"`~`"20"` 형식으로 통일합니다. 숫자 `1`과 문자열 `"01"`이 섞이면 조회와 정렬에서 오류가 생기기 쉽습니다.

---

## 4️⃣ 챕터 목록을 한곳에서 관리하기

DocsController와 DashboardController가 각각 챕터 목록을 가지고 있으면 제목이나 순서가 쉽게 달라집니다. 목록을 하나의 클래스로 분리합니다.

```ruby
# app/models/curriculum.rb
class Curriculum
  Chapter = Data.define(:id, :slug, :title)

  CHAPTERS = [
    Chapter.new(id: "01", slug: "01_overview", title: "채독스 전체 구조 이해"),
    Chapter.new(id: "02", slug: "02_rails_basics", title: "Ruby on Rails 기초"),
    Chapter.new(id: "03", slug: "03_dev_setup", title: "개발 환경 세팅"),
    Chapter.new(id: "04", slug: "04_landing_page", title: "랜딩페이지 구축"),
    Chapter.new(id: "05", slug: "05_project_structure", title: "프로젝트 구조 설계"),
    Chapter.new(id: "06", slug: "06_database", title: "Database & Migrations"),
    Chapter.new(id: "07", slug: "07_authentication", title: "Authentication (Devise)"),
    Chapter.new(id: "08", slug: "08_authorization", title: "Authorization & 권한 관리"),
    Chapter.new(id: "09", slug: "09_payment", title: "Payment (Toss / PortOne)"),
    Chapter.new(id: "10", slug: "10_dashboard", title: "사용자 대시보드"),
    Chapter.new(id: "11", slug: "11_admin", title: "관리자 대시보드"),
    Chapter.new(id: "12", slug: "12_email", title: "Email & 알림"),
    Chapter.new(id: "13", slug: "13_file_upload", title: "파일 업로드 (Active Storage)"),
    Chapter.new(id: "14", slug: "14_api", title: "API 설계 & JSON"),
    Chapter.new(id: "15", slug: "15_testing", title: "테스트"),
    Chapter.new(id: "16", slug: "16_performance", title: "성능 최적화 & 캐싱"),
    Chapter.new(id: "17", slug: "17_security", title: "보안 & OWASP"),
    Chapter.new(id: "18", slug: "18_deployment", title: "배포"),
    Chapter.new(id: "19", slug: "19_monitoring", title: "모니터링 & 에러 추적"),
    Chapter.new(id: "20", slug: "20_launch", title: "런칭 & 운영")
  ].freeze

  def self.all
    CHAPTERS
  end

  def self.find(id)
    CHAPTERS.find { |chapter| chapter.id == id.to_s.rjust(2, "0") }
  end
end
```

기존 `DocsController::CHAPTERS`를 사용 중이라면 위 상수로 교체합니다.

```ruby
# app/controllers/docs_controller.rb
def index
  @chapters = Curriculum.all
end
```

문서 파일이 아직 작성되지 않은 챕터까지 전체 진도에 포함할지 정책을 먼저 결정해야 합니다. 이 장에서는 커리큘럼 전체 목표가 20장이므로 `Curriculum.all.size`를 분모로 사용합니다.

---

## 5️⃣ 대시보드 컨트롤러 구현

```bash
bin/rails generate controller Dashboards show
```

제너레이터가 `get "dashboards/show"` 라우트를 추가했다면 삭제하고, 앞에서 만든 `resource :dashboard`만 남깁니다.

```ruby
# app/controllers/dashboards_controller.rb
class DashboardsController < ApplicationController
  before_action :authenticate_user!

  def show
    authorize :dashboard, :access?

    @subscription = current_user.subscription
    @completed_ids = current_user.chapter_progresses
                                 .completed
                                 .order(completed_at: :desc)
                                 .pluck(:chapter_id)

    @total_chapters = Curriculum.all.size
    @completed_count = @completed_ids.size
    @progress_percent = progress_percent(@completed_count, @total_chapters)
    @recent_chapters = @completed_ids.first(3).filter_map { |id| Curriculum.find(id) }
    @next_chapter = Curriculum.all.find { |chapter| !@completed_ids.include?(chapter.id) }
  end

  private

  def progress_percent(completed_count, total_count)
    return 0 if total_count.zero?

    ((completed_count.to_f / total_count) * 100).round
  end
end
```

### 대시보드 Policy

8장에서 만든 `DashboardPolicy`를 사용합니다. 심볼 레코드를 authorize할 수 있도록 생성자의 두 번째 인자를 받습니다.

```ruby
# app/policies/dashboard_policy.rb
class DashboardPolicy < ApplicationPolicy
  def access?
    user.present?
  end
end
```

`authenticate_user!`와 `authorize`를 모두 사용하는 이유는 역할이 다르기 때문입니다.

- `authenticate_user!`: 로그인하지 않은 사용자를 로그인 페이지로 보냅니다.
- `authorize`: 로그인한 사용자가 해당 기능을 실행할 권한이 있는지 검사합니다.

---

## 6️⃣ 구독 상태 표시 헬퍼

상태 이름과 색상 같은 표현 로직은 헬퍼로 분리합니다.

```ruby
# app/helpers/dashboards_helper.rb
module DashboardsHelper
  SUBSCRIPTION_BADGES = {
    "active" => ["구독 중", "bg-emerald-100 text-emerald-700"],
    "past_due" => ["결제 확인 필요", "bg-amber-100 text-amber-700"],
    "canceled" => ["해지됨", "bg-slate-100 text-slate-700"],
    "expired" => ["만료됨", "bg-rose-100 text-rose-700"],
    "pending" => ["결제 대기", "bg-blue-100 text-blue-700"]
  }.freeze

  def subscription_badge(subscription)
    label, classes = SUBSCRIPTION_BADGES.fetch(
      subscription&.status,
      ["체험판", "bg-violet-100 text-violet-700"]
    )

    tag.span(label, class: "inline-flex rounded-full px-3 py-1 text-sm font-semibold #{classes}")
  end

  def subscription_period_text(user, subscription)
    if subscription&.status == "active" && subscription.current_period_end.present?
      "다음 결제일: #{l(subscription.current_period_end.to_date, format: :long)}"
    elsif user.trial_active?
      "무료 체험 #{user.trial_days_left}일 남음"
    else
      "이용 가능한 구독이 없습니다"
    end
  end
end
```

8장의 `User` 모델에 `trial_days_left`가 없다면 다음 메서드를 추가합니다.

```ruby
# app/models/user.rb
def trial_days_left
  return 0 unless trial_ends_at.present?

  [(trial_ends_at.to_date - Date.current).to_i, 0].max
end
```

날짜는 서버 기본 형식에 맡기지 않고 `I18n.l`의 축약형인 `l`로 표시합니다.

```yaml
# config/locales/ko.yml
ko:
  date:
    formats:
      long: "%Y년 %-m월 %-d일"
```

```ruby
# config/application.rb
config.i18n.default_locale = :ko
```

---

## 7️⃣ 대시보드 화면 만들기

```erb
<!-- app/views/dashboards/show.html.erb -->
<main class="mx-auto max-w-6xl px-4 py-10 sm:px-6 lg:px-8">
  <header class="mb-8 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
    <div>
      <p class="text-sm font-semibold text-blue-600">MY DASHBOARD</p>
      <h1 class="mt-1 text-3xl font-bold tracking-tight text-slate-900">
        안녕하세요, <%= current_user.email %>님
      </h1>
      <p class="mt-2 text-slate-600">오늘도 다음 챕터부터 이어서 학습해 보세요.</p>
    </div>

    <%= link_to "전체 문서 보기", docs_path,
          class: "rounded-lg bg-blue-600 px-4 py-2.5 text-center font-semibold text-white hover:bg-blue-700" %>
  </header>

  <section aria-label="이용 현황" class="grid gap-5 md:grid-cols-3">
    <article class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold text-slate-900">이용 상태</h2>
        <%= subscription_badge(@subscription) %>
      </div>
      <p class="mt-5 text-sm text-slate-600">
        <%= subscription_period_text(current_user, @subscription) %>
      </p>

      <% if @subscription&.status == "active" %>
        <%= link_to "구독 관리", "#",
              class: "mt-4 inline-block text-sm font-semibold text-blue-600 hover:text-blue-700" %>
      <% else %>
        <%= link_to "구독 시작", billing_checkout_path,
              class: "mt-4 inline-block text-sm font-semibold text-blue-600 hover:text-blue-700" %>
      <% end %>
    </article>

    <article class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm md:col-span-2">
      <div class="flex items-center justify-between">
        <h2 class="font-semibold text-slate-900">학습 진도</h2>
        <strong class="text-2xl text-blue-600"><%= @progress_percent %>%</strong>
      </div>
      <p class="mt-2 text-sm text-slate-600">
        전체 <%= @total_chapters %>개 중 <%= @completed_count %>개 완료
      </p>
      <div class="mt-5 h-3 overflow-hidden rounded-full bg-slate-100"
           role="progressbar"
           aria-label="커리큘럼 학습 진도"
           aria-valuenow="<%= @progress_percent %>"
           aria-valuemin="0"
           aria-valuemax="100">
        <div class="h-full rounded-full bg-blue-600 transition-all"
             style="width: <%= @progress_percent %>%"></div>
      </div>
    </article>
  </section>

  <section class="mt-8 grid gap-8 lg:grid-cols-3">
    <article class="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm lg:col-span-2">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold text-slate-900">최근 완료한 챕터</h2>
        <%= link_to "전체 보기", docs_path, class: "text-sm font-semibold text-blue-600" %>
      </div>

      <% if @recent_chapters.any? %>
        <ul class="mt-4 divide-y divide-slate-100">
          <% @recent_chapters.each do |chapter| %>
            <li class="flex items-center justify-between gap-4 py-4">
              <div>
                <p class="text-sm text-slate-500">Chapter <%= chapter.id %></p>
                <p class="font-medium text-slate-900"><%= chapter.title %></p>
              </div>
              <%= link_to "다시 보기", doc_path(chapter.id),
                    class: "shrink-0 text-sm font-semibold text-blue-600" %>
            </li>
          <% end %>
        </ul>
      <% else %>
        <div class="mt-4 rounded-xl bg-slate-50 p-6 text-center">
          <p class="text-slate-600">아직 완료한 챕터가 없습니다.</p>
          <%= link_to "첫 챕터 시작", doc_path("01"),
                class: "mt-3 inline-block font-semibold text-blue-600" %>
        </div>
      <% end %>
    </article>

    <aside class="rounded-2xl bg-slate-900 p-6 text-white shadow-sm">
      <p class="text-sm font-semibold text-blue-300">NEXT STEP</p>
      <% if @next_chapter %>
        <h2 class="mt-3 text-xl font-bold"><%= @next_chapter.title %></h2>
        <p class="mt-2 text-sm text-slate-300">Chapter <%= @next_chapter.id %></p>
        <%= link_to "이어서 학습", doc_path(@next_chapter.id),
              class: "mt-6 block rounded-lg bg-white px-4 py-2.5 text-center font-semibold text-slate-900 hover:bg-slate-100" %>
      <% else %>
        <h2 class="mt-3 text-xl font-bold">모든 챕터를 완료했습니다!</h2>
        <p class="mt-2 text-sm text-slate-300">필요한 챕터를 다시 복습해 보세요.</p>
      <% end %>
    </aside>
  </section>
</main>
```

`style="width: ..."`에 들어가는 값은 서버가 계산한 0~100 범위의 정수만 사용합니다. 사용자가 전달한 문자열을 그대로 넣지 않습니다.

---

## 8️⃣ 챕터 완료 처리

대시보드에 진도를 표시하려면 문서 화면에서 완료 상태를 변경할 수 있어야 합니다.

### 라우트

```ruby
# config/routes.rb
resources :chapter_progresses, only: :create do
  delete :destroy, on: :collection
end
```

### 컨트롤러

```ruby
# app/controllers/chapter_progresses_controller.rb
class ChapterProgressesController < ApplicationController
  before_action :authenticate_user!

  def create
    chapter = Curriculum.find(params[:chapter_id])
    return head :not_found unless chapter

    progress = current_user.chapter_progresses.find_or_initialize_by(chapter_id: chapter.id)
    progress.update!(completed_at: Time.current)

    redirect_to doc_path(chapter.id), notice: "완료한 챕터로 표시했습니다."
  end

  def destroy
    chapter = Curriculum.find(params[:chapter_id])
    return head :not_found unless chapter

    current_user.chapter_progresses.find_by(chapter_id: chapter.id)&.destroy!
    redirect_to doc_path(chapter.id), notice: "완료 표시를 취소했습니다."
  end
end
```

`current_user.chapter_progresses`에서 조회해야 다른 사용자의 진도 레코드를 수정할 수 없습니다.

### 문서 화면 버튼

```erb
<!-- app/views/docs/show.html.erb 하단 -->
<% if user_signed_in? %>
  <% progress = current_user.chapter_progresses.find_by(chapter_id: @current_id) %>

  <div class="mt-10 border-t border-slate-200 pt-6">
    <% if progress&.completed? %>
      <%= button_to "완료 표시 취소",
            chapter_progresses_path(chapter_id: @current_id),
            method: :delete,
            class: "rounded-lg border border-slate-300 px-4 py-2 font-semibold text-slate-700" %>
    <% else %>
      <%= button_to "이 챕터 완료",
            chapter_progresses_path(chapter_id: @current_id),
            method: :post,
            class: "rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white" %>
    <% end %>
  </div>
<% end %>
```

---

## 9️⃣ 테스트

### 모델 테스트

```ruby
# test/models/chapter_progress_test.rb
require "test_helper"

class ChapterProgressTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "한 사용자는 같은 챕터를 한 번만 기록한다" do
    @user.chapter_progresses.create!(chapter_id: "01", completed_at: Time.current)
    duplicate = @user.chapter_progresses.new(chapter_id: "01", completed_at: Time.current)

    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:chapter_id, :taken)
  end

  test "챕터 번호 형식을 검증한다" do
    progress = @user.chapter_progresses.new(chapter_id: "21")

    assert_not progress.valid?
  end
end
```

### 대시보드 접근 테스트

```ruby
# test/controllers/dashboards_controller_test.rb
require "test_helper"

class DashboardsControllerTest < ActionDispatch::IntegrationTest
  test "비로그인 사용자는 로그인 페이지로 이동한다" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "로그인 사용자는 자신의 대시보드를 본다" do
    user = users(:one)
    sign_in user

    get dashboard_path

    assert_response :success
    assert_select "h1", text: /#{Regexp.escape(user.email)}/
  end
end
```

### 진도 변경 테스트

```ruby
# test/controllers/chapter_progresses_controller_test.rb
require "test_helper"

class ChapterProgressesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "현재 사용자의 완료 기록을 만든다" do
    assert_difference("@user.chapter_progresses.count", 1) do
      post chapter_progresses_path, params: { chapter_id: "01" }
    end

    assert_redirected_to doc_path("01")
    assert @user.chapter_progresses.exists?(chapter_id: "01")
  end

  test "존재하지 않는 챕터는 기록하지 않는다" do
    assert_no_difference("ChapterProgress.count") do
      post chapter_progresses_path, params: { chapter_id: "99" }
    end

    assert_response :not_found
  end
end
```

프로젝트가 Minitest 대신 RSpec을 사용한다면 검증 항목은 그대로 두고 테스트 문법만 변환합니다.

---

## 🔟 자주 발생하는 문제

| 문제 | 원인 | 해결 |
|------|------|------|
| 로그인 후 랜딩페이지로 이동 | Devise 기본 경로 사용 | `after_sign_in_path_for` 확인 |
| 진도율이 항상 0% | `completed_at`이 비어 있음 | 완료 처리 시 `Time.current` 저장 |
| 같은 챕터가 중복 집계됨 | 복합 유니크 인덱스 없음 | DB 인덱스와 모델 검증 모두 추가 |
| 다른 사용자의 진도가 보임 | `ChapterProgress.all`로 조회 | 항상 `current_user.chapter_progresses` 사용 |
| 구독했는데 체험판으로 표시 | 결제 승인 후 상태 미반영 | 9장의 승인 API와 상태 저장 확인 |
| 미작성 챕터 링크가 404 | 전체 목록을 그대로 추천 | 공개된 챕터만 추천하는 정책 추가 |

### N+1 쿼리 피하기

대시보드에서 구독과 진도를 여러 사용자 기준으로 반복 조회하지 않습니다. 사용자 한 명의 화면에서는 연관을 각각 한 번씩 읽고, 관리자 목록처럼 여러 사용자를 표시할 때는 `includes`를 사용합니다.

```ruby
users = User.includes(:subscription, :chapter_progresses)
```

### 구독 상태를 화면에서 변경하지 않기

대시보드는 구독 정보를 읽어 보여주는 역할만 합니다. `active`, `canceled`, `past_due` 같은 상태 변경은 9장의 결제 승인, 해지, 웹훅 처리에서 수행합니다.

---

## ✅ 챕터 10 체크리스트

### 접근 제어

- [ ] 비로그인 사용자는 `/dashboard`에 접근할 수 없다
- [ ] 로그인 후 `/dashboard`로 이동한다
- [ ] Pundit으로 대시보드 접근 권한을 검사한다

### 데이터

- [ ] 사용자와 `ChapterProgress` 관계를 설정했다
- [ ] 사용자별 챕터 중복 기록을 DB에서 차단했다
- [ ] 구독과 진도 조회가 항상 `current_user` 범위에서 실행된다

### 화면

- [ ] 체험판, 구독, 결제 지연 상태가 구분되어 보인다
- [ ] 완료 수와 전체 수로 진도율을 표시한다
- [ ] 최근 완료 챕터와 다음 챕터 링크가 동작한다
- [ ] 빈 상태와 전체 완료 상태를 처리한다

### 테스트

- [ ] 비로그인 접근 테스트가 통과한다
- [ ] 진도 생성과 중복 방지 테스트가 통과한다
- [ ] 존재하지 않는 챕터를 기록할 수 없다

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| 사용자 범위 제한 | 모든 개인 데이터는 `current_user` 연관을 통해 조회 |
| 상태의 단일 출처 | 결제 상태는 Subscription, 학습 상태는 ChapterProgress에서 조회 |
| 권한과 UI 분리 | 버튼을 숨겨도 서버의 Policy 검사는 반드시 실행 |
| 표현 로직 분리 | 컨트롤러는 집계, 헬퍼와 뷰는 표시 담당 |
| 다음 행동 제시 | 사용자가 화면을 본 뒤 무엇을 할지 명확하게 안내 |

---

## ➡️ 다음 챕터

11장에서는 전체 사용자, 구독, 결제 상태를 운영자가 관리할 수 있는 **관리자 대시보드**를 구현합니다.
