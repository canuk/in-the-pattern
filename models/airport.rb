class Airport < ActiveRecord::Base
  validates_presence_of :name, :identifier, :approach_rwy, :departure_rwy
  
  has_many :arrivals
  has_many :departures

end
