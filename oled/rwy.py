# rwy.py
# Runway Numbers
# Display the approach and departure runway numbers

import sys, getopt
import time
import board
import busio
import digitalio
from PIL import Image, ImageDraw, ImageFont

import adafruit_tca9548a
import adafruit_ssd1306


def main(argv):
    i2c = busio.I2C(board.SCL, board.SDA)
    
    # Create the TCA9548A object and give it the I2C bus
    tca = adafruit_tca9548a.TCA9548A(i2c)
    rwy_font = ImageFont.truetype('/home/pi/in-the-pattern/oled/16x8pxl-mono.ttf', 72)
    
    # multiplexer index for runway number OLEDs
    runway = {}
    runway['appch'] = 0
    runway['dep'] = 1
    
    input_appch = ''
    input_dep = ''
    clear_oled = "false"    
    
    try:
        opts, args = getopt.getopt(argv,"ha:d:c:",["approach=","departure=","clear="])
    except getopt.GetoptError:
        print('rwy.py -a <approach runway number 1-2 digit> -d <departure runway number 1-2 digit>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print('rwy.py -a <approach runway number 1-2 digit> -d <departure runway number 1-2 digit>')
            sys.exit()
        elif opt in ("-a", "--approach"):
            input_appch = arg
        elif opt in ("-d", "--departure"):
            input_dep = arg
        elif opt in ("-c", "--clear"):
            clear_oled = arg
    
    # Runway Names
    rwy_number = {}
    rwy_number['appch'] = input_appch
    rwy_number['dep'] = input_dep

    for rwy in runway.keys():
        rwy_name = adafruit_ssd1306.SSD1306_I2C(128, 64, tca[runway[rwy]])
        W, H = (rwy_name.width, rwy_name.height)
        rwy_name.fill(0)
        rwy_name.show()
        rwy_img = Image.new("1", (W, H))
        draw_rwy = ImageDraw.Draw(rwy_img)
        w, h = draw_rwy.textsize(rwy_number[rwy], font=rwy_font) #Figure out the height and width of runway number so we can center it
        draw_rwy.text(((W-w)/2,(H-h)/2), rwy_number[rwy], font=rwy_font, fill=255)
        rwy_name.image(rwy_img)
        rwy_name.show()    
        if clear_oled == "true" :
            rwy_name.fill(0)
            rwy_name.show()
    
if __name__ == "__main__":
    main(sys.argv[1:])