require "test_helper"

# Handoff 0092 R3 -- what the guide page says matches what a click does. Episode cards: 보기 → (+ 로그인 없이 보기 / 미리 보기
# on an 열린 편) when the episode opens, otherwise what it takes (로그인 후 보기 / 이용 시작 후 보기 / 구매 후 보기). The access
# box adds "E01은 로그인 없이 / 구매 전에 볼 수 있습니다." when there's an 열린 편, and the gate's redirect message is the
# guide's own (이용을 시작하면 / 구매하면 볼 수 있습니다.). All from the episode gate's own checks.
class OpenPreviewLabelsTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "ol-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "ol-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("free-guide", 0)
    @paid = guide!("paid-guide", 1_100)
  end

  def guide!(slug, amount)
    line = ProductLine.create!(internal_name: slug, customer_name: "가이드 #{slug}", slug: slug, introduction: "소개", status: "published")
    line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
    line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문", status: "published")
    line.content_episodes.create!(position: 3, customer_title: "예정 편", body: "본문", status: "draft")
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def open_first!(*lines) = lines.each { |line| line.content_episodes.find_by!(position: 1).update!(open_preview: true) }

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  # { "01" => [cta text, badge text or nil] } for the published episode cards (not the 공개 예정 one).
  def cards(slug)
    get product_line_path(slug)
    css_select("#episodes + ol > li > a").to_h do |a|
      spans = a.css("div > span")
      [ a["href"].split("/").last, [ spans.last.text.strip, spans.size > 2 ? spans.first.text.strip : nil ] ]
    end
  end

  def box_line
    css_select("#product-purchase p").map { |p| p.text.squish }.find { |t| t.include?("볼 수 있습니다.") && t.start_with?("E") }
  end

  # Every card that says 보기 → really opens; every other one is really stopped.
  def assert_cards_match_gate(slug)
    cards(slug).each do |id, (cta, _)|
      get product_episode_path(slug, id)
      if cta == "보기 →"
        assert_response :success, "#{slug}/#{id} says 보기 →"
      else
        assert_response :redirect, "#{slug}/#{id} says #{cta}"
      end
    end
  end

  # --- the table (a) with 열린 편 on E01 ------------------------------------------------------------------------

  test "guest: free -- E01 보기 → + 로그인 없이 보기, the rest 로그인 후 보기; paid -- the rest 구매 후 보기" do
    open_first!(@free, @paid)
    assert_equal({ "01" => [ "보기 →", "로그인 없이 보기" ], "02" => [ "로그인 후 보기", nil ] }, cards("free-guide"))
    assert_equal({ "01" => [ "보기 →", "로그인 없이 보기" ], "02" => [ "구매 후 보기", nil ] }, cards("paid-guide"))
    assert_cards_match_gate("free-guide")
    assert_cards_match_gate("paid-guide")
  end

  test "member before use (free): E01 보기 → without a badge, the rest 이용 시작 후 보기" do
    open_first!(@free)
    sign_in(@member)
    assert_equal({ "01" => [ "보기 →", nil ], "02" => [ "이용 시작 후 보기", nil ] }, cards("free-guide"))
    assert_cards_match_gate("free-guide")
  end

  test "member who hasn't bought (paid): E01 보기 → + 미리 보기, the rest 구매 후 보기" do
    open_first!(@paid)
    sign_in(@member)
    assert_equal({ "01" => [ "보기 →", "미리 보기" ], "02" => [ "구매 후 보기", nil ] }, cards("paid-guide"))
    assert_cards_match_gate("paid-guide")
  end

  test "member in use: every card 보기 →, as before" do
    open_first!(@free)
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    assert_equal({ "01" => [ "보기 →", nil ], "02" => [ "보기 →", nil ] }, cards("free-guide"))
    assert_cards_match_gate("free-guide")
  end

  test "a guide without a commerce product: every card 보기 →, as before" do
    line = ProductLine.create!(internal_name: "n", customer_name: "가격 없는 가이드", slug: "plain-guide", introduction: "소개", status: "published")
    line.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
    assert_equal({ "01" => [ "보기 →", nil ] }, cards("plain-guide"))
  end

  test "the 공개 예정 card is unchanged" do
    get product_line_path("free-guide")
    assert_includes css_select("#episodes + ol").first.text, "예정 편"
    assert_select "#episodes + ol > li > div", 1 # the 공개 예정 card isn't a link
  end

  # --- every switch off: what production looks like right after the deploy -----------------------------------

  test "with every switch off: guests see 로그인 후 보기 / 구매 후 보기 on every card and no box line" do
    assert_equal({ "01" => [ "로그인 후 보기", nil ], "02" => [ "로그인 후 보기", nil ] }, cards("free-guide"))
    assert_nil box_line
    assert_equal({ "01" => [ "구매 후 보기", nil ], "02" => [ "구매 후 보기", nil ] }, cards("paid-guide"))
    assert_nil box_line
    assert_cards_match_gate("free-guide")
  end

  # --- the access box line (b) ---------------------------------------------------------------------------------

  test "guest: 'E01은 로그인 없이 볼 수 있습니다.' in the free and the paid box, linking to E01" do
    open_first!(@free, @paid)
    %w[free-guide paid-guide].each do |slug|
      get product_line_path(slug)
      assert_equal "E01은 로그인 없이 볼 수 있습니다.", box_line, slug
      assert_select "#product-purchase a[href=?]", product_episode_path(slug, "01"), text: "E01"
    end
    get product_line_path("free-guide")
    assert_select "#product-purchase", text: /이용하기/
  end

  test "member who hasn't bought: 'E01은 구매 전에 볼 수 있습니다.'; member before a free guide: no line" do
    open_first!(@free, @paid)
    sign_in(@member)
    get product_line_path("paid-guide")
    assert_equal "E01은 구매 전에 볼 수 있습니다.", box_line
    assert_includes css_select("#product-purchase").text.squish, "1,100원 (VAT 포함)" # the rest of the paid box is unchanged
    get product_line_path("free-guide")
    assert_nil box_line
  end

  test "the first 열린 편 is the one named, and an in-use box has no line" do
    @free.content_episodes.find_by!(position: 2).update!(open_preview: true)
    get product_line_path("free-guide")
    assert_equal "E02는 로그인 없이 볼 수 있습니다.", box_line # 은/는 by the number's sound
    view = ActionView::Base.empty
    view.extend(ProductLinesHelper)
    assert_equal %w[은 는 은 는 는 은 은 은 는 은], %w[01 02 03 04 05 06 07 08 09 10].map { |n| view.number_topic_particle(n) }

    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get product_line_path("free-guide")
    assert_equal "이용 중인 가이드입니다.", css_select("#product-purchase").text.squish
  end

  # --- the gate's message (c) ----------------------------------------------------------------------------------

  test "the gate's message: 이용을 시작하면 (free) / 구매하면 (paid) 볼 수 있습니다." do
    sign_in(@member)
    get product_episode_path("free-guide", "02")
    assert_redirected_to product_line_path("free-guide")
    assert_equal "이용을 시작하면 볼 수 있습니다.", flash[:alert]
    get product_episode_path("paid-guide", "02")
    assert_equal "구매하면 볼 수 있습니다.", flash[:alert]
  end

  test "the admin preview keeps R2's marker and its own CTA" do
    open_first!(@free)
    sign_in(@admin)
    get admin_product_line_path(@free)
    assert_select "main ol li", text: /로그인 없이 보기/, count: 1
    assert_select "main ol li", text: /편집하기 →/, minimum: 2
  end
end
