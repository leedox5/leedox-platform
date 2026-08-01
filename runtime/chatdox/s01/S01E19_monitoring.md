# 19. 모니터링 & 에러 추적

> 서비스를 열고 나면 "지금 잘 되고 있나?"를 사람이 계속 화면을 눌러보며 확인할 수는 없습니다. 문제가 생겼을 때 사람보다 먼저 알아채고 알려주는 장치가 필요합니다. 이 장에서는 에러 추적, 로그, 헬스체크의 기본을 다룹니다.

---

## 📋 목표

1. 에러가 났을 때 사람이 신고하기 전에 먼저 알아채는 구조를 만든다
2. 로그에 무엇을 남기고, 무엇을 남기면 안 되는지 구분한다
3. 서버가 정상 동작 중인지 외부에서 확인할 수 있는 창구(헬스체크)를 만든다

---

## 1️⃣ 왜 에러 추적 서비스가 필요한가

에러가 나면 Rails는 기본적으로 서버 로그에 스택트레이스를 남깁니다. 문제는 로그가 서버 어딘가에 쌓이기만 할 뿐, **누가 그걸 실시간으로 보고 있지 않으면 아무도 모른다**는 것입니다.

Sentry 같은 에러 추적 서비스는 에러가 발생하는 순간 그 내용(에러 메시지, 발생 위치, 어떤 요청이었는지)을 자동으로 수집해서 알림을 보내줍니다. 같은 에러가 반복되면 "새 에러"가 아니라 "기존 이슈가 몇 번째 또 발생"으로 묶어서 보여주기 때문에, 진짜 새로운 문제와 이미 알고 있는 문제를 구분하기도 쉬워집니다.

```ruby
# Gemfile
gem "sentry-ruby"
gem "sentry-rails"

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.breadcrumbs_logger = [:active_support_logger]
  config.traces_sample_rate = 0.1   # 성능 추적은 일부만 샘플링
end
```

> 참고: 이 프로젝트도 인프라 준비 단계에서 Sentry + Railway 조합을 검토해서 조건부로 승인해뒀지만, 이 문서를 쓰는 시점까지는 아직 실제로 연결하지 않았습니다. "결정은 했지만 아직 실행 전"인 상태도 실제 프로젝트에서는 흔합니다 — 우선순위에 따라 먼저 처리해야 할 일들이 있었기 때문입니다.

---

## 2️⃣ 로그 — 무엇을 남기고 무엇을 가릴지

```ruby
Rails.logger.info("Order created: #{order.public_id}")
Rails.logger.warn("Payment verification retried: #{order.public_id}")
Rails.logger.error("DB backup failed: pg_dump exited with status #{status}")
```

로그 레벨을 상황에 맞게 씁니다.

| 레벨 | 언제 쓰나 |
|---|---|
| `debug` | 개발 중에만 필요한 상세 정보 |
| `info` | 정상적인 흐름 중 기록해둘 만한 이벤트 |
| `warn` | 실패는 아니지만 주의 깊게 볼 상황 |
| `error` | 실제로 실패한 상황 |

**민감정보는 로그에도 남기지 않습니다.** 비밀번호, API 키, 카드 정보 같은 값은 에러 메시지 안에 섞여 들어올 수 있으니(17장에서 다룬 redact 패턴 참고), 로그에 무엇이 찍히는지 한 번씩 직접 확인하는 습관이 필요합니다.

---

## 3️⃣ 헬스체크 — 서버가 살아있는지 확인하는 창구

```ruby
# config/routes.rb
get "/up", to: "rails/health#show", as: :rails_health_check
```

Rails는 기본으로 `/up` 헬스체크 엔드포인트를 제공합니다. 서버가 정상이면 200을, 문제가 있으면(예: DB 연결 실패) 다른 상태 코드를 반환합니다. Railway 같은 배포 플랫폼은 이 엔드포인트를 주기적으로 호출해서, 응답이 없으면 자동으로 재시작하거나 알림을 보낼 수 있습니다.

직접 커스텀 헬스체크를 만들 수도 있습니다.

```ruby
class HealthController < ApplicationController
  def show
    checks = {
      database: database_ok?,
      redis: redis_ok?
    }

    if checks.values.all?
      render json: { status: "ok", checks: checks }
    else
      render json: { status: "degraded", checks: checks }, status: :service_unavailable
    end
  end

  private

  def database_ok?
    ActiveRecord::Base.connection.active?
  rescue StandardError
    false
  end
end
```

---

## 4️⃣ 알림 — 발견보다 전달이 더 중요할 때가 있다

에러를 잘 수집해도, 아무도 안 보고 있으면 소용없습니다. 심각한 에러(결제 실패, 서버 다운)는 Slack이나 이메일로 바로 알림이 가게 연결해두는 게 좋습니다. 모든 에러를 다 알림으로 보내면 정작 중요한 알림이 묻히니, 심각도에 따라 알림 여부를 구분합니다.

---

## ✅ 챕터 19 체크리스트

- [ ] 에러가 발생하면 사람이 직접 로그를 뒤지지 않아도 알 수 있는 구조가 있다
- [ ] 로그 레벨을 상황에 맞게 구분해서 쓰고 있다
- [ ] 민감정보가 로그에 그대로 남지 않는다
- [ ] 서버가 정상 동작 중인지 외부에서 확인할 수 있는 헬스체크가 있다
- [ ] 심각한 문제는 사람에게 즉시 알림이 간다

---

## 🎯 핵심 원칙

| 원칙 | 설명 |
|------|------|
| 사람보다 시스템이 먼저 알아채야 한다 | 고객 문의로 장애를 처음 아는 상황은 피해야 한다 |
| 모든 에러가 같은 무게는 아니다 | 심각도를 구분해서, 정말 중요한 알림이 묻히지 않게 한다 |
| 로그도 보안 경계다 | 디버깅에 필요한 정보와 유출되면 안 되는 정보를 구분한다 |
| 결정과 실행은 다른 단계다 | "하기로 했다"와 "이미 돼 있다"를 구분해서 진행 상태를 정직하게 기록한다 |

---

*이 장은 아직 이 프로젝트에서 실제로 구현된 사례가 아니라, 검토·승인은 됐지만 실행 전인 계획과 일반적인 원칙으로 채워져 있습니다. 실제로 연결하고 나면 그 경험으로 보강할 예정입니다.*
