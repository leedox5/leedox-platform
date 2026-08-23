require "test_helper"

class LicenseTest < ActiveSupport::TestCase
  setup do
    Commerce::CatalogBootstrap.call!
    @user = User.create!(name: "테스트 유저", email: "license-unique-index@example.com", password: "password123")
    @product = Product.find_by!(code: "chatdox")
    @today = Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date
  end

  def build_license(status:, starts_on: @today)
    end_date = starts_on + 30.days
    License.new(
      user: @user, product: @product, source: status == "canceled" ? "coupon" : "paid", status: status,
      starts_on: starts_on, last_usable_on: end_date - 1.day,
      access_ends_at: Commerce::PeriodCalculator::KST.local(end_date.year, end_date.month, end_date.day)
    )
  end

  test "a canceled license does not block a real license on the same user/product/start-date (partial unique index)" do
    build_license(status: "canceled").save!

    assert build_license(status: "active").save, "an active license on the same start date should not collide with a canceled one"
  end

  test "two non-canceled licenses for the same user/product/start-date are still rejected" do
    build_license(status: "active").save!

    duplicate = build_license(status: "scheduled")
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end
end
