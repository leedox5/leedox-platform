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
  get "/aigravity", to: "pages#aigravity", as: :aigravity

  # Customer URLs for a ProductLine and its Episodes (handoff 0056 R3; the
  # Season level was removed in 0065). Kept separate from /content/:product_code/...
  # (the file-based products' and legacy ContentBundle's namespace).
  # Handoff 0068 -- the list, linked from the header. Doesn't collide with the
  # :product_slug route below: that one always needs a second path segment, this
  # one never has one.
  get "/products", to: "product_lines#index", as: :products
  get "/products/:product_slug", to: "product_lines#show", as: :product_line
  # Handoff 0056 R5 -- ProductLine cover image variants (hero/thumb). A separate
  # top-level path on purpose: under /products/:slug/... a segment named
  # "cover" would collide with episode ids.
  get "/product-covers/:product_slug/:variant", to: "product_covers#show", as: :product_cover
  # Handoff 0063 -- inline images of an introduction or an episode body, looked
  # up by their random public id. Top-level for the same reason as the covers.
  get "/product-images/:public_id", to: "product_images#show", as: :product_image
  # Episode ids are numbers ("00", "01", ..., see ContentEpisode#display_id); the
  # constraint is what keeps them apart from the old Season slugs below.
  get "/products/:product_slug/:episode_id", to: "product_lines#episode", as: :product_episode, constraints: { episode_id: /\d+/ }
  get "/products/:product_slug/:episode_id/assets/:asset_id", to: "product_asset_downloads#show", as: :product_episode_asset, constraints: { episode_id: /\d+/ }
  # Handoff 0065 (D5) -- the old Season URLs: /products/:line/:season[/:episode[/assets/:asset]]
  # redirect permanently to the product that Season became.
  get "/products/:product_slug/:season_slug", to: "legacy_season_redirects#show", as: :legacy_product_season
  get "/products/:product_slug/:season_slug/:episode_id", to: "legacy_season_redirects#show", as: :legacy_product_season_episode
  get "/products/:product_slug/:season_slug/:episode_id/assets/:asset_id", to: "legacy_season_redirects#show", as: :legacy_product_season_episode_asset

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
  # Handoff 0055 -- DB-backed products only. Segment count alone disambiguates
  # from the 2-segment route above (a 3-segment URL never matches it), so
  # there's no routing ambiguity even though both point at #show -- see
  # result.md §3 and ProductContentController#show's source-class branch.
  get "/content/:product_code/:bundle_slug/:episode_id", to: "product_content#show", as: :product_bundle_episode
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

  get "/admin/products", to: redirect("/admin/commerce/products")
  get "/admin/payment-docs", to: redirect("/refs"), as: :admin_payment_docs
  get "/admin/payment-docs/:section", to: redirect("/refs/payment-%{section}"), as: :admin_payment_docs_section

  namespace :admin do
    get "/dashboard", to: "dashboard#show", as: :dashboard
    get "/content_progress", to: "content_progress#show", as: :content_progress
    post "/db_backup", to: "db_backup#download", as: :db_backup
    resources :users, only: %i[index update] do
      post :grant_free_license, on: :member
    end
    # Handoff 0053 R3 -- minimal admin authoring UI for DB-backed content
    # bundles/episodes/takeaways. `shallow: true` keeps new/create nested
    # under the bundle (an episode needs its bundle_id to be created) while
    # edit/update/show/custom member routes drop the bundle_id prefix once
    # the episode itself has an id.
    resources :content_bundles, only: %i[index new create edit update] do
      resources :content_episodes, only: %i[new create edit update show destroy], shallow: true do
        member do
          patch :transition
          patch :publish
          patch :unpublish
        end
        resources :content_takeaways, only: %i[new create edit update], shallow: true
        # Handoff 0056 R4 -- downloadable files, managed only for Season
        # episodes (Admin::ContentAssetsController rejects Bundle episodes).
        resources :content_assets, only: %i[new create edit update destroy], shallow: true do
          get :download, on: :member, controller: "content_asset_downloads", action: :show
        end
      end
    end
    # The single entry point for new products: ProductLine -> Episode (handoff
    # 0056 R3; the Season level was removed in 0065). Episodes reuse the shallow
    # content_episodes routes above for edit/update/show/destroy/transition/
    # takeaways (they don't care which kind of parent an episode has); only
    # new/create need their own nesting under a product.
    resources :product_lines, only: %i[index show new create edit update] do
      resources :content_episodes, only: %i[new create], shallow: true
      # Handoff 0057/0065 -- one-time price and sale switch for the product.
      resource :sale, only: %i[update], controller: "product_line_sales" do
        patch :start
        patch :stop
      end
    end
    # Handoff 0063 -- inline images (introduction / episode body) and the Markdown preview.
    post "product_lines/:product_line_id/content_images", to: "content_images#create", as: :product_line_content_images
    post "content_episodes/:content_episode_id/content_images", to: "content_images#create", as: :content_episode_content_images
    get "content_images/:public_id/:variant", to: "content_images#file", as: :content_image_file, constraints: { variant: /body|thumb/ }
    patch "content_images/:public_id", to: "content_images#update", as: :content_image
    delete "content_images/:public_id", to: "content_images#destroy"
    post "markdown_preview", to: "markdown_previews#create", as: :markdown_preview
    get "product_lines/:product_line_id/cover/:variant", to: "product_line_covers#show", as: :product_line_cover_image
    delete "product_lines/:product_line_id/cover", to: "product_line_covers#destroy", as: :product_line_cover
    namespace :commerce do
      resources :orders, only: %i[index show], param: :id do
        post :abandon, on: :member
        post :confirm_manual_payment, on: :member
      end
      resources :refund_requests, only: %i[index show update], param: :id
      resources :products, only: %i[index edit update]
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
  post "/billing/free_access/:product_code", to: "free_access_claims#create", as: :claim_free_access
  get "/billing/orders/:id", to: "billing_orders#show", as: :billing_order
  get "/billing/orders/:id/retry", to: "billing_orders#retry_preview", as: :retry_billing_order
  post "/billing/orders/:id/retry", to: "billing_orders#retry", as: :create_retry_billing_order
  get "/billing/orders/:id/refund_request/new", to: "refund_requests#new", as: :new_billing_order_refund_request
  post "/billing/orders/:id/refund_requests", to: "refund_requests#create", as: :billing_order_refund_requests
  get "/refund_requests/:id", to: "refund_requests#show", as: :refund_request

  resources :premium_waitlists, only: :create
  post "/webhooks/portone", to: "webhooks/portone#receive"
end
