require 'sinatra/base'
require "sinatra/activerecord"

require_relative "models/airport.rb"
require_relative "models/arrival.rb"
require_relative "models/setting.rb"

module InThePattern
  class App < Sinatra::Base
    register Sinatra::ActiveRecordExtension
    
    set :database, {adapter: "sqlite3", database: "itp.sqlite3"}
    
    get "/" do
      erb :"index.html"
    end
    
    get "/arrivals" do
      @settings = Setting.first
      @airport = Airport.find(@settings.airport_id)
      @arrivals = Arrival.order(arrived_at: :desc).limit(5)
      erb :"arrivals.html"
    end

    get "/assets/js/application.js" do
      content_type :js
      @scheme = ENV['RACK_ENV'] == "production" ? "wss://" : "ws://"
      erb :"application.js"
    end
  end
end
