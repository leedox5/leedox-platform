# Devise 세션 기반 전환 퍼널 & GitHub CLI 자율 PR/Merge 워크플로우

> **Phase 4: 자율 디버깅 & 자율 PR/Merge 배포 파이프라인**  
> **Key Objective**: 비로그인 유저를 로그인 페이지로 유도 후 원 목적지로 자동 복귀시키는 Devise 세션 퍼널과, GitHub CLI(`gh`)를 활용한 자율 PR/Merge 배포 파이프라인을 완성한다.

---

## 📖 1. Devise `store_location_for` 세션 기반 퍼널

비로그인 유저가 [자세히 보기] 클릭 시 로그인 페이지(`/users/sign_in?redirect_to=/content/aigravity`)로 유도하고, 로그인 완료 후 Devise 세션에 저장된 주소로 자동 리다이렉트합니다.

```ruby
# ApplicationController
def store_redirect_location
  if params[:redirect_to].present?
    store_location_for(:user, params[:redirect_to])
  end
end
```

---

## 🔤 2. Core English Definition

> **Core English Definition**: *Conversion Funnel & Autonomous PR Workflow*  
> - **Simple Definition**: Guiding unauthenticated users through a seamless login funnel while letting AI agents issue, review, and merge GitHub Pull Requests autonomously via CLI.  
> - **Practical Meaning**: 유저의 이탈을 방지하고 로그인 완료 후 목적지로 돌려보내는 전환 퍼널 패턴과, CLI 명령어로 브랜치 생성부터 PR 발행 및 머지까지 완전 자동화하는 자율 파이프라인.



