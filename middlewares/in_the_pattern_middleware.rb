require 'faye/websocket'
require 'thread'
require 'redis'
require 'json'
require 'erb'
require 'socket' 
require 'date'
require 'time'
require 'csv'		
require 'rest-client'

module InThePattern
  class InThePatternBackend
    KEEPALIVE_TIME = 1 # in seconds
    CHANNEL        = "in-the-pattern"

    def initialize(app)
      @app     = app
      @settings = Setting.first
      @clients = []
      uri = URI.parse(ENV["REDISCLOUD_URL"])
      @redis = Redis.new(host: uri.host, port: uri.port, password: uri.password)
      Thread.new do
        redis_sub = Redis.new(host: uri.host, port: uri.port, password: uri.password)
        redis_sub.subscribe(CHANNEL) do |on|
          on.message do |channel, msg|
            @clients.each {|ws| ws.send(msg) }
          end
        end
      end
      if @settings.use_1090dump
        local_1090dump_thread
      else
        remote_adsbx_thread
      end
    end
    
    def local_1090dump_thread
      puts "Starting local 1090dump Thread."
      @incoming_local_adsb_data = Thread.new { local_1090dump }
    rescue
      sleep(2)
      retry
    end   
    
    def remote_adsbx_thread
      puts "Starting remote ADSB-Exchange Thread."
      @incoming_remote_adsb_data = Thread.new { remote_adsbx }
    rescue
      sleep(2)
      retry
    end     
    
    def restart_adsb_source_after_settings_change
      @settings = Setting.first
      Thread.kill @incoming_local_adsb_data
      Thread.kill @@incoming_remote_adsb_data
      if @settings.use_1090dump
        local_1090dump_thread
      else
        remote_adsbx_thread
      end
    end
    
    def initialize_traffic_pattern_details
      @airport = Airport.find(@settings.airport_id)
      @tpa = @airport.field_elevation + 1500

      # Runway Numbers
      # Variables and Hashes are all "hardwired" for a Left (Standard) Pattern
      if @airport.left_pattern
        appch_rwy = @airport.approach_rwy.to_s
        dep_rwy = @airport.departure_rwy.to_s
      else
        dep_rwy = @airport.approach_rwy.to_s
        appch_rwy = @airport.departure_rwy.to_s
      end
      if ENV['PI'] == "true"
        system 'python3 /home/pi/in-the-pattern/oled/rwy.py -a '+ appch_rwy + ' -d ' + dep_rwy
      end
      
      #Traffic Pattern
      @pattern_fence = Hash.new
      @airport.upwind == nil ? @pattern_fence["upwind"] = [] : @pattern_fence["upwind"] = JSON.parse(@airport.upwind)
      @airport.crosswind == nil ? @pattern_fence["crosswind"] = [] : @pattern_fence["crosswind"] = JSON.parse(@airport.crosswind)          
      @airport.downwind == nil ? @pattern_fence["downwind"] = [] : @pattern_fence["downwind"] = JSON.parse(@airport.downwind)
      @airport.base == nil ? @pattern_fence["base"] = [] : @pattern_fence["base"] = JSON.parse(@airport.base)
      @airport.final == nil ? @pattern_fence["final"] = [] : @pattern_fence["final"] = JSON.parse(@airport.final)
      @airport.overhead == nil ? @overhead = [] : @overhead = JSON.parse(@airport.overhead)   
              
      # Initialize OLED pattern leg displays
      @pattern_leg_array = ["upwind", "crosswind", "downwind", "base", "final"]
      
      #Initialize current_airplane hash
      @current_pattern = Hash.new
      @pattern_leg_array.each do |leg|
        @current_pattern[leg] = Hash.new
      end      
      welcome_message = Hash.new
      welcome_message = {"upwind"=>"UPWIND", "crosswind"=>"XWIND", "downwind"=>"DNWIND", "base"=>"BASE", "final"=>"FINAL"}       
      if ENV['PI'] == "true"
        @pattern_leg_array.each do |leg|
          system 'python3 /home/pi/in-the-pattern/oled/aip.py -l '+ leg.to_s + ' -t' + welcome_message[leg]  + ' -p ' + @airport.left_pattern.to_s
        end
      end    
    end          
    
    def remote_adsbx
      initialize_traffic_pattern_details  
      
      radius = 5
      
      exit_requested = false
      Kernel.trap( "INT" ) { exit_requested = true }
      
      url = "https://adsbexchange.com/api/aircraft/json/lat/#{@airport.lat}/lon/#{@airport.lng}/dist/#{radius}/"
            
      while !exit_requested
      
        # clean up any legs where the airplane has left the pattern or if it's taken off or landed
        clean_up_pattern_legs  
      
        # Grab the data from the API
        data = RestClient.get(url, {"accept-encoding": "gzip", "api-auth": @settings.adsbx_api_key})
        adsbx_return = JSON.parse(Zlib::GzipReader.new(StringIO.new(data)).read) # data comes gzipped
        
        # loop through the data return to see if anyone is in the pattern
        unless adsbx_return["ac"].blank?
          adsbx_return["ac"].each do |aircraft|
            puts n_number = aircraft["reg"]
            lat = aircraft["lat"].to_f
        		lng = aircraft["lon"].to_f
            alt = aircraft["alt"]      
            airplane = Hash.new
        		airplane["n_number"] = n_number
            airplane["position"] = [lat,lng]
            airplane["alt"] = alt
            airplane["last_seen"] = Time.now
            
            @pattern_leg_array.each_with_index do |leg, idx|
              if !airplane["alt"].blank? && airplane["alt"].to_i <= @tpa # Don't even bother if not at or below TPA
                if inside?(@pattern_fence[leg], airplane["position"])
                  if @current_pattern[leg].blank? || @current_pattern[leg]["n_number"] != airplane["n_number"]
                    @current_pattern[leg] = airplane
                    puts "#{leg.upcase} - ID: #{airplane['n_number']} ALT: #{airplane['alt']}"
                    @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => airplane["n_number"], :traffic_leg => leg, :altitude => airplane["alt"].to_s}))
                    if ENV['PI'] == "true"
                      system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + leg + ' -t ' + airplane["n_number"] + ' -p ' + @airport.left_pattern.to_s
                    end  
                    # Now check to see if we need to remove the airplane from previous leg
                    previous_leg = @pattern_leg_array[idx-1]
                    if !@current_pattern[previous_leg].blank?
                      if @current_pattern[previous_leg]["n_number"] == airplane["n_number"]
                        if previous_leg == "upwind"
                          # insert into departures database if the went from upwind to crosswind.
                          Departure.find_or_create_by(airport_id: @airport.id, tail_number: @current_pattern[previous_leg]["n_number"], departed_at: @current_pattern[previous_leg]["last_seen"])
                          @redis.publish(CHANNEL, JSON.generate({:date_type => "departure", :who => @current_pattern[previous_leg]["n_number"]}))
                        end                
                        @current_pattern[previous_leg] = nil
                        if ENV['PI'] == "true"
                          system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + @pattern_leg_array[idx-1] + ' -c leg'
                        end  
                      end    
                    end                 
                  #It's already logged in the hash, update the last seen
                  elsif @current_pattern[leg]["n_number"] == airplane["n_number"] 
                    @current_pattern[leg]["last_seen"] = Time.now
                    puts @current_pattern
                  end   
                end
              end
            end 
            if inside?(@overhead, airplane["position"])
              if alt.to_i > @tpa
                puts "overhead - ID: "+n_number+" ALT: "+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => n_number, :traffic_leg => "overhead", :altitude => alt.to_s}))
              end
            end            
          end 
        end       
        
        sleep(6) # wait six seconds to not overwhelm API
      end
    end
    
    def local_1090dump
      initialize_traffic_pattern_details
      
      exit_requested = false
      Kernel.trap( "INT" ) { exit_requested = true }
            
      hostname = @settings.ip_1090dump #PiAware/1090Dump Device IP
      port = @settings.port_1090dump  #30003

      sock = TCPSocket.open(hostname, port)
      
      while (line = sock.gets) && (!exit_requested)
        if line
          line = sock.gets.chomp
          #read next line from the socket - Ruby uses LF = \n to detect newline
          #gets returns a string and a '\n' character, while chomp removes this '\n'
          #gets returns nil at end of file.
          #when a socket is closed, it sends eof to the other side.
          #therefore gets() returns nil
          	fields = line.split(",")
            airplane_info = fields
            
            # Uncomment below to test to see if receiving data
            #puts fields[4].to_s
            
            # clean up any legs where the airplane has left the pattern or if it's taken off or landed
            clean_up_pattern_legs
          
          	if fields[0].to_s == "MSG" && fields[1].to_s == "3" #Airborne Position Message
              
              n_number = fields[4].to_s
              airplane = Hash.new
          		airplane["n_number"] = n_number
              lat = fields[14].to_f
          		lng = fields[15].to_f
              airplane["position"] = [lat,lng]
              airplane["alt"] = fields[11].to_s
              airplane["last_seen"] = Time.now
                       
              # Figure out if airplane is in the traffic pattern, and where it is
              # If it's in the next leg, remove it from the previous leg hash
              # airplane info should include identifier, etc.
              @pattern_leg_array.each_with_index do |leg, idx|
                if !airplane["alt"].blank? && airplane["alt"].to_i <= @tpa # Don't even bother if not at or below TPA
                  if inside?(@pattern_fence[leg], airplane["position"])
                    if @current_pattern[leg].blank? || @current_pattern[leg]["n_number"] != airplane["n_number"]
                      @current_pattern[leg] = airplane
                      puts "#{leg.upcase} - ID: #{airplane['n_number']} ALT: #{airplane['alt']}"
                      @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => airplane["n_number"], :traffic_leg => leg, :altitude => airplane["alt"].to_s}))
                      if ENV['PI'] == "true"
                        system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + leg + ' -t ' + airplane["n_number"] + ' -lp ' + @airport.left_pattern
                      end  
                      # Now check to see if we need to remove the airplane from previous leg
                      previous_leg = @pattern_leg_array[idx-1]
                      if !@current_pattern[previous_leg].blank?
                        if @current_pattern[previous_leg]["n_number"] == airplane["n_number"]
                          if previous_leg == "upwind"
                            # insert into departures database if the went from upwind to crosswind.
                            Departure.find_or_create_by(airport_id: @airport.id, tail_number: @current_pattern[previous_leg]["n_number"], departed_at: @current_pattern[previous_leg]["last_seen"])
                            @redis.publish(CHANNEL, JSON.generate({:date_type => "departure", :who => @current_pattern[previous_leg]["n_number"]}))
                          end                
                          @current_pattern[previous_leg] = nil
                          if ENV['PI'] == "true"
                            system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + @pattern_leg_array[idx-1] + ' -c leg'
                          end  
                        end    
                      end                 
                    #It's already logged in the hash, update the last seen
                    elsif @current_pattern[leg]["n_number"] == airplane["n_number"] 
                      @current_pattern[leg]["last_seen"] = Time.now
                      puts @current_pattern
                    end   
                  end
                end
              end
              # if inside?(@overhead, airplane_position)
              #   if alt.to_i > @tpa + 500
              #     puts "overhead - ID: "+n_number+" ALT: "+alt
              #     @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => n_number, :traffic_leg => "overhead", :altitude => alt.to_s}))
              #   end
              # end    
          	end  # If 1090 message is "3" which is an aircraft position report 
          end # if line is not nil
      end

      if ENV['PI'] == "true"
        system 'python3 /home/pi/in-the-pattern/oled/aip.py -l final -c all' # clear the pattern
      end
      sock.close               # Close the socket when done      
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        ws = Faye::WebSocket.new(env, nil, {ping: KEEPALIVE_TIME })
        ws.on :open do |event|
          p [:open, ws.object_id]
          @clients << ws
        end

        ws.on :message do |event|
          p [:message, event.data]
          @redis.publish(CHANNEL, sanitize(event.data))
        end

        ws.on :close do |event|
          p [:close, ws.object_id, event.code, event.reason]
          @clients.delete(ws)
          ws = nil
        end

        # Return async Rack response
        ws.rack_response

      else
        @app.call(env)
      end
    end
    
    def clean_up_pattern_legs
      # see if any airplanes in the pattern need to be removed.
      # If the last timestamp was more than 15 seconds, then remove it.
      @pattern_leg_array.each do |leg|
        if !@current_pattern[leg].blank?
          if @current_pattern[leg]["last_seen"] <= Time.now - 15 # 15 seconds ago
            if leg == "final"
              # insert into arrivals database
              Arrival.find_or_create_by(airport_id: @airport.id, tail_number: @current_pattern[leg]["n_number"], arrived_at: @current_pattern[leg]["last_seen"])
              @redis.publish(CHANNEL, JSON.generate({:date_type => "arrival", :who => @current_pattern[leg]["n_number"]}))
            elsif leg == "upwind"
              # insert into departures database
              Departure.find_or_create_by(airport_id: @airport.id, tail_number: @current_pattern[leg]["n_number"], departed_at: @current_pattern[leg]["last_seen"])
              @redis.publish(CHANNEL, JSON.generate({:date_type => "departure", :who => @current_pattern[leg]["n_number"]}))
            end 
            # Clear the the airplane from the pattern leg it was in (this will clear orphaned n_numbers when they fly through a pattern but don't go to the next leg)
            @current_pattern[leg] = nil
            # ... and clear the OLED
            if ENV['PI'] == "true"
              system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + leg + ' -c leg'
            end                     
          end
        end 
      end 
    end     

    private
    def sanitize(message)
      json = JSON.parse(message)
      json.each {|key, value| json[key] = ERB::Util.html_escape(value) }
      JSON.generate(json)
    end
    
    def inside?(vertices, test_point)
      vs = vertices + [vertices.first]
      xi, yi = vertices.reduce([0,0]) { |(sx,sy),(x,y)| [sx+x, sy+y] }.map { |e|
        e.to_f/vertices.size } # interior point
      x, y = test_point
      vs.each_cons(2).all? do |(x0,y0),(x1,y1)|
        if x0 == x1 # vertical edge
          (xi > x0) ? (x >= x0) : (x <= x0)
        else
          k, slope = line_equation(x0,y0,x1,y1)
          (k + xi*slope > yi) ? (k + x*slope >= y) : (k + x*slope <= y)
        end
      end
    end
    
    def line_equation(x0,y0,x1,y1)
      s = (y1-y0).to_f/(x1-x0)
      [y0-s*x0, s]
    end    
  end
end
