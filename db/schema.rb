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

ActiveRecord::Schema[8.1].define(version: 2026_08_07_052212) do
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
    t.index ["user_id", "product_id", "starts_on"], name: "index_licenses_on_user_product_start", unique: true
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

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.boolean "free_access", default: false, null: false
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

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.integer "channel_hash", limit: 8, null: false
    t.datetime "created_at", null: false
    t.binary "payload", limit: 536870912, null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", limit: 4, null: false
    t.datetime "created_at", null: false
    t.binary "key", limit: 1024, null: false
    t.integer "key_hash", limit: 8, null: false
    t.binary "value", limit: 536870912, null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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

  add_foreign_key "chapter_progresses", "users"
  add_foreign_key "commerce_audit_events", "users", column: "actor_id"
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
  add_foreign_key "refund_requests", "orders"
  add_foreign_key "refund_requests", "users"
  add_foreign_key "refund_requests", "users", column: "processed_by_id"
  add_foreign_key "service_desk_jobs", "service_desk_requests"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
