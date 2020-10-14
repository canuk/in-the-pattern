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
Grab a Raspbian Lite Image
Setup CLI/Autologin
Setup Wifi
Setup Interfacing Options: SSH, I2C
Setup Timezone, Locale, Keyboard

Install git and Ruby (Python3 is already on the Lite Image)
```
sudo apt-get install -y git
sudo apt-get install -y ruby-full
```

Install x-window so we can run a chromeless browser to display the arrivals [link](https://die-antwort.eu/techblog/2017-12-setup-raspberry-pi-for-kiosk-mode/)
```
sudo apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox
sudo apt-get install --no-install-recommends chromium-browser

```

Install Python Libraries
```
sudo apt install -y python3-dev
sudo apt install -y python-smbus i2c-tools python3-pil python3-pip python3-setuptools python3-rpi.gpio
   
sudo pip3 install adafruit-circuitpython-tca9548a
sudo pip3 install adafruit-circuitpython-ssd1306

## I Don't think we need these as they are installed with the stuff above
#sudo pip3 install Adafruit-Blinka
#sudo pip3 install RPI.GPIO

sudo apt-get install -y libmagickwand-dev imagemagick
```
   
Install Ruby gems
`sudo gem install bundler`

Grab the repo from Github
`bundle install`


Setup [Redis](https://habilisbest.com/install-redis-on-your-raspberrypi)
Copy the itp_live.service to `/etc/systemd/system/itp_live.service`
`sudo systemctl start itp_live.service`

Make it run on boot:
`sudo systemctl enable itp_live.service`


`bundle exec rake db:seed`

