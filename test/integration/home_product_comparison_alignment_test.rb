require "test_helper"

# Handoff 0071 removed the home section these tests were written for (the Chatdox / Claudox / Antigravity
# comparison cards); the story-series home replaced it. What remains here are the guards that still apply to
# the new home: removed copy stays removed, and no pricing tables or unconfirmed promises on the home.
class HomeProductComparisonAlignmentTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "5. '무엇부터 읽어야 할까요?', 'Choose your starting point', and unconfirmed bundle product note are removed" do
    get root_path
    assert_response :success

    assert_no_match(/Choose your starting point/, response.body)
    assert_no_match(/무엇부터 읽어야 할까요\?/, response.body)
    assert_no_match(/묶음 상품과 구매 조건은 아직 확정되지 않았습니다/, response.body)
    assert_no_match(/두 기록을 함께 탐색/, response.body)
  end

  test "8. Home page does not display pricing tables or excluded unconfirmed feature promises" do
    get root_path
    assert_response :success

    assert_no_match(/GitHub Private Lab/, response.body)
    assert_no_match(/보장형 지원/, response.body)
    assert_no_match(/얼리버드 20%/, response.body)
  end
end
