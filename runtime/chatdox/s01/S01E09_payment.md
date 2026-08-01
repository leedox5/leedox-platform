# 09. 결제 (PortOne)

> Chatdox는 월 구독이 아니라 **자동 갱신 없는 기간제 선불 라이선스**를 판매합니다.
> 결제 공급자는 **PortOne V2 하나만** 씁니다 — 처음엔 Toss Payments를 직접 연동했지만, PG 채널 교체 유연성 때문에 PortOne으로 마이그레이션하면서 신규 결제는 PortOne 경로만 남기고 강제했습니다. (이후 카카오페이 심사 문제로 계좌이체를 임시 추가한 사연은 1️⃣1️⃣에서 다룹니다.)
> 결제 성공/실패/취소, 그리고 "같은 결제를 두 번 시도했을 때 주문이 중복 생성되지 않는 것"까지 다룹니다.

---

## 📋 목표

1. PortOne V2 Browser SDK + REST API 연동 구조 이해
2. `Product` / `ProductOffer` / `Order` / `OrderItem` / `License` / `PaymentTransaction` 데이터 모델 이해
3. 체크아웃부터 라이선스 발급까지 전체 흐름 구현
4. 서버 측 결제 검증(클라이언트 응답을 그대로 믿지 않는 원칙)
5. 결제 실패/취소, 그리고 중복 주문 방지
6. 웹훅으로 상태 동기화
7. PG 심사가 막혔을 때의 대안 결제 수단(계좌이체) 설계
8. 하나의 결제 인프라로 여러 상품을 지원하도록 일반화하기

---

## 1️⃣ 왜 PortOne 하나만 쓰는가

포트원은 PG(카드사/간편결제사)가 아니라 **여러 PG를 연결해주는 결제 인프라**입니다. 포트원 콘솔에 실제 PG 채널을 등록하고 `PORTONE_CHANNEL_KEY`로 그 채널을 지정하는 식으로 동작합니다.

이 코드베이스엔 사실 지금도 Toss Payments 연동 코드(`TossGateway`, `TossPayments::Client`, 웹훅 컨트롤러)가 파일로는 남아있습니다 — 처음 Toss로 직접 연동했다가 PortOne으로 옮겨가는 과정에서 생긴 흔적입니다. 하지만 런타임에서는 강제로 막혀 있습니다.

```ruby
# app/services/payments/gateway.rb (개념 발췌)
def self.current
  provider = ENV.fetch("PAYMENT_PROVIDER", nil)
  raise "PortOne만 지원합니다" unless provider == "portone"
  PortoneGateway.new
end
```

`Payments::Configuration#checkout_ready?`도 provider가 `"portone"`이 아니면 항상 false를 반환합니다. **새 결제는 무조건 PortOne 경로로만 갈 수 있습니다.** 남아있는 Toss 코드는 과거에 이미 결제했던 고객 데이터를 조회하기 위한 것이지, 신규 결제 경로가 아닙니다.

> 💡 실전 교훈: "언젠가 필요할지도 모르니 두 공급자를 다 지원하자"는 설계는 코드량만 두 배로 늘립니다. 실제로 이 프로젝트는 초기엔 Toss/PortOne 이중 지원 구조였지만, GoLive 정리 과정에서 "Simple is best" 원칙에 따라 죽은 Toss 경로를 정리 대상으로 분류했습니다.

---

## 2️⃣ 이 서비스가 파는 것: 구독이 아니라 "기간제 라이선스"

일반적인 SaaS 튜토리얼은 보통 "매달 자동 결제되는 구독"을 다룹니다. Chatdox는 다릅니다.

| 항목 | 일반적인 SaaS 구독 | Chatdox |
|---|---|---|
| 결제 방식 | 매달 자동 청구(빌링키) | **선불 일회성 결제** |
| 자동 갱신 | 있음 | **없음** |
| 만료 시 | 자동 재결제 시도 | 접근 종료, 재구매는 새 주문 |
| 필요한 기능 | 빌링키 발급, 정기 청구 Job, 결제 실패 재시도 | 필요 없음 |

