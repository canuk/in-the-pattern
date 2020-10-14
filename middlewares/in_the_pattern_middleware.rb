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
        end
        sock = TCPSocket.open(hostname, port)
        
        overhead = JSON.parse(@airport.overhead)   #[[33.787192,-117.083074], [33.788048,-116.950208], [33.674409,-116.952611], [33.674695,-117.089941]]
        
        appch_rwy = @airport.approach_rwy.to_s
        dep_rwy = @airport.departure_rwy.to_s
        if ENV['PI'] == "true"
          system 'python3 ~/in-the-pattern/rwy.py -a '+ appch_rwy + ' -d ' + dep_rwy
        end
        
        # KHMT Traffic Pattern
        upwind = JSON.parse(@airport.upwind) #[[33.731881,-117.024530], [33.720102,-117.052339], [33.723814,-117.054914], [33.733451,-117.025646]]
        crosswind = JSON.parse(@airport.crosswind) #[[33.711463,-117.049850], [33.715033,-117.040323], [33.723386,-117.043327], [33.720316,-117.054056]]
        downwind = JSON.parse(@airport.downwind) #[[33.734815,-116.994328], [33.711605,-117.049946], [33.703894,-117.043423], [33.726883,-116.983342]]
        base = JSON.parse(@airport.base) #[[33.739739,-117.004327], [33.742309,-116.998319], [33.734208,-116.994371], [33.732066,-117.000679]]
        final = JSON.parse(@airport.final) #[[33.734574,-117.021013], [33.734003,-117.020712], [33.741488,-117.000894], [33.742345,-117.002182]]
        
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
        
        pattern_leg_array = ["upwind", "crosswind", "downwind", "base", "final"]
        if ENV['PI'] == "true"
          pattern_leg_array.each do |leg|
            system 'python3 ~/in-the-pattern/aip.py -l '+ leg.to_s + ' -t' + leg.upcase.to_s
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
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "upwind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 ~/in-the-pattern/aip.py -l upwind -t ' + hexident.to_s
                end
                airplane_upwind[hexident] = airplane_info
              end
            elsif inside?(crosswind, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "CROSSWIND - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "crosswind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 ~/in-the-pattern/aip.py -l crosswind -t ' + hexident.to_s
                end
                airplane_crosswind[hexident] = airplane_info
                if airplane_upwind[hexident]
                  airplane_upwind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "upwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 ~/in-the-pattern/aip.py -l upwind -c leg'
                  end
                end
              end
            elsif inside?(downwind, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "DOWNWIND - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "downwind", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 ~/in-the-pattern/aip.py -l downwind -t ' + hexident.to_s
                end
                airplane_downwind[hexident] = airplane_info
                if airplane_crosswind[hexident]
                  airplane_crosswind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "crosswind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 ~/in-the-pattern/aip.py -l crosswind -c leg'
                  end
                end
              end
            elsif inside?(base, airplane_position)
              if alt.to_i < TPA
                airplanes_in_the_pattern |= [hexident] # add the airplane to the array we'll check later if they need to be removed from the pattern leg
                puts "BASE - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "base", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 ~/in-the-pattern/aip.py -l base -t ' + hexident.to_s
                end
                airplane_base[hexident] = airplane_info
                if airplane_downwind[hexident]
                  airplane_downwind.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "downwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                    system 'python3 ~/in-the-pattern/aip.py -l downwind -c leg'
                  end
                end
              end
            elsif inside?(final, airplane_position)
              if alt.to_i < TPA
                airplanes_on_final |= [hexident] # add ident to array if not already in there
                puts "Airplanes on final: #{airplanes_on_final}"
                puts "FINAL - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "final", :altitude => alt.to_s}))
                if ENV['PI'] == "true"
                  system 'python3 ~/in-the-pattern/aip.py -l final -t ' + hexident.to_s
                end
                airplane_final[hexident] = airplane_info
                if airplane_base[hexident]
                  airplane_base.delete(hexident)
                  @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "base", :altitude => ""}))
                  if ENV['PI'] == "true"
                   system 'python3 ~/in-the-pattern/aip.py -l base -c leg'
                  end
                end
              end
            elsif inside?(overhead, airplane_position)
              if alt.to_i > TPA + 500
                puts "OVERHEAD - ID:"+hexident+" ALT:"+alt
                @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "overhead", :altitude => alt.to_s}))
              end
            end    
        
        	end
          
          puts "AIP: #{airplanes_in_the_pattern}"
          
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
                @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "final", :altitude => ""}))
                if ENV['PI'] == "true"
                 system 'python3 ~/in-the-pattern/aip.py -l final -c leg'
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
                  @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "upwind", :altitude => ""}))
                  if ENV['PI'] == "true"
                   system 'python3 ~/in-the-pattern/aip.py -l upwind -c leg'
                  end            
                end
                if airplane_crosswind[a]
                  last_return = DateTime.strptime(airplane_crosswind[a][6] + 'T' + airplane_crosswind[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_crosswind.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "crosswind", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 ~/in-the-pattern/aip.py -l crosswind -c leg'
                    end            
                  end
                end
                if airplane_downwind[a]
                  last_return = DateTime.strptime(airplane_downwind[a][6] + 'T' + airplane_downwind[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_downwind.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "downwind", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 ~/in-the-pattern/aip.py -l downwind -c leg'
                    end            
                  end
                end
                if airplane_base[a]
                  last_return = DateTime.strptime(airplane_base[a][6] + 'T' + airplane_base[a][7] + '-07:00', '%Y/%m/%dT%H:%M:%S.%L%z')
                  if five_seconds_ago > Time.parse(last_return.to_s)  # is older than 10 seconds
                    airplane_base.delete(a)
                    @redis.publish(CHANNEL, JSON.generate({:who => "", :traffic_leg => "base", :altitude => ""}))
                    if ENV['PI'] == "true"
                     system 'python3 ~/in-the-pattern/aip.py -l base -c leg'
                    end            
                  end
                end                
              end
            end
          end        
        end

        if ENV['PI'] == "true"
          system 'python3 ~/in-the-pattern/aip.py -l final -c all' # clear the pattern
        end
        sock.close               # Close the socket when done     
    
      end
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
