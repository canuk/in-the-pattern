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
    TPA = 3000 # I added 500 to it.

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
        
        if @settings.use_1090dump == true
          hostname = @settings.ip_1090dump #PiAware/1090Dump Device IP 192.168.0.137
          port = @settings.port_1090dump  #30003
        elsif @settings.use_1090dump == false
          hostname = @settings.ip_1090dump #PiAware/1090Dump Device IP 192.168.0.137
          port = @settings.port_1090dump  #30003          
        end
        sock = TCPSocket.open(hostname, port)
        
        overhead = JSON.parse(@airport.overhead)
        
        appch_rwy = @airport.approach_rwy.to_s
        dep_rwy = @airport.departure_rwy.to_s
        if ENV['PI'] == "true"
          system 'python3 /home/pi/in-the-pattern/oled/rwy.py -a '+ appch_rwy + ' -d ' + dep_rwy
        end
        
        #Traffic Pattern
        pattern_fence = Hash.new
        @airport.upwind == nil ? pattern_fence["upwind"] = [] : pattern_fence["upwind"] = JSON.parse(@airport.upwind)
        @airport.crosswind == nil ? pattern_fence["crosswind"] = [] : pattern_fence["crosswind"] = JSON.parse(@airport.crosswind)
        @airport.downwind == nil ? pattern_fence["downwind"] = [] : pattern_fence["downwind"] = JSON.parse(@airport.downwind)
        @airport.base == nil ? pattern_fence["base"] = [] : pattern_fence["base"] = JSON.parse(@airport.base)
        @airport.final == nil ? pattern_fence["final"] = [] : pattern_fence["final"] = JSON.parse(@airport.final)
                
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
        
        airplane_upwind = Hash.new
        airplane_crosswind = Hash.new
        airplane_downwind = Hash.new
        airplane_base = Hash.new
        airplane_final = Hash.new
        
        airplanes_on_final = Array.new
        airplanes_in_the_pattern = Array.new
        
        # Initialize OLED pattern leg displays
        pattern_leg_array = ["upwind", "crosswind", "downwind", "base", "final"]
        welcome_message = Hash.new
        welcome_message["upwind"] = "UPWIND"
        welcome_message["crosswind"] = "XWIND"
        welcome_message["downwind"] = "DNWIND"
        welcome_message["base"] = "BASE"
        welcome_message["final"] = "FINAL"
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
        
        def in_pattern_leg?(airplane)
          n_number = airplane.reg.to_s
          altitude = airplane.alt.to_i
          if altitude.to_i <= TPA
            pattern_leg_array.each do |pattern_leg|
              if inside?(pattern_fence[pattern_leg], [airplane.lat, airplane.lon])            
                airplanes_in_the_pattern |= [airplane.icao] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "#{pattern_leg.upcase} - ID: #{n_number} ALT: #{altitude}"
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => n_number, :traffic_leg => "upwind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + pattern_leg + ' -t ' + n_number
                end
                airplane_upwind[airplane.icao] = airplane
              end
            end
          end   
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
            airplane["last_seen"] = DateTime.strptime(fields[6] + 'T' + fields[7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
            # Figure out if airplane is in the traffic pattern, and where it is
            # If it's in the next leg, remove it from the previous leg hash
            # airplane info should include identifier, etc.
            if !airplane["alt"].blank? && airplane["alt"].to_i <= TPA # Don't even bother if not at or below TPA
              pattern_leg_array.each do |leg|
                # see if any airplanes in the pattern need to be removed.
                # If the last timestamp was more than 2 minutes ago, then remove it.
                if !current_pattern[leg].blank?
                  if current_pattern[leg]["last_seen"] >= Time.now - 120 # 120 seconds = 2 minutes
                    if leg == "final"
                      # insert into arrivals database
                      Arrival.find_or_create_by(airport_id: @airport.id, tail_number: airplane["n_number"], arrived_at: current_pattern[leg]["last_seen"])
                    elsif leg == "upwind"
                      # insert into departures database
                      Departure.find_or_create_by(airport_id: @airport.id, tail_number: airplane["n_number"], arrived_at: current_pattern[leg]["last_seen"])
                    end 
                    # Clear the current_airplane hash
                    current_pattern[leg] = nil
                  end
                end
                if inside?(pattern_fence[leg], airplane["position"])
                  if current_pattern[leg].blank? || current_pattern[leg]["n_number"] != airplane["n_number"]
                    current_pattern[leg] = airplane
                  elsif current_pattern[leg]["n_number"] == airplane["n_number"] #Its already logged in the hash, update the last seen
                    current_pattern[leg]["last_seen"] = Time.now
                    puts current_pattern
                  end
                  puts "#{leg.upcase} - ID: #{airplane['n_number']} ALT: #{airplane['alt']}"
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => airplane["n_number"], :traffic_leg => leg, :altitude => airplane["alt"].to_s}))
                  if ENV['PI'] == "true"
                    system 'python3 /home/pi/in-the-pattern/oled/aip.py -l ' + pattern_leg + ' -t ' + airplane["n_number"]
                  end    
                end
              end
            end
            # if inside?(overhead, airplane_position)
            #   if alt.to_i > TPA + 500
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
