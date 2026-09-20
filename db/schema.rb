# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_20_110000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "chapter_progresses", force: :cascade do |t|
    t.string "chapter_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "product_code", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "chapter_id", "product_code"], name: "idx_on_user_id_chapter_id_product_code_a1d40a0cbd", unique: true
    t.index ["user_id"], name: "index_chapter_progresses_on_user_id"
  end

  create_table "commerce_audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.integer "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.string "from_state"
    t.datetime "occurred_at", null: false
    t.string "reason_code"
    t.string "to_state"
    t.datetime "updated_at", null: false
    t.index ["action", "occurred_at"], name: "index_commerce_audit_events_on_action_and_occurred_at"
    t.index ["actor_id"], name: "index_commerce_audit_events_on_actor_id"
    t.index ["auditable_type", "auditable_id", "occurred_at"], name: "index_commerce_audits_on_target_and_time"
  end

  create_table "content_assets", force: :cascade do |t|
    t.integer "content_episode_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["content_episode_id", "position"], name: "index_content_assets_on_content_episode_id_and_position", unique: true
    t.index ["content_episode_id"], name: "index_content_assets_on_content_episode_id"
  end

  create_table "content_bundles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_title"
    t.string "internal_name", null: false
    t.integer "owner_id"
    t.integer "position", default: 0, null: false
    t.integer "product_id"
    t.string "slug"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["owner_id"], name: "index_content_bundles_on_owner_id"
    t.index ["product_id", "slug"], name: "index_content_bundles_on_product_id_and_slug", unique: true
    t.index ["product_id"], name: "index_content_bundles_on_product_id"
  end

  create_table "content_episodes", force: :cascade do |t|
    t.integer "author_id"
    t.text "body"
    t.integer "bundle_id"
    t.datetime "created_at", null: false
    t.string "customer_title"
    t.string "internal_ref"
    t.integer "lock_version", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.integer "product_season_id"
    t.datetime "published_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_content_episodes_on_author_id"
    t.index ["bundle_id", "position"], name: "index_content_episodes_on_bundle_id_and_position"
    t.index ["bundle_id"], name: "index_content_episodes_on_bundle_id"
    t.index ["product_season_id", "position"], name: "index_content_episodes_on_season_and_position", unique: true
    t.index ["product_season_id"], name: "index_content_episodes_on_product_season_id"
    t.check_constraint "(bundle_id IS NOT NULL AND product_season_id IS NULL) OR (bundle_id IS NULL AND product_season_id IS NOT NULL)", name: "content_episodes_exactly_one_parent"
  end

  create_table "content_revisions", force: :cascade do |t|
    t.text "body_snapshot"
    t.datetime "created_at", null: false
    t.integer "editor_id"
    t.integer "episode_id", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["editor_id"], name: "index_content_revisions_on_editor_id"
    t.index ["episode_id"], name: "index_content_revisions_on_episode_id"
  end

  create_table "content_takeaways", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "episode_id", null: false
    t.string "kind", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["episode_id", "position"], name: "index_content_takeaways_on_episode_id_and_position"
    t.index ["episode_id"], name: "index_content_takeaways_on_episode_id"
  end

  create_table "external_account_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "invited_at"
    t.string "normalized_username", null: false
    t.string "provider", default: "github", null: false
    t.string "public_id", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "username", null: false
    t.index ["public_id"], name: "index_external_account_links_on_public_id", unique: true
    t.index ["user_id"], name: "index_external_account_links_on_user_id", unique: true
  end

  create_table "licenses", force: :cascade do |t|
    t.datetime "access_ends_at", null: false
    t.datetime "created_at", null: false
    t.date "last_usable_on", null: false
    t.integer "order_item_id"
    t.integer "product_id", null: false
    t.string "source", default: "paid", null: false
    t.date "starts_on", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_item_id"], name: "index_licenses_on_order_item_id", unique: true
    t.index ["product_id"], name: "index_licenses_on_product_id"
    t.index ["user_id", "product_id", "access_ends_at"], name: "index_licenses_on_user_product_access_end"
    t.index ["user_id", "product_id", "starts_on"], name: "index_licenses_on_user_product_start", unique: true, where: "status != 'canceled'"
    t.index ["user_id"], name: "index_licenses_on_user_id"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "KRW", null: false
    t.integer "discount_bps", default: 0, null: false
    t.integer "duration_months", null: false
    t.string "offer_code", null: false
    t.integer "offer_version", null: false
    t.integer "order_id", null: false
    t.string "product_code", null: false
    t.integer "product_id", null: false
    t.string "product_name", null: false
    t.integer "product_offer_id", null: false
    t.integer "supply_amount", null: false
    t.integer "total_amount", null: false
    t.datetime "updated_at", null: false
    t.integer "vat_amount", null: false
    t.index ["order_id", "product_id"], name: "index_order_items_on_order_id_and_product_id", unique: true
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
    t.index ["product_offer_id"], name: "index_order_items_on_product_offer_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "abandoned_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "KRW", null: false
    t.datetime "finalized_at"
    t.datetime "last_provider_event_at"
    t.datetime "paid_at"
    t.datetime "payment_requested_at", null: false
    t.string "provider", null: false
    t.string "public_id", null: false
    t.date "requested_start_on", null: false
    t.integer "retry_of_order_id"
    t.string "status", default: "pending", null: false
    t.integer "supply_amount", null: false
    t.integer "total_amount", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "vat_amount", null: false
    t.index ["public_id"], name: "index_orders_on_public_id", unique: true
    t.index ["retry_of_order_id"], name: "index_orders_on_retry_of_order_id", unique: true
    t.index ["status", "payment_requested_at"], name: "index_orders_on_status_and_payment_requested_at"
    t.index ["user_id", "status"], name: "index_orders_on_user_id_and_status"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "payment_transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "KRW", null: false
    t.string "order_id", null: false
    t.string "provider", null: false
    t.datetime "provider_observed_at"
    t.json "provider_payload"
    t.string "provider_payment_id", null: false
    t.string "provider_status"
    t.integer "purchase_order_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payment_transactions_on_order_id", unique: true
    t.index ["provider", "provider_payment_id"], name: "index_payment_transactions_on_provider_and_provider_payment_id", unique: true
    t.index ["purchase_order_id"], name: "index_payment_transactions_on_purchase_order_id", unique: true
  end

  create_table "premium_waitlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "source", default: "landing_pricing", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_premium_waitlists_on_email", unique: true
  end

  create_table "product_lines", force: :cascade do |t|
    t.string "ai_supporter"
    t.string "cover_image_alt"
    t.datetime "created_at", null: false
    t.string "customer_name", null: false
    t.text "expected_result", null: false
    t.string "internal_name", null: false
    t.text "problem", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.text "target_audience", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_product_lines_on_slug", unique: true
  end

  create_table "product_offers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "available_from"
    t.datetime "available_until"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "KRW", null: false
    t.integer "discount_bps", default: 0, null: false
    t.integer "duration_months", null: false
    t.integer "product_id", null: false
    t.integer "supply_amount", null: false
    t.integer "total_amount", null: false
    t.datetime "updated_at", null: false
    t.integer "vat_amount", null: false
    t.integer "version", null: false
    t.index ["code"], name: "index_product_offers_on_code", unique: true
    t.index ["product_id", "duration_months", "version"], name: "index_product_offers_on_product_duration_version", unique: true
    t.index ["product_id"], name: "index_product_offers_on_product_id"
  end

  create_table "product_seasons", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_title"
    t.string "internal_name", null: false
    t.integer "position", default: 0, null: false
    t.integer "product_line_id", null: false
    t.string "season_code", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["product_line_id", "season_code"], name: "index_product_seasons_on_product_line_id_and_season_code", unique: true
    t.index ["product_line_id", "slug"], name: "index_product_seasons_on_product_line_id_and_slug", unique: true
    t.index ["product_line_id"], name: "index_product_seasons_on_product_line_id"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "free_access", default: false, null: false
    t.integer "guest_chapter_limit"
    t.string "landing_page_path"
    t.string "name", null: false
    t.boolean "sale_enabled", default: false, null: false
    t.string "tagline"
    t.integer "trial_chapter_limit"
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_products_on_code", unique: true
  end

  create_table "refund_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "customer_note"
    t.datetime "decided_at"
    t.datetime "external_processed_at"
    t.boolean "external_refund_confirmed", default: false, null: false
    t.boolean "full_request", default: true, null: false
    t.text "internal_note"
    t.integer "order_id", null: false
    t.integer "processed_by_id"
    t.datetime "processing_started_at"
    t.string "provider_refund_status", default: "not_requested", null: false
    t.string "public_id", null: false
    t.text "public_response"
    t.string "reason_code", null: false
    t.integer "requested_amount", null: false
    t.datetime "reviewed_at"
    t.string "status", default: "requested", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id", "status"], name: "index_refund_requests_on_order_id_and_status"
    t.index ["order_id"], name: "index_refund_requests_on_one_open_per_order", unique: true, where: "status IN ('requested','reviewing','approved','processing')"
    t.index ["order_id"], name: "index_refund_requests_on_order_id"
    t.index ["processed_by_id"], name: "index_refund_requests_on_processed_by_id"
    t.index ["public_id"], name: "index_refund_requests_on_public_id", unique: true
    t.index ["user_id"], name: "index_refund_requests_on_user_id"
  end

  create_table "service_desk_jobs", force: :cascade do |t|
    t.string "author", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "job_number", null: false
    t.datetime "performed_at", null: false
    t.integer "service_desk_request_id", null: false
    t.datetime "updated_at", null: false
    t.index ["service_desk_request_id", "job_number"], name: "idx_on_service_desk_request_id_job_number_b8b84ea463", unique: true
    t.index ["service_desk_request_id"], name: "index_service_desk_jobs_on_service_desk_request_id"
  end

  create_table "service_desk_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "description"
    t.integer "request_number", null: false
    t.string "requester", null: false
    t.integer "status", default: 0, null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.integer "visibility", default: 0, null: false
    t.index ["request_number"], name: "index_service_desk_requests_on_request_number", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chapter_progresses", "users"
  add_foreign_key "commerce_audit_events", "users", column: "actor_id"
  add_foreign_key "content_assets", "content_episodes"
  add_foreign_key "content_bundles", "products"
  add_foreign_key "content_bundles", "users", column: "owner_id"
  add_foreign_key "content_episodes", "content_bundles", column: "bundle_id"
  add_foreign_key "content_episodes", "product_seasons"
  add_foreign_key "content_episodes", "users", column: "author_id"
  add_foreign_key "content_revisions", "content_episodes", column: "episode_id"
  add_foreign_key "content_revisions", "users", column: "editor_id"
  add_foreign_key "content_takeaways", "content_episodes", column: "episode_id"
  add_foreign_key "external_account_links", "users"
  add_foreign_key "licenses", "order_items"
  add_foreign_key "licenses", "products"
  add_foreign_key "licenses", "users"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "product_offers"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "orders", column: "retry_of_order_id"
  add_foreign_key "orders", "users"
  add_foreign_key "payment_transactions", "orders", column: "purchase_order_id"
  add_foreign_key "product_offers", "products"
  add_foreign_key "product_seasons", "product_lines"
  add_foreign_key "refund_requests", "orders"
  add_foreign_key "refund_requests", "users"
  add_foreign_key "refund_requests", "users", column: "processed_by_id"
  add_foreign_key "service_desk_jobs", "service_desk_requests"
end
