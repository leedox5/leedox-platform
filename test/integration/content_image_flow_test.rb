require "test_helper"

# Handoff 0063 -- upload, insert, display and delivery of inline images, and the
# gates that keep an image exactly as reachable as the text that shows it.
class ContentImageFlowTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
    @admin = User.create!(name: "관리자", email: "ci-admin-#{SecureRandom.hex(3)}@example.com", password: "password123", role: :admin)
    @user = User.create!(name: "일반", email: "ci-user-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    @line = ProductLine.create!(internal_name: "A", customer_name: "이미지 제품", slug: "image-line", introduction: "소개", status: "published")
    @episode = @line.content_episodes.create!(position: 1, customer_title: "첫 편", body: "본문", status: "published")
  end

  def sign_in(user)
    post user_session_path, params: { user: { email: user.email, password: "password123" } }
  end

  def sign_out
    delete destroy_user_session_path
  end

  def upload(fixture = "covers/cover.jpg", type = "image/jpeg")
    fixture_file_upload(fixture, type)
  end

  def add_image(parent, alt: "화면 캡처")
    parent.content_images.create!(alt: alt, file: { io: file_fixture("covers/cover.jpg").open, filename: "cover.jpg", content_type: "image/jpeg" })
  end

  def with_class_method(klass, name, value)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*| value }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  # --- access control of the admin side -------------------------------------

  test "only admins can upload, edit, delete, view or preview images" do
    image = add_image(@line)
    files = [
      [ :post, admin_product_line_content_images_path(@line), { content_image: { file: upload, alt: "x" } } ],
      [ :post, admin_content_episode_content_images_path(@episode), { content_image: { file: upload, alt: "x" } } ],
      [ :patch, admin_content_image_path(image.public_id), { content_image: { alt: "바꿈" } } ],
      [ :delete, admin_content_image_path(image.public_id), {} ],
      [ :get, admin_content_image_file_path(image.public_id, variant: "thumb"), {} ],
      [ :post, admin_markdown_preview_path, { text: "x", parent_type: "product_line", parent_id: @line.id } ]
    ]

    [ nil, @user ].each do |who|
      sign_in(who) if who
      assert_no_difference "ContentImage.count" do
        files.each do |verb, path, params|
          public_send(verb, path, params: params)
          assert_response :redirect, "#{verb} #{path} for #{who ? 'a non-admin' : 'a guest'}"
        end
      end
      assert_equal "화면 캡처", image.reload.alt
      sign_out if who
    end
  end

  # --- admin upload ---------------------------------------------------------

  test "an admin uploads an image to a product line and the edit screen lists it with an insert button" do
    sign_in(@admin)
    assert_difference "ContentImage.count", 1 do
      post admin_product_line_content_images_path(@line), params: { content_image: { file: upload, alt: "화면 캡처" } }
    end
    assert_redirected_to edit_admin_product_line_path(@line)
    image = @line.content_images.sole

    follow_redirect!
    assert_select "#content-images li", 1
    assert_select "#content-images img[src=?]", admin_content_image_file_path(image.public_id, variant: "thumb")
    assert_select "#content-images button[data-markdown-editor-snippet-param=?]", "![화면 캡처](image:#{image.public_id})", text: "본문에 삽입"
    assert_select "#content-images form[action=?] input[name='content_image[alt]']", admin_content_image_path(image.public_id)
  end

  test "an admin uploads an image to an episode" do
    sign_in(@admin)
    assert_difference "@episode.content_images.count", 1 do
      post admin_content_episode_content_images_path(@episode), params: { content_image: { file: upload("covers/cover.png", "image/png"), alt: "다이어그램" } }
    end
    assert_redirected_to edit_admin_content_episode_path(@episode)
  end

  test "an upload without alt text, of a forbidden type, or over the limits is refused and reported" do
    sign_in(@admin)
    [
      [ { file: upload, alt: "" }, "대체문구" ],
      [ { file: upload("covers/evil.svg", "image/svg+xml"), alt: "x" }, "허용되지 않는 형식" ],
      [ { file: upload("covers/anim.gif", "image/gif"), alt: "x" }, "허용되지 않는 형식" ],
      [ { file: upload("covers/truncated.jpg"), alt: "x" }, "" ],
      [ { alt: "파일 없음" }, "이미지 파일" ]
    ].each do |params, expected|
      assert_no_difference "ContentImage.count" do
        post admin_product_line_content_images_path(@line), params: { content_image: params }
      end
      assert_redirected_to edit_admin_product_line_path(@line)
      assert_includes flash[:alert].to_s, expected
    end

    with_class_method(ContentImage, :max_images_per_parent, 0) do
      assert_no_difference "ContentImage.count" do
        post admin_product_line_content_images_path(@line), params: { content_image: { file: upload, alt: "x" } }
      end
      assert_includes flash[:alert].to_s, "최대 0장"
    end
  end

  test "a storage outage while uploading saves nothing and shows the plain try-again message" do
    sign_in(@admin)
    ContentImage.class_eval { def upload_pending_attachments_before_commit = raise(Errno::ECONNREFUSED) }
    begin
      assert_no_difference [ "ContentImage.count", "ActiveStorage::Blob.count" ] do
        post admin_product_line_content_images_path(@line), params: { content_image: { file: upload, alt: "x" } }
      end
    ensure
      ContentImage.send(:remove_method, :upload_pending_attachments_before_commit)
    end
    assert_redirected_to edit_admin_product_line_path(@line)
    assert_equal StorageFailures::UNAVAILABLE_MESSAGE, flash[:alert]
  end

  test "an admin can change the alt text and delete an image (its stored file goes too)" do
    image = add_image(@line)
    blob_id = image.file.blob.id
    sign_in(@admin)

    patch admin_content_image_path(image.public_id), params: { content_image: { alt: "새 설명" } }
    assert_equal "새 설명", image.reload.alt
    patch admin_content_image_path(image.public_id), params: { content_image: { alt: "" } }
    assert_equal "새 설명", image.reload.alt

    @line.update!(introduction: "글 ![x](#{image.reference})")
    assert_difference "ContentImage.count", -1 do
      delete admin_content_image_path(image.public_id)
    end
    assert_not ActiveStorage::Blob.exists?(blob_id)
    assert_match(/남아 있으니 지워/, flash[:notice])
  end

  test "the admin can view the stored image and its thumbnail, draft or not, and only those two variants" do
    @line.update!(status: "draft")
    image = add_image(@line)
    sign_in(@admin)

    %w[thumb body].each do |variant|
      get admin_content_image_file_path(image.public_id, variant: variant)
      assert_response :success
      assert_equal "image/webp", response.media_type
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
      assert_includes response.headers["Cache-Control"], "no-cache"
      assert_not_includes response.headers["Cache-Control"], "public"
    end
    get "/admin/content_images/#{image.public_id}/original"
    assert_response :not_found
  end

  # --- editing screens ------------------------------------------------------

  test "the editing screens carry the image panel and the Markdown preview controls, the new-product form does not" do
    sign_in(@admin)
    [ [ edit_admin_product_line_path(@line), "product_line", @line.id, "product_line[introduction]" ],
      [ edit_admin_content_episode_path(@episode), "content_episode", @episode.id, "content_episode[body]" ] ].each do |path, type, id, field|
      get path
      assert_response :success
      assert_select "div[data-controller='markdown-editor'][data-markdown-editor-url-value=?][data-markdown-editor-parent-type-value=?][data-markdown-editor-parent-id-value=?]",
        admin_markdown_preview_path, type, id.to_s
      assert_select "div[data-controller='markdown-editor'] textarea[name=?][data-markdown-editor-target='textarea']", field
      assert_select "button[data-action='markdown-editor#preview']", text: "미리보기"
      assert_select "[data-markdown-editor-target='preview'][hidden]"
      assert_select "#content-images form[enctype='multipart/form-data'] input[type=file][accept='image/jpeg,image/png,image/webp'][required]"
      assert_select "#content-images input[name='content_image[alt]'][required]"
      assert_select "#content-images form form", 0, "forms must not nest"
    end

    get new_admin_product_line_path
    assert_response :success
    assert_select "#content-images", 0
  end

  # Between a deploy and its migration the images table does not exist yet: nothing may fail.
  test "before the migration has run, customer pages and the admin editing screens still work" do
    with_class_method(ContentImage, :table_exists?, false) do
      @episode.update!(body: "본문 ![x](image:11111111-1111-1111-1111-111111111111)")
      [ product_line_path(@line.slug), product_episode_path(@line.slug, @episode.display_id) ].each do |path|
        get path
        assert_response :success, path
      end
      get product_image_path("11111111-1111-1111-1111-111111111111")
      assert_response :not_found

      sign_in(@admin)
      [ edit_admin_product_line_path(@line), edit_admin_content_episode_path(@episode) ].each do |path|
        get path
        assert_response :success, path
        assert_select "#content-images-unavailable"
        assert_select "#content-images", 0
      end
    end
  end

  test "the preview renders the draft like the customer page, resolves the record's own images and reports what it dropped" do
    image = add_image(@episode)
    sign_in(@admin)

    post admin_markdown_preview_path, params: {
      text: "**굵게** ![x](#{image.reference}) ![외부](https://evil.example/t.png) <script>x</script>",
      parent_type: "content_episode", parent_id: @episode.id
    }
    assert_response :success
    assert_select ".doc-content strong", "굵게"
    assert_select ".doc-content img[src=?]", admin_content_image_file_path(image.public_id, variant: "body")
    assert_select ".doc-content img", 1
    assert_select ".doc-content script", 0
    assert_select "ul li", text: /외부 이미지는 사용할 수 없어/

    post admin_markdown_preview_path, params: { text: "![x](#{image.reference})", parent_type: "product_line", parent_id: @line.id }
    assert_select ".doc-content img", 0
    assert_select "ul li", text: /속하지 않았거나 삭제된 이미지/
  end

  # --- what customers see ---------------------------------------------------

  test "the introduction shows the product's image and it is delivered with the safe headers" do
    image = add_image(@line, alt: "제품 화면")
    @line.update!(introduction: "소개 글\n\n![제품 화면](#{image.reference})")

    get product_line_path(@line.slug)
    assert_response :success
    assert_select "main .doc-content img[src=?][alt=?][loading=lazy]", product_image_path(image.public_id), "제품 화면"

    get product_image_path(image.public_id)
    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Cache-Control"], "max-age=300"
    assert_includes response.headers["Cache-Control"], "private"
    assert_operator response.body.bytesize, :>, 100
    assert_no_match(/secret-original-name|cover\.jpg/, response.headers.to_h.values.join(" "), "the stored file name is never sent")
  end

  test "an image of a draft or unpublished product is a 404 for visitors and visible to admins" do
    image = add_image(@line)
    @line.update!(status: "draft")

    get product_image_path(image.public_id)
    assert_response :not_found
    sign_in(@user)
    get product_image_path(image.public_id)
    assert_response :not_found
    sign_out

    sign_in(@admin)
    get product_image_path(image.public_id)
    assert_response :success
  end

  test "an unknown image id is a 404" do
    get product_image_path("11111111-1111-1111-1111-111111111111")
    assert_response :not_found
  end

  test "an episode image is shown in the episode body and takeaway, and follows the episode's gates" do
    image = add_image(@episode)
    @episode.update!(body: "앞\n\n![캡처](#{image.reference})")
    @episode.content_takeaways.create!(kind: "카드", body: "![카드](#{image.reference})", position: 1)

    get product_episode_path(@line.slug, @episode.display_id)
    assert_response :success
    assert_select ".doc-content img[src=?]", product_image_path(image.public_id), 2

    get product_image_path(image.public_id)
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-cache", "an episode image is re-checked on every request"
    assert_not_includes response.headers["Cache-Control"], "public"

    @episode.update!(status: "draft")
    get product_image_path(image.public_id)
    assert_response :not_found
  end

  test "an image inside a license-gated product needs the license, like the episode itself" do
    Commerce::ProductLineSales.set_price!(product_line: @line, total_amount: 0, actor: @admin)
    Commerce::ProductLineSales.start_sale!(product_line: @line, actor: @admin)
    holder = User.create!(name: "보유", email: "ci-holder-#{SecureRandom.hex(3)}@example.com", password: "password123", created_at: 30.days.ago)
    Commerce::ClaimFreeAccess.call!(user: holder, product_line: @line.reload)
    image = add_image(@episode)

    get product_image_path(image.public_id)
    assert_response :not_found

    sign_in(@user)
    get product_image_path(image.public_id)
    assert_response :not_found
    sign_out

    sign_in(holder)
    get product_image_path(image.public_id)
    assert_response :success
  end

  test "a text can only show its own record's images" do
    episode_image = add_image(@episode)
    @line.update!(introduction: "![남의 이미지](#{episode_image.reference})")

    get product_line_path(@line.slug)
    assert_response :success
    assert_select "main .doc-content img", 0
  end

  test "raw HTML and external images in a text are inert on the customer page" do
    @line.update!(introduction: %(<script>alert(1)</script> <img src="https://evil.example/x.png" onerror="alert(1)"> ![외부](https://evil.example/t.png) <b style="color:red">굵게</b>))

    get product_line_path(@line.slug)
    assert_response :success
    assert_select "main script", 0
    assert_select "main img", 0
    assert_select "main b", 0
    assert_select "main [style]", 0
    assert_select "main [onerror]", 0
    assert_no_match(/evil\.example/, css_select("main .doc-content").to_html.gsub(/&lt;.*?&gt;/, ""), "no live reference to an outside host outside the escaped text")
  end

  test "existing episode content still renders: tables, checklists, code and links" do
    @episode.update!(body: "| a | b |\n|---|---|\n| 1 | 2 |\n\n- [ ] 할 일\n- [x] 끝\n\n```ruby\nputs 1\n```\n\n[링크](https://example.com)")

    get product_episode_path(@line.slug, @episode.display_id)
    assert_response :success
    assert_select ".doc-content table th", 2
    assert_select ".doc-content li.checklist-item input[type=checkbox][disabled]", 2
    assert_select ".doc-content li[style]", 0
    assert_select ".doc-content pre code"
    assert_select ".doc-content a[href='https://example.com'][target='_blank'][rel='noopener noreferrer nofollow']"
  end
end
