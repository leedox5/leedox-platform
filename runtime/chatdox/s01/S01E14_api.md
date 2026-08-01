# 14. API 설계 & JSON

> 사람이 브라우저로 보는 화면 말고도, 다른 프로그램(모바일 앱, 다른 서버, AI 에이전트)이 우리 서비스에 데이터를 주고받을 수 있는 통로가 필요할 때가 있습니다. 이 장에서는 JSON 기반 API를 설계하고 안전하게 노출하는 방법을 다룹니다.

---

## 📋 목표

1. HTML 화면과 JSON API의 차이 이해
2. RESTful한 API 엔드포인트 설계
3. 브라우저 로그인과는 다른 API 인증 방식 이해
4. 일관된 JSON 응답/에러 포맷 설계

---

## 1️⃣ 화면과 API는 다른 손님을 상대한다

지금까지 만든 컨트롤러 액션들은 `render :show` 처럼 HTML 화면을 그려서 사람에게 보여줬습니다. API는 다릅니다 — 사람이 아니라 **프로그램**이 호출하고, 응답도 화면이 아니라 데이터(보통 JSON)입니다.

```ruby
def show
  @request = ServiceDeskRequest.find_by(request_number: params[:id])
  render json: {
    request_number: @request.request_number,
    subject: @request.subject,
    status: @request.status_label
  }
end
```

같은 데이터를 다루더라도, 화면용 컨트롤러와 API용 컨트롤러는 보통 분리합니다 — 반환 형식도 다르고, 인증 방식도 다른 경우가 많기 때문입니다.

---

## 2️⃣ 인증 방식 — 로그인 세션과 API 키는 다르다

브라우저는 로그인하면 세션 쿠키가 생기고, 이후 요청마다 그 쿠키로 "누구인지" 확인합니다. 그런데 브라우저 세션이 없는 호출자(다른 서버, 배치 스크립트, AI 에이전트)는 로그인 화면을 통과할 수 없습니다. 이런 경우엔 보통 **API 토큰(키)** 방식을 씁니다.

```ruby
class Api::BaseController < ActionController::Base
  skip_before_action :verify_authenticity_token, raise: false
  before_action :authenticate_token!

  private

  def authenticate_token!
    expected = ENV["API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s.delete_prefix("Bearer ")

    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, provided)

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end
```

토큰 비교엔 일반 `==` 대신 `ActiveSupport::SecurityUtils.secure_compare`를 씁니다 — 문자열을 앞에서부터 한 글자씩 비교하는 일반 비교는 "얼마나 많이 맞았는지"가 응답 시간 차이로 미세하게 드러날 수 있는데(타이밍 공격), `secure_compare`는 이런 시간차를 없애서 막습니다.

> 💡 참고: 이 프로젝트의 서비스데스크 기능도 브라우저 화면(사람용, 로그인 세션 기반)과 별개로 API 엔드포인트(`POST /service-desk/api/requests`)를 두고 있습니다. AI 에이전트가 브라우저 로그인 없이도 티켓을 등록할 수 있게 하기 위해서입니다 — 정확히 위 패턴(고정 Bearer 토큰)을 씁니다.

---

## 3️⃣ 일관된 응답 포맷

API를 쓰는 쪽(프론트엔드, 다른 서버)이 매번 다른 형태의 응답을 받으면 매번 새로 파싱 로직을 짜야 합니다. 성공/실패 형태를 미리 정해두는 게 좋습니다.

```ruby
# 성공
render json: { request_number: 27, subject: "...", status: "New" }, status: :ok

# 생성 성공
render json: { request_number: 28, ... }, status: :created

# 유효성 검증 실패
render json: { errors: ["Subject can't be blank"] }, status: :unprocessable_content

# 인증 실패
render json: { error: "unauthorized" }, status: :unauthorized

# 존재하지 않음
render json: { error: "not found" }, status: :not_found
```

HTTP 상태 코드도 응답의 일부입니다 — 실패인데 `200 OK`를 보내면, 호출하는 쪽이 성공으로 착각하고 다음 로직을 계속 진행해버릴 수 있습니다.

---

## 4️⃣ RESTful 라우트 설계

```ruby
# config/routes.rb
namespace :api do
  resources :requests, only: %i[index show create] do
    resources :jobs, only: %i[create]
  end
end
```

| 메서드 | 경로 | 의미 |
|---|---|---|
| `GET /api/requests` | 목록 조회 | index |
| `GET /api/requests/:id` | 단건 조회 | show |
| `POST /api/requests` | 생성 | create |
| `POST /api/requests/:id/jobs` | 하위 리소스 생성 | jobs#create |

동사(만들기/삭제하기)를 URL에 넣지 않고, HTTP 메서드(GET/POST/PATCH/DELETE)로 표현하는 게 REST의 핵심입니다. `POST /api/requests/delete` 같은 경로보다 `DELETE /api/requests/:id`가 더 표준적인 형태입니다.

---

## 5️⃣ 응답에 무엇을 담을지 — 모델을 그대로 노출하지 않는다

```ruby
# ❌ 위험: 모델 전체를 그대로 노출
render json: @user

# ✅ 안전: 노출해도 되는 필드만 골라서 구성
render json: {
  id: @user.id,
  email: @user.email,
  name: @user.name
  # password_digest, reset_password_token 등은 절대 포함하지 않는다
}
```

`render json: @user`처럼 모델을 그대로 직렬화하면, 나중에 민감한 컬럼(비밀번호 해시, 내부용 토큰 등)이 추가됐을 때 실수로 API 응답에 같이 노출될 위험이 있습니다. 응답에 들어갈 필드를 명시적으로 골라 쓰는 습관이 안전합니다.

---

## ✅ 챕터 14 체크리스트

- [ ] HTML 화면용 컨트롤러와 API용 컨트롤러를 구분했다
- [ ] 브라우저 세션이 없는 호출자를 위한 별도 인증 방식(토큰 등)을 마련했다
- [ ] 토큰 비교에 타이밍 공격에 안전한 방식을 썼다
- [ ] 성공/실패 응답 포맷이 일관되고, HTTP 상태 코드가 실제 결과와 일치한다
- [ ] 모델을 그대로 노출하지 않고, 응답에 포함할 필드를 명시적으로 골랐다

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| 화면과 API는 분리한다 | 반환 형식과 인증 방식이 다른 경우가 많아, 컨트롤러를 나누는 게 유지보수에 유리하다 |
| HTTP 상태 코드는 거짓말하지 않는다 | 실패는 실패답게, 2xx가 아닌 코드로 응답한다 |
| 모델이 아니라 계약을 노출한다 | API 응답 형태는 우리가 정한 "계약"이지, DB 컬럼을 그대로 복사한 게 아니다 |
| 토큰은 안전하게 비교한다 | 일반 문자열 비교 대신 타이밍 공격에 안전한 비교 방식을 쓴다 |

---

## ➡️ 다음 챕터

15장에서는 이렇게 만든 기능들이 계속 잘 동작하는지 확인하는 **테스트**를 다룹니다.

---

*이 장은 아직 이 프로젝트의 실제 사례가 아니라 일반적인 Rails API 설계 원칙으로 채워져 있습니다. 실제 API 관련 작업을 하게 되면 그 경험으로 보강할 예정입니다.*