```text
1개월  —   7,700원(VAT포함)
3개월  —  23,100원
6개월  —  41,580원 (10% 할인)
12개월 —  73,920원 (20% 할인)
```

자동 갱신이 없다는 건 코드가 훨씬 단순해진다는 뜻입니다 — 빌링키 저장, 정기 청구 스케줄러, 실패 시 재시도 로직이 전부 필요 없습니다. 라이선스 시작일부터 종료일까지 계산해서 접근 권한만 부여하면 됩니다.

---

## 3️⃣ 데이터 모델

```text
User ─┬─ has_many Order ──┬─ has_many OrderItem ── belongs_to Product, ProductOffer
      │                   │              └─ has_one License
      │                   ├─ has_one  PaymentTransaction
      │                   └─ has_many RefundRequest
      └─ has_many License
```

핵심 테이블 6개:

```ruby
# Product — 판매 대상(chatdox, claudox)
t.string  :code, null: false          # "chatdox"
t.string  :name, null: false
t.boolean :active,       default: true
t.boolean :sale_enabled, default: false   # 판매 스위치, 시딩만으로는 켜지지 않음

# ProductOffer — 상품의 기간별 가격 옵션
t.references :product, null: false
t.string  :code, null: false          # "chatdox-1m-v1"
t.integer :duration_months, null: false
t.integer :supply_amount, null: false  # 공급가
t.integer :vat_amount, null: false
t.integer :total_amount, null: false   # 실제 결제 금액
t.integer :discount_bps, default: 0    # 할인율(basis points)

# Order — 구매 시도, 상태머신 pending → paid|failed|canceled|abandoned
t.references :user, null: false
t.string  :public_id, null: false      # 외부에 노출되는 주문 ID
t.string  :provider, null: false       # "portone"
t.string  :status, default: "pending"
t.integer :total_amount, null: false   # 생성 시점 스냅샷, 이후 불변
t.date    :requested_start_on

# OrderItem — 구매 시점 Product+ProductOffer 스냅샷
t.references :order, null: false
t.references :product, null: false
t.references :product_offer, null: false
t.integer :duration_months, null: false

# License — 실제 보유 권한
t.references :user, null: false
t.references :product, null: false
t.references :order_item
t.date :starts_on, null: false
t.date :access_ends_at, null: false    # KST 자정 기준 계산
t.string :status, default: "scheduled" # scheduled/active/canceled

# PaymentTransaction — PG 연동 기록
t.references :order, null: false
t.string :provider, null: false
t.string :provider_payment_id, null: false
t.string :status, default: "pending"
```

`Order`가 생성되는 시점에 가격/기간을 **스냅샷으로 저장**하는 게 중요합니다. 나중에 `ProductOffer`의 가격이 바뀌어도, 이미 생성된 주문의 금액은 그대로 유지됩니다.

---

## 4️⃣ 결제 흐름 전체 그림

```text
[사용자] 오퍼 선택(1/3/6/12개월)
  ↓
[Rails] GET /billing/checkout — 판매 gate 확인, 오퍼 목록 표시
  ↓ 오퍼 선택 후 제출
[Rails] POST /billing/orders — pending Order + OrderItem + PaymentTransaction 생성
  ↓ 주문 상세 페이지로 리다이렉트
[Rails] GET /billing/orders/:id — PortOne 결제창 호출 버튼 렌더링
  ↓ 버튼 클릭
[PortOne Browser SDK] requestPayment()
  ↓ 카드 결제 진행
[PortOne] → redirectUrl로 이동
  ↓
[Rails] GET /billing/success — 서버가 PortOne REST API로 재검증
  ↓ 검증 통과
[Commerce::OrderFinalizer] Order → paid, License 발급
```

**"pending Order는 결제 완료 전에 이미 생성된다"**는 점이 중요합니다 — 사용자가 결제창을 열기만 하고 안 닫고, 취소하고, 다시 시도해도 그때마다 DB엔 흔적이 남습니다. 8️⃣에서 이 문제를 실제로 어떻게 다뤘는지 다룹니다.

