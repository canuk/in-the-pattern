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
      @arrivals = Arrival.order(arrived_at: :desc).limit(4)
      erb :"arrivals.html", layout: false
    end
    
    get "/geofence" do
      erb :"geofence.html"
    end
    
    get "/settings" do
      @settings = Setting.first
      @airports = Airport.all
      erb :"settings.html"
    end
    
    post "/settings" do
      @airports = Airport.all
      
      @settings = Setting.first
      @settings.airport_id = params[:airport_id].to_i
      @settings.airport_id = params[:use_1090dump]
      @settings.airport_id = params[:ip_1090dump]
      @settings.airport_id = params[:port_1090dump]
      @settings.airport_id = params[:adsbx_api_key]
      @settings.updated_at = Time.now
      @settings.save!
            
      erb :"settings.html"
    end

    get "/assets/js/application.js" do
      content_type :js
      @scheme = ENV['RACK_ENV'] == "production" ? "wss://" : "ws://"
      erb :"application.js"
    end
  end
end
