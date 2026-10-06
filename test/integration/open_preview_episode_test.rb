require "test_helper"

# Handoff 0092 R2 (D-012) -- "열린 편": an episode the admin switches on (로그인 없이 보기 허용, content_episodes.open_preview)
# opens its body to anyone the guide is open to -- guests, members who haven't started a free guide, members who
# haven't bought a paid one. Files and comments still need the license (one line each instead, comments by count);
# file URLs and comment posts stay blocked. An episode that isn't switched on is exactly as before.
class OpenPreviewEpisodeTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze
  FILES_LINE = "실전 자료는 이용을 시작하면 받을 수 있습니다."
  COMMENTS_LINE = "이용을 시작하면 댓글을 보고 남길 수 있습니다."

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "op-adm-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @member = User.create!(name: "회원", email: "op-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @free = guide!("free-guide", 0)
    @paid = guide!("paid-guide", 1_100)
    [ @free, @paid ].each { |line| line.content_episodes.find_by!(position: 1).update!(open_preview: true) }
  end

  def guide!(slug, amount)
    line = ProductLine.create!(internal_name: slug, customer_name: "가이드 #{slug}", slug: slug, introduction: "소개", status: "published")
    ep1 = line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "열린 본문", status: "published")
    line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "닫힌 본문", status: "published")
    ep1.content_takeaways.create!(kind: "체크리스트", body: "- 항목", position: 1)
    ep1.content_assets.create!(kind: "템플릿", title: "자료", file: { io: StringIO.new("x"), filename: "a.txt", content_type: "text/plain" })
    ep1.episode_comments.create!(user: @admin, body: "운영자 댓글")
    Commerce::ProductLineSales.set_price!(product_line: line, total_amount: amount, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: line.reload, actor: @admin)
    line.reload
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def main_text = css_select("main").first.text.squish

  def assert_open_without_license(path)
    get path, headers: BROWSER
    assert_response :success, path
    assert_includes main_text, "열린 본문"
    assert_select "main section h2", text: "이 편의 실전 자료"
    assert_includes main_text, FILES_LINE
    assert_select "main a", text: "다운로드", count: 0
    assert_not_includes main_text, "체크리스트"
    assert_select "#comments h2", text: /댓글\s*1/
    assert_includes css_select("#comments").first.text, COMMENTS_LINE
    assert_select "#comments ol", 0
    assert_select "#comments form, #comments textarea", 0
    assert_not_includes main_text, "운영자 댓글"
  end

  # --- an open episode without the license ----------------------------------------------------------------

  test "a guest reads an open episode's body; files and comments are one line each" do
    assert_open_without_license("/products/free-guide/01")
    assert_open_without_license("/products/paid-guide/01")
  end

  test "a member who hasn't started the free guide, or bought the paid one, gets the same" do
    sign_in(@member)
    assert_open_without_license("/products/free-guide/01")
    assert_open_without_license("/products/paid-guide/01")
  end

  test "file URLs and comment posts stay blocked on an open episode" do
    asset = @free.content_episodes.find_by!(position: 1).content_assets.first
    get product_episode_asset_path("free-guide", "01", asset.id)
    assert_redirected_to new_user_session_path
    post product_episode_comments_path("free-guide", "01"), params: { episode_comment: { body: "게스트" } }
    assert_redirected_to new_user_session_path

    sign_in(@member)
    get product_episode_asset_path("free-guide", "01", asset.id)
    assert_redirected_to product_line_path("free-guide")
    assert_no_difference -> { EpisodeComment.count } do
      post product_episode_comments_path("free-guide", "01"), params: { episode_comment: { body: "미이용" } }
    end
    assert_redirected_to product_line_path("free-guide")
  end

  # --- with the license, or switched off ------------------------------------------------------------------

  test "a member using the guide sees the whole open episode, as before" do
    sign_in(@member)
    post claim_free_access_path(@free.product.code)
    get "/products/free-guide/01", headers: BROWSER
    assert_includes main_text, "체크리스트"
    assert_select "main a", text: "다운로드", count: 1
    assert_select "#comments ol li", minimum: 1
    assert_select "#comments form textarea", minimum: 1 # the comment form (+ reply forms)
    assert_not_includes main_text, FILES_LINE
    assert_not_includes main_text, COMMENTS_LINE
  end

  test "an episode that isn't switched on is exactly as before" do
    get "/products/free-guide/02"
    assert_redirected_to new_user_session_path
    sign_in(@member)
    get "/products/free-guide/02"
    assert_redirected_to product_line_path("free-guide")
    get "/products/paid-guide/02"
    assert_redirected_to product_line_path("paid-guide")
  end

  test "switched on but the guide isn't open to customers, or the episode isn't published: not opened" do
    @free.update_columns(status: "draft")
    get "/products/free-guide/01"
    assert_response :not_found

    draft = @paid.content_episodes.create!(position: 3, customer_title: "초안", body: "초안", status: "draft", open_preview: true)
    get product_episode_path("paid-guide", draft.display_id)
    assert_response :not_found
  end

  test "a guide without a commerce product is unchanged (anyone reads it, comments included)" do
    open = ProductLine.create!(internal_name: "o", customer_name: "가격 없는 가이드", slug: "open-guide", introduction: "소개", status: "published")
    open.content_episodes.create!(position: 1, customer_title: "편", body: "본문", status: "published")
    get "/products/open-guide/01"
    assert_response :success
    assert_select "#comments a", text: "로그인하고 댓글 쓰기"
    assert_not_includes main_text, COMMENTS_LINE
  end

  # --- view counts -----------------------------------------------------------------------------------------

  test "a guest's view of an open episode is counted, with signed_in false; a member's with true" do
    assert_difference -> { EpisodeView.count }, 1 do
      get "/products/free-guide/01", headers: BROWSER
    end
    assert_equal false, EpisodeView.last.signed_in
    sign_in(@member)
    get "/products/free-guide/01", headers: BROWSER
    assert_equal true, EpisodeView.order(:id).last.signed_in
    assert_no_difference -> { EpisodeView.count } do
      get "/products/free-guide/01", headers: { "User-Agent" => "Googlebot/2.1" }
    end
  end

  # --- the admin field -------------------------------------------------------------------------------------

  test "the admin switch saves and reads back on the edit form, and the preview marks the episode" do
    episode = @free.content_episodes.find_by!(position: 2)
    sign_in(@admin)
    get edit_admin_content_episode_path(episode)
    assert_select "input[type=checkbox][name='content_episode[open_preview]']:not([checked])"
    assert_includes response.body, "로그인 없이 보기 허용"

    patch admin_content_episode_path(episode), params: { content_episode: { customer_title: episode.customer_title, lock_version: episode.lock_version, open_preview: "1" } }
    assert episode.reload.open_preview?
    get edit_admin_content_episode_path(episode)
    assert_select "input[type=checkbox][name='content_episode[open_preview]'][checked]"

    get admin_product_line_path(@free)
    assert_select "main ol li", text: /로그인 없이 보기/, count: 2 # E01 (setup) and E02
  end

  test "no noindex on an open episode" do
    get "/products/free-guide/01"
    assert_select "meta[name='robots']", 0
  end
end