---

## 5️⃣ 체크아웃 화면과 주문 생성

```ruby
# app/controllers/billing_controller.rb (발췌)
def checkout
  @chatdox_product = Product.find_by(code: "chatdox")
  unless Commerce::Sales.enabled_for?(@chatdox_product)
    render :checkout   # "구매 준비 중" 화면
    return
  end

  configuration = Payments::Configuration.current
  unless configuration.checkout_ready?
    render :checkout
    return
  end

  authenticate_user!
  return if performed?

  @offers = @chatdox_product.product_offers.active.ordered.select(&:available_at?)
  render :checkout_enabled
end
```

판매 여부(`sale_enabled`)와 결제 설정 완비 여부(`checkout_ready?`) **두 게이트를 모두 통과해야만** 실제 오퍼 목록과 구매 버튼이 보입니다. 둘 중 하나라도 막혀 있으면 "구매 준비 중" 화면만 보여줍니다.

오퍼를 선택해 제출하면 `POST /billing/orders`가 새 pending Order를 만듭니다(구체적인 서비스 객체는 8️⃣ 참고).

---

## 6️⃣ PortOne 결제창 호출 (실제 코드)

```erb
<!-- app/views/billing_orders/show.html.erb -->
<script src="https://cdn.portone.io/v2/browser-sdk.js"></script>

<button id="payment-button">
  <%= number_with_delimiter(@order.total_amount) %>원 결제하기
</button>

<script>
  document.getElementById("payment-button").addEventListener("click", async () => {
    try {
      const response = await PortOne.requestPayment({
        storeId: <%= raw json_escape(@portone_store_id.to_json) %>,
        channelKey: <%= raw json_escape(@portone_channel_key.to_json) %>,
        paymentId: <%= raw json_escape(@order.public_id.to_json) %>,
        orderName: <%= raw json_escape("#{@order_item.product_name} #{@order_item.duration_months}개월".to_json) %>,
        totalAmount: <%= @order.total_amount %>,
        currency: <%= raw json_escape(@order.currency.to_json) %>,
        payMethod: "CARD",
        customer: { email: <%= raw json_escape(current_user.email.to_json) %> },
        redirectUrl: <%= raw json_escape(billing_success_url.to_json) %>
      });
      if (response.code) throw new Error(response.message || "결제가 취소되었습니다.");
      window.location.href = <%= raw json_escape(billing_success_url.to_json) %> + "?paymentId=" + encodeURIComponent(response.paymentId);
    } catch (paymentError) {
      // 화면에 paymentError.message 표시
    }
  });
</script>
```

> ⚠️ `response.code`가 존재하면 실패로 간주하고, `response.message`가 없으면 "결제가 취소되었습니다"라는 고정 문구를 보여줍니다. 실제로는 카드 거절, 채널 설정 오류, 도메인 미등록 등 다양한 원인이 전부 이 문구로 뭉뚱그려질 수 있습니다 — **진짜 원인은 PortOne 콘솔의 결제내역에서 확인해야** 합니다. 화면 문구 하나만 보고 "사용자가 취소했다"고 단정하면 안 됩니다.

`paymentId`로 `@order.public_id`를 그대로 쓰는 게 핵심입니다 — 이렇게 해야 나중에 서버가 어떤 주문에 대한 결제인지 다시 찾을 수 있습니다.

---

## 7️⃣ 서버 측 검증 — 클라이언트를 믿지 않는다

```text
클라이언트 화면만 믿으면 안 된다.
진짜 결제 상태는 PortOne 서버 조회 API로 확정한다.
```

```ruby
# app/controllers/billing_controller.rb (발췌)
def success
  order = find_purchase_order
  process_purchase_order_success(order)
end

private

def process_purchase_order_success(order)
  raise Pundit::NotAuthorizedError unless order.user == current_user

  gateway = Payments::Gateway.for(order.provider)
  payment = gateway.verify_payment!(
    payment_id: params[:paymentId],
    expected_amount: order.total_amount,
    expected_currency: order.currency
  )

  Commerce::OrderFinalizer.call!(order: order, payment: payment_attributes)
  redirect_to dashboard_path, notice: "결제가 완료되었습니다."
end
```

