require 'faye/websocket'
require 'thread'
require 'redis'
require 'json'
require 'erb'
require 'socket' 
require 'date'
require 'csv'		

module InThePattern
  class InThePatternBackend
    KEEPALIVE_TIME = 3 # in seconds
    CHANNEL        = "in-the-pattern"

    def initialize(app)
      @app     = app
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
        
        hostname = '192.168.0.137' #PiAware/1090Dump Device IP
        port = 30003
        sock = TCPSocket.open(hostname, port)
        
        overhead = [[32.57459172113418, -117.20214843749999], [34.175453097578526, -119.2181396484375], [34.72355492704221, -117.55920410156249], [34.261756524459805, -116.34521484375001], [32.713355353177555, -115.5047607421875]]
        
        # KHMT Traffic Pattern
        upwind = [[33.734297564682706, -117.0219039916992], [33.733119808460394, -117.02121734619139], [33.72305468688201, -117.0455503463745], [33.72159121985561, -117.0479965209961], [33.71877129840258, -117.05447673797607], [33.720270508682205, -117.05529212951659]]
        crosswind = [[33.72255496923924, -117.0289421081543], [33.72769478320399, -117.03203201293945], [33.71662952401543, -117.06207275390624], [33.71220302097189, -117.05984115600586]]
        downwind = [[33.738722928405565, -116.99147701263428], [33.733851446803584, -117.0017123222351], [33.72241219223553, -117.02911376953124], [33.712060226751866, -117.05975532531738], [33.69806524140501, -117.05314636230469], [33.72262635765204, -116.98379516601561]]
        base = [[33.74040022435128, -117.00096130371095], [33.74132807610421, -117.00093984603882], [33.74455763566878, -116.99304342269897], [33.738687240901484, -116.9915199279785], [33.73383360204015, -117.00173377990723], [33.73825898969434, -117.00430870056152], [33.739151177296705, -117.0049738883972]]
        final = [[33.735206,-117.020215], [33.733992,-117.019270], [33.735563,-117.015354], [33.737633,-117.009808], [33.740381,-117.000956], [33.741309,-117.000946], [33.744556,-116.993092], [33.746340,-116.994637], [33.740702,-117.007340]]
        
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
              puts "UPWIND - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "upwind", :altitude => alt.to_s}))
              airplane_upwind[hexident] = airplane_info
              if airplane_final[hexident]
               airplane_final.delete(hexident)
              end
            elsif inside?(crosswind, airplane_position)
              puts "CROSSWIND - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "crosswind", :altitude => alt.to_s}))
              airplane_crosswind[hexident] = airplane_info
              if airplane_upwind[hexident]
               airplane_upwind.delete(hexident)
              end
            elsif inside?(downwind, airplane_position)
              puts "DOWNWIND - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "downwind", :altitude => alt.to_s}))
              airplane_downwind[hexident] = airplane_info
              if airplane_crosswind[hexident]
               airplane_crosswind.delete(hexident)
              end
            elsif inside?(base, airplane_position)
              puts "BASE - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "base", :altitude => alt.to_s}))
              airplane_base[hexident] = airplane_info
              if airplane_downwind[hexident]
               airplane_downwind.delete(hexident)
              end
            elsif inside?(final, airplane_position)
              puts "FINAL - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "final", :altitude => alt.to_s}))
              airplane_final[hexident] = airplane_info
              if airplane_base[hexident]
               airplane_base.delete(hexident)
              end
            elsif inside?(overhead, airplane_position)
              puts "OVERHEAD - ID:"+hexident+" ALT:"+alt
              @redis.publish(CHANNEL, JSON.generate({:who => hexident.to_s, :traffic_leg => "overhead", :altitude => alt.to_s}))
            end    
        
        	end
          
        end
        
        puts "Upwind"
        puts airplane_upwind
        puts "Crosswind"
        puts airplane_crosswind
        puts "Downwind"
        puts airplane_downwind
        puts "Base"
        puts airplane_base
        puts "Final"
        puts airplane_final
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
