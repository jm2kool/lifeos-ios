"""Draws the still layers for the Matinee promo: the phone's screen mask and bezel, captions and the end card."""
import os
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1080, 1920
SW, SH = 718, 1560          # phone screen on the canvas (1206 x 2622 recording, scaled)
SX, SY = (W - SW) // 2, 316
R = 92                      # screen corner radius
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
SERIF = os.path.join(FONTS, "InstrumentSerif-Regular.ttf")         # headlines: a film-poster serif
SERIF_IT = os.path.join(FONTS, "InstrumentSerif-Italic.ttf")
SANS = os.path.join(FONTS, "Manrope[wght].ttf")                     # small lines


def sans(size, weight="SemiBold"):
    f = ImageFont.truetype(SANS, size)
    f.set_variation_by_name(weight)
    return f


def tracked(d, xy, text, font, fill, track=0.14):
    """Centred small caps with letter-spacing (a fraction of the font size)."""
    gap = font.size * track
    width = sum(d.textlength(c, font=font) for c in text) + gap * (len(text) - 1)
    x, y = xy[0] - width / 2, xy[1] + font.getmetrics()[0]
    for c in text:
        d.text((x, y), c, font=font, anchor="ls", fill=fill)   # on the baseline, so punctuation sits right
        x += d.textlength(c, font=font) + gap


def mask(out):
    m = Image.new("L", (SW, SH), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, SW - 1, SH - 1], R, fill=255)
    m.save(out)


def bezel(out):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    b = 14
    ImageDraw.Draw(shadow).rounded_rectangle([SX - b, SY - b + 30, SX + SW + b, SY + SH + b + 30], R + b, fill=(0, 0, 0, 170))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(40)))
    d = ImageDraw.Draw(img)
    # Black frame round the screen, with a thin titanium edge.
    d.rounded_rectangle([SX - b, SY - b, SX + SW + b, SY + SH + b], R + b, outline=(120, 120, 128, 255), width=3)
    d.rounded_rectangle([SX - b + 3, SY - b + 3, SX + SW + b - 3, SY + SH + b - 3], R + b - 3, outline=(8, 8, 10, 255), width=b - 2)
    # Cut the screen area back out (the frame must not cover it).
    hole = Image.new("L", (W, H), 255)
    ImageDraw.Draw(hole).rounded_rectangle([SX, SY, SX + SW - 1, SY + SH - 1], R, fill=0)
    a = img.getchannel("A")
    img.putalpha(Image.composite(a, Image.new("L", (W, H), 0), hole))
    img.save(out)


def caption(out, line1, line2="", accent=(255, 255, 255)):
    """A big serif headline over the top of the frame, with a small line under it in the clip's colour."""
    img = Image.new("RGBA", (W, 300), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = 112
    f1 = ImageFont.truetype(SERIF, size)
    while d.textlength(line1, font=f1) > W - 100:
        size -= 4; f1 = ImageFont.truetype(SERIF, size)
    f2 = sans(36)
    y1 = 58 if line2 else 100
    y2 = y1 + size + 14
    def draw(dr, fill1, fill2):
        dr.text((W / 2, y1), line1, font=f1, anchor="mt", fill=fill1)
        if line2: tracked(dr, (W / 2, y2), line2.upper(), f2, fill2)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw(ImageDraw.Draw(glow), (0, 0, 0, 210), (0, 0, 0, 210))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(16)))
    draw(ImageDraw.Draw(img), (255, 255, 255, 255), accent + (255,))
    img.save(out)


def endcard(out, icon):
    img = Image.new("RGB", (W, H), (0, 0, 0))
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W / 2 - 420, 520, W / 2 + 420, 1240], fill=(150, 40, 30))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(160)), 0.9)
    ic = Image.open(icon).convert("RGBA").resize((360, 360), Image.LANCZOS)
    m = Image.new("L", (360, 360), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, 359, 359], 82, fill=255)
    img.paste(ic, ((W - 360) // 2, 640), m)
    d = ImageDraw.Draw(img)
    d.text((W / 2, 1050), "Matinee", font=ImageFont.truetype(SERIF, 190), anchor="mt", fill=(255, 255, 255))
    d.text((W / 2, 1260), "Films and shows, scored out of 100.", font=ImageFont.truetype(SERIF_IT, 62), anchor="mt", fill=(255, 214, 196))
    tracked(d, (W / 2, 1370), "A FILM & TV DIARY FOR IPHONE", sans(30), (190, 190, 196), 0.2)
    img.save(out)


if __name__ == "__main__":
    out = sys.argv[1]
    mask(f"{out}/mask.png")
    bezel(f"{out}/bezel.png")
    endcard(f"{out}/end.png", sys.argv[2])
