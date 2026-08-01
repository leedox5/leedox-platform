# 4. 랜딩페이지 구축

> 채독스의 첫 인상을 결정하는 랜딩페이지를 만듭니다.
> Tailwind CSS를 활용해 반응형 디자인을 구현하고,
> Rails의 라우팅과 뷰 구조를 실전으로 익힙니다.

---

## 📋 이 챕터에서 만드는 것

| # | 섹션 | 설명 |
|---|------|------|
| 1 | Header | 로고 + 네비게이션 |
| 2 | Hero | 메인 메시지 + CTA |
| 3 | 커리큘럼 | 20개 챕터 소개 |
| 4 | 상품 비교표 | 기본형/프리미엄형 |
| 5 | 가격 플랜 | 요금제 정보 |
| 6 | 기술 스택 | 사용된 기술 소개 |
| 7 | FAQ | 자주 묻는 질문 |
| 8 | Footer | 하단 정보 |

---

## 1️⃣ 라우팅 설정

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root "pages#home"   # http://localhost:3000 → pages#home
end
```

---

## 2️⃣ Controller 생성

```bash
rails generate controller Pages home
```

생성되는 파일:
```
app/controllers/pages_controller.rb
app/views/pages/home.html.erb
```

```ruby
# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
    # 랜딩페이지는 DB 조회 없이 정적 렌더링
  end
end
```

---

## 3️⃣ 레이아웃 구조 설정

Rails의 공통 레이아웃 파일에 기본 구조를 잡습니다.

```erb
<!-- app/views/layouts/application.html.erb -->
<!DOCTYPE html>
<html lang="ko">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>채독스 — SaaS 실전 구현 패키지</title>
    <%= csrf_meta_tags %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  </head>
  <body class="bg-white text-gray-900 font-sans">
    <%= render "shared/header" %>
    <main>
      <%= yield %>
    </main>
    <%= render "shared/footer" %>
  </body>
</html>
```

---

## 4️⃣ Header 컴포넌트

```bash
mkdir -p app/views/shared
```

```erb
<!-- app/views/shared/_header.html.erb -->
<header class="sticky top-0 z-50 bg-white border-b border-gray-100 shadow-sm">
  <div class="max-w-6xl mx-auto px-4 py-4 flex items-center justify-between">

    <!-- 로고 -->
    <a href="/" class="text-xl font-bold text-indigo-600">채독스</a>

    <!-- 네비게이션 -->
    <nav class="hidden md:flex items-center gap-6 text-sm text-gray-600">
      <a href="#curriculum" class="hover:text-indigo-600">커리큘럼</a>
      <a href="#pricing"    class="hover:text-indigo-600">가격</a>
      <a href="#faq"        class="hover:text-indigo-600">FAQ</a>
    </nav>

    <!-- 로그인/시작 버튼 -->
    <div class="flex items-center gap-3">
      <a href="/users/sign_in"
         class="text-sm text-gray-600 hover:text-indigo-600">로그인</a>
      <a href="/users/sign_up"
         class="text-sm bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700">
        무료 체험
      </a>
    </div>

  </div>
</header>
```

---

## 5️⃣ Hero 섹션

```erb
<!-- app/views/pages/home.html.erb (Hero 부분) -->
<section class="py-24 px-4 text-center bg-gradient-to-b from-indigo-50 to-white">
  <div class="max-w-3xl mx-auto">

    <p class="text-sm font-medium text-indigo-600 mb-4 uppercase tracking-wide">
      SaaS 실전 구현 패키지
    </p>

    <h1 class="text-4xl md:text-5xl font-bold text-gray-900 leading-tight mb-6">
      따라하면 서비스가<br>완성되는 실전 패키지
    </h1>

    <p class="text-lg text-gray-500 mb-8">
      누구나 단계별로 프로덕션 준비 완료된 SaaS를 직접 구현합니다.<br>
      20개 완전한 문서 + GitHub 템플릿 코드 + 프로덕션 운영까지
    </p>

    <div class="flex flex-col sm:flex-row gap-3 justify-center">
      <a href="/users/sign_up"
         class="bg-indigo-600 text-white px-8 py-3 rounded-lg text-base font-medium hover:bg-indigo-700">
        7일 무료 체험 시작
      </a>
      <a href="#curriculum"
         class="border border-gray-300 text-gray-700 px-8 py-3 rounded-lg text-base font-medium hover:border-indigo-400">
        커리큘럼 보기
      </a>
    </div>

    <p class="text-xs text-gray-400 mt-4">신용카드 불필요 · 언제든 취소 가능</p>

  </div>
