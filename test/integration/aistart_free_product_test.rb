require "test_helper"

# Real end-to-end validation of stage 5 (the final step of the multi-product
# platform generalization): a genuine, HQ-authored product ("aistart", 5 free
# chapters) registered purely via Commerce::CatalogBootstrap + a
# sync_curriculum.sh content pull -- zero ProductContent/DocPolicy/
# ChapterProgress/dashboard/pricing code changes. See
# leedox_multi_product_platform_stage5_r1 result.md.
class AistartFreeProductTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @aistart = Product.find_by!(code: "aistart")
  end

  test "aistart is readable without login for its index and chapters (guest access restored, leedox_restore_free_content_guest_access_r1)" do
    get "/content/aistart"
    assert_response :success

    get "/content/aistart/01"
    assert_response :success
  end

  test "all 5 chapters are readable as a guest, each rendering its own real content" do
    get "/content/aistart"
    assert_response :success
    # No leading number prefix here anymore (leedox_content_template_unification_r1) --
    # the chapter id already shows once in its own icon badge, so the title
    # itself should be the plain heading text, not "1. 오늘, AI와 첫 만남".
    assert_match(/오늘, AI와 첫 만남/, response.body)
    assert_no_match(/1\.\s*오늘, AI와 첫 만남/, response.body)
    assert_match(/오늘의 첫 결과물/, response.body)

    source = ProductContent.for("aistart")
    assert_equal 5, source.chapters.size

    # Checking status 200 alone wouldn't catch a chapter accidentally
    # rendering the wrong file's content (e.g. an id/slug mixup) -- compare
    # against each chapter's real title and first body line straight from
    # the synced markdown file on disk instead.
    source.chapters.each do |chapter|
      get "/content/aistart/#{chapter[:id]}"
      assert_response :success
      assert_match(chapter[:title], response.body)

      file_path = source.path.join("#{chapter[:slug]}.md")
      first_body_line = File.readlines(file_path).drop(1).find { |line| line.strip.present? }.strip
      assert_includes response.body, first_body_line
    end

    get "/content/aistart/06"
    assert_response :not_found
    assert_match(/아직 공개되지 않은 챕터입니다/, response.body)
  end

  test "aistart does not appear on the user dashboard under Option B policy (handoff 0021)" do
    user = User.create!(name: "테스트 유저", email: "aistart-dashboard@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get dashboard_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    section = doc.css("section[aria-label]").find { |s| s["aria-label"].include?(@aistart.name) }
    assert_nil section, "aistart must be excluded from user dashboard under Option B policy"
  end

  test "aistart shows up on /pricing as a free product, not a not-yet-launched paid one" do
    get pricing_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    card = doc.css("article").find { |c| c.text.include?(@aistart.name) }
    assert card, "expected a pricing card for aistart"
    assert_match(/무료 이용 가능/, card.text)
    assert_match(/무료/, card.text)
    assert_no_match(/준비 중/, card.text)

    link = card.at_css("a")
    # Free-access products skip the login funnel (leedox_restore_free_content_guest_access_r1)
    # -- unlike paid products, whose /pricing detail link still routes through sign-in first.
    assert link, "expected a link straight to the content, bypassing the login funnel"
    assert_equal product_content_index_path("aistart"), link["href"]
  end

  test "checkout for aistart shows the same graceful not-ready screen as any other sale_enabled: false product" do
    get billing_checkout_path("aistart")
    assert_response :success
    assert_match(/신규 결제를 준비하고 있습니다/, response.body)
  end

  test "mypage does not error for a user with no license/order history on a free, offer-less product" do
    user = User.create!(name: "테스트 유저", email: "aistart-mypage@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get mypage_path
    assert_response :success
    assert_select "title", text: /마이페이지 - LEEDOX/
    assert_match(/AI, 오늘부터 시작/, response.body)
    assert_match(/무료 이용/, response.body)
    assert_match(/전체 이용 가능 · 기간 제한 없음/, response.body)
    assert_match(/아직 유료 상품 라이선스가 없습니다/, response.body)
    assert_select "a[href=?]", product_content_index_path("aistart"), text: /콘텐츠 보기/
  end
end
