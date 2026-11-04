#!/usr/bin/env python3
"""Prepares the Gemini artwork for scripts/make-gemini-mockups.mjs.

Each framed image is 688x1529 (0.450) — narrower than Play accepts — and
carries an iOS status bar with a battery percentage plus a baked-in headline
("Full-Scale Trading Journal and Performance Analytics" sits on the Desk,
Journal and Calendar screens alike). This script:

  * drops the status bar and that headline (everything above the phone),
  * extends the bottom edge so the feather does not eat the home indicator,
  * upscales to the size the canvas will show it at,
  * feathers the left/right/top edges into a blurred, darkened copy of the same
    scene, which is where the 1080x1920 canvas comes from.

Run from the project root, then:  node scripts/make-gemini-mockups.mjs
"""

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import os

DOWNLOAD = "C:/Users/JeyMTLL/Downloads"
OUT = "store/.gemini"

# Everything above the phone bezel: iOS status bar + the generated headline.
HEAD_TOP = 330
ART_HEIGHT = 1500
CANVAS = (1080, 1920)

# Filename -> what the phone inside actually shows.
slides = {
    "01-journal": "Gemini_Generated_Image_yk46yhyk46yhyk46.jpg",
    "02-desk": "Gemini_Generated_Image_ocbhj5ocbhj5ocbh.jpg",
    "04-chart-levels": "Gemini_Generated_Image_inj1uminj1uminj1.jpg",
    "05-calendar": "Gemini_Generated_Image_34o9jq34o9jq34o9.jpg",
}

BACKDROP_SOURCE = "02-desk"


def cover(im, size):
    """Scale to fill size, then centre-crop the overflow."""
    tw, th = size
    ratio = max(tw / im.width, th / im.height)
    scaled = im.resize((round(im.width * ratio), round(im.height * ratio)), Image.LANCZOS)
    left = (scaled.width - tw) // 2
    top = (scaled.height - th) // 2
    return scaled.crop((left, top, left + tw, top + th))


def feather(im, side=130, top=60, bottom=60, blur=50):
    mask = Image.new("L", im.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle([side, top, im.width - side, im.height - bottom], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(blur))
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def backdrop(art):
    """Blurred, darkened copy of the phone scene, filling one whole screen."""
    bg = cover(art, CANVAS).filter(ImageFilter.GaussianBlur(52))
    bg = ImageEnhance.Brightness(bg).enhance(0.52)
    return ImageEnhance.Color(bg).enhance(1.15)


def main():
    os.makedirs(OUT, exist_ok=True)
    backdrops = {}

    for name, filename in slides.items():
        source = Image.open(os.path.join(DOWNLOAD, filename)).convert("RGB")
        art = source.crop((0, HEAD_TOP, source.width, source.height))

        # Repeat the last row so the bottom feather lands on backdrop, not on
        # the home indicator, which sits only ~60px up from the crop edge.
        pad = 110
        padded = Image.new("RGB", (art.width, art.height + pad))
        padded.paste(art, (0, 0))
        padded.paste(art.crop((0, art.height - 1, art.width, art.height)).resize((art.width, pad)), (0, art.height))

        scale = ART_HEIGHT / padded.height
        padded = padded.resize((round(padded.width * scale), ART_HEIGHT), Image.LANCZOS)
        padded = padded.filter(ImageFilter.UnsharpMask(radius=2, percent=40, threshold=2))

        feather(padded).save(os.path.join(OUT, f"{name}-art.png"))
        backdrops[name] = backdrop(art)
        print(f"{name}  art {padded.width}x{padded.height}")

    # Every frame shares one scene, so the analytics slide borrows a backdrop
    # from the framed artwork instead of growing a fake one of its own.
    backdrops[BACKDROP_SOURCE].save(os.path.join(OUT, "03-analytics-bg.jpg"), "JPEG", quality=88)
    for name, bg in backdrops.items():
        bg.save(os.path.join(OUT, f"{name}-bg.jpg"), "JPEG", quality=88)

    # Gemini only returned the analytics screen bare, with the status bar
    # overlapping the page title. Crop below both; the CSS screen centre-crops
    # the 3% of width that buys.
    shot = Image.open("store/screenshots/03-analytics.jpg").convert("RGB")
    screen = shot.crop((0, 150, 1080, 1920))
    screen = screen.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))
    screen.save(os.path.join(OUT, "03-analytics-screen.jpg"), "JPEG", quality=92)
    print(f"03-analytics  screen {screen.width}x{screen.height}")


if __name__ == "__main__":
    main()
