require "test_helper"

# Handoff 0092 R4 (D-012) -- "읽은 뒤 이어 보기": /products/:slug/continue[?to=NN] signs a guest in (and back), confirms once
# before a free guide starts (POST -- the same free start as 이용하기), sends a paid guide to its checkout, and then goes
# to the episode in ?to= (only a published episode of this guide) or the episode list. A GET never creates a license.
# The end of an 열린 편 offers the way on to anyone without the license, instead of a next-episode link they can't open.
class GuideContinueTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "gc-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "gc-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("free-guide", 0)
    @paid = guide!("paid-guide", 1_100)
    @other = guide!("other-guide", 0, episodes: 9)
  end

  def guide!(slug, amount, episodes: 2)
    line = ProductLine.create!(internal_name: slug, customer_name: "가이드 #{slug}", slug: slug, introduction: "소개", status: "published")
    (1..episodes).each { |p| line.content_episodes.create!(position: p, customer_title: "편 #{p}", body: "본문 #{p}", status: "published") }
    line.content_episodes.create!(position: episodes + 1, customer_title: "초안", body: "초안", status: "draft")
    line.content_episodes.find_by!(position: 1).update!(open_preview: true)
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def licenses = License.where(user: @member, product: @free.product)

  # --- a GET never creates a license -------------------------------------------------------------------------

  test "GET /continue creates no license for a guest, a member before use, or a prefetch" do
    assert_no_difference -> { License.count } do
      get product_continue_path("free-guide", to: "02")
      sign_in(@member)
      get product_continue_path("free-guide", to: "02")
      get product_continue_path("free-guide", to: "02"), headers: { "Sec-Purpose" => "prefetch" }
      get product_continue_path("free-guide")
    end
    assert_response :success # the confirmation page
  end

  # --- the flows (a) -----------------------------------------------------------------------------------------

  test "guest -> sign in -> back to the confirmation -> POST starts the guide -> E02 opens" do
    get product_continue_path("free-guide", to: "02")
    assert_redirected_to new_user_session_path
    sign_in(@member)
    assert_redirected_to product_continue_path("free-guide", to: "02")
    follow_redirect!
    assert_response :success
    assert_select "#guide-continue h1", text: "이 가이드를 시작하고 E02부터 볼까요?"
    assert_includes css_select("#guide-continue").text, "지금은 모든 에피소드를 무료로 이용할 수 있습니다. 시작해 두면 계속 볼 수 있습니다."
    assert_select "#guide-continue form[action=?][method=post] button", product_continue_path("free-guide", to: "02"), text: "이용하고 이어 보기"
    assert_select "#guide-continue a[href=?]", product_line_path("free-guide"), text: "← 가이드로 돌아가기"

    assert_difference -> { licenses.count }, 1 do
      post product_continue_path("free-guide", to: "02")
    end
    assert_redirected_to product_episode_path("free-guide", "02")
    follow_redirect!
    assert_response :success
    assert_includes css_select("main").text, "본문 2"
  end

  test "a new sign-up comes back to the same confirmation" do
    get product_continue_path("free-guide", to: "02")
    post user_registration_path, params: { user: { name: "새 회원", email: "gc-new-#{SecureRandom.hex(3)}@example.com",
      password: "fresh-pass-2026", password_confirmation: "fresh-pass-2026", terms_accepted: "1" } }
    assert_redirected_to product_continue_path("free-guide", to: "02")
  end

  test "without ?to= the page asks 'start this guide?', and the POST goes to the episode list" do
    sign_in(@member)
    get product_continue_path("free-guide")
    assert_select "#guide-continue h1", text: "이 가이드를 시작할까요?"
    assert_select "#guide-continue button", text: "이용하기"
    post product_continue_path("free-guide")
    assert_redirected_to product_line_path("free-guide", anchor: "episodes")
  end

  test "already using the guide: straight to the destination, no confirmation" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_continue_path("free-guide", to: "02")
    assert_redirected_to product_episode_path("free-guide", "02")
  end

  test "a repeated POST keeps one license and still goes on" do
    sign_in(@member)
    post product_continue_path("free-guide", to: "02")
    assert_no_difference -> { licenses.count } do
      post product_continue_path("free-guide", to: "02")
    end
    assert_redirected_to product_episode_path("free-guide", "02")
    assert_equal 1, licenses.count
  end

  test "a paid guide goes to its checkout; a closed one to the guide page; one not open to customers is a 404" do
    sign_in(@member)
    get product_continue_path("paid-guide", to: "02")
    assert_redirected_to billing_checkout_path(@paid.product.code)

    @free.product.update!(sale_enabled: false)
    get product_continue_path("free-guide", to: "02")
    assert_redirected_to product_line_path("free-guide")
    assert_no_difference -> { License.count } do
      post product_continue_path("free-guide", to: "02")
    end
    assert_redirected_to product_line_path("free-guide")

    @other.update_columns(status: "draft")
    get product_continue_path("other-guide", to: "02")
    assert_response :not_found
  end

  # --- ?to= only ever means a published episode of this guide ----------------------------------------------

  test "?to= that isn't a published episode of this guide falls back to the episode list" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    list = product_line_path("free-guide", anchor: "episodes")
    {
      "09" => "another guide's episode number",
      "03" => "a draft episode",
      "abc" => "not a number",
      "//evil.example" => "an outside address",
      "https://evil.example/x" => "an outside URL",
      "" => "empty"
    }.each do |to, why|
      get product_continue_path("free-guide", to: to)
      assert_redirected_to list, why
    end
    get product_continue_path("free-guide", to: "2") # without the leading zero, still that episode
    assert_redirected_to product_episode_path("free-guide", "02")
  end

  # --- the box at the end of an 열린 편 (b) --------------------------------------------------------------------

  def box = css_select("#continue-box").first
  def next_link_shown? = css_select("main a").any? { |a| a.text.include?("→") && a["href"]&.end_with?("/02") }

  test "guest, free: 'E02부터는 로그인하고 이어서 보세요. …' + 로그인하고 이어 보기 -> continue?to=02, no next link" do
    get product_episode_path("free-guide", "01"), headers: BROWSER
    assert_equal "E02부터는 로그인하고 이어서 보세요. 지금은 모든 에피소드를 무료로 이용할 수 있고, 시작해 두면 계속 볼 수 있습니다.",
      box.at_css("p").text.strip
    assert_includes box.text, "다음 편 · 편 2"
    assert_equal product_continue_path("free-guide", to: "02"), box.at_css("a")["href"]
    assert_equal "로그인하고 이어 보기", box.at_css("a").text.strip
    assert_not next_link_shown?
  end

  test "member before use, free: 'E02부터는 이용을 시작하면 …' + 이용하고 이어 보기 as a POST right here" do
    sign_in(@member)
    get product_episode_path("free-guide", "01"), headers: BROWSER
    assert_equal "E02부터는 이용을 시작하면 볼 수 있습니다. 지금은 모든 에피소드를 무료로 이용할 수 있고, 시작해 두면 계속 볼 수 있습니다.",
      box.at_css("p").text.strip
    assert_select "#continue-box form[action=?][method=post] button", product_continue_path("free-guide", to: "02"), text: "이용하고 이어 보기"
    post product_continue_path("free-guide", to: "02")
    assert_redirected_to product_episode_path("free-guide", "02")
  end

  test "paid, guest or not bought: 'E02부터는 구매하면 볼 수 있습니다.' + 구매하고 이어 보기 -> continue -> checkout" do
    get product_episode_path("paid-guide", "01"), headers: BROWSER
    assert_equal "E02부터는 구매하면 볼 수 있습니다.", box.at_css("p").text.strip
    assert_equal [ "구매하고 이어 보기", product_continue_path("paid-guide", to: "02") ], [ box.at_css("a").text.strip, box.at_css("a")["href"] ]
    sign_in(@member)
    get product_episode_path("paid-guide", "01"), headers: BROWSER
    assert_equal "구매하고 이어 보기", box.at_css("a").text.strip
    get box.at_css("a")["href"]
    assert_redirected_to billing_checkout_path(@paid.product.code)
  end

  test "an 열린 편 that is the last episode: the box offers the guide (이용하기 / 구매하기, no ?to=)" do
    @free.content_episodes.find_by!(position: 2).update!(open_preview: true)
    get product_episode_path("free-guide", "02"), headers: BROWSER
    assert_equal "이 가이드를 시작하면 실전 자료와 댓글을 볼 수 있습니다.", box.at_css("p").text.strip
    assert_equal [ "이용하기", product_continue_path("free-guide") ], [ box.at_css("a").text.strip, box.at_css("a")["href"] ]

    @paid.content_episodes.find_by!(position: 2).update!(open_preview: true)
    get product_episode_path("paid-guide", "02"), headers: BROWSER
    assert_equal "구매하면 실전 자료와 댓글을 볼 수 있습니다.", box.at_css("p").text.strip
    assert_equal "구매하기", box.at_css("a").text.strip
  end

  test "with the license there's no box and the next link is as before" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_episode_path("free-guide", "01"), headers: BROWSER
    assert_nil box
    assert next_link_shown?
  end

  # --- the links (c, d) ---------------------------------------------------------------------------------------

  test "the guest's 이용하기 and the locked cards go to continue; the 열린 편 card to the episode" do
    get product_line_path("free-guide")
    assert_select "#product-purchase a[href=?]", product_continue_path("free-guide"), text: "이용하기"
    assert_select "#episodes + ol a[href=?]", product_episode_path("free-guide", "01")
    assert_select "#episodes + ol a[href=?]", product_continue_path("free-guide", to: "02")
    get product_episode_path("free-guide", "02") # typing an episode URL still meets the gate
    assert_redirected_to new_user_session_path
  end
end
