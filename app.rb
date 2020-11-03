require 'sinatra/base'
require "sinatra/activerecord"

require_relative "models/airport.rb"
require_relative "models/arrival.rb"
require_relative "models/departure.rb"
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
      @airports = Airport.all
      erb :"airports/index.html"
    end
    
    get "/airports/new" do
      @airport = Airport.new
      erb :"airports/new.html"
    end 
    
    post "/airports/create" do
      
      erb :"airports/show.html"
    end     
    
    get "/airports/edit/:id" do
      @airport = Airport.find(params[:id])
      erb :"airports/edit.html"
    end  
    
    post "/airports/update" do
      @airport = Airport.find(params[:id]) 
      @airport.name = params[:name]
      @airport.name = params[:identifier]
      @airport.name = params[:lat]
      @airport.name = params[:lng]
      @airport.name = params[:overhead]
      @airport.name = params[:upwind]
      @airport.name = params[:crosswind]
      @airport.name = params[:downwind]
      @airport.name = params[:base]
      @airport.name = params[:final]
      @airport.name = params[:approach_rwy]
      @airport.name = params[:departure_rwy]
      if params[:left_pattern].blank? 
        @airport.left_pattern = false
      else
        @airport.left_pattern = true
      end   
      @airpo      
      @airport.updated_at = Time.now
      @airport.save!      
      erb :"airports/show.html"
    end           

    get "/assets/js/application.js" do
      content_type :js
      @scheme = ENV['RACK_ENV'] == "production" ? "wss://" : "ws://"
      erb :"application.js"
    end
  end
end
