require "test_helper"

# Handoff 0073 -- episode view counts. Every open that actually rendered a published episode's body
# adds a view (R3); people are distinct viewers. Never for bots, prefetches or HEAD (admins count like
# anyone on the customer page since R2, never in the admin preview); admin-only display; nothing on
# customer screens.
class EpisodeViewCountsTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36" }.freeze
  KST = ActiveSupport::TimeZone["Asia/Seoul"]

  setup do
    @admin = User.create!(name: "관리자", email: "ev-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "독자", email: "ev-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
    @line = ProductLine.create!(internal_name: "조회", customer_name: "관찰 시리즈", slug: "views-line", introduction: "소개", status: "published")
    @ep1 = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문 1", status: "published")
    @ep2 = @line.content_episodes.create!(position: 2, customer_title: "둘째 편", body: "본문 2", status: "published")
    @draft = @line.content_episodes.create!(position: 3, customer_title: "예정 편", body: "본문 3", status: "draft")
  end

  def view(episode = @ep1, headers: {}, line: @line)
    get product_episode_path(line.slug, episode.display_id), headers: BROWSER.merge(headers)
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  # Total views (SUM(view_count)) and people (distinct viewers), optionally for one episode.
  def views(episode = nil) = (episode ? EpisodeView.where(content_episode: episode) : EpisodeView.all).sum(:view_count)
  def people(episode = nil) = (episode ? EpisodeView.where(content_episode: episode) : EpisodeView.all).distinct.count(:viewer_key)

  # --- views and people --------------------------------------------------------

  test "every open of the same episode the same day adds a view; the guest is still one person (one row)" do
    view
    assert_response :success
    view
    view
    assert_equal 3, views(@ep1)
    assert_equal 1, people(@ep1)
    record = EpisodeView.sole
    assert_equal [ @ep1, Date.current, 3 ], [ record.content_episode, record.viewed_on, record.view_count ]
  end

  test "different episodes count separately for the same person" do
    view(@ep1)
    view(@ep2)
    assert_equal [ 1, 1 ], [ views(@ep1), views(@ep2) ]
    assert_equal 1, people, "one person across both episodes"
  end

  test "two different guest browsers count as two people" do
    view
    open_session { |other| other.get product_episode_path(@line.slug, "01"), headers: BROWSER }
    assert_equal 2, views(@ep1)
    assert_equal 2, people(@ep1)
  end

  test "the same person on two days: 2 views, still 1 person all time" do
    sign_in(@user)
    travel_to(1.day.ago) { view }
    view
    assert_equal 2, EpisodeView.count, "one row per day"
    assert_equal 2, views(@ep1)
    assert_equal 1, people(@ep1)
  end

  # The real guarantee is the single upsert statement (ON CONFLICT ... DO UPDATE SET view_count = view_count + 1);
  # SQLite test transactions can't host truly parallel writers, so this pins the statement's semantics by calling
  # the recorder's exact upsert repeatedly, starting from "no row".
  test "the upsert inserts once and then increments exactly, never duplicating the row" do
    attrs = { content_episode_id: @ep1.id, viewed_on: Date.current, viewer_key: "k" * 32, view_count: 1, created_at: Time.current }
    5.times do
      EpisodeView.upsert(attrs, unique_by: EpisodeView::UNIQUENESS, on_duplicate: Arel.sql("view_count = episode_views.view_count + 1"))
    end
    assert_equal 1, EpisodeView.count
    assert_equal 5, EpisodeView.sole.view_count
  end

  test "the day boundary is KST midnight" do
    travel_to KST.local(2026, 10, 4, 23, 59) do
      view
    end
    travel_to KST.local(2026, 10, 5, 0, 1) do
      view
    end
    assert_equal [ Date.new(2026, 10, 4), Date.new(2026, 10, 5) ], EpisodeView.order(:viewed_on).pluck(:viewed_on)
  end

  test "a signed-in user is one person across browsers; each open is a view" do
    sign_in(@user)
    view
    open_session do |other|
      other.post user_session_path, params: { user: { email: @user.email, password: "password123" } }
      other.get product_episode_path(@line.slug, "01"), headers: BROWSER
    end
    assert_equal 2, views(@ep1)
    assert_equal 1, people(@ep1)
  end

  test "a guest who signs in the same day may be counted as two people (browser + user), as the handoff allows" do
    view
    sign_in(@user)
    view
    assert_equal 2, people(@ep1)
  end

  # --- what doesn't count --------------------------------------------------

  # 0073 R2 -- admins count like any signed-in user on the customer page.
  test "an admin's opens of the customer episode page count like any signed-in user's" do
    sign_in(@admin)
    view
    assert_response :success
    view
    assert_equal 2, views(@ep1)
    assert_equal 1, people(@ep1)
  end

  test "an admin can't reach a draft episode through the customer URL, so it isn't counted" do
    sign_in(@admin)
    assert_no_difference -> { EpisodeView.count } do
      view(@draft)
      assert_response :not_found
    end
  end

  test "the admin episode preview isn't counted" do
    sign_in(@admin)
    assert_no_difference -> { EpisodeView.count } do
      get admin_content_episode_path(@ep1), headers: BROWSER
      assert_response :success
    end
  end

  test "Turbo and browser prefetches aren't counted" do
    assert_no_difference -> { EpisodeView.count } do
      view(headers: { "X-Sec-Purpose" => "prefetch" })
      view(headers: { "Sec-Purpose" => "prefetch;prerender" })
      view(headers: { "Purpose" => "prefetch" })
    end
  end

  test "bots and requests without a User-Agent aren't counted" do
    assert_no_difference -> { EpisodeView.count } do
      view(headers: { "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" })
      view(headers: { "User-Agent" => "Mozilla/5.0 (compatible; Yeti/1.1; +https://naver.me/spd)" })
      view(headers: { "User-Agent" => "facebookexternalhit/1.1" })
      view(headers: { "User-Agent" => "kakaotalk-scrap/1.0" })
      get product_episode_path(@line.slug, "01"), headers: { "User-Agent" => "" }
    end
  end

  test "HEAD requests aren't counted" do
    assert_no_difference -> { EpisodeView.count } do
      head product_episode_path(@line.slug, "01"), headers: BROWSER
    end
  end

  test "a draft episode (404) isn't counted" do
    assert_no_difference -> { EpisodeView.count } do
      view(@draft)
      assert_response :not_found
    end
  end

  test "an episode of an unlisted or draft series isn't counted" do
    @line.update!(visibility: "unlisted")
    assert_no_difference -> { EpisodeView.count } do
      view
      assert_response :success
    end

    @line.update!(visibility: "public", status: "draft")
    assert_no_difference -> { EpisodeView.count } do
      view
      assert_response :not_found
    end
  end

  test "a gated episode counts only when the license gate lets the body render" do
    Commerce::CatalogBootstrap.call!
    previous = ENV["LEEDOX_COMMERCE_ENABLED"]
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 10_000, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    @line.reload

    assert_no_difference -> { EpisodeView.count } do
      view
      assert_redirected_to new_user_session_path
      sign_in(@user)
      view
      assert_redirected_to product_line_path(@line.slug)
    end

    order = Commerce::OrderCreator.call!(user: @user, product_code: @line.product.code, offer_code: @line.lifetime_offer.code, requested_start_on: nil, provider: "manual")
    Commerce::ConfirmManualPayment.call!(order: order, actor: @admin)
    view
    assert_response :success
    assert_equal 1, views(@ep1)
  ensure
    previous.nil? ? ENV.delete("LEEDOX_COMMERCE_ENABLED") : ENV["LEEDOX_COMMERCE_ENABLED"] = previous
  end

  # --- storage --------------------------------------------------------------

  # Simulated rather than by dropping the table: a drop would leave the connection's schema cache without the
  # unique index for every later test in the process. Both a database error (what a missing table raises) and a
  # non-database one (e.g. ArgumentError from upsert's unique_by lookup) must leave the page at 200.
  test "the episode page still renders when recording fails (e.g. the table doesn't exist yet)" do
    [ ActiveRecord::StatementInvalid.new("no such table: episode_views"), ArgumentError.new("No unique index found") ].each do |error|
      EpisodeView.define_singleton_method(:upsert) { |*, **| raise error }
      view
      assert_response :success
      assert_includes response.body, "본문 1"
    ensure
      EpisodeView.singleton_class.remove_method(:upsert)
    end
    assert_equal 0, EpisodeView.count
  end

  test "only the episode, the day, an HMAC viewer key, a count and created_at are stored" do
    sign_in(@user)
    view
    assert_equal %w[content_episode_id created_at id view_count viewed_on viewer_key], EpisodeView.column_names.sort
    key = EpisodeView.last.viewer_key
    assert_match(/\A\h{32}\z/, key)
    assert_not_includes key, @user.id.to_s if @user.id.to_s.length > 2
  end

  test "the unique index rejects a duplicate (episode, day, viewer) at the database level" do
    attrs = { content_episode_id: @ep1.id, viewed_on: Date.current, viewer_key: "k" * 32, created_at: Time.current }
    EpisodeView.insert(attrs, unique_by: EpisodeView::UNIQUENESS)
    EpisodeView.insert(attrs, unique_by: EpisodeView::UNIQUENESS)
    assert_equal 1, EpisodeView.count
    assert_raises(ActiveRecord::RecordNotUnique) { EpisodeView.insert!(attrs) }
  end

  test "deleting an episode deletes its views" do
    view(@ep2)
    view(@ep2)
    assert_difference -> { EpisodeView.count }, -1 do
      @ep2.destroy!
    end
  end

  # --- display ----------------------------------------------------------------

  # Viewer "a" sees E01 today (3 times) and 8 days ago, and E02 30 days ago; "b" sees E01 6 days ago (2 times);
  # "c" sees E01 7 days ago -- just outside the last 7 days (today included).
  def seed_views
    EpisodeView.insert_all([
      { content_episode_id: @ep1.id, viewed_on: Date.current, viewer_key: "a", view_count: 3, created_at: Time.current },
      { content_episode_id: @ep1.id, viewed_on: Date.current - 8, viewer_key: "a", view_count: 1, created_at: Time.current },
      { content_episode_id: @ep1.id, viewed_on: Date.current - 6, viewer_key: "b", view_count: 2, created_at: Time.current },
      { content_episode_id: @ep1.id, viewed_on: Date.current - 7, viewer_key: "c", view_count: 1, created_at: Time.current },
      { content_episode_id: @ep2.id, viewed_on: Date.current - 30, viewer_key: "a", view_count: 1, created_at: Time.current }
    ], unique_by: EpisodeView::UNIQUENESS)
  end

  test "the admin product list shows each series' views and people (all time / last 7 days), plus the counting note" do
    seed_views
    sign_in(@admin)
    get admin_product_lines_path
    assert_response :success
    row = css_select("tr").find { |tr| tr.text.include?("관찰 시리즈") }
    # all time: 3+1+2+1+1 = 8 views; people a, b, c = 3 (a saw two episodes on three days -- still one person)
    assert_equal "8회 · 3명", row.at_css("[data-view-total]").text.strip
    # last 7 days: a today (3) + b 6 days ago (2) = 5 views, 2 people
    assert_equal "5회 · 2명", row.at_css("[data-view-recent]").text.strip
    assert_includes response.body, "횟수는 열 때마다 1회 · 사람 수는 같은 사람을 한 번만 셈(비로그인은 브라우저 기준) · 로봇 제외 ·"
    assert_not_includes response.body, "관리자·로봇"
    assert_includes response.body, "#{I18n.l(Date.current - 30, format: :long, locale: :ko)}부터"
  end

  test "a series' people are distinct viewers across its episodes, not the sum of each episode's people" do
    stats = EpisodeView.stats_by_product_line([ @line.id ])
    assert_nil stats[:total][@line.id]
    seed_views
    stats = EpisodeView.stats_by_product_line([ @line.id ])[:total][@line.id]
    episode_stats = EpisodeView.stats_by_episode([ @ep1.id, @ep2.id ])[:total]
    assert_equal 4, episode_stats.values.sum(&:people), "E01 3 people + E02 1 person"
    assert_equal 3, stats.people
  end

  test "the admin edit page lists each episode's views in order, with — for a draft" do
    seed_views
    sign_in(@admin)
    get edit_admin_product_line_path(@line)
    assert_response :success
    cells = css_select("[data-episode-views]").map { |n| n.text.squish }
    assert_equal [ "조회 7회 · 3명 최근 7일 5회 · 2명", "조회 1회 · 1명 최근 7일 0회 · 0명", "조회 —" ], cells
    assert_includes response.body, "사람 수는 같은 사람을 한 번만 셈"
  end

  test "with nothing counted yet the note says so" do
    sign_in(@admin)
    get admin_product_lines_path
    assert_includes response.body, "아직 집계된 조회가 없습니다"
  end

  test "no customer screen prints a view count, and every link to an episode opts out of Turbo prefetch" do
    seed_views
    @line.update!(featured: true)
    [ root_path, products_path, product_line_path(@line.slug), product_episode_path(@line.slug, "01") ].each do |path|
      get path, headers: BROWSER
      assert_response :success
      assert_no_match(/조회|views/i, css_select("main").text, "#{path} shows a view count")
      css_select("a[href^='#{product_line_path(@line.slug)}/']").each do |a|
        assert_equal "false", a["data-turbo-prefetch"], "#{path}: #{a['href']} can be prefetched"
      end
    end
  end
end
