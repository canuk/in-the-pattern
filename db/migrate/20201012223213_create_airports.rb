class CreateAirports < ActiveRecord::Migration[6.0]
  def change
    create_table :airports do |t|
      t.string :name
      t.string :identifier
      t.float :lat
      t.float :lng
      t.string :overhead
      t.string :upwind
      t.string :crosswind
      t.string :downwind
      t.string :base
      t.string :final
      t.integer :approach_rwy
      t.integer :departure_rwy
      t.datetime :created_at
      t.datetime :updated_at
    end
  end
end
