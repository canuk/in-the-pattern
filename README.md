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

## On the Raspberry Pi
Install Python3
Install Ruby

Install Python Libraries
There is some version of `board` that isn't the right one, we need the one from Adafruit Blinka

```
sudo apt install -y python3-dev
sudo apt install -y python-smbus i2c-tools
sudo apt install -y python3-pil
sudo apt install -y python3-pip
sudo apt install -y python3-setuptools
sudo apt install -y python3-rpi.gpio
   
sudo pip3 install adafruit-circuitpython-ssd1306
pip3 install adafruit-circuitpython-tca9548a
pip3 uninstall board
pip3 install Adafruit-Blinka
pip3 install RPI.GPIO

sudo apt-get install libmagickwand-dev imagemagick
```
   
Install Ruby gems
`bundle install`

Setup [Redis](https://habilisbest.com/install-redis-on-your-raspberrypi)
Copy the itp_live.service to `/etc/systemd/system/itp_live.service`
`sudo systemctl start itp_live.service`

Make it run on boot:
`sudo systemctl enable itp_live.service`


`bundle exec rake db:seed`

