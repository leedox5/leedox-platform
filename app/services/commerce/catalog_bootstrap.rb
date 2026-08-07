module Commerce
  class CatalogBootstrap
    PRODUCTS = {
      "chatdox" => {
        name: "Chatdox",
        tagline: "AI와 함께 SaaS를 기획부터 배포까지 직접 만들어보는 실전 커리큘럼",
        landing_page_path: "/chatdox",
        theme: "blue",
        display_order: 2
      },
      "claudox" => {
        name: "Claudox",
        tagline: "Claude를 팀에 합류시켜 실제로 협업한 기록을 그대로 따라가는 콘텐츠",
        landing_page_path: "/claudox",
        theme: "violet",
        display_order: 3
      },
      # Free content available in full after login (see
      # hq/aistart/content_meta.yml -- guest/trial limits both cover all 5
      # chapters, while ProductContentController requires an account for
      # free_access products). Not for sale: no
      # ProductOffer entries below. sale_enabled stays false like every other
      # product's initial state here, and must stay false permanently for
      # this one specifically -- flipping it on would expose a checkout page
      # with zero offers to choose from, since Commerce::Sales.enabled_for?
      # only checks active/sale_enabled, not offer existence. free_access:
      # true is what actually tells /pricing and the dashboard this is a
      # permanently-free product, not a not-yet-launched paid one (see
      # leedox_aistart_free_product_visibility_r1).
      "aistart" => {
        name: "AI, 오늘부터 시작",
        tagline: nil,
        landing_page_path: "/content/aistart",
        free_access: true,
        theme: "teal",
        display_order: 1
      },
      "aigravity" => {
        name: "Antigravity 개발 실전",
        tagline: "15년 차 베테랑의 AI 에이전트 무중력 코딩 실전 가이드",
        landing_page_path: "/aigravity",
        theme: "emerald",
        display_order: 4
      }
    }.freeze
    CHATDOX_OFFERS = [
      { code: "chatdox-1m-v1", version: 1, duration_months: 1,
        supply_amount: 7_000, vat_amount: 700, total_amount: 7_700, discount_bps: 0 },
      { code: "chatdox-3m-v1", version: 1, duration_months: 3,
        supply_amount: 21_000, vat_amount: 2_100, total_amount: 23_100, discount_bps: 0 },
      { code: "chatdox-6m-v1", version: 1, duration_months: 6,
        supply_amount: 37_800, vat_amount: 3_780, total_amount: 41_580, discount_bps: 1_000 },
      { code: "chatdox-12m-v1", version: 1, duration_months: 12,
        supply_amount: 67_200, vat_amount: 6_720, total_amount: 73_920, discount_bps: 2_000 }
    ].freeze
    # Exactly 50% of the matching CHATDOX_OFFERS amounts; discount_bps tiers unchanged.
    CLAUDOX_OFFERS = [
      { code: "claudox-1m-v1", version: 1, duration_months: 1,
        supply_amount: 3_500, vat_amount: 350, total_amount: 3_850, discount_bps: 0 },
      { code: "claudox-3m-v1", version: 1, duration_months: 3,
        supply_amount: 10_500, vat_amount: 1_050, total_amount: 11_550, discount_bps: 0 },
      { code: "claudox-6m-v1", version: 1, duration_months: 6,
        supply_amount: 18_900, vat_amount: 1_890, total_amount: 20_790, discount_bps: 1_000 },
      { code: "claudox-12m-v1", version: 1, duration_months: 12,
        supply_amount: 33_600, vat_amount: 3_360, total_amount: 36_960, discount_bps: 2_000 }
    ].freeze

    def self.call!
      ApplicationRecord.transaction do
        products = PRODUCTS.to_h do |code, attributes|
          product = Product.find_or_create_by!(code: code) do |record|
            record.name = attributes.fetch(:name)
            record.active = true
            record.sale_enabled = false
            record.tagline = attributes.fetch(:tagline)
            record.landing_page_path = attributes.fetch(:landing_page_path)
          end
          product.update!(
            landing_page_path: attributes.fetch(:landing_page_path),
            free_access: attributes.fetch(:free_access, false)
          )
          [ code, product ]
        end

        CHATDOX_OFFERS.each do |attributes|
          ProductOffer.find_or_create_by!(code: attributes.fetch(:code)) do |offer|
            offer.assign_attributes(
              attributes.merge(product: products.fetch("chatdox"), currency: "KRW", active: true)
            )
          end
        end

        CLAUDOX_OFFERS.each do |attributes|
          ProductOffer.find_or_create_by!(code: attributes.fetch(:code)) do |offer|
            offer.assign_attributes(
              attributes.merge(product: products.fetch("claudox"), currency: "KRW", active: true)
            )
          end
        end

        products
      end
    end
  end
end
