class AddAdsbxchangeapikeytosettings < ActiveRecord::Migration[6.0]
  def change
    add_column :settings, :adsbx_api_key, :string
  end
end
