require "test_helper"

class SeasonChapterAccessPolicyTest < ActiveSupport::TestCase
  KST = Commerce::PeriodCalculator::KST

  setup do
    Commerce::CatalogBootstrap.call!
    @guest = nil
    @trial = create_user("trial", created_at: Time.current)
    @expired_trial = create_user("expired", created_at: 30.days.ago)
    @licensed = create_user("licensed", created_at: 30.days.ago)
    @admin = create_user("admin", created_at: 30.days.ago, role: :admin)
    create_chatdox_license(@licensed)
  end

  test "published guest trial and license tiers return stable decisions" do
    assert_decision(true, :allowed, @guest, chapter(:guest))
    assert_decision(false, :authentication_required, @guest, chapter(:trial))
    assert_decision(true, :allowed, @trial, chapter(:trial))
    assert_decision(false, :trial_required, @expired_trial, chapter(:trial))
    assert_decision(false, :authentication_required, @guest, chapter(:license))
    assert_decision(false, :license_required, @expired_trial, chapter(:license))
    assert_decision(true, :allowed, @licensed, chapter(:license))
    assert_decision(true, :allowed, @admin, chapter(:license))
  end

  test "one existing Chatdox license applies to S01 and S02" do
    assert_decision(true, :allowed, @licensed, chapter(:license, id: "S01E20"))
    assert_decision(true, :allowed, @licensed, chapter(:license, id: "S02E20"))
  end

  test "draft and review are hidden except for explicit admin preview" do
    %i[draft review].each do |status|
      value = chapter(:unpublished, status:)
      assert_decision(false, :not_public, @licensed, value)
      assert_decision(true, :allowed, @admin, value, context: :admin)
      assert_decision(false, :not_public, @expired_trial, value, context: :admin)
    end
  end

  test "archived content requires a license and direct protected body" do
    archived = chapter(:archived, status: :archived, protected: true)
    assert_decision(false, :not_public, @licensed, archived, context: :public)
    assert_decision(false, :archived_license_required, @expired_trial, archived)
    assert_decision(true, :allowed, @licensed, archived)

    assert_decision(false, :content_unavailable, @licensed, archived.merge(protected: false))
    assert_decision(true, :allowed, @admin, archived, context: :admin)
  end

  test "season status overrides published episode visibility" do
    %i[draft upcoming archived].each do |status|
      assert_decision(false, :not_public, @licensed, chapter(:guest, season_status: status))
    end
    %i[publishing completed].each do |status|
      assert_decision(true, :allowed, @guest, chapter(:guest, season_status: status))
    end
  end

  test "invalid snapshot malformed identity status and missing body fail closed" do
    assert_decision(false, :invalid_snapshot, @licensed, chapter(:guest), snapshot_usable: false)
    assert_decision(false, :content_unavailable, @licensed, chapter(:guest, id: "01"))
    assert_decision(false, :content_unavailable, @licensed, chapter(:guest, status: :withdrawn))
    assert_decision(false, :content_unavailable, @licensed, chapter(:guest, file_present: false))
    assert_decision(false, :not_public, @licensed, nil)
  end

  test "DocPolicy delegates canonical records and preserves the reason code" do
    policy = DocPolicy.new(@expired_trial, chapter(:license))

    assert_not policy.view?
    assert_equal :license_required, policy.access_reason
    assert DocPolicy.new(@licensed, chapter(:license, id: "S02E01")).view?
  end

  private

  def chapter(tier, id: "S01E01", status: :published, season_status: :completed, file_present: true, protected: false)
    {
      id:, product_code: "chatdox", status:, season_status:, access_tier: tier,
      file_present:, protected:
    }
  end

  def assert_decision(allowed, reason, user, value, context: :direct, snapshot_usable: true)
    decision = SeasonChapterAccessPolicy.new(user:, chapter: value, context:, snapshot_usable:).decision
    assert_equal allowed, decision.allowed?
    assert_equal reason, decision.reason
  end

  def create_user(label, created_at:, role: :user)
    User.create!(
      name: "테스트 유저",
      email: "season-#{label}-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      created_at:,
      role:
    )
  end

  def create_chatdox_license(user)
    product = Product.find_by!(code: "chatdox")
    today = Time.current.in_time_zone(KST).to_date
    last_day = today + 1.month - 1.day
    end_day = last_day + 1.day
    License.create!(
      user:,
      product:,
      source: "paid",
      status: "active",
      starts_on: today,
      last_usable_on: last_day,
      access_ends_at: KST.local(end_day.year, end_day.month, end_day.day)
    )
  end
end
