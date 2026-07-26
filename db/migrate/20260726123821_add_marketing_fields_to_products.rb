class AddMarketingFieldsToProducts < ActiveRecord::Migration[8.1]
  # Local, migration-scoped model -- deliberately not the real Product class,
  # so this backfill keeps working even if app/models/product.rb changes
  # shape later.
  class Product < ActiveRecord::Base
    self.table_name = "products"
  end

  TAGLINES = {
    "chatdox" => "AI와 함께 SaaS를 기획부터 배포까지 직접 만들어보는 실전 커리큘럼",
    "claudox" => "Claude를 팀에 합류시켜 실제로 협업한 기록을 그대로 따라가는 콘텐츠"
  }.freeze

  LANDING_PAGE_PATHS = {
    "chatdox" => "/chatdox",
    "claudox" => "/claudox"
  }.freeze

  def up
    add_column :products, :tagline, :string
    add_column :products, :landing_page_path, :string

    Product.reset_column_information
    TAGLINES.each do |code, tagline|
      Product.where(code: code).update_all(tagline: tagline, landing_page_path: LANDING_PAGE_PATHS.fetch(code))
    end
  end

  def down
    remove_column :products, :landing_page_path
    remove_column :products, :tagline
  end
end
