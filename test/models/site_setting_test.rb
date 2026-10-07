require "test_helper"

# Handoff 0097 -- the home's featured-section title: the operator's text on one line, the default when blank.
class SiteSettingTest < ActiveSupport::TestCase
  test "the default until a title is saved, and again once it is blanked" do
    assert_equal "지금 시작하는 가이드", SiteSetting.home_featured_title
    assert SiteSetting.save_home_featured_title("BEST 인기 가이드").errors.none?
    assert_equal "BEST 인기 가이드", SiteSetting.home_featured_title
    SiteSetting.save_home_featured_title("   ")
    assert_equal "지금 시작하는 가이드", SiteSetting.home_featured_title
    assert_equal "", SiteSetting.home_featured_title_input
    assert_equal 1, SiteSetting.count
  end

  test "line breaks and runs of spaces become one space; at most 30 characters" do
    SiteSetting.save_home_featured_title("새로 만든\r\n  가이드")
    assert_equal "새로 만든 가이드", SiteSetting.home_featured_title
    assert SiteSetting.save_home_featured_title("가" * 30).errors.none?
    assert SiteSetting.save_home_featured_title("가" * 31).errors.any?
    assert_equal "가" * 30, SiteSetting.home_featured_title
  end
end
