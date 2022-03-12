# In The Pattern

A webserver that connects to your local [PiAware](https://flightaware.com/adsb/piaware/build) or [Dump1090](https://github.com/antirez/dump1090) you can see in real-time who is in your local traffic pattern.

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

Copy `env.sample` to `.env` to get started.
`cp env.sample .env`

Boot the app with foreman.
 
```
$ foreman start
```

Visit <http://localhost:5000> to see the application.

## How to Set up your Raspberry Pi
 - Grab a Raspbian Lite Image (Tested with Buster)
 - Setup CLI/Autologin
 - Setup WiFi Network
 - Setup Interfacing Options: SSH, I2C
 - Setup Timezone, Locale, Keyboard
 
Copy ITP config.txt file over.
`sudo cp rpi/system_files/config.txt /boot/config.txt` (Will rotate display and set up the proper size)

Install git and Ruby (Python3 is already on the Lite Image)
```
sudo apt-get install -y git
sudo apt-get install -y ruby-full
```

Install x-windows so we can run a lightweight browser to display the arrivals [link](https://die-antwort.eu/techblog/2017-12-setup-raspberry-pi-for-kiosk-mode/)
```
sudo apt-get install --no-install-recommends xserver-xorg x11-xserver-utils xinit openbox
sudo apt-get install surf
sudo rm /etc/xdg/openbox/autostart
sudo cp rpi_system_files/openbox.autostart /etc/xdg/openbox/autostart
# copy ITP openbox config file over so that Surf will start in fullscreen mode
sudo rm /etc/xdg/openbox/rc.xml
sudo cp rpi_system_files/openbox.rc.xml /etc/xdg/openbox/rc.xml
# Now append to .bash_profile to start X automatically on boot.
echo '[[ -z $DISPLAY && $XDG_VTNR -eq 1 ]] && startx -- -nocursor' >>~/.bash_profile
```

Trying out Surf browser from Suckless because Chrome keeps wanting to upgrade to latest version
OK, not what I was hoping for. There must be some way to remove the chrome and make the window fullscreen automatically...
```
sudo apt-get install surf
```

Trying out Midori, surf seems to overheat the pi
https://maker-tutorials.com/en/auto-start-midori-browser-in-fullscreen-kiosk-modus-raspberry-pi-linux/#midori-full-screen-autostart

sudo apt-get install -y midori matchbox
sudo apt-get install -y unclutter


Install Python Libraries
```
sudo apt install -y python3-dev
sudo apt install -y i2c-tools python3-pil python3-pip python3-setuptools python3-rpi.gpio
sudo pip3 install smbus2
   
sudo pip3 install adafruit-circuitpython-tca9548a
sudo pip3 install adafruit-circuitpython-ssd1306

## I Don't think we need these as they are installed with the stuff above
#sudo pip3 install Adafruit-Blinka
#sudo pip3 install RPI.GPIO

sudo apt-get install -y libmagickwand-dev imagemagick
```
   
Install Ruby gems
First install sqlite3
`apt-get install libsqlite3-dev`
`sudo gem install bundler`
`sudo gem install foreman`

Setup [Redis](https://habilisbest.com/install-redis-on-your-raspberrypi)

Grab the repo from Github
`git clone https://github.com/canuk/in-the-pattern.git`
`bundle install`

Copy `.env.sample` to `.env` to get started.
`cp env.sample .env`

`nano .env`
change to `PI=true`

Seed the database with default values:
`bundle exec rake db:seed`

Copy the in-the-pattern.service to `/etc/systemd/system/in-the-pattern.service`
`sudo cp in-the-pattern.service /etc/systemd/system/in-the-pattern.service`
`sudo systemctl start in-the-pattern.service`

Check to make sure it's working
`systemctl status in-the-pattern.service`

Make it run on boot:
`sudo systemctl enable in-the-pattern.service`


Calibrate Touch Screen
install xi
```
sudo apt-get install libx11-dev libxext-dev libxi-dev x11proto-input-dev 
wget http://github.com/downloads/tias/xinput_calibrator/xinput_calibrator-0.7.5.tar.gz
tar -zxvf xinput_calibrator*.tar.gz
./configure
make
sudo make install 
```

`sudo nano /usr/share/X11/xorg.conf.d/40-libinput.conf`
Under the Section
```
Section "InputClass"
    Identifier "libinput touchscreen catchall"
```
add the line: `Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"`
This will switch the orientation for the touch screen so it matches the vertical layout. Then the touchscreen section should look like this:

```
Section "InputClass"
    Identifier "libinput touchscreen catchall"
    MatchIsTouchScreen "on"
    MacthDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "TransformationMatrix" "0 1 0 -1 0 1 0 0 1"
EndSection
```

With Chrome (on X11) running on the pi, from the terminal (either ssh in or ctrl-alt-F2 to get a different session and then ctrl-alt-F1 to go back) type `DISPLAY=:0 xinput_calibrator` and then you'll get the calibrator.
After you've calibrated it, Copy the output and then put it into the `99-calibration.conf`
```
sudo mkdir /etc/X11/xorg.conf.d/
sudo nano /etc/X11/xorg.conf.d/99-calibration.conf
```

Install Boot Splash Screen
```
sudo apt-get install fbi
sudo cp in-the-pattern-splash.png /etc/splash.png
sudo cp asplashscreen.service /etc/systemd/system/asplashscreen.service
sudo systemctl enable asplashscreen.service
```

Install mDNS (to access the Pi using Bonjour)
```
sudo apt-get install avahi-daemon
```

Now change the hostname (change `raspberrypi` to `inthepattern`)
```
sudo nano /etc/hosts
sudo nano /etc/hostname
```

Install nginx so we can access at inthepattern.local without a port number
```
sudo apt update
sudo apt install -y nginx
sudo rm /etc/nginx/sites-enabled/default
sudo cp rpi_system_files/nginx.sites-enabled.default /etc/nginx/sites-enabled/default
// Start on Boot
sudo update-rc.d -f nginx defaults;
```

Now you can access the server at http://inthepattern.local

(c) 2020 Reuben Thiessen
