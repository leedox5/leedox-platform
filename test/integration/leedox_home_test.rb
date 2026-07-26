require "test_helper"

class LeedoxHomeTest < ActionDispatch::IntegrationTest
  setup do
    Commerce::CatalogBootstrap.call!
  end

  test "integrated home presents LEEDOX and both products without unconfirmed pricing" do
    get root_path

    assert_response :success
    assert_select "title", text: /LEEDOX/
    assert_select "header a[href=?]", root_path, text: /LEEDOX/
    assert_select "h1", text: /AI와 함께 일하는 방법을/
    assert_select "a[href=?]", chatdox_path, minimum: 1
    assert_select "a[href=?]", claudox_path, minimum: 1
    assert_select "a[href='#products']", minimum: 2
    assert_select "footer a[href=?]", terms_path
    assert_select "footer a[href=?]", privacy_path
    assert_no_match(/₩|9,900원|무료 체험|프리미엄 요금제/, response.body)
  end

  test "homepage proof section shows live chapter titles for both products, not frozen copies" do
    get root_path
    assert_response :success

    chatdox_titles = ProductContent.for("chatdox").chapters.first(4).map { |c| c[:title] }
    claudox_titles = %w[01 03 05 10].map { |id| ProductContent.for("claudox").find(id)[:title].sub(/\A\d+\.\s*/, "") }

    (chatdox_titles + claudox_titles).each do |title|
      assert_match(/#{Regexp.escape(title)}/, response.body)
    end
    # Numbering prefix from the raw Claudox heading must not leak into this
    # section (Chatdox's curated titles never had one, and doubling the
    # chapter number that's already shown as its own badge would look broken).
    assert_no_match(/\d+\. 클로독스와의 첫만남/, response.body)
  end

  test "guest header keeps authentication actions on desktop and mobile" do
    get root_path

    assert_response :success
    assert_select "a[href=?]", new_user_session_path, text: "로그인", count: 2
    assert_select "a[href=?]", new_user_registration_path, text: "회원가입", count: 2
    assert_select "nav[aria-label='모바일 내비게이션']"
  end

  test "guest and signed-in top navigation has no standalone docs entry and hides service desk" do
    get root_path
    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", docs_path, count: 0
    assert_select "nav[aria-label='모바일 내비게이션'] a[href=?]", docs_path, count: 0
    assert_select "a[href=?]", service_desk_path, count: 0

    user = User.create!(name: "테스트 유저", email: "nav-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get root_path
    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", docs_path, count: 0
    assert_select "nav[aria-label='모바일 내비게이션'] a[href=?]", docs_path, count: 0
    assert_select "a[href=?]", service_desk_path, count: 0
  end

  test "admin navigation keeps a working service desk link" do
    admin = User.create!(name: "테스트 유저", email: "nav-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get root_path

    assert_response :success
    assert_select "a[href=?]", service_desk_path, minimum: 1
  end

  test "mobile menu details element is wired to close on outside tap via Stimulus" do
    get root_path

    assert_response :success
    assert_select "details[data-controller='mobile-menu']"
  end

  test "service desk blocks guests and non-admin users but allows admins" do
    request = ServiceDeskRequest.create!(request_number: 5001, requester: "Tester", subject: "Guard check", description: "body", visibility: :visible)

    get service_desk_path
    assert_response :redirect
    assert_redirected_to new_user_session_path

    get service_desk_request_path(request)
    assert_response :redirect
    assert_redirected_to new_user_session_path

    user = User.create!(name: "테스트 유저", email: "sd-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get service_desk_path
    assert_response :redirect
    assert_redirected_to root_path

    delete destroy_user_session_path

    admin = User.create!(name: "테스트 유저", email: "sd-admin@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_path
    assert_response :success

    get service_desk_request_path(request)
    assert_response :success
  end

  test "service desk hides Private-visibility requests from index and direct show access" do
    visible_request = ServiceDeskRequest.create!(request_number: 5002, requester: "Tester", subject: "Public ticket should show", visibility: :visible)
    private_request = ServiceDeskRequest.create!(request_number: 5003, requester: "Tester", subject: "Private ticket should stay hidden", visibility: :restricted)

    admin = User.create!(name: "테스트 유저", email: "sd-admin-vis@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_path
    assert_response :success
    assert_match(/Public ticket should show/, response.body)
    assert_no_match(/Private ticket should stay hidden/, response.body)

    get service_desk_request_path(private_request)
    assert_response :not_found

    get service_desk_request_path(visible_request)
    assert_response :success
  end

  test "service desk request page renders description/job sections and links to neighboring requests" do
    first = ServiceDeskRequest.create!(request_number: 5004, requester: "Tester", subject: "First ticket", description: "First body", status: :confirmed, visibility: :visible)
    second = ServiceDeskRequest.create!(request_number: 5005, requester: "Tester", subject: "Second ticket", description: "Second body", visibility: :visible)
    first.service_desk_jobs.create!(author: "Claudox", content: "Did the work")

    admin = User.create!(name: "테스트 유저", email: "sd-admin-render@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_request_path(first)

    assert_response :success
    assert_no_match(/```/, response.body)
    assert_select "h2", text: "Description"
    assert_select "h2", text: "Job"
    assert_select "article", text: /Confirmed/
    assert_match(/Did the work/, response.body)
    assert_select "a[href=?]", service_desk_request_path(second), minimum: 1
  end

  test "service desk list stays visible without a desktop-only breakpoint (mobile regression)" do
    ServiceDeskRequest.create!(request_number: 5006, requester: "Tester", subject: "Mobile visible ticket", visibility: :visible)

    admin = User.create!(name: "테스트 유저", email: "sd-admin-mobile@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_path

    assert_response :success
    assert_no_match(/hidden lg:block/, response.body)
    assert_select "a", text: /Mobile visible ticket/
  end

  test "admin can publish a new ticket via the web form and it gets an auto-numbered request_number" do
    admin = User.create!(name: "테스트 유저", email: "sd-admin-create@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get new_service_desk_request_path
    assert_response :success

    assert_difference "ServiceDeskRequest.count", 1 do
      post service_desk_path, params: { service_desk_request: { subject: "New web ticket", requester: "Tommy", visibility: "visible", description: "Filed from the web form" } }
    end

    created = ServiceDeskRequest.order(:request_number).last
    assert_equal "New web ticket", created.subject
    assert_redirected_to service_desk_request_path(created)

    follow_redirect!
    assert_match(/New web ticket/, response.body)
  end

  test "admin can add a job entry via the web form with auto-numbered job_number" do
    request = ServiceDeskRequest.create!(request_number: 5007, requester: "Tester", subject: "Job target", visibility: :visible)

    admin = User.create!(name: "테스트 유저", email: "sd-admin-job@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    assert_difference "request.service_desk_jobs.count", 1 do
      post service_desk_request_jobs_path(request), params: { service_desk_job: { author: "Tommy", content: "Investigated and fixed" } }
    end

    job = request.service_desk_jobs.order(:job_number).last
    assert_equal 1, job.job_number
    assert_redirected_to service_desk_request_path(request)

    follow_redirect!
    assert_match(/Investigated and fixed/, response.body)
  end

  test "publishing a ticket and adding a job auto-fill requester/author from the signed-in user's name, ignoring any submitted value" do
    admin = User.create!(name: "오토필 관리자", email: "sd-admin-autofill@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    post service_desk_path, params: { service_desk_request: { subject: "Autofill ticket", visibility: "visible", description: "body" } }
    created = ServiceDeskRequest.order(:request_number).last
    assert_equal admin.name, created.requester

    post service_desk_request_jobs_path(created), params: { service_desk_job: { author: "Someone Else", content: "Autofill job" } }
    job = created.service_desk_jobs.order(:job_number).last
    assert_equal admin.name, job.author
  end

  test "admin can edit a ticket's subject/status/visibility/description but not requester/request_number/date" do
    request = ServiceDeskRequest.create!(request_number: 5009, requester: "Original Requester", subject: "Original subject", visibility: :visible, status: :pending)
    original_date = request.date

    admin = User.create!(name: "테스트 유저", email: "sd-admin-edit@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get edit_service_desk_request_path(request)
    assert_response :success
    assert_select "input[name=?]", "service_desk_request[requester]", count: 0

    patch service_desk_request_path(request), params: { service_desk_request: { subject: "Updated subject", status: "confirmed", visibility: "restricted", description: "Updated body", requester: "Hijacked requester" } }

    assert_redirected_to service_desk_request_path(request)
    request.reload
    assert_equal "Updated subject", request.subject
    assert_equal "confirmed", request.status
    assert_equal "restricted", request.visibility
    assert_equal "Updated body", request.description
    assert_equal "Original Requester", request.requester
    assert_equal 5009, request.request_number
    assert_equal original_date, request.date
  end

  test "editing a ticket with an invalid subject re-renders the edit form with errors" do
    request = ServiceDeskRequest.create!(request_number: 5010, requester: "Tester", subject: "Keep me", visibility: :visible)

    admin = User.create!(name: "테스트 유저", email: "sd-admin-edit-invalid@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    patch service_desk_request_path(request), params: { service_desk_request: { subject: "", visibility: "visible", description: "" } }

    assert_response :unprocessable_content
    request.reload
    assert_equal "Keep me", request.subject
  end

  test "admin can edit a job's content but author and performed_at stay unchanged" do
    request = ServiceDeskRequest.create!(request_number: 5011, requester: "Tester", subject: "Job edit target", visibility: :visible)
    job = request.service_desk_jobs.create!(author: "Original Author", content: "Original content")
    original_performed_at = job.performed_at

    admin = User.create!(name: "테스트 유저", email: "sd-admin-job-edit@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get edit_service_desk_request_job_path(request, job.job_number)
    assert_response :success

    patch service_desk_request_job_path(request, job.job_number), params: { service_desk_job: { content: "Updated content", author: "Hijacked author" } }

    assert_redirected_to service_desk_request_path(request)
    job.reload
    assert_equal "Updated content", job.content
    assert_equal "Original Author", job.author
    assert_equal original_performed_at.to_i, job.performed_at.to_i
  end

  test "ticket and job edit routes block guests and non-admin users" do
    request = ServiceDeskRequest.create!(request_number: 5012, requester: "Tester", subject: "Guard check", visibility: :visible)
    job = request.service_desk_jobs.create!(author: "Tester", content: "content")

    get edit_service_desk_request_path(request)
    assert_redirected_to new_user_session_path
    patch service_desk_request_path(request), params: { service_desk_request: { subject: "Nope" } }
    assert_redirected_to new_user_session_path
    get edit_service_desk_request_job_path(request, job.job_number)
    assert_redirected_to new_user_session_path
    patch service_desk_request_job_path(request, job.job_number), params: { service_desk_job: { content: "Nope" } }
    assert_redirected_to new_user_session_path

    user = User.create!(name: "테스트 유저", email: "sd-user-edit-guard@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get edit_service_desk_request_path(request)
    assert_redirected_to root_path
    patch service_desk_request_path(request), params: { service_desk_request: { subject: "Nope" } }
    assert_redirected_to root_path
    get edit_service_desk_request_job_path(request, job.job_number)
    assert_redirected_to root_path
    patch service_desk_request_job_path(request, job.job_number), params: { service_desk_job: { content: "Nope" } }
    assert_redirected_to root_path

    request.reload
    job.reload
    assert_equal "Guard check", request.subject
    assert_equal "content", job.content
  end

  test "job timestamps render in KST (UTC+9), not UTC" do
    request = ServiceDeskRequest.create!(request_number: 5013, requester: "Tester", subject: "Timezone check", visibility: :visible)
    job = nil
    travel_to Time.utc(2026, 3, 15, 5, 6, 0) do
      job = request.service_desk_jobs.create!(author: "Tester", content: "job at a known instant")
    end

    admin = User.create!(name: "테스트 유저", email: "sd-admin-tz@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_request_path(request)

    assert_response :success
    assert_equal "Asia/Seoul", Time.zone.name
    assert_equal 14, job.performed_at.hour
    assert_match(/14:06/, response.body)
    assert_no_match(/05:06/, response.body)
  end

  test "service desk home shows a '내 관련' card scoped to the signed-in admin's own requester/author matches" do
    admin = User.create!(name: "테스트 유저", email: "sd-admin-mine@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    ServiceDeskRequest.create!(request_number: 5014, requester: admin.name, subject: "Filed by me", visibility: :visible)
    mine_by_job = ServiceDeskRequest.create!(request_number: 5015, requester: "someone-else@example.com", subject: "I left a job here", visibility: :visible)
    mine_by_job.service_desk_jobs.create!(author: admin.name, content: "my note")
    not_mine = ServiceDeskRequest.create!(request_number: 5016, requester: "someone-else@example.com", subject: "Not related to me", visibility: :visible)
    not_mine.service_desk_jobs.create!(author: "someone-else@example.com", content: "their note")

    get service_desk_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    my_related_card = doc.css("article").find { |article| article.at_css("h2")&.text == "내 관련" }
    assert my_related_card, "expected a '내 관련' card"
    assert_match(/2건/, my_related_card.at_css("span").text)
    assert_match(/Filed by me/, my_related_card.text)
    assert_match(/I left a job here/, my_related_card.text)
    assert_no_match(/Not related to me/, my_related_card.text)
  end

  test "service desk home shows a '신규' card for New-status tickets" do
    admin = User.create!(name: "테스트 유저", email: "sd-admin-new@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    ServiceDeskRequest.create!(request_number: 5017, requester: "Tester", subject: "Freshly filed", visibility: :visible, status: :pending)
    ServiceDeskRequest.create!(request_number: 5018, requester: "Tester", subject: "Already confirmed", visibility: :visible, status: :confirmed)

    get service_desk_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    new_card = doc.css("article").find { |article| article.at_css("h2")&.text == "신규" }
    assert new_card, "expected a '신규' card"
    assert_match(/1건/, new_card.at_css("span").text)
    assert_match(/Freshly filed/, new_card.text)
    assert_no_match(/Already confirmed/, new_card.text)
  end

  test "service desk home still renders the full unfiltered list below the summary cards" do
    admin = User.create!(name: "테스트 유저", email: "sd-admin-full-list@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    ServiceDeskRequest.create!(request_number: 5019, requester: "someone-else@example.com", subject: "Unrelated confirmed ticket", visibility: :visible, status: :confirmed)

    get service_desk_path

    assert_response :success
    assert_match(/Unrelated confirmed ticket/, response.body)
  end

  test "service desk export downloads a zip of all requests" do
    ServiceDeskRequest.create!(request_number: 5008, requester: "Tester", subject: "Export me", visibility: :visible)

    admin = User.create!(name: "테스트 유저", email: "sd-admin-export@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    post service_desk_export_path

    assert_response :success
    assert_equal "application/zip", response.media_type
    assert response.body.start_with?("PK"), "expected a zip file signature"
  end

  test "service desk API rejects requests without a valid bearer token" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"

    post service_desk_api_requests_path, params: { subject: "No auth", requester: "Agent" }
    assert_response :unauthorized

    post service_desk_api_requests_path, params: { subject: "Wrong token", requester: "Agent" },
                                          headers: { "Authorization" => "Bearer wrong-token" }
    assert_response :unauthorized
  ensure
    ENV["SERVICE_DESK_API_TOKEN"] = original_token
  end

  test "service desk API creates requests and jobs for AI agents with a valid bearer token" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"
    auth_headers = { "Authorization" => "Bearer test-token-123" }

    assert_difference "ServiceDeskRequest.count", 1 do
      post service_desk_api_requests_path, params: { subject: "Agent-filed ticket", requester: "Claudox", visibility: "visible", description: "Filed via API" },
                                            headers: auth_headers
    end
    assert_response :created
    body = JSON.parse(response.body)
    request = ServiceDeskRequest.find_by(request_number: body["request_number"])
    assert_equal "Agent-filed ticket", request.subject

    assert_difference "request.service_desk_jobs.count", 1 do
      post service_desk_api_request_jobs_path(request_id: request.request_number), params: { author: "Claudox", content: "Handled via API" },
                                                                                    headers: auth_headers
    end
    assert_response :created
    job_body = JSON.parse(response.body)
    assert_equal "Handled via API", job_body["content"]
    assert_equal 1, job_body["job_number"]
  ensure
    ENV["SERVICE_DESK_API_TOKEN"] = original_token
  end

  test "service desk API rejects reads without a valid bearer token" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"
    request = ServiceDeskRequest.create!(request_number: 6001, requester: "Tester", subject: "Guarded ticket", visibility: :visible)

    get service_desk_api_request_path(request.request_number)
    assert_response :unauthorized

    get service_desk_api_requests_path
    assert_response :unauthorized
  ensure
    ENV["SERVICE_DESK_API_TOKEN"] = original_token
  end

  test "service desk API shows a single request with its full job list" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"
    auth_headers = { "Authorization" => "Bearer test-token-123" }
    request = ServiceDeskRequest.create!(request_number: 6002, requester: "Tommy", subject: "Readable ticket", description: "body text", visibility: :visible)
    request.service_desk_jobs.create!(author: "Claudox", content: "First job")
    request.service_desk_jobs.create!(author: "Claudox", content: "Second job")

    get service_desk_api_request_path(request.request_number), headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal request.request_number, body["request_number"]
    assert_equal "Readable ticket", body["subject"]
    assert_equal "Tommy", body["requester"]
    assert_equal "New", body["status"]
    assert_equal "Public", body["visibility"]
    assert_equal "body text", body["description"]
    assert_equal 2, body["jobs"].length
    assert_equal "First job", body["jobs"][0]["content"]
    assert_equal 1, body["jobs"][0]["job_number"]
  ensure
    ENV["SERVICE_DESK_API_TOKEN"] = original_token
  end

  test "service desk API returns 404 for a missing request" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"
    auth_headers = { "Authorization" => "Bearer test-token-123" }

    get service_desk_api_request_path(999_999), headers: auth_headers

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not found", body["error"]
  ensure
    ENV["SERVICE_DESK_API_TOKEN"] = original_token
  end

  test "service desk API lists requests newest-first with job counts and no descriptions" do
    original_token = ENV["SERVICE_DESK_API_TOKEN"]
    ENV["SERVICE_DESK_API_TOKEN"] = "test-token-123"
    auth_headers = { "Authorization" => "Bearer test-token-123" }
    older = ServiceDeskRequest.create!(request_number: 6003, requester: "Tester", subject: "Older ticket", visibility: :visible)
    newer = ServiceDeskRequest.create!(request_number: 6004, requester: "Tester", subject: "Newer ticket", visibility: :restricted)
    newer.service_desk_jobs.create!(author: "Claudox", content: "Some work")

    get service_desk_api_requests_path, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    newer_entry = body.find { |entry| entry["request_number"] == newer.request_number }
    older_entry = body.find { |entry| entry["request_number"] == older.request_number }
    assert body.index(newer_entry) < body.index(older_entry)
    assert_equal 1, newer_entry["job_count"]
    assert_equal 0, older_entry["job_count"]
    assert_equal "Private", newer_entry["visibility"]
    assert_not newer_entry.key?("description")
  end

  test "signed in header keeps account identity and sign out actions" do
    user = User.create!(name: "홈테스트 유저", email: "home-test@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get root_path

    assert_response :success
    assert_select "header", text: /홈테스트 유저/
    assert_select "a[href=?][data-turbo-method='delete']", destroy_user_session_path, text: "로그아웃", count: 2
    assert_select "a[href=?]", mypage_path, minimum: 1
    assert_select "a[href=?]", new_user_session_path, count: 0
  end

  test "signing up without a name fails validation and does not create a User" do
    assert_no_difference "User.count" do
      post user_registration_path, params: { user: { email: "no-name@example.com", password: "password123", password_confirmation: "password123" } }
    end

    assert_response :unprocessable_content
  end

  test "signing up with a name creates the User with that name and signs them in" do
    assert_difference "User.count", 1 do
      post user_registration_path, params: { user: { name: "새 유저", email: "new-signup@example.com", password: "password123", password_confirmation: "password123" } }
    end

    created = User.order(:created_at).last
    assert_equal "새 유저", created.name
    assert_equal "new-signup@example.com", created.email
    assert_redirected_to dashboard_path
  end

  test "the signup form has no name field pre-filled and shows Korean labels" do
    get new_user_registration_path

    assert_response :success
    assert_select "input[name='user[name]']"
    assert_select "input[name='user[email]']"
    assert_match(/이름/, response.body)
  end

  test "editing account info can change the name without touching email/password" do
    user = User.create!(name: "원래 이름", email: "edit-name@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    patch user_registration_path, params: { user: { name: "바뀐 이름", current_password: "password123" } }

    assert_redirected_to root_path
    user.reload
    assert_equal "바뀐 이름", user.name
    assert_equal "edit-name@example.com", user.email
  end

  test "dashboard greets the signed-in user by name" do
    user = User.create!(name: "대시보드 유저", email: "dashboard-name@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get dashboard_path

    assert_response :success
    assert_match(/안녕하세요, 대시보드 유저님/, response.body)
    assert_no_match(/dashboard-name@example\.com/, response.body)
  end

  test "mypage shows both name and email in account info" do
    user = User.create!(name: "마이페이지 유저", email: "mypage-name@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get mypage_path

    assert_response :success
    assert_select "dt", text: "이름"
    assert_select "dd", text: "마이페이지 유저"
    assert_select "dt", text: "이메일"
    assert_select "dd", text: "mypage-name@example.com"
  end

  test "admin users index shows name as primary text and email as secondary" do
    admin = User.create!(name: "관리자 유저", email: "admin-index@example.com", password: "password123", role: :admin)
    other = User.create!(name: "다른 유저", email: "other-index@example.com", password: "password123")
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get admin_users_path

    assert_response :success
    doc = Nokogiri::HTML(response.body)
    row = doc.css("tbody tr").find { |tr| tr.text.include?(other.email) }
    assert row, "expected a row for #{other.email}"
    assert_equal "다른 유저", row.at_css("td p.font-medium").text
    assert_match(/other-index@example\.com/, row.at_css("td p.text-xs").text)
  end

  test "billing order page still sends the user's email (not name) to the payment widgets" do
    Commerce::CatalogBootstrap.call!
    original_env = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
                       PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET].to_h { |key| [ key, ENV[key] ] }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["PAYMENT_PROVIDER"] = "portone"
    ENV["PORTONE_API_SECRET"] = "test-api-secret"
    ENV["PORTONE_STORE_ID"] = "test-store-id"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel-key"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-portone-webhook-secret"
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)

    user = User.create!(name: "결제 유저", email: "billing-name-regression@example.com", password: "password123")
    order = Commerce::OrderCreator.call!(
      user: user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "portone"
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get billing_order_path(order.public_id)

    assert_response :success
    doc = Nokogiri::HTML(response.body)
    widget_script = doc.css("script").map(&:text).find { |text| text.include?("PortOne.requestPayment") }
    assert widget_script, "expected the PortOne payment widget script"
    assert_match(/customer: \{ email: "billing-name-regression@example\.com" \}/, widget_script)
    assert_no_match(/결제 유저/, widget_script)
  ensure
    original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "Chatdox presents fixed-term VAT-inclusive prices without a purchase path" do
    get chatdox_path

    assert_response :success
    assert_select "h1", text: /웹서비스 구축 패키지/
    assert_select "h2", text: /완전한 커리큘럼/
    assert_select "h2", text: /상품 구성/
    assert_select "h2", text: /기간별 이용 안내/
    assert_select "h2", text: /기술 스택/
    assert_select "h2", text: /자주 묻는 질문/
    assert_match(/7,700원/, response.body)
    assert_match(/23,100원/, response.body)
    assert_match(/41,580원/, response.body)
    assert_match(/73,920원/, response.body)
    assert_match(/VAT 포함/, response.body)
    assert_match(/자동 갱신 없는 기간제 선불 라이선스/, response.body)
    assert_match(/구매 준비 중/, response.body)
    assert_no_match(/9,900원|평생 접근|1년 무료 업데이트|7일 이내 100% 환불|언제든 취소|월 구독/, response.body)
    assert_no_match(/무료 체험|프리미엄형|오픈 알림/, response.body)
    assert_no_match(/선택형 운영 지원|커뮤니티 이용|라이브 오피스아워|코드리뷰 크레딧|아키텍처 클리닉/, response.body)
    assert_select "a[href=?]", docs_path, text: /커리큘럼 문서 보기/
    assert_select "a[href=?]", billing_checkout_path, count: 0
  end

  test "Claudox product page includes required structure and links into viewer" do
    get claudox_path

    assert_response :success
    assert_select "h1", text: /클로드가 들어온 날, 팀이 달라졌다/
    assert_match(/실제 구성과 목차/, response.body)
    assert_match(/포함 항목 \/ 미포함 항목/, response.body)
    assert_match(/FAQ/, response.body)
    assert_match(/구매 준비 중/, response.body)
    assert_no_match(/9,900원|평생 접근|1년 무료 업데이트|7일 이내 100% 환불/, response.body)
    assert_select "a[href=?]", claudox_read_path, text: /읽기 시작하기/
    assert_select "a[href=?]", claudox_chapter_path("01"), minimum: 1
    assert_select "a[href=?]", billing_checkout_path, count: 0
    assert_select "a[href=?]", billing_checkout_path("claudox"), count: 0
  end

  test "signed-in product pages also keep the legacy checkout link hidden" do
    user = User.create!(name: "테스트 유저", email: "policy-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    [ chatdox_path, claudox_path ].each do |path|
      get path
      assert_response :success
      assert_select "a[href=?]", billing_checkout_path, count: 0
    end
  end

  test "legacy checkout is a server-rendered inactive screen for guests and users" do
    assert_no_difference "PaymentTransaction.count" do
      get billing_checkout_path
    end

    assert_response :success
    assert_match(/신규 결제를 준비하고 있습니다/, response.body)
    assert_match(/결제나 결제 수단 등록을 시작할 수 없습니다/, response.body)
    assert_select "#pay-button", count: 0
    assert_select "script[src*='tosspayments']", count: 0
    assert_select "script[src*='portone']", count: 0

    user = User.create!(name: "테스트 유저", email: "checkout-blocked@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    assert_no_difference "PaymentTransaction.count" do
      get billing_checkout_path
    end
    assert_response :success
    assert_match(/신규 결제를 준비하고 있습니다/, response.body)
  end

  test "Claudox product page marks chapter completion accurately against source chapter files" do
    placeholder = ClaudoxProductsController::UNWRITTEN_PLACEHOLDER
    chapter_file = ->(id) { Dir.glob(ClaudoxProductsController::CLAUDOX_PATH.join("#{id}_*.md")).sort.first }
    written_count = (1..20).count { |n| (file = chapter_file.call(n.to_s.rjust(2, "0"))) && !File.read(file).include?(placeholder) }
    incomplete_id = (1..20).find { |n| (file = chapter_file.call(n.to_s.rjust(2, "0"))) && File.read(file).include?(placeholder) }

    get claudox_path

    assert_response :success
    assert_match(/완성\s*#{written_count}\s*\/\s*20/, response.body)
    assert_match(/CH\s*01.*?>완성</m, response.body)
    assert_match(/CH\s*#{incomplete_id.to_s.rjust(2, "0")}.*?>준비 중</m, response.body) if incomplete_id
  end

  test "Claudox chapter page does not duplicate the chapter title as a second heading in the body" do
    get claudox_chapter_path("01")

    assert_response :success
    doc = Nokogiri::HTML(response.body)
    doc_content = doc.at_css(".doc-content")
    assert doc_content, "expected a .doc-content section"
    assert_equal 0, doc_content.css("h1").size, "chapter body should not re-render the page's own <h1> title"
  end

  test "Claudox chapter page shows the last-updated timestamp in Korean date/time format" do
    get claudox_chapter_path("01")

    assert_response :success
    assert_match(/최종 업데이트: \d{4}년 \d{1,2}월 \d{1,2}일 \d{2}:\d{2}/, response.body)
  end

  test "Docs chapter page shows the last-updated timestamp in Korean, not the app's default English locale" do
    get doc_path("01")

    assert_response :success
    assert_match(/최종 업데이트: \d{4}년 \d{1,2}월 \d{1,2}일 \d{2}:\d{2}/, response.body)
    assert_no_match(/최종 업데이트: [A-Za-z]/, response.body)
  end

  test "Claudox chapter page has a back-to-list link outside the desktop-only sidebar" do
    get claudox_chapter_path("01")

    assert_response :success
    doc = Nokogiri::HTML(response.body)
    main_content = doc.at_css("main")
    back_link = main_content.at_css("a[href='#{claudox_read_path}']")
    assert back_link, "expected a back-to-list link inside <main>, visible on mobile"
    assert_equal "← 클로독스 목록", back_link.text.strip
  end

  test "Claudox index is a full chapter table of contents, not a single chapter's content" do
    get claudox_read_path

    assert_response :success
    assert_select "h1", text: "전체 목차"
    assert_match(/Part 1/, response.body)
    assert_match(/Part 2/, response.body)
    assert_match(/Part 3/, response.body)
    assert_select "a[href=?]", claudox_chapter_path("01"), minimum: 1
    assert_no_match(/Claude를 우리 팀에 합류시키려면/, response.body)
  end

  test "Claudox chapter grouping uses its own Part 1/2/3 structure, not Chatdox's Phase 1/2/3" do
    get claudox_read_path
    assert_response :success

    doc = Nokogiri::HTML(response.body)
    phase_list = doc.at_css("div.space-y-4")
    labels = phase_list.css("summary div.min-w-0 p.text-xs").map(&:text)
    assert_equal [ "Part 1", "Part 2", "Part 3", "부록" ], labels

    titles = phase_list.css("summary h2").map(&:text)
    assert_equal [ "입문", "중급", "고급", "특별판" ], titles

    assert_match(/관계 맺기와 기본 협업 규칙 — Claudox와 처음 만나 이름을 정하고, 작업 규칙과 기억 체계를 세우는 단계\./, response.body)
    assert_match(/실제 개발 워크플로우 — 폴더 구조부터 코드 리뷰, 테스트, Git\/PR까지 엔지니어링 작업을 함께 처리하는 단계\./, response.body)
    assert_match(/규모 확장과 메타적 자동화 — 서브에이전트와 워크플로우로 범위를 넓히고, 보안까지 챙기는 단계\./, response.body)

    part_1 = phase_list.css("details")[0]
    assert_match(/8\/8/, part_1.at_css(".text-right").text)
    chapter_titles_in_part_1 = part_1.css("span.font-medium").map(&:text)
    assert_equal 8, chapter_titles_in_part_1.size
    assert_equal "1. 클로독스와의 첫만남", chapter_titles_in_part_1.first
    assert_equal "8. 질문과 답변 — QNA로 지식 쌓기", chapter_titles_in_part_1.last
  end

  test "Chatdox docs index keeps its own Phase 1/2/3 grouping, unaffected by the Claudox model" do
    get docs_path

    assert_response :success
    assert_match(/Phase 1/, response.body)
    assert_match(/기초 &amp; 환경/, response.body)
    assert_match(/Phase 2/, response.body)
    assert_match(/핵심 기능 구현/, response.body)
    assert_match(/Phase 3/, response.body)
    assert_match(/프로덕션 운영/, response.body)
  end

  test "Claudox and existing core entry points remain reachable" do
    get claudox_path
    assert_response :success

    get claudox_read_path
    assert_response :success

    get claudox_chapter_path("01")
    assert_response :success

    get docs_path
    assert_response :success

    get new_user_session_path
    assert_response :success

    get dashboard_path
    assert_response :redirect

    get billing_checkout_path
    assert_response :success
    assert_match(/신규 결제를 준비하고 있습니다/, response.body)
  end

  test "Chatdox pricing banner only shows when sales are actually disabled" do
    get chatdox_path

    assert_response :success
    assert_match(/신규 결제 시스템을 준비 중이며 현재는 구매할 수 없습니다/, response.body)

    Commerce::CatalogBootstrap.call!
    original_env = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
                       PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET].to_h { |key| [ key, ENV[key] ] }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["PAYMENT_PROVIDER"] = "portone"
    ENV["PORTONE_API_SECRET"] = "test-api-secret"
    ENV["PORTONE_STORE_ID"] = "test-store-id"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel-key"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-portone-webhook-secret"
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)

    get chatdox_path

    assert_response :success
    assert_no_match(/신규 결제 시스템을 준비 중이며 현재는 구매할 수 없습니다/, response.body)
    assert_select "a[href=?]", billing_checkout_path, text: /기간제 라이선스 구매/
  ensure
    original_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "signed-in regular user's navigation includes a link back to /dashboard" do
    user = User.create!(name: "네비 유저", email: "nav-dashboard-user@example.com", password: "password123")
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get root_path

    assert_response :success
    assert_select "header nav[aria-label='주요 내비게이션'] a[href=?]", dashboard_path, text: "대시보드"
    assert_select "nav[aria-label='모바일 내비게이션'] a[href=?]", dashboard_path, text: "대시보드"
  end

  test "pending order in the commerce summary explains what 'pending' means" do
    Commerce::CatalogBootstrap.call!
    original_env = %w[LEEDOX_COMMERCE_ENABLED PAYMENT_PROVIDER
                       PORTONE_API_SECRET PORTONE_STORE_ID PORTONE_CHANNEL_KEY PORTONE_WEBHOOK_SECRET].to_h { |key| [ key, ENV[key] ] }
    ENV["LEEDOX_COMMERCE_ENABLED"] = "true"
    ENV["PAYMENT_PROVIDER"] = "portone"
    ENV["PORTONE_API_SECRET"] = "test-api-secret"
    ENV["PORTONE_STORE_ID"] = "test-store-id"
    ENV["PORTONE_CHANNEL_KEY"] = "test-channel-key"
    ENV["PORTONE_WEBHOOK_SECRET"] = "test-portone-webhook-secret"
    Product.find_by!(code: "chatdox").update!(sale_enabled: true)

    user = User.create!(name: "대기 유저", email: "pending-order-user@example.com", password: "password123")
    Commerce::OrderCreator.call!(
      user: user,
      product_code: "chatdox",
      offer_code: "chatdox-1m-v1",
      requested_start_on: Time.current.in_time_zone(Commerce::PeriodCalculator::KST).to_date,
      provider: "portone"
    )
    post user_session_path, params: { user: { email: user.email, password: "password123" } }

    get mypage_path

    assert_response :success
    assert_select "span", text: "결제 대기"
    assert_match(/결제가 완료되지 않은 주문입니다/, response.body)
  ensure
    original_env&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "service desk ticket and job detail pages show the author's name, not their email" do
    admin = User.create!(name: "이름표시 관리자", email: "sd-name-display@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    post service_desk_path, params: { service_desk_request: { subject: "Name display ticket", visibility: "visible", description: "body" } }
    created = ServiceDeskRequest.order(:request_number).last
    post service_desk_request_jobs_path(created), params: { service_desk_job: { content: "Name display job" } }

    get service_desk_request_path(created)

    assert_response :success
    assert_match(/이름표시 관리자/, response.body)
    assert_no_match(/sd-name-display@example\.com/, response.body)
  end

  test "service desk dates render as YYYY.MM.DD while other pages keep their existing date format" do
    request = ServiceDeskRequest.create!(request_number: 5020, requester: "Tester", subject: "Date format check", visibility: :visible)
    admin = User.create!(name: "테스트 유저", email: "sd-admin-dateformat@example.com", password: "password123", role: :admin)
    post user_session_path, params: { user: { email: admin.email, password: "password123" } }

    get service_desk_path
    assert_response :success
    assert_match(/#{Regexp.escape(I18n.l(request.date, format: :service_desk))}/, response.body)
    assert_no_match(/#{Regexp.escape(I18n.l(request.date, format: :long))}/, response.body)

    get service_desk_request_path(request)
    assert_response :success
    assert_match(/#{Regexp.escape(I18n.l(request.date, format: :service_desk))}/, response.body)

    get claudox_chapter_path("01")
    assert_response :success
    assert_no_match(/\d{4}\.\d{2}\.\d{2}/, response.body)
  end
end