`gateway.verify_payment!`는 요청 파라미터가 아니라 **PortOne 서버에 직접 조회**(`GET https://api.portone.io/payments/{paymentId}`)해서 다음을 확인합니다.

1. 조회한 결제 ID가 서버가 발급한 주문 ID와 같은가
2. 상태가 결제 완료 상태인가
3. `amount.total`이 서버에 저장된 주문 금액과 같은가(주문 생성 시점 스냅샷)
4. 통화가 `KRW`인가

넷 중 하나라도 안 맞으면 결제를 확정하지 않습니다. **브라우저가 보낸 금액을 그대로 신뢰하지 않는다**는 원칙이 여기서 가장 중요합니다.

---

## 8️⃣ 결제 실패·취소·중복 처리 — 실전에서 실제로 겪은 문제

### 중복 pending 주문 문제 (실제로 발생했던 버그)

체크아웃 폼을 제출할 때마다(결제창을 닫고 다시 시도, 오퍼를 바꿔서 다시 시도) 아무 방지 장치 없이 매번 새 `Order`를 만들면 어떻게 될까요? 실제로 이 프로젝트에서 첫 실전 테스트를 하며 겪은 일입니다 — 실제 완료한 주문은 2건인데 "결제 대기" 주문이 4건이나 쌓여 있었습니다.

원인은 단순했습니다.

```ruby
# 문제가 있던 버전 — 매번 무조건 새 Order 생성
def call!
  Order.create!(user: @user, status: "pending", ...)
  # 이미 pending 주문이 있는지 확인하는 로직이 없었음
end
```

해결책은 체크아웃 진입점에만 중복 방지 로직을 추가하는 것이었습니다.

```ruby
# app/services/commerce/checkout_submission.rb (요지)
def call!
  existing_pending = find_existing_pending(product)

  if existing_pending
    return existing_pending if existing_pending.order_items.first!.offer_code == @offer_code
    return existing_pending unless Commerce::PendingOrderAssessment.evidence_free?(order: existing_pending)
  end

  ApplicationRecord.transaction do
    replace_pending_order!(existing_pending) if existing_pending
    Commerce::OrderCreator.call!(user: @user, product_code: @product_code, offer_code: @offer_code, ...)
  end
end
```

- **같은 오퍼로 재제출** → 새로 안 만들고 기존 pending 주문을 그대로 재사용
- **다른 오퍼로 재제출** → PG가 아직 손대지 않은(`evidence_free?`) 게 확인되면 기존 주문을 안전하게 폐기하고 새로 생성
- **paid 주문은 전혀 영향 없음** — pending 상태만 확인 대상

> 💡 여기서 배운 것: 이 로직을 처음엔 저수준 `Commerce::OrderCreator`(주문을 실제로 만드는 서비스) 안에 직접 넣으려 했는데, 그러면 "재시도 흐름"이나 테스트 코드가 의도적으로 "같은 조건으로 독립된 주문 여러 개"를 만드는 경우까지 막혀버렸습니다. 그래서 dedup 로직은 **실제 체크아웃 폼 제출이라는 특정 진입점**(`CheckoutSubmission`)에만 얇게 씌우고, 저수준 생성 로직(`OrderCreator`) 자체는 건드리지 않았습니다. "여러 곳에서 재사용되는 저수준 함수"와 "한 화면의 특정 정책"을 같은 곳에 섞지 않는 게 핵심이었습니다.

### 결제 취소/실패

```ruby
def cancel
  redirect_to dashboard_path, alert: "결제가 취소되었습니다."
end
```

결제 승인 검증(7️⃣)이 실패하면 `Order`는 `pending` 상태 그대로 남습니다 — 함부로 `failed`로 단정하지 않고, 사용자가 `/billing/orders/:id/retry`로 같은 주문을 안전하게 다시 시도할 수 있게 열어둡니다.

