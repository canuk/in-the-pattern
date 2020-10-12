# aip.py
# Airplane In Pattern!
# Display tail number in the correct leg in pattern.

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
    tail_font = ImageFont.truetype('16x8pxl-mono.ttf', 38)

    # multiplexer index for each OLED
    pattern_leg = {}
    pattern_leg['upwind'] = 2
    pattern_leg['crosswind'] = 3
    pattern_leg['downwind'] = 4
    pattern_leg['base'] = 5
    pattern_leg['final'] = 6
    
    input_leg = ''
    input_tail = ''
    clear_oled = "false"

    try:
        opts, args = getopt.getopt(argv,"hl:t:c:",["leg=","tail=","clear="])
    except getopt.GetoptError:
        print('aip.py -l <pattern leg> -t <tail number>\nAcceptable pattern legs are upwind, crosswind, downwind, base, or final')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print('aip.py -l <pattern leg> -t <tail number>\nAcceptable pattern legs are upwind, crosswind, downwind, base, or final')
            sys.exit()
        elif opt in ("-l", "--leg"):
            input_leg = arg
        elif opt in ("-t", "--tail"):
            input_tail = arg
        elif opt in ("-c", "--clear"):
            clear_oled = arg
    
    tail_number = input_tail
    
    leg = input_leg
    leg_name = adafruit_ssd1306.SSD1306_I2C(128, 32, tca[pattern_leg[leg]])
    if clear_oled == "leg" :
        leg_name.fill(0)
        leg_name.show()
        sys.exit()
    if clear_oled == "all" :    
        for leg in pattern_leg.keys():
            leg_name = adafruit_ssd1306.SSD1306_I2C(128, 32, tca[pattern_leg[leg]])
            leg_name.fill(0)
            leg_name.show()
            sys.exit()
                
    W, H = (leg_name.width, leg_name.height)
    leg_name.fill(0)
    leg_name.show()
    tail_number_img = Image.new("1", (W, H))
    draw_tail_number = ImageDraw.Draw(tail_number_img)
    w, h = draw_tail_number.textsize(tail_number, font=tail_font) #Figure out the height and width of tail number so we can center it
    draw_tail_number.text(((W-w)/2,(H-h)/2), tail_number, font=tail_font, fill=255)
    leg_name.image(tail_number_img)
    leg_name.show()

if __name__ == "__main__":
    main(sys.argv[1:])