require 'sinatra/base'
require "sinatra/activerecord"
require "sinatra/cross_origin"
require 'sinatra/custom_logger'
require 'logger'

require_relative "models/airport.rb"
require_relative "models/arrival.rb"
require_relative "models/departure.rb"
require_relative "models/setting.rb"

module InThePattern
  class App < Sinatra::Base
    helpers Sinatra::CustomLogger
    register Sinatra::ActiveRecordExtension
    use Rack::MethodOverride
    
    configure do
      set :database, {adapter: "sqlite3", database: "itp.sqlite3"}
          
      enable :cross_origin
      
      logger = Logger.new(File.open("#{root}/log/#{environment}.log", 'a'))
      logger.level = Logger::DEBUG if development?
      set :logger, logger
    end  
    
    get "/" do
      @settings = Setting.first
      @airport = Airport.find(@settings.airport_id)
      erb :"index.html"
    end
    
    get "/status_board" do
      @settings = Setting.first
      @airport = Airport.find(@settings.airport_id)
      @arrivals = Arrival.order(arrived_at: :desc).limit(3)
      @departures = Departure.order(departed_at: :desc).limit(3)
      erb :"status_board.html", layout: false
    end
    
    get "/arrivals_and_departures" do
      @arrivals = Arrival.order(arrived_at: :desc).limit(100)
      @departures = Departure.order(departed_at: :desc).limit(100)
      erb :"arrivals_and_departures.html"
    end    
    
    delete "/arrivals/:id" do
      @arrival = Arrival.find(params[:id])
      @arrival.destroy
      redirect "/arrivals_and_departures"
    end
    
    delete "/departures/:id" do
      @departure = Departure.find(params[:id])
      @departure.destroy
      redirect "/arrivals_and_departures"
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
      if params[:use_1090dump].blank? 
        @settings.use_1090dump = false
      else
        @settings.use_1090dump = true
      end
      @settings.ip_1090dump = params[:ip_1090dump]
      @settings.port_1090dump = params[:port_1090dump]
      @settings.adsbx_api_key = params[:adsbx_api_key]
      @settings.updated_at = Time.now
      @settings.save!
            
      erb :"settings.html"
    end
    
    get "/airports" do
      @airports = Airport.order(name: :asc).all
      erb :"airports/index.html"
    end
    
    delete "/airports/:id" do
      @airport = Airport.find(params[:id])
      @airport.destroy
      redirect "/airports"
    end    
    
    get "/airports/show/:id" do
      @airport = Airport.find(params[:id]) 
      erb :"airports/show.html"
    end
    
    get "/airports/new" do
      erb :"airports/new.html"
    end 
    
    post "/airports/create" do
      @airport = Airport.new 
      @airport.name = params[:name]
      @airport.identifier = params[:identifier].upcase
      @airport.lat = params[:lat]
      @airport.lng = params[:lng]
      @airport.overhead = params[:overhead]
      @airport.upwind = params[:upwind]
      @airport.crosswind = params[:crosswind]
      @airport.downwind = params[:downwind]
      @airport.base = params[:base]
      @airport.final = params[:final]
      @airport.approach_rwy = params[:approach_rwy]
      @airport.departure_rwy = params[:departure_rwy]
      if params[:left_pattern].blank? 
        @airport.left_pattern = false
      else
        @airport.left_pattern = true
      end        
      @airport.created_at = Time.now
      @airport.updated_at = Time.now
      @airport.save!      
      redirect to "/airports/show/#{@airport.id}"      
    end     
    
    get "/airports/edit/:id" do
      @airport = Airport.find(params[:id])
      erb :"airports/edit.html"
    end  
    
    post "/airports/update" do
      @airport = Airport.find(params[:id]) 
      @airport.name = params[:name].chomp
      @airport.identifier = params[:identifier].upcase.chomp
      @airport.lat = params[:lat]
      @airport.lng = params[:lng]
      @airport.overhead = params[:overhead]
      @airport.upwind = params[:upwind]
      @airport.crosswind = params[:crosswind]
      @airport.downwind = params[:downwind]
      @airport.base = params[:base]
      @airport.final = params[:final]
      @airport.approach_rwy = params[:approach_rwy].chomp
      @airport.departure_rwy = params[:departure_rwy].chomp
      if params[:left_pattern].blank? 
        @airport.left_pattern = false
      else
        @airport.left_pattern = true
      end        
      @airport.updated_at = Time.now
      @airport.save!      
      redirect to "/airports/show/#{@airport.id}"
    end           

    get "/assets/js/application.js" do
      content_type :js
      @scheme = ENV['RACK_ENV'] == "production" ? "wss://" : "ws://"
      erb :"application.js"
    end
  end
end