---

## 9️⃣ 웹훅으로 상태 동기화

`POST /webhooks/portone` 엔드포인트를 별도로 둡니다. 처리 순서가 중요합니다.

```text
서명 검증 → 중복 확인 → 서버 재조회 → 금액/상태 확인 → DB 트랜잭션
```

웹훅 payload 내용만 믿고 상태를 바로 바꾸지 않습니다 — payload는 "이 결제ID를 다시 확인해봐"라는 신호일 뿐이고, 실제 상태는 항상 PortOne 서버에 재조회해서 확정합니다. `(provider, provider_payment_id)` 고유 인덱스로 같은 이벤트가 여러 번 와도 한 번만 반영되게 막습니다.

---

## 🔟 테스트 방법 (샌드박스)

1. PortOne 콘솔에서 테스트 채널의 Store ID / Channel Key 발급
2. `PAYMENT_PROVIDER=portone` + 테스트 채널 값으로 환경변수 설정
3. `LEEDOX_COMMERCE_ENABLED=true`, 어드민 화면(11장 참고)에서 `Product.sale_enabled` 켜기
4. 실제로 회원가입부터 체크아웃, 결제, 대시보드에서 라이선스 확인까지 전 과정을 사람이 직접 눌러본다

확인 포인트:

1. 결제창이 정상 로드되는가
2. `redirectUrl`로 `paymentId`가 전달되는가
3. 서버 재조회 검증이 통과하는가
4. `License`가 정확한 시작일/종료일로 발급되는가
5. 같은 콜백/웹훅이 반복되어도 한 번만 반영되는가
6. 체크아웃을 여러 번 시도해도 pending 주문이 1개로 유지되는가

---

## 1️⃣1️⃣ 카카오페이 심사가 막혔을 때 — 계좌이체로 우회하기

실제 서비스 오픈을 준비하며 카카오페이 채널을 열려고 했더니, 조건이 하나 걸려 있었습니다. **실제로 구매 가능한 상품이 2~3주간 라이브 상태로 운영되고 있어야** 심사가 진행된다는 것이었습니다. 그런데 정작 카드 결제(PortOne 채널) 승인 자체도 다른 채널 심사에 걸려 진행이 막혀 있었습니다 — 상품을 열려면 심사가 필요하고, 심사를 받으려면 상품이 열려 있어야 하는 순환 구조였습니다.

이 순환을 끊는 방법은 카드/간편결제가 아닌 **수동 계좌이체**였습니다. PG 심사가 전혀 필요 없는, 가장 오래된 결제 방식으로 일단 "구매 가능한 상품"을 만드는 것이었습니다.

```ruby
# app/models/order.rb
MANUAL_PROVIDER = "manual"

# app/services/payments/gateway.rb
PROVIDERS = %w[portone manual].freeze

def self.for(provider)
  case provider
  when "portone" then PortoneGateway.new
  # "manual"은 의도적으로 매핑하지 않는다 — 자동 결제 검증 대상이 아니기 때문
  else raise "지원하지 않는 provider: #{provider}"
  end
end
```

계좌이체는 PG가 대신 검증해주지 않으므로, 결제 확정도 사람이 직접 처리합니다.

```ruby
# app/services/commerce/confirm_manual_payment.rb (요지)
def call!
  raise "이미 처리된 주문입니다" unless @order.provider == Order::MANUAL_PROVIDER
  Commerce::OrderFinalizer.call!(order: @order, payment: manual_payment_attributes)
end
```

어드민이 실제 입금을 은행 앱으로 확인한 뒤 "입금 확인" 버튼을 누르면, 카드 결제와 똑같은 `Commerce::OrderFinalizer`를 재사용해 라이선스를 발급합니다. 결제 방식은 다르지만 "주문이 확정되면 무슨 일이 벌어지는가"는 하나로 유지한 것입니다. 처리 기한은 24시간 SLA로 안내했습니다.

