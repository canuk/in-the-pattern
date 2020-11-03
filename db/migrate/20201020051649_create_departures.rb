class CreateDepartures < ActiveRecord::Migration[6.0]
  def change
    create_table :departures do |t|
      t.integer :airport_id
      t.string :tail_number
      t.string :aircraft_type
      t.datetime :departed_at
    end    
  end
end