Airport.create(name: "Hemet-Ryan Airport", 
               identifier: "KHMT", 
               lat: 33.7301, 
               lng: 117.0222, 
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