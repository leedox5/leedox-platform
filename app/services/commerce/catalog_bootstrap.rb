module Commerce
  class CatalogBootstrap
    PRODUCTS = {
      "chatdox" => {
        name: "Chatdox",
        tagline: "AI와 함께 SaaS를 기획부터 배포까지 직접 만들어보는 실전 커리큘럼",
        landing_page_path: "/chatdox"
      },
      "claudox" => {
        name: "Claudox",
        tagline: "Claude를 팀에 합류시켜 실제로 협업한 기록을 그대로 따라가는 콘텐츠",
        landing_page_path: "/claudox"
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
