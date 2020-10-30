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
        if ENV['PI'] == "true"
          pattern_leg_array.each do |leg|
            system 'python3 /home/pi/in-the-pattern/oled/aip.py -l '+ leg.to_s + ' -t' + leg.upcase.to_s
          end
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
            
        		hexident = fields[4].to_s
            lat = fields[14].to_f
        		lng = fields[15].to_f
            airplane_position = [fields[14].to_f,fields[15].to_f]
            alt = fields[11].to_s
            
            # Figure out if airplane is in the traffic pattern, and where it is
            # If it's in the next leg, remove it from the previous leg hash
            # airplane info should include identifier, etc.
            if inside?(upwind, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "UPWIND - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "upwind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l upwind -t ' + hexident.to_s
                end
                airplane_upwind[hexident] = airplane_info
              end
            elsif inside?(crosswind, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "CROSSWIND - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "crosswind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l crosswind -t ' + hexident.to_s
                end
                airplane_crosswind[hexident] = airplane_info
                if airplane_upwind[hexident]
                  airplane_upwind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "upwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 /home/pi/in-the-pattern/oled/aip.py -l upwind -c leg'
                  end
                end
              end
            elsif inside?(downwind, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "DOWNWIND - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "downwind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l downwind -t ' + hexident.to_s
                end
                airplane_downwind[hexident] = airplane_info
                if airplane_crosswind[hexident]
                  airplane_crosswind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "crosswind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 /home/pi/in-the-pattern/oled/aip.py -l crosswind -c leg'
                  end
                end
              end
            elsif inside?(base, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "BASE - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "base", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l base -t ' + hexident.to_s
                end
                airplane_base[hexident] = airplane_info
                if airplane_downwind[hexident]
                  airplane_downwind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "downwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 /home/pi/in-the-pattern/oled/aip.py -l downwind -c leg'
                  end
                end
              end
            elsif inside?(final, airplane_position)
              if alt.to_i < TPA
                airplanes_on_final |= [hexident] # add ident to array if not already in there
                puts "Airplanes on final: #{airplanes_on_final}"
                puts "FINAL - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "final", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 /home/pi/in-the-pattern/oled/aip.py -l final -t ' + hexident.to_s
                end
                airplane_final[hexident] = airplane_info
                if airplane_base[hexident]
                  airplane_base.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "base", :altitude => ""}))
                  if ENV['PI'] == "true"
                   system 'python3 /home/pi/in-the-pattern/oled/aip.py -l base -c leg'
                  end
                end
              end
            elsif inside?(overhead, airplane_position)
              if alt.to_i > TPA + 500
                puts "OVERHEAD - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => hexident.to_s, :traffic_leg => "overhead", :altitude => alt.to_s}))
              end
            end    
        
        	end
          
          # Have any of the airplanes on final, landed?
          # we say if we haven't got a return from them after 10 seconds, and they were on final, then they landed
          unless airplanes_on_final.empty?
            unless airplane_final.empty?
            airplanes_on_final.each do |aof|
              last_return = DateTime.strptime(airplane_final[aof][6] + 'T' + airplane_final[aof][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
              if (Time.now - 5) > Time.parse(last_return.to_s)  # is older than 10 seconds
                puts "LOGGING ARRIVAL"
                  Arrival.find_or_create_by(airport_id: @airport.id, tail_number: aof, arrived_at: last_return) # find_or_create_by prevents creating duplicates... I think...
                  airplane_final.delete(aof) # Remove it from the airplane_final hash
                  airplanes_on_final.delete(aof) # remove it from the airplanes on final
                @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "final", :altitude => ""}))
                if ENV['PI'] == "true"
                 system 'python3 /home/pi/in-the-pattern/oled/aip.py -l final -c leg'
                end            
              end
            end
          end
          end
          
          # clear airplanes who left the pattern without landing
          unless airplanes_in_the_pattern.empty?
            airplanes_in_the_pattern.each do |a|
              five_seconds_ago = Time.now - 5
              if airplane_upwind[a]
                last_return = DateTime.strptime(airplane_upwind[a][6] + 'T' + airplane_upwind[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                  airplane_upwind.delete(a)
                  @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "upwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                   system 'python3 /home/pi/in-the-pattern/oled/aip.py -l upwind -c leg'
                  end            
                end
                if airplane_crosswind[a]
                  last_return = DateTime.strptime(airplane_crosswind[a][6] + 'T' + airplane_crosswind[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_crosswind.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "crosswind", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 /home/pi/in-the-pattern/oled/aip.py -l crosswind -c leg'
                    end            
                  end
                end
                if airplane_downwind[a]
                  last_return = DateTime.strptime(airplane_downwind[a][6] + 'T' + airplane_downwind[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_downwind.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "downwind", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 /home/pi/in-the-pattern/oled/aip.py -l downwind -c leg'
                    end            
                  end
                end
                if airplane_base[a]
                  last_return = DateTime.strptime(airplane_base[a][6] + 'T' + airplane_base[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_base.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:date_type => "pattern_location", :who => "", :traffic_leg => "base", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 /home/pi/in-the-pattern/oled/aip.py -l base -c leg'
                    end            
                  end
                end                
              end
            end
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
