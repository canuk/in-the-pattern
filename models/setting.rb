class Setting < ActiveRecord::Base
  validates_presence_of :airport_id
end