</section>
```

---

## 6️⃣ 커리큘럼 섹션

```erb
<section id="curriculum" class="py-20 px-4 bg-white">
  <div class="max-w-4xl mx-auto">

    <h2 class="text-3xl font-bold text-center mb-12">완전한 커리큘럼 (20개 챕터)</h2>

    <div class="grid md:grid-cols-3 gap-8">

      <!-- Phase 1 -->
      <div class="bg-indigo-50 rounded-xl p-6">
        <h3 class="font-bold text-indigo-700 mb-4">📖 Phase 1: 기초 & 환경</h3>
        <ol class="space-y-2 text-sm text-gray-700 list-decimal list-inside">
          <li>전체 구조 이해</li>
          <li>Ruby on Rails 기초</li>
          <li>개발 환경 세팅</li>
          <li>랜딩페이지 구축</li>
          <li>프로젝트 구조 설계</li>
        </ol>
      </div>

      <!-- Phase 2 -->
      <div class="bg-blue-50 rounded-xl p-6">
        <h3 class="font-bold text-blue-700 mb-4">💻 Phase 2: 핵심 기능 구현</h3>
        <ol start="6" class="space-y-2 text-sm text-gray-700 list-decimal list-inside">
          <li>사용자 인증</li>
          <li>데이터베이스 설계</li>
          <li>API 개발</li>
          <li>결제 시스템</li>
          <li>검색 기능</li>
          <li>이메일 알림</li>
        </ol>
      </div>

      <!-- Phase 2 continued + Phase 3 -->
      <div class="bg-green-50 rounded-xl p-6">
        <h3 class="font-bold text-green-700 mb-4">🔧 Phase 3: 프로덕션 운영</h3>
        <ol start="12" class="space-y-2 text-sm text-gray-700 list-decimal list-inside">
          <li>파일 업로드</li>
          <li>문서 관리 시스템</li>
          <li>대시보드 UI</li>
          <li>테스트 작성</li>
          <li>배포</li>
          <li>모니터링</li>
          <li>보안 강화</li>
          <li>성능 최적화</li>
          <li>마치며</li>
        </ol>
      </div>

    </div>
  </div>
</section>
```

---

## 7️⃣ 가격 섹션

```erb
<section id="pricing" class="py-20 px-4 bg-gray-50">
  <div class="max-w-4xl mx-auto text-center">

    <h2 class="text-3xl font-bold mb-4">심플한 가격 정책</h2>
    <p class="text-gray-500 mb-12">연간 결제 시 36% 할인 · 3일 무료 체험</p>

    <div class="grid md:grid-cols-2 gap-6 max-w-2xl mx-auto">

      <!-- 기본형 -->
      <div class="bg-white rounded-2xl border border-gray-200 p-8 text-left">
        <h3 class="text-lg font-bold mb-1">기본형</h3>
        <p class="text-gray-500 text-sm mb-4">혼자서 완성하는 분께</p>
        <div class="text-4xl font-bold mb-1">$29<span class="text-base font-normal text-gray-400">/월</span></div>
        <p class="text-sm text-gray-400 mb-6">연간 $199 (36% 할인)</p>
        <ul class="space-y-2 text-sm text-gray-600 mb-8">
          <li>✅ 20개 완전 문서</li>
          <li>✅ GitHub 템플릿 코드</li>
          <li>✅ 이메일 지원 (48시간)</li>
          <li class="text-gray-300">❌ 커뮤니티 액세스</li>
        </ul>
        <a href="/users/sign_up"
           class="block text-center bg-indigo-600 text-white py-3 rounded-lg hover:bg-indigo-700">
          무료 체험 시작
        </a>
      </div>

      <!-- 프리미엄형 -->
      <div class="bg-indigo-600 rounded-2xl p-8 text-left text-white relative">
        <span class="absolute top-4 right-4 text-xs bg-yellow-400 text-yellow-900 px-2 py-1 rounded-full font-medium">인기</span>
        <h3 class="text-lg font-bold mb-1">프리미엄형</h3>
        <p class="text-indigo-200 text-sm mb-4">함께 성장하고 싶은 분께</p>
        <div class="text-4xl font-bold mb-1">$79<span class="text-base font-normal text-indigo-300">/월</span></div>
        <p class="text-sm text-indigo-300 mb-6">연간 $599 (36% 할인)</p>
        <ul class="space-y-2 text-sm text-indigo-100 mb-8">
          <li>✅ 기본형 모든 기능</li>
          <li>✅ 커뮤니티 액세스</li>
          <li>✅ 우선 지원 (24시간)</li>
          <li>✅ 향후 고급 기능</li>
        </ul>
        <a href="/users/sign_up"
           class="block text-center bg-white text-indigo-600 py-3 rounded-lg hover:bg-indigo-50 font-medium">
          무료 체험 시작
        </a>
      </div>

    </div>
  </div>
