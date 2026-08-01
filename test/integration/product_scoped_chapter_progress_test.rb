require "test_helper"

class ProductScopedChapterProgressTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "product-scoped-progress@example.com", password: "password123")
    post user_session_path, params: { user: { email: @user.email, password: "password123" } }
  end

  test "Chatdox doc page shows 학습 상태 completion controls and can toggle completion" do
    get doc_path("05")
    assert_response :success
    assert_match(/학습 상태/, response.body)
    assert_match(/완료한 챕터로 표시하면/, response.body)

    # The redirect target is the generic product_chapter_path now (design
    # section B-2 -- internal link/redirect generation no longer uses the
    # legacy doc_path/claudox_chapter_path helpers), even though doc_path
    # itself still works as an external entry point (asserted above via GET).
    post chapter_progresses_path, params: { chapter_id: "05", product_code: "chatdox" }
    assert_redirected_to product_chapter_path("chatdox", "05")
    assert @user.chapter_progresses.find_by(chapter_id: "S01E05", product_code: "chatdox").completed?

    get doc_path("05")
    assert_match(/이 챕터를 완료한 상태입니다/, response.body)

    delete chapter_progresses_path, params: { chapter_id: "05", product_code: "chatdox" }
    assert_redirected_to product_chapter_path("chatdox", "05")
    assert_nil @user.chapter_progresses.find_by(chapter_id: "S01E05", product_code: "chatdox")
  end

  test "Claudox read page now has the same 학습 상태 completion controls (new in this round)" do
    get claudox_chapter_path("05")
    assert_response :success
    assert_match(/학습 상태/, response.body)

    post chapter_progresses_path, params: { chapter_id: "05", product_code: "claudox" }
    assert_redirected_to product_chapter_path("claudox", "05")
    assert @user.chapter_progresses.find_by(chapter_id: "05", product_code: "claudox").completed?

    get claudox_chapter_path("05")
    assert_match(/이 챕터를 완료한 상태입니다/, response.body)

    delete chapter_progresses_path, params: { chapter_id: "05", product_code: "claudox" }
    assert_nil @user.chapter_progresses.find_by(chapter_id: "05", product_code: "claudox")
  end

  test "completing the same chapter number for both products creates two independent records, not one overwritten record" do
    post chapter_progresses_path, params: { chapter_id: "05", product_code: "chatdox" }
    post chapter_progresses_path, params: { chapter_id: "05", product_code: "claudox" }

    assert_equal 2, @user.chapter_progresses.count
    assert @user.chapter_progresses.find_by(chapter_id: "S01E05", product_code: "chatdox").completed?
    assert @user.chapter_progresses.find_by(chapter_id: "05", product_code: "claudox").completed?

    delete chapter_progresses_path, params: { chapter_id: "05", product_code: "claudox" }
    assert_equal 1, @user.chapter_progresses.count
    assert @user.chapter_progresses.find_by(chapter_id: "S01E05", product_code: "chatdox").completed?,
      "deleting the Claudox completion must not touch the Chatdox record for the same chapter number"
  end

  test "legacy reader dual-reads an existing canonical completion and repeated writes stay canonical" do
    ChapterProgress.create!(user: @user, chapter_id: "S01E05", product_code: "chatdox", completed_at: 1.day.ago)

    get doc_path("05")
    assert_match(/이 챕터를 완료한 상태입니다/, response.body)

    assert_no_difference -> { @user.chapter_progresses.count } do
      post chapter_progresses_path, params: { chapter_id: "05", product_code: "chatdox" }
    end
    assert_equal [ "S01E05" ], @user.chapter_progresses.where(product_code: "chatdox").pluck(:chapter_id)
  end

  test "dashboard's Chatdox progress count is unaffected by Claudox completions (regression check for section E)" do
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "chatdox" }
    post chapter_progresses_path, params: { chapter_id: "01", product_code: "claudox" }
    post chapter_progresses_path, params: { chapter_id: "02", product_code: "claudox" }
    post chapter_progresses_path, params: { chapter_id: "03", product_code: "claudox" }

    get dashboard_path
    assert_response :success
    assert_match(/전체 20개 중 1개 완료/, response.body)
  end
end
