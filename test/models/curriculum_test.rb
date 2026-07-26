require "test_helper"

class CurriculumTest < ActiveSupport::TestCase
  test "last_updated_at delegates to ContentManifest against DOCS_PATH" do
    result = Curriculum.last_updated_at("01_overview")
    assert_equal ContentManifest.last_updated_at(Curriculum::DOCS_PATH, "01_overview"), result
  end

  test "last_updated_at is zone-converted to the app's time zone" do
    result = Curriculum.last_updated_at("01_overview")
    assert_equal ActiveSupport::TimeZone["Asia/Seoul"], result.time_zone
  end
end
