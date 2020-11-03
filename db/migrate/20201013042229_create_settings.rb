class CreateSettings < ActiveRecord::Migration[6.0]
  def change
    create_table :settings do |t|
      t.integer :airport_id
      t.boolean :use_1090dump
      t.string :ip_1090dump
      t.integer :port_1090dump
      t.string :adsbx_api_key
      t.datetime :updated_at
    end
  end
end
