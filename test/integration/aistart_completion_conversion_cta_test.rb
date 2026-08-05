require "test_helper"

class AistartCompletionConversionCtaTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @chatdox = Product.find_by!(code: "chatdox")
    @claudox = Product.find_by!(code: "claudox")
    @user = User.create!(name: "완독 사용자", email: "aistart-finisher@example.com", password: "password123")
  end

  test "1. Unauthenticated guest viewing Aistart chapter 05 sees confirmed copywriting, sign-up CTA, and pricing link" do
    get product_chapter_path("aistart", "05")
    assert_response :success

    # Confirmed headlines and copy
    assert_select "#aistart-completion-cta" do
      assert_select "h2", text: "무료 가이드로 AI 협업의 감을 잡으셨나요?"
      assert_select "p", text: "이제 실제 서비스를 만들고 팀의 업무 방식을 바꾼 과정을 Chatdox와 Claudox에서 이어서 살펴보세요."
      assert_select "p", text: /Chatdox: AI와 함께 SaaS를 기획하고 배포한 실전 과정/
      assert_select "p", text: /Claudox: AI 에이전트가 팀에 합류해 업무 방식을 바꾼 기록/
      assert_select "p", text: /두 상품 모두 일부 챕터를 무료로 확인할 수 있습니다/

      # Guest Primary & Secondary CTAs
      assert_select "a[href=?]", new_user_registration_path, text: "회원가입하고 실전 가이드 둘러보기"
      assert_select "a[href=?]", pricing_path, text: "전체 상품과 가격 보기"
    end
  end

  test "2. Logged-in user viewing Aistart chapter 05 sees dashboard CTA instead of sign-up CTA" do
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
    get product_chapter_path("aistart", "05")
    assert_response :success

    assert_select "#aistart-completion-cta" do
      # Sign-up CTA must NOT be present for logged-in user
      assert_select "a[href=?]", new_user_registration_path, count: 0
      assert_no_match(/회원가입하고 실전 가이드 둘러보기/, response.body)

      # Logged-in Primary & Secondary CTAs
      assert_select "a[href=?]", dashboard_path, text: "내 콘텐츠에서 이어보기"
      assert_select "a[href=?]", pricing_path, text: "전체 상품과 가격 보기"
    end
  end

  test "3. Aistart index and chapters 01 to 04 do not display completion CTA card" do
    # Aistart index page
    get product_content_index_path("aistart")
    assert_response :success
    assert_select "#aistart-completion-cta", count: 0

    # Aistart chapters 01 to 04
    %w[01 02 03 04].each do |id|
      get product_chapter_path("aistart", id)
      assert_response :success
      assert_select "#aistart-completion-cta", count: 0
    end
  end

  test "4. Chatdox and Claudox paid/free chapters do not display Aistart completion CTA card" do
    # Chatdox free chapter
    get product_chapter_path("chatdox", "01")
    assert_response :success
    assert_select "#aistart-completion-cta", count: 0

    # Claudox free chapter
    get product_chapter_path("claudox", "01")
    assert_response :success
    assert_select "#aistart-completion-cta", count: 0
  end

  test "5. Unauthenticated guest access to Aistart chapter 05 and other chapters remains 100% free" do
    %w[01 02 03 04 05].each do |id|
      get product_chapter_path("aistart", id)
      assert_response :success
      assert_no_match(/로그인 후 이용 가능합니다/, response.body)
    end
  end

  test "6. Unproven marketing claims (3초, 1화 무료, 20% 할인 쿠폰, /register) are not in the new card" do
    get product_chapter_path("aistart", "05")
    assert_response :success

    cta_card_html = response.body.slice(/id="aistart-completion-cta".*?<\/div>\s*<\/div>\s*<\/div>/m) || response.body
    assert_no_match(/3초/, cta_card_html)
    assert_no_match(/1화 무료/, cta_card_html)
    assert_no_match(/20%/, cta_card_html)
    assert_no_match(/쿠폰/, cta_card_html)
    assert_no_match(/\/register/, cta_card_html)
    assert_no_match(/#pricing-section/, cta_card_html)
  end
end
