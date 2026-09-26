require "test_helper"
require Rails.root.join("db/migrate/20260921120000_replace_product_line_problem_result_audience_with_introduction")

# Handoff 0060 -- ProductLine's problem / expected_result / target_audience are
# replaced by one free-form `introduction`.
class ProductLineIntroductionTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(name: "관리자", email: "intro-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "A", customer_name: "소개 제품", slug: "intro-line", status: "published",
      introduction: "첫 줄입니다.\n\n둘째 문단 **굵게** <b>태그</b>")
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  # --- customer page --------------------------------------------------------

  # Handoff 0063 reversed 0060's "no Markdown": the introduction is rendered as restricted Markdown
  # (ContentMarkdown, :marketing profile) -- still one section, with the stored text unchanged.
  test "the customer page shows the introduction as one section, rendering Markdown but never raw HTML" do
    get product_line_path(@line.slug)
    assert_response :success
    assert_select "main .doc-content p", text: /첫 줄입니다\./
    assert_select "main .doc-content strong", text: "굵게"
    assert_select "main b", count: 0
    assert_includes css_select("main .doc-content").text, "<b>태그</b>"
    # Handoff 0069 R2: the "소개" heading now duplicates the summary above it with no new information, so it's
    # sr-only -- kept (not deleted) for the heading structure, but never visible.
    assert_select "main h2.sr-only", text: "소개", count: 1
    assert_select "main h2.text-2xl", text: "소개", count: 0
    assert_select "main p.text-xs", text: "소개", count: 0
    assert_select "main .doc-content.max-w-\\[740px\\]", count: 1
    body = css_select("main").text
    %w[해결할\ 문제 기대\ 결과 대상\ 고객].each { |label| assert_not_includes body, label }
  end

  # Handoff 0066: the AI supporter title is the same heading as 소개, not the old small blue label.
  test "the AI supporter section title is a heading like the introduction, and only shown when set" do
    get product_line_path(@line.slug)
    assert_select "main h2", text: "AI 서포터", count: 0

    @line.update!(ai_supporter: "Codex")
    get product_line_path(@line.slug)
    assert_select "main h2.text-2xl.font-bold.text-slate-900", text: "AI 서포터", count: 1
    assert_select "main p.text-xs", text: "AI 서포터", count: 0
    assert_select "main p", text: "Codex"
  end

  test "guests and signed-in visitors see the identical introduction and a draft product is still hidden" do
    get product_line_path(@line.slug)
    guest = css_select("main .doc-content").first.text
    sign_in(@admin)
    get product_line_path(@line.slug)
    assert_equal guest, css_select("main .doc-content").first.text

    @line.update!(status: "draft")
    get product_line_path(@line.slug)
    assert_response :not_found
  end

  # --- admin forms ----------------------------------------------------------

  test "the admin edit and new forms have one 소개 textarea and none of the three old inputs" do
    sign_in(@admin)
    [ edit_admin_product_line_path(@line), new_admin_product_line_path ].each do |path|
      get path
      assert_response :success
      assert_select "textarea[name='product_line[introduction]']", 1
      assert_select "label[for='product_line_introduction']", text: "소개"
      %w[problem expected_result target_audience].each { |field| assert_select "[name='product_line[#{field}]']", 0 }
    end
    get edit_admin_product_line_path(@line)
    assert_includes css_select("textarea[name='product_line[introduction]']").first.text, "첫 줄입니다."
  end

  test "an admin can create and update a product with an introduction; blank is rejected; old params are ignored" do
    sign_in(@admin)
    assert_difference "ProductLine.count", 1 do
      post admin_product_lines_path, params: { product_line: { internal_name: "n", customer_name: "새 제품", slug: "new-intro", introduction: "새 소개\n둘째 줄",
        problem: "옛 값", expected_result: "옛 값", target_audience: "옛 값" } }
    end
    created = ProductLine.find_by!(slug: "new-intro")
    assert_equal "새 소개\n둘째 줄", created.introduction
    assert_nil created.problem, "the retired columns are not written any more"

    patch admin_product_line_path(created), params: { product_line: { introduction: "고친 소개" } }
    assert_equal "고친 소개", created.reload.introduction

    assert_no_difference "ProductLine.count" do
      post admin_product_lines_path, params: { product_line: { internal_name: "x", customer_name: "x", slug: "blank-intro", introduction: "  " } }
      assert_response :unprocessable_entity
    end
    patch admin_product_line_path(created), params: { product_line: { introduction: "" } }
    assert_response :unprocessable_entity
    assert_equal "고친 소개", created.reload.introduction
  end

  test "the admin preview shows the same introduction section" do
    sign_in(@admin)
    get admin_product_line_path(@line)
    assert_response :success
    assert_select ".doc-content p", text: /첫 줄입니다/
  end

  # --- data migration -------------------------------------------------------

  test "the migration draft keeps every old value under its old heading, in order" do
    migration = ReplaceProductLineProblemResultAudienceWithIntroduction
    assert_equal "해결할 문제\n문제 문장\n\n기대 결과\n결과 문장\n\n대상 고객\n대상 문장",
      migration.merged_draft("문제 문장", "결과 문장", "대상 문장")
  end

  test "the migration draft skips blank parts with their heading, trims, and keeps inner line breaks" do
    migration = ReplaceProductLineProblemResultAudienceWithIntroduction
    assert_equal "해결할 문제\n한 줄\n두 줄\n\n대상 고객\n개발자", migration.merged_draft("  한 줄\n두 줄 \n", nil, "개발자")
    assert_equal "", migration.merged_draft(nil, "", "  ")
  end
end
