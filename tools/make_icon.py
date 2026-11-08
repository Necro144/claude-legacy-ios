# Draws the app icon: an orange tile with a cream starburst.
import math
from PIL import Image, ImageDraw

S = 2048
img = Image.new("RGB", (S, S), (217, 119, 87))
d = ImageDraw.Draw(img)
c = S / 2
lengths = [0.40, 0.31, 0.37, 0.29, 0.40, 0.33, 0.38, 0.30, 0.41, 0.32, 0.37, 0.30]
n = len(lengths)
for i, L in enumerate(lengths):
    a = math.radians(i * 360 / n - 90)
    r = L * S
    w = 0.036 * S
    tip = (c + r * math.cos(a), c + r * math.sin(a))
    p = a + math.pi / 2
    left = (c + w * math.cos(p), c + w * math.sin(p))
    right = (c - w * math.cos(p), c - w * math.sin(p))
    d.polygon([tip, left, right], fill=(250, 244, 236))
d.ellipse([c - 0.05 * S, c - 0.05 * S, c + 0.05 * S, c + 0.05 * S], fill=(250, 244, 236))
img.resize((1024, 1024), Image.LANCZOS).save("ClaudeLegacy/Assets.xcassets/AppIcon.appiconset/icon.png")
