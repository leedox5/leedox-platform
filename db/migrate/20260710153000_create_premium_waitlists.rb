class CreatePremiumWaitlists < ActiveRecord::Migration[8.1]
  def change
    create_table :premium_waitlists do |t|
      t.string :email, null: false
      t.string :source, null: false, default: "landing_pricing"

      t.timestamps
    end

    add_index :premium_waitlists, :email, unique: true
  end
end
