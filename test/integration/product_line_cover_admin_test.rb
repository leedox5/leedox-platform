require "test_helper"

# Handoff 0056 R5 -- admin cover image create/edit/preview/delete.
class ProductLineCoverAdminTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(name: "관리자", email: "cover-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반유저", email: "cover-user-#{SecureRandom.hex(3)}@example.com", password: "password123")
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def line_params(overrides = {})
    { product_line: { internal_name: "내부", customer_name: "커버 제품", slug: "cover-line", introduction: "소개" }.merge(overrides) }
  end

  def make_line(with_cover: true, status: "draft", slug: "cover-line")
    line = ProductLine.create!(internal_name: "내부", customer_name: "커버 제품", slug: slug, introduction: "소개", status: status)
    if with_cover
      line.cover_image.attach(io: file_fixture("covers/cover.jpg").open, filename: "hero.jpg", content_type: "image/jpeg")
      line.update!(cover_image_alt: "대체문구 원본")
    end
    line
  end

  test "guests and non-admins cannot reach or change any cover image URL" do
    line = make_line
    [ admin_product_line_cover_image_path(line, "hero") ].each do |url|
      get url
      assert_redirected_to new_user_session_path
    end
    delete admin_product_line_cover_path(line)
    assert_redirected_to new_user_session_path

    sign_in_as(@user)
    get admin_product_line_cover_image_path(line, "hero")
    assert_redirected_to root_path
    assert_no_difference "ActiveStorage::Blob.count" do
      delete admin_product_line_cover_path(line)
    end
    assert line.reload.cover_image.attached?
  end

  test "create with a cover image and alt text" do
    sign_in_as(@admin)
    get new_admin_product_line_path
    assert_select "form[enctype='multipart/form-data']"
    assert_select "input[type=file][name='product_line[cover_image]'][accept*='image/webp']"
    assert_match(/1600×900/, response.body)
    assert_match(/16:9/, response.body)

    assert_difference [ "ProductLine.count", "ActiveStorage::Blob.count" ], 1 do
      post admin_product_lines_path, params: line_params(cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "코드가 완성되는 화면")
    end
    line = ProductLine.last
    assert_redirected_to edit_admin_product_line_path(line)
    assert line.cover_image.attached?
    assert_equal "코드가 완성되는 화면", line.cover_image_alt
  end

  # The picker is presentational: same file input, name and accept, so the
  # submit / validation behavior tested elsewhere in this file is unchanged.
  def assert_cover_picker
    assert_select "div[data-controller='file-picker']", 1
    # The inline-image panel (handoff 0063) has its own upload form; this picker is the cover's.
    assert_select "input[type=file][name='product_line[cover_image]']", 1
    assert_select "input[type=file][name='product_line[cover_image]'][accept='image/jpeg,image/png,image/webp']"
    assert_select "input[type=file][data-file-picker-target='input'][data-action='file-picker#update']"

    input_id = css_select("input[type=file][name='product_line[cover_image]']").first["id"]
    assert input_id.present?

    # the visible button is the label bound to the real input, so clicking / Enter / Space still opens the native dialog
    button = css_select("label[for='#{input_id}']").first
    assert_not_nil button, "no label bound to the file input"
    assert_equal "대표 이미지 선택", button.text.strip
    assert_not_nil button.at_css("svg[aria-hidden='true']"), "upload icon missing"
    %w[border bg-white px-4 py-2 rounded-lg cursor-pointer hover:bg-blue-50 hover:border-blue-400 peer-focus-visible:ring-2 peer-focus-visible:border-blue-600].each do |klass|
      assert_includes button["class"].split, klass, "button missing #{klass}"
    end

    # the input is visually hidden but not removed from the tab order, and precedes its label so `peer-*` styles apply
    input = css_select("input[type=file]").first
    assert_includes input["class"].split, "sr-only"
    assert_includes input["class"].split, "peer"
    assert_nil input["hidden"]
    assert_nil input["tabindex"]
    assert_not_includes input["style"].to_s, "display"

    name = css_select("[data-file-picker-target='name']").first
    assert_equal "선택된 파일 없음", name.text.strip
    assert_equal "polite", name["aria-live"]
  end

  test "the create screen shows a real upload button, not a bare file input" do
    sign_in_as(@admin)
    get new_admin_product_line_path
    assert_response :success
    assert_cover_picker
  end

  test "the edit screen shows the same upload button, with and without a stored image" do
    sign_in_as(@admin)
    without_image = make_line(with_cover: false, slug: "no-image-line")
    get edit_admin_product_line_path(without_image)
    assert_cover_picker
    assert_select "#content-images input[type=file]", 1
    assert_no_match(/새 이미지로 교체/, response.body)

    line = make_line
    get edit_admin_product_line_path(line)
    assert_cover_picker
    assert_match(/새 이미지로 교체 \(선택\)/, response.body)
    assert_match(/교체되어 삭제됩니다/, response.body)
  end

  test "the file-picker controller is registered with the importmap" do
    sign_in_as(@admin)
    get new_admin_product_line_path
    assert_match(%r{"controllers/file_picker_controller"}, response.body)
  end

  test "a failed create re-renders the picker and keeps working" do
    sign_in_as(@admin)
    post admin_product_lines_path, params: line_params(customer_name: "", cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "설명")
    assert_response :unprocessable_entity
    assert_cover_picker
  end

  test "create without an image still works and needs no alt" do
    sign_in_as(@admin)
    assert_difference "ProductLine.count", 1 do
      post admin_product_lines_path, params: line_params
    end
    assert_not ProductLine.last.cover_image.attached?
  end

  test "an image without alt text is refused and nothing is saved (no partial save)" do
    sign_in_as(@admin)
    assert_no_difference [ "ProductLine.count", "ActiveStorage::Blob.count" ] do
      post admin_product_lines_path, params: line_params(cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "")
      assert_response :unprocessable_entity
      assert_match(/대체문구/, response.body)
    end
  end

  test "invalid product fields with a valid image save neither" do
    sign_in_as(@admin)
    assert_no_difference [ "ProductLine.count", "ActiveStorage::Blob.count" ] do
      post admin_product_lines_path, params: line_params(customer_name: "", cover_image: fixture_file_upload("covers/cover.jpg", "image/jpeg"), cover_image_alt: "설명")
      assert_response :unprocessable_entity
    end
  end

  test "rejected image types show the reason and store nothing" do
    sign_in_as(@admin)
    { "evil.svg" => "image/svg+xml", "anim.gif" => "image/gif", "doc.pdf" => "application/pdf",
      "not_image.jpg" => "image/jpeg", "truncated.jpg" => "image/jpeg" }.each do |name, type|
      assert_no_difference [ "ProductLine.count", "ActiveStorage::Blob.count" ] do
        post admin_product_lines_path, params: line_params(cover_image: fixture_file_upload("covers/#{name}", type), cover_image_alt: "설명")
        assert_response :unprocessable_entity, "#{name} accepted"
        assert_match(/대표 이미지|Cover image|이미지/, response.body)
      end
    end
  end

  test "edit shows the current image preview, filename, size and resolution, and the replace warning" do
    sign_in_as(@admin)
    line = make_line
    get edit_admin_product_line_path(line)
    assert_response :success
    assert_match(/hero\.jpg/, response.body)
    assert_match(/640×360px/, response.body)
    assert_match(/교체되어 삭제됩니다/, response.body)
    assert_select "img[src^='#{admin_product_line_cover_image_path(line, "thumb")}']"
    assert_select "input[name='product_line[cover_image_alt]'][value='대체문구 원본']"
  end

  test "edit: replacing the image swaps the file, cleans up the old blob and file, and keeps other data" do
    sign_in_as(@admin)
    line = make_line
    old_blob = line.cover_image.blob
    old_key = old_blob.key

    perform_enqueued_jobs do
      patch admin_product_line_path(line), params: { product_line: { cover_image: fixture_file_upload("covers/cover.png", "image/png"), cover_image_alt: "새 설명" } }
    end
    assert_redirected_to edit_admin_product_line_path(line)
    line.reload
    assert_equal "cover.png", line.cover_image.filename.to_s
    assert_equal "새 설명", line.cover_image_alt
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(old_key)
  end

  test "edit: a failed update (bad image, or bad field) leaves the stored image and fields untouched" do
    sign_in_as(@admin)
    line = make_line
    blob_id = line.cover_image.blob.id

    assert_no_difference "ActiveStorage::Blob.count" do
      patch admin_product_line_path(line), params: { product_line: { customer_name: "바뀜", cover_image: fixture_file_upload("covers/evil.svg", "image/svg+xml") } }
      assert_response :unprocessable_entity
      patch admin_product_line_path(line), params: { product_line: { customer_name: "", cover_image: fixture_file_upload("covers/cover.png", "image/png"), cover_image_alt: "x" } }
      assert_response :unprocessable_entity
      assert_select "img[src^='#{admin_product_line_cover_image_path(line, "thumb")}']", 1
    end
    line.reload
    assert_equal blob_id, line.cover_image.blob.id
    assert_equal "커버 제품", line.customer_name
    assert_equal "대체문구 원본", line.cover_image_alt
  end

  test "editing other fields with no new file keeps the image" do
    sign_in_as(@admin)
    line = make_line
    blob_id = line.cover_image.blob.id
    patch admin_product_line_path(line), params: { product_line: { customer_name: "이름만 변경" } }
    assert_equal blob_id, line.reload.cover_image.blob.id
    assert_equal "이름만 변경", line.customer_name
  end

  test "the delete section names the product and file and warns it is irreversible; it does nothing until submitted" do
    sign_in_as(@admin)
    line = make_line
    get edit_admin_product_line_path(line)
    confirm = css_select("form[action='#{admin_product_line_cover_path(line)}'] button").first["data-turbo-confirm"]
    assert_includes confirm, "커버 제품"
    assert_includes confirm, "hero.jpg"
    assert_includes confirm, "되돌릴 수 없습니다"
    assert line.reload.cover_image.attached?
  end

  test "deleting the cover removes attachment, blob, variants, files and the alt text; product data stays" do
    sign_in_as(@admin)
    line = make_line
    get admin_product_line_cover_image_path(line, "hero") # creates the variant
    assert_response :success
    keys = ActiveStorage::Blob.pluck(:key)
    assert_equal 2, keys.size

    perform_enqueued_jobs { delete admin_product_line_cover_path(line) }

    assert_redirected_to edit_admin_product_line_path(line)
    assert_match(/hero\.jpg.*삭제했습니다/, flash[:notice])
    line.reload
    assert_not line.cover_image.attached?
    assert_nil line.cover_image_alt
    assert_equal "커버 제품", line.customer_name
    assert_equal 0, ActiveStorage::Blob.count
    keys.each { |key| assert_not ActiveStorage::Blob.service.exist?(key) }

    delete admin_product_line_cover_path(line)
    assert_response :not_found
  end

  test "admin preview shows the draft product's Hero image with its alt text" do
    sign_in_as(@admin)
    line = make_line(status: "draft")
    get admin_product_line_path(line)
    assert_response :success
    assert_select "img[alt='대체문구 원본'][src^='#{admin_product_line_cover_image_path(line, "hero")}']"
    get admin_product_line_cover_image_path(line, "hero")
    assert_response :success
    assert_equal "image/webp", response.media_type
  end

  test "admin list shows the thumbnail; a product without one shows the shared placeholder" do
    sign_in_as(@admin)
    line = make_line
    ProductLine.create!(internal_name: "n", customer_name: "이미지 없음", slug: "no-cover", introduction: "소개")
    get admin_product_lines_path
    assert_response :success
    assert_select "img", 2
    assert_select "img[src^='#{admin_product_line_cover_image_path(line, "thumb")}']", 1
    assert_select "img[alt='대표 이미지 없음 (기본 이미지)']", 1
  end

  test "admin cover route: unknown variant, missing cover and missing product are 404" do
    sign_in_as(@admin)
    line = make_line
    get admin_product_line_cover_image_path(line, "original")
    assert_response :not_found
    get admin_product_line_cover_image_path(line, "../../etc")
    assert_response :not_found
    get admin_product_line_cover_image_path(make_line_without = ProductLine.create!(internal_name: "x", customer_name: "x", slug: "x-line", introduction: "소개"), "hero")
    assert_response :not_found
    assert make_line_without.persisted?
    get admin_product_line_cover_image_path(0, "hero")
    assert_response :not_found
  end
end
