import time
import board
import busio
import digitalio
from PIL import Image, ImageDraw, ImageFont

import adafruit_tca9548a
import adafruit_ssd1306

# Create I2C bus as normal
i2c = busio.I2C(board.SCL, board.SDA)

# Create the TCA9548A object and give it the I2C bus
tca = adafruit_tca9548a.TCA9548A(i2c)

rwy_font = ImageFont.truetype('/home/pi/in-the-pattern/oled/16x8pxl-mono.ttf', 72)
tail_font = ImageFont.truetype('/home/pi/in-the-pattern/oled/16x8pxl-mono.ttf', 38)


# multiplexer index for each OLED
pattern_leg = {}
pattern_leg['upwind'] = 2
pattern_leg['crosswind'] = 3
pattern_leg['downwind'] = 4
pattern_leg['base'] = 5
pattern_leg['final'] = 6

tail_number = "N99WWW"

for leg in pattern_leg.keys():
    leg_name = adafruit_ssd1306.SSD1306_I2C(128, 32, tca[pattern_leg[leg]])
    W, H = (leg_name.width, leg_name.height)
    leg_name.fill(0)
    leg_name.show()
    tail_number_img = Image.new("1", (W, H))
    draw_tail_number = ImageDraw.Draw(tail_number_img)
    w, h = draw_tail_number.textsize(tail_number, font=tail_font) #Figure out the height and width of tail number so we can center it
    draw_tail_number.text(((W-w)/2,(H-h)/2), tail_number, font=tail_font, fill=255)
    leg_name.image(tail_number_img)
    leg_name.show()

# multiplexer index for runway number OLEDs
runway = {}
runway['appch'] = 0
runway['dep'] = 1

# Runway Names
rwy_number = {}
rwy_number['appch'] = "28L"
rwy_number['dep'] = "10R"

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