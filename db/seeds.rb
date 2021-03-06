Airport.create(name: "Hemet-Ryan Airport", 
               identifier: "KHMT", 
               lat: 33.7301, 
               lng: -117.0222, 
               field_elevation: 1513,
               overhead: "[[33.787192,-117.083074], [33.788048,-116.950208], [33.674409,-116.952611], [33.674695,-117.089941]]",
               upwind: "[[33.731881,-117.024530], [33.720102,-117.052339], [33.723814,-117.054914], [33.733451,-117.025646]]", 
               crosswind: "[[33.711463,-117.049850], [33.715033,-117.040323], [33.723386,-117.043327], [33.720316,-117.054056]]", 
               downwind: "[[33.734815,-116.994328], [33.711605,-117.049946], [33.703894,-117.043423], [33.726883,-116.983342]]", 
               base: "[[33.739739,-117.004327], [33.742309,-116.998319], [33.734208,-116.994371], [33.732066,-117.000679]]", 
               final: "[[33.734574,-117.021013], [33.734003,-117.020712], [33.741488,-117.000894], [33.742345,-117.002182]]", 
               approach_rwy: 23, 
               departure_rwy: 5, 
               left_pattern: true,
               created_at: Time.now, 
               updated_at: Time.now)
               
Airport.create(name: "Montgomery-Gibbs Executive Airport 28R", 
               identifier: "KMYF", 
               lat: 32.8157222, 
               lng: -117.1395556, 
               field_elevation: 427,
               overhead: "[[32.842639,-117.083534], [32.840188,-117.098126], [32.840476,-117.127651], [32.839899,-117.136578], [32.836582,-117.155461], [32.837159,-117.159924], [32.844947,-117.170567], [32.846389,-117.177433], [32.843505,-117.196316], [32.787096,-117.195458], [32.785797,-117.040447], [32.846389,-117.040447], [32.850860,-117.042507], [32.853600,-117.064652], [32.848552,-117.074093]]",
               upwind: "[[32.815233,-117.138262], [32.829622,-117.171688], [32.831641,-117.169628], [32.815990,-117.137528]]", 
               crosswind: "[[32.834779,-117.160835], [32.837627,-117.163534], [32.831641,-117.169628], [32.829983,-117.165337]]", 
               downwind: "[[32.808164,-117.096634], [32.825890,-117.153387], [32.831687,-117.153783], [32.837771,-117.163277], [32.839646,-117.160788], [32.813970,-117.091952]]", 
               base: "[[32.810724,-117.120791], [32.803149,-117.100535], [32.810147,-117.096071], [32.817432,-117.115641]]", 
               final: "[[32.814908,-117.133322], [32.800119,-117.093411], [32.797089,-117.095556], [32.813393,-117.134695]]", 
               approach_rwy: "28R", 
               departure_rwy: "10L", 
               left_pattern: false,
               created_at: Time.now, 
               updated_at: Time.now)               
  
Setting.create(airport_id: 1, 
               use_1090dump: true, 
               ip_1090dump: '192.168.0.137',
               port_1090dump: 30003,
               updated_at: Time.now)
               
Arrival.create(airport_id: 1, 
               tail_number: 'N182DV', 
               aircraft_type: 'C182',
               arrived_at: Time.now - 1.hour) 
               
Departure.create(airport_id: 1, 
               tail_number: 'N182DV', 
               aircraft_type: 'C182',
               departed_at: Time.now)                              