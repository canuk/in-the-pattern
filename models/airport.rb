class Airport < ActiveRecord::Base
  validates_presence_of :name, :identifier, :lat, :lng, :overhead, :upwind, :crosswind, :downwind, :base, :final, :approach_rwy, :departure_rwy
end