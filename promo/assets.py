"""Draws the still layers for the Matinee promo: the phone's screen mask and bezel, captions and the end card."""
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1080, 1920
SW, SH = 718, 1560          # phone screen on the canvas (1206 x 2622 recording, scaled)
SX, SY = (W - SW) // 2, 316
R = 92                      # screen corner radius
BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
MED = "/usr/share/fonts/opentype/inter/InterDisplay-Medium.otf"


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
    """Two lines over the top of the frame: a big bold line and a smaller one under it."""
    img = Image.new("RGBA", (W, 300), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = 84
    f1 = ImageFont.truetype(BOLD, size)
    while d.textlength(line1, font=f1) > W - 110:
        size -= 4; f1 = ImageFont.truetype(BOLD, size)
    f2 = ImageFont.truetype(MED, 46)
    y1 = 70 if line2 else 110
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.text((W / 2, y1), line1, font=f1, anchor="mt", fill=(0, 0, 0, 200))
    if line2: gd.text((W / 2, y1 + size + 22), line2, font=f2, anchor="mt", fill=(0, 0, 0, 200))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(14)))
    d = ImageDraw.Draw(img)
    d.text((W / 2, y1), line1, font=f1, anchor="mt", fill=(255, 255, 255, 255))
    if line2: d.text((W / 2, y1 + size + 22), line2, font=f2, anchor="mt", fill=accent + (255,))
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
    d.text((W / 2, 1080), "Matinee", font=ImageFont.truetype(BOLD, 120), anchor="mt", fill=(255, 255, 255))
    d.text((W / 2, 1235), "Films. Shows. Scored out of 100.", font=ImageFont.truetype(MED, 48), anchor="mt", fill=(255, 255, 255, 200))
    d.text((W / 2, 1320), "A film and TV diary for iPhone", font=ImageFont.truetype(MED, 40), anchor="mt", fill=(200, 200, 205))
    img.save(out)


if __name__ == "__main__":
    out = sys.argv[1]
    mask(f"{out}/mask.png")
    bezel(f"{out}/bezel.png")
    endcard(f"{out}/end.png", sys.argv[2])
