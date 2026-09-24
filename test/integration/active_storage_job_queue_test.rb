require "test_helper"

# Production has no job worker and no Solid Queue tables (its SQLite queue file
# is empty after every deploy), so anything that *enqueues* a job raises and
# turns the request into a 500 -- after the upload was already stored. Active
# Storage enqueues an AnalyzeJob for every new blob (an uploaded cover, and each
# new image variant the first time it is rendered), so that job has to run inline.
class ActiveStorageJobQueueTest < ActionDispatch::IntegrationTest
  class QueueWithoutTables
    def enqueue(_job) = raise(ActiveRecord::StatementInvalid, "Could not find table 'solid_queue_jobs'")
    def enqueue_at(_job, _timestamp) = enqueue(_job)
  end

  setup do
    @admin = User.create!(name: "관리자", email: "queue-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @line = ProductLine.create!(internal_name: "A", customer_name: "제품", slug: "queue-line", introduction: "소개", status: "published")
    @previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = QueueWithoutTables.new
  end

  teardown { ActiveJob::Base.queue_adapter = @previous }

  def cover_upload
    Rack::Test::UploadedFile.new(file_fixture("covers/cover.jpg"), "image/jpeg")
  end

  test "blob analysis is configured to run inline, not through the job queue" do
    assert_equal "inline", ActiveStorage::AnalyzeJob.queue_adapter_name
    assert_equal "inline", ActiveStorage::PurgeJob.queue_adapter_name
  end

  test "saving a cover from the admin form and rendering its variants work while the job queue is unusable" do
    post user_session_path, params: { user: { email: @admin.email, password: "password123" } }

    patch admin_product_line_path(@line), params: { product_line: { cover_image: cover_upload, cover_image_alt: "표지" } }
    assert_response :redirect, "the save must not 500 on the analyze job"
    assert @line.reload.cover_image.attached?

    get product_cover_path(@line.slug, "hero")
    assert_response :success
    assert_equal "image/webp", response.media_type

    # Replacing the cover removes the old file inline as well.
    patch admin_product_line_path(@line), params: { product_line: { cover_image: cover_upload, cover_image_alt: "새 표지" } }
    assert_response :redirect
    get admin_product_line_cover_image_path(@line, "thumb")
    assert_response :success
  end
end
