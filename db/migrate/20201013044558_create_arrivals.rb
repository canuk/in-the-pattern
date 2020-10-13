class CreateArrivals < ActiveRecord::Migration[6.0]
  def change
    create_table :arrivals do |t|
      t.integer :airport_id
      t.string :tail_number
      t.string :aircraft_type
      t.datetime :arrived_at
    end    
  end
end