> 💡 실전 교훈: 첫 설계안에는 "관리자 확인 버튼 하나만 있으면 된다"고 생각했지만, 실제 구현 과정에서 놓쳤던 관문이 세 개 더 나왔습니다(이미 처리된 주문의 재확정 방지, 계좌이체 주문에서 카드 전용 검증 로직이 잘못 타지 않게 분기, 어드민 권한 체크). 결제처럼 "돈이 걸린" 기능은 처음 떠올린 happy path보다 항상 숨은 분기가 많습니다.

## 1️⃣2️⃣ 결제 인프라를 상품 무관하게 만들기

계좌이체로 카카오페이 심사용 상품 하나(Chatdox)는 열었지만, 곧 두 번째 상품(Claudox)도 판매를 시작하려 하면서 문제가 드러났습니다. `billing_controller`가 애초부터 `Product.find_by(code: "chatdox")`처럼 **Chatdox 하나만 알도록 하드코딩**되어 있었던 것입니다. "상품 데이터만 새로 만들면 자동으로 반영될 것"이라는 첫 가정은 틀렸습니다.

체크아웃 경로 전체를 상품 코드로 파라미터화했습니다.

```ruby
# app/controllers/billing_controller.rb (개념 발췌)
def checkout
  @product = Product.find_by!(code: params[:product_code] || "chatdox")
  @provider = checkout_provider_for(@product)
  # ...
end

private

def checkout_provider_for(product)
  Commerce::Sales.manual_only?(product) ? Order::MANUAL_PROVIDER : "portone"
end
```

```ruby
# config/routes.rb
get "/billing/checkout(/:product_code)", to: "billing#checkout"
```

가격 카드도 상품별로 따로 두지 않고, `product_code` 하나만 받으면 스스로 `Product`/`ProductOffer`/판매 상태를 조회해 렌더링하는 공용 partial로 바꿨습니다.

```erb
<!-- app/views/shared/_product_pricing.html.erb -->
<%= render "shared/product_pricing", product_code: "claudox" %>
```

이 구조가 실제로 상품 무관한지는 **세 번째 가상 상품**을 만들어 검증했습니다. 컨트롤러/뷰 코드를 한 줄도 안 건드리고 새 상품이 그대로 체크아웃까지 도는 걸 확인한 뒤에야 이 리팩터링을 완료로 표시했습니다.

---

## ✅ 챕터 9 체크리스트

- [ ] `Product`/`ProductOffer`/`Order`/`OrderItem`/`License`/`PaymentTransaction` 데이터 모델을 이해했다
- [ ] `Commerce::Sales.enabled_for?` + `Payments::Configuration#checkout_ready?` 두 게이트를 통과해야 체크아웃이 열린다
- [ ] PortOne Browser SDK로 결제창을 호출할 수 있다
- [ ] 서버에서 PortOne API로 재조회해서 금액/상태를 검증한다(클라이언트 응답을 그대로 신뢰하지 않는다)
- [ ] 같은 유저·같은 상품의 pending 주문이 중복 생성되지 않는다
- [ ] 웹훅은 서명 검증 → 중복 확인 → 서버 재조회 순서로 처리한다
- [ ] 샌드박스 채널로 성공/실패/재시도 흐름을 실제로 검증했다
- [ ] PG 심사가 막힌 상황에서 계좌이체 같은 대안 결제 수단을 설계할 수 있다
- [ ] 결제 컨트롤러/라우트/뷰를 특정 상품에 종속되지 않게 파라미터화할 수 있다

### 공식 참고 문서

- [PortOne V2 REST API 개요](https://developers.portone.io/api/rest-v2/overview?v=v2)
- [PortOne V2 결제 연동](https://developers.portone.io/opi/ko/integration/start/v2/checkout?v=v2)
- [PortOne V2 웹훅](https://developers.portone.io/opi/ko/integration/webhook/readme-v2?v=v2)

---

## ➡️ 다음 챕터

10장에서는 사용자별 라이선스/주문 상태를 확인할 수 있는 **대시보드**를 구현합니다.
