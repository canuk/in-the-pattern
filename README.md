# In The Pattern

A cool website that connects to your local [PiAware](https://flightaware.com/adsb/piaware/build) or [Dump1090](https://github.com/antirez/dump1090) you can see in real-time who is in your local traffic pattern.

You can also build a cool wall installation. Check it out [here](https://www.inthepattern.net).

## Setup

Gems:
 - [faye-websocket](https://github.com/faye/faye-websocket-ruby)
 - [Puma](https://github.com/puma/puma)
 - [Sinatra](https://github.com/sinatra/sinatra).
 
To install all the dependencies, run:

```
$ bundle install
```

Copy `.env.sample` to `.env` to get started.

Boot the app with foreman.

```
$ foreman start
```

Visit <http://localhost:5000> to see the application.
