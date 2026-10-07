require "test_helper"

# Handoff 0101 -- the dark palette became tokens, but the admin preview of a guide and of an episode (and the admin's
# light header) render the light values of the same partials and theme tables, which were left alone. This pins every
# color class on those pages to the set they had before 0101 (captured from the pre-0101 code), so a later change to
# the customer side can't quietly reach them.
class AdminPreviewColorsTest < ActionDispatch::IntegrationTest
  COLOR = /\A(?:[a-z-]+:)*-?(?:bg|text|border(?:-[trblxy])?|ring|outline|decoration|from|via|to|divide|fill|stroke|placeholder)-
            (?:\[\#[0-9a-fA-F]{3,8}\]|white|black|transparent|(?:slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|
            emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose)-\d{2,3}|page|card|ink(?:-[23])?|accent(?:-[a-z-]+)?|
            ok(?:-[a-z]+)?|on-accent|danger|line|tint|cover-\d)(?:\/\d+)?\z/x

  EXPECTED = {
    guide: %w[
      bg-blue-50 bg-emerald-50 bg-slate-100 bg-slate-950 bg-white bg-white/90 border-blue-100
      border-blue-200 border-gray-200 border-red-200 border-slate-100 border-slate-200 border-slate-200/70
      focus-visible:ring-indigo-500 focus-visible:ring-red-500 group-hover:bg-indigo-700 hover:bg-red-50
      hover:bg-slate-50 hover:border-blue-300 hover:border-red-300 hover:text-slate-950 text-blue-600
      text-blue-700 text-blue-800 text-emerald-700 text-gray-400 text-gray-500 text-gray-700 text-gray-900
      text-red-600 text-slate-500 text-slate-600 text-slate-700 text-slate-900 text-slate-950 text-white
    ],
    episode: %w[
      bg-blue-50 bg-slate-950 bg-white bg-white/90 border-blue-200 border-gray-100 border-red-200
      border-slate-100 border-slate-200 border-slate-200/70 focus-visible:ring-indigo-500
      focus-visible:ring-red-500 group-hover:bg-indigo-700 hover:bg-red-50 hover:bg-slate-50
      hover:border-red-300 hover:text-blue-600 hover:text-slate-950 text-blue-600 text-blue-800
      text-gray-400 text-gray-500 text-gray-900 text-red-600 text-slate-500 text-slate-600 text-slate-700
      text-slate-950 text-white
    ]
  }.freeze

  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "apc-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "apc", customer_name: "미리보기 가이드", slug: "apc-guide", summary: "요약",
      introduction: "## 제목\n\n소개 [링크](https://example.com)\n\n> 인용\n\n`코드`", status: "published")
    @ep = @line.content_episodes.create!(position: 1, customer_title: "첫 편", summary: "예고", body: "본문", status: "published", open_preview: true)
    @line.content_episodes.create!(position: 2, customer_title: "예정 편", body: "본문", status: "draft")
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line.reload, actor: @admin)
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }
  end

  def color_classes
    css_select("body *").flat_map { |node| node["class"].to_s.split }.select { |klass| klass.match?(COLOR) }.uniq.sort
  end

  test "the admin guide preview and episode preview keep their pre-0101 color classes" do
    get admin_product_line_path(@line)
    guide = color_classes
    get admin_content_episode_path(@ep)
    episode = color_classes
    assert_equal EXPECTED[:guide], guide
    assert_equal EXPECTED[:episode], episode
  end
end
