require 'faye/websocket'
require 'thread'
require 'redis'
require 'json'
require 'erb'
require 'socket' 
require 'date'
require 'time'
require 'csv'		

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
      Thread.new do
      
        exit_requested = false
        Kernel.trap( "INT" ) { exit_requested = true }
        
        @airport = Airport.find(@settings.airport_id)
        @tpa = @airport.field_elevation + 1500
        
        if @settings.use_1090dump == true
          hostname = @settings.ip_1090dump #PiAware/1090Dump Device IP 192.168.0.137
          port = @settings.port_1090dump  #30003
        elsif @settings.use_1090dump == false # so it doesn't fail, just keep using 1090dump
          # eventually here we'll figure out what to do with ADSBExchange
          hostname = @settings.ip_1090dump
          port = @settings.port_1090dump          
        end
        sock = TCPSocket.open(hostname, port)
        
        overhead = JSON.parse(@airport.overhead)
        
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
        pattern_fence = Hash.new
        @airport.downwind == nil ? pattern_fence["downwind"] = [] : pattern_fence["downwind"] = JSON.parse(@airport.downwind)
        # Variables and Hashes are all "hardwired" for a Left (Standard) Pattern
        if @airport.left_pattern
          @airport.upwind == nil ? pattern_fence["upwind"] = [] : pattern_fence["upwind"] = JSON.parse(@airport.upwind)
          @airport.crosswind == nil ? pattern_fence["crosswind"] = [] : pattern_fence["crosswind"] = JSON.parse(@airport.crosswind)          
          @airport.base == nil ? pattern_fence["base"] = [] : pattern_fence["base"] = JSON.parse(@airport.base)
          @airport.final == nil ? pattern_fence["final"] = [] : pattern_fence["final"] = JSON.parse(@airport.final)
        else # its a Right Pattern, so everything is "backwards" since we have all the variables in the code hard-wired for Left (standard) patterns
          @airport.upwind == nil ? pattern_fence["final"] = [] : pattern_fence["final"] = JSON.parse(@airport.upwind)
          @airport.crosswind == nil ? pattern_fence["base"] = [] : pattern_fence["base"] = JSON.parse(@airport.crosswind)
          @airport.base == nil ? pattern_fence["crosswind"] = [] : pattern_fence["crosswind"] = JSON.parse(@airport.base)
          @airport.final == nil ? pattern_fence["upwind"] = [] : pattern_fence["upwind"] = JSON.parse(@airport.final)          
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
                
        # Initialize OLED pattern leg displays
        pattern_leg_array = ["upwind", "crosswind", "downwind", "base", "final"]
        welcome_message = Hash.new
        if @airport.left_pattern
          welcome_message["upwind"] = "UPWIND"
          welcome_message["crosswind"] = "XWIND"
          welcome_message["downwind"] = "DNWIND"
          welcome_message["base"] = "BASE"
          welcome_message["final"] = "FINAL"
        else
          welcome_message["upwind"] = "FINAL"
          welcome_message["crosswind"] = "BASE"
          welcome_message["downwind"] = "DNWIND"
          welcome_message["base"] = "XWIND"
          welcome_message["final"] = "UPWIND"  
        end        
        if ENV['PI'] == "true"
          pattern_leg_array.each do |leg|
            system 'python3 /home/pi/in-the-pattern/oled/aip.py -l '+ leg.to_s + ' -t' + welcome_message[leg]
          end
        end     
        
        #Initialize current_airplane hash
        current_pattern = Hash.new
        pattern_leg_array.each do |leg|
          current_pattern[leg] = Hash.new
        end

        while (line = sock.gets.chomp) &&  (!exit_requested)
         
        #read next line from the socket - Ruby uses LF = \n to detect newline
        #gets returns a string and a '\n' character, while chomp removes this '\n'
        #gets returns nil at end of file.
        #when a socket is closed, it sends eof to the other side.
        #therefore gets() returns nil
        	fields = line.split(",")
          airplane_info = fields
        
        	if fields[0].to_s == "MSG" && fields[1].to_s == "3" #Airborne Position Message
            
            n_number = fields[4].to_s
            airplane = Hash.new
        		airplane["n_number"] = n_number
            lat = fields[14].to_f
        		lng = fields[15].to_f
            airplane["position"] = [fields[14].to_f,fields[15].to_f]
            airplane["alt"] = fields[11].to_s
            airplane["last_seen"] = Time.now
            
            # see if any airplanes in the pattern need to be removed.
            # If the last timestamp was more than 2 minutes ago, then remove it.
            pattern_leg_array.each do |leg|
              if !current_pattern[leg].blank?
                if current_pattern[leg]["last_seen"] <= Time.now - 20 # 120 seconds = 2 minutes
                  if leg == "final"
                    # insert into arrivals database
                    Arrival.find_or_create_by(airport_id: @airport.id, tail_number: current_pattern[leg]["n_number"], arrived_at: current_pattern[leg]["last_seen"])
                  elsif leg == "upwind"
                    # insert into departures database
                    Departure.find_or_create_by(airport_id: @airport.id, tail_number: current_pattern[leg]["n_number"], departed_at: current_pattern[leg]["last_seen"])
                  end 
                  # Clear the the airplane from the pattern leg it was in (this will clear orphaned n_numbers when they fly through a pattern but don't go to the next leg)
                  current_pattern[leg] = nil
                  # ... and clear the OLED
                  if ENV['PI'] == "true"
                    system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + leg + ' -c leg'
                  end                     
                end
              end 
            end           
            # Figure out if airplane is in the traffic pattern, and where it is
            # If it's in the next leg, remove it from the previous leg hash
            # airplane info should include identifier, etc.
            pattern_leg_array.each_with_index do |leg, idx|
              if !airplane["alt"].blank? && airplane["alt"].to_i <= @tpa # Don't even bother if not at or below TPA
                if inside?(pattern_fence[leg], airplane["position"])
                  if current_pattern[leg].blank? || current_pattern[leg]["n_number"] != airplane["n_number"]
                    current_pattern[leg] = airplane
                    puts "#{leg.upcase} - ID: #{airplane['n_number']} ALT: #{airplane['alt']}"
                    @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => airplane["n_number"], :traffic_leg => leg, :altitude => airplane["alt"].to_s}))
                    if ENV['PI'] == "true"
                      system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + leg + ' -t ' + airplane["n_number"]
                    end  
                    # Now remove the airplane from previous leg
                    if pattern_leg_array[idx-1]["n_number"] == airplane["n_number"]
                      pattern_leg_array[idx-1] = nil
                      if ENV['PI'] == "true"
                        system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + pattern_leg_array[idx-1] + ' -c leg'
                      end  
                    end                     
                  #It's already logged in the hash, update the last seen
                  elsif current_pattern[leg]["n_number"] == airplane["n_number"] 
                    current_pattern[leg]["last_seen"] = Time.now
                    puts current_pattern
                  end   
                end
              end
            end
            # if inside?(overhead, airplane_position)
            #   if alt.to_i > @tpa + 500
            #     puts "OVERHEAD - ID:"+hexident+" ALT:"+alt
            #     @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "overhead", :altitude => alt.to_s}))
            #   end
            # end    
        	end                 
        end

        if ENV['PI'] == "true"
          system 'python3 /home/pi/in-the-pattern/oled/aip.py -l final -c all' # clear the pattern
        end
        sock.close               # Close the socket when done     
    
      end #Thread
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

    private
    def sanitize(message)
      json = JSON.parse(message)
      json.each {|key, value| json[key] = ERB::Util.html_escape(value) }
      JSON.generate(json)
    end
  end
end
