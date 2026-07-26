Rails.application.routes.draw do
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "pages#home"

  get "/chatdox", to: "pages#chatdox", as: :chatdox

  # Legacy per-product URLs and route helper names, kept exactly as they were
  # (bookmarks/external links/SEO) -- product_code comes in via `defaults:`
  # instead of the path, so both route to the single ProductContentController.
  # See docs/internal/content_platform_design.md section B.
  get "/docs", to: "product_content#index", defaults: { product_code: "chatdox" }, as: :docs
  get "/docs/images/*filename", to: "product_content#image", defaults: { product_code: "chatdox" }, as: :doc_image, format: false
  get "/docs/:id", to: "product_content#show", defaults: { product_code: "chatdox" }, as: :doc
  get "/claudox", to: "claudox_products#show", as: :claudox
  get "/claudox/read", to: "product_content#index", defaults: { product_code: "claudox" }, as: :claudox_read
  get "/claudox/images/*filename", to: "product_content#image", defaults: { product_code: "claudox" }, as: :claudox_image, format: false
  get "/claudox/read/:id", to: "product_content#show", defaults: { product_code: "claudox" }, as: :claudox_chapter

  # Generic pattern any future product is automatically covered by -- no new
  # route needed just to register a 3rd+ product (see ProductContent.for).
  get "/content/:product_code", to: "product_content#index", as: :product_content_index
  get "/content/:product_code/images/*filename", to: "product_content#image", as: :product_content_image, format: false
  get "/content/:product_code/:id", to: "product_content#show", as: :product_chapter
  get "/service-desk", to: "service_desk#index", as: :service_desk
  get "/service-desk/new", to: "service_desk#new", as: :new_service_desk_request
  post "/service-desk", to: "service_desk#create"
  post "/service-desk/export", to: "service_desk#export", as: :service_desk_export
  get "/service-desk/requests/:id", to: "service_desk#show", as: :service_desk_request
  get "/service-desk/requests/:id/edit", to: "service_desk#edit", as: :edit_service_desk_request
  patch "/service-desk/requests/:id", to: "service_desk#update"
  post "/service-desk/requests/:id/jobs", to: "service_desk_jobs#create", as: :service_desk_request_jobs
  get "/service-desk/requests/:id/jobs/:job_id/edit", to: "service_desk_jobs#edit", as: :edit_service_desk_request_job
  patch "/service-desk/requests/:id/jobs/:job_id", to: "service_desk_jobs#update", as: :service_desk_request_job

  post "/service-desk/api/requests", to: "service_desk/api/requests#create", as: :service_desk_api_requests
  get "/service-desk/api/requests", to: "service_desk/api/requests#index"
  get "/service-desk/api/requests/:id", to: "service_desk/api/requests#show", as: :service_desk_api_request
  post "/service-desk/api/requests/:request_id/jobs", to: "service_desk/api/jobs#create", as: :service_desk_api_request_jobs
  get "/dashboard", to: "dashboard#show"
  get "/mypage", to: "mypage#show", as: :mypage
  resources :chapter_progresses, only: :create
  delete "/chapter_progresses", to: "chapter_progresses#destroy"

  get "/getting-started", to: "pages#getting_started"
  get "/pricing", to: "pages#pricing"
  get "/community", to: "pages#community"
  get "/login", to: "pages#login"
  get "/terms", to: "pages#terms"
  get "/privacy", to: "pages#privacy"

  get "/refs", to: "refs#index", as: :refs
  get "/refs/:id", to: "refs#show", as: :ref

  get "/admin/payment-docs", to: redirect("/refs"), as: :admin_payment_docs
  get "/admin/payment-docs/:section", to: redirect("/refs/payment-%{section}"), as: :admin_payment_docs_section

  namespace :admin do
    get "/dashboard", to: "dashboard#show", as: :dashboard
    get "/content_progress", to: "content_progress#show", as: :content_progress
    post "/db_backup", to: "db_backup#download", as: :db_backup
    resources :users, only: %i[index update]
    namespace :commerce do
      resources :orders, only: %i[index show], param: :id do
        post :abandon, on: :member
        post :confirm_manual_payment, on: :member
      end
      resources :refund_requests, only: %i[show update], param: :id
      resources :products, only: %i[index update]
      get "/github_access", to: "github_access#index", as: :github_access
      patch "/github_access/:id/invite", to: "github_access#invite", as: :invite_github_access
      patch "/github_access/:id/revoke", to: "github_access#revoke", as: :revoke_github_access
    end
  end

  resource :github_access, only: %i[show create], controller: :github_access

  get  "/billing/checkout(/:product_code)", to: "billing#checkout", as: :billing_checkout
  get  "/billing/success",  to: "billing#success",   as: :billing_success
  post "/billing/success",  to: "billing#success"
  get  "/billing/cancel",   to: "billing#cancel",    as: :billing_cancel
  post "/billing/orders", to: "billing_orders#create", as: :billing_orders
  get "/billing/orders/:id", to: "billing_orders#show", as: :billing_order
  get "/billing/orders/:id/retry", to: "billing_orders#retry_preview", as: :retry_billing_order
  post "/billing/orders/:id/retry", to: "billing_orders#retry", as: :create_retry_billing_order
  get "/billing/orders/:id/refund_request/new", to: "refund_requests#new", as: :new_billing_order_refund_request
  post "/billing/orders/:id/refund_requests", to: "refund_requests#create", as: :billing_order_refund_requests
  get "/refund_requests/:id", to: "refund_requests#show", as: :refund_request

  resources :premium_waitlists, only: :create
  post "/webhooks/portone", to: "webhooks/portone#receive"
end