</section>
```

---

## 8️⃣ FAQ 섹션

```erb
<section id="faq" class="py-20 px-4 bg-white">
  <div class="max-w-2xl mx-auto">
    <h2 class="text-3xl font-bold text-center mb-12">자주 묻는 질문</h2>

    <div class="space-y-4">
      <% [
        ["개발 경험이 없는데 가능할까요?",
         "네, 충분히 가능합니다. 모든 문서가 초보자 기준으로 작성되어 있으며, 단계별로 따라하면 동일한 결과물을 얻을 수 있습니다."],
        ["문서는 어디서 보나요?",
         "채독스 서비스 내 자체 마크다운 문서 시스템에서 제공됩니다. 외부 도구 가입 없이 구독 즉시 접근 가능합니다."],
        ["언제든 취소할 수 있나요?",
         "네, 언제든지 취소 가능합니다. 다음 결제일 전 취소하면 이후 청구가 발생하지 않습니다."]
      ].each do |question, answer| %>
        <details class="border border-gray-200 rounded-xl p-5 group">
          <summary class="font-medium cursor-pointer list-none flex justify-between items-center">
            <%= question %>
            <span class="text-gray-400 group-open:rotate-180 transition-transform">▾</span>
          </summary>
          <p class="mt-3 text-gray-500 text-sm leading-relaxed"><%= answer %></p>
        </details>
      <% end %>
    </div>
  </div>
</section>
```

---

## 9️⃣ Footer 컴포넌트

```erb
<!-- app/views/shared/_footer.html.erb -->
<footer class="bg-gray-900 text-gray-400 py-12 px-4">
  <div class="max-w-6xl mx-auto flex flex-col md:flex-row justify-between gap-6 text-sm">

    <div>
      <p class="text-white font-bold mb-2">채독스</p>
      <p>상호명: -  |  대표: -</p>
      <p>사업자등록번호: -  |  통신판매업신고: -</p>
      <p>주소: -  |  이메일: -</p>
    </div>

    <div class="flex gap-4 items-start">
      <a href="/terms"   class="hover:text-white">이용 약관</a>
      <a href="/privacy" class="hover:text-white">개인정보 처리 방침</a>
    </div>

  </div>
  <div class="max-w-6xl mx-auto mt-6 pt-6 border-t border-gray-800 text-xs text-gray-600">
    © 2026 채독스. All rights reserved.
  </div>
</footer>
```

---

## 🎨 Tailwind 핵심 클래스 정리

| 클래스 | 역할 |
|--------|------|
| `max-w-6xl mx-auto` | 최대 너비 + 가운데 정렬 |
| `flex items-center justify-between` | 가로 배치 + 양끝 정렬 |
| `grid md:grid-cols-2` | 모바일 1열 → 데스크탑 2열 |
| `hidden md:flex` | 모바일 숨김 → 데스크탑 표시 |
| `py-20 px-4` | 상하 패딩 / 좌우 패딩 |
| `rounded-xl` | 둥근 모서리 |
| `hover:bg-indigo-700` | 마우스 오버 시 색상 변경 |
| `text-sm text-gray-500` | 글자 크기 / 색상 |

---

## ✅ 챕터 4 체크리스트

- [ ] `rails generate controller Pages home` 실행
- [ ] `root "pages#home"` 라우팅 설정
- [ ] 공통 레이아웃 (`application.html.erb`) 수정
- [ ] Header partial 생성
- [ ] Hero 섹션 완성
- [ ] 커리큘럼 섹션 완성
- [ ] 가격 섹션 완성
- [ ] FAQ 섹션 완성
- [ ] Footer partial 생성
- [ ] `http://localhost:3000` 에서 전체 랜딩페이지 확인

---

## 🔎 심화 사례 — 단일 상품 홈에서 통합 브랜드 홈으로

이 장은 최초 랜딩페이지를 만드는 초보자용 흐름입니다. 실제 운영에서는 Chatdox 단일 상품 홈을 보존하면서 `/`를 LEEDOX 상위 브랜드 홈으로 확장했습니다.

라우팅 책임 분리, 기존 partial 재사용, 인증 상태 Header, 모바일 한국어 줄바꿈, 통합 테스트와 브라우저 검증을 함께 살펴봅니다.

**[심화 사례: 단일 상품 홈을 LEEDOX 통합 홈으로 확장하기 →](case_leedox_integrated_home.md)**

> 심화 사례는 이 장의 기초 예제를 대체하는 복사본이 아닙니다. 기초 구조가 실제 요구 변화에 따라 확장된 과정을 비교하며 학습합니다.

---
## ➡️ 다음 챕터

**[5. 프로젝트 구조 설계 →](/docs/5)**

> 랜딩페이지가 완성되었습니다. 다음 챕터에서는 채독스의 핵심 기능을 위한
> 데이터 구조와 프로젝트 아키텍처를 설계합니다.
