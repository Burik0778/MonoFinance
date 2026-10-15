"""Генерирует иконку MONO 1024×1024 (без прозрачности) в стиле «Graphite»:
чёрный фон, белое ядро и радиальная шкала — тот же мотив, что у голосового прибора в приложении."""
import math
import sys
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024
SS = 3  # суперсэмплинг для гладких краёв
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"

# Фон: графит с холодным светом сверху.
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
top = np.array([0x1A, 0x1A, 0x1D], np.float32) / 255
bottom = np.array([0x00, 0x00, 0x00], np.float32) / 255
t = (yy / S)[..., None]
bg = top * (1 - t) + bottom * t
r = np.sqrt((xx - S * 0.3) ** 2 + (yy - 0) ** 2) / (S * 0.9)
bg += (np.array([0xFF, 0xFF, 0xFF], np.float32) / 255)[None, None, :] * (0.03 * np.clip(1 - r, 0, 1) ** 2)[..., None]
base = Image.fromarray((np.clip(bg, 0, 1) * 255).astype(np.uint8), "RGB").resize((S * SS, S * SS), Image.BICUBIC)

draw = ImageDraw.Draw(base, "RGBA")
c = S * SS / 2
accent = (0xF4, 0xF4, 0xF6, 255)
tick = (0xC7, 0xC7, 0xCC)

# Радиальная шкала: 60 штрихов, каждый пятый длиннее и ярче; длина меняется плавно — «голос».
count = 60
inner = 0.30 * S * SS
for i in range(count):
    a = i / count * 2 * math.pi - math.pi / 2
    major = i % 5 == 0
    wave = 0.5 + 0.5 * math.sin(i / count * 2 * math.pi * 3 + 0.6)
    length = (0.022 + 0.05 * wave) * S * SS if not major else 0.08 * S * SS
    x1, y1 = c + math.cos(a) * inner, c + math.sin(a) * inner
    x2, y2 = c + math.cos(a) * (inner + length), c + math.sin(a) * (inner + length)
    alpha = 235 if major else int(80 + 110 * wave)
    draw.line([(x1, y1), (x2, y2)], fill=tick + (alpha,), width=int((8 if major else 5) * SS / 1.5))

# Кольцо-орбита.
ring = 0.255 * S * SS
draw.ellipse([c - ring, c - ring, c + ring, c + ring], outline=(0xFF, 0xFF, 0xFF, 70), width=int(3 * SS))

# Ядро: сплошной акцент и мягкий блик сверху.
core = 0.215 * S * SS
draw.ellipse([c - core, c - core, c + core, c + core], fill=accent)
hl = Image.new("L", base.size, 0)
ImageDraw.Draw(hl).ellipse([c - core * 0.9, c - core * 0.98, c + core * 0.9, c + core * 0.2], fill=0)
hl = hl.filter(ImageFilter.GaussianBlur(40 * SS / 3))
mask = Image.new("L", base.size, 0)
ImageDraw.Draw(mask).ellipse([c - core, c - core, c + core, c + core], fill=255)
hl = ImageChops.multiply(hl, mask)
base = Image.composite(Image.new("RGB", base.size, (255, 255, 255)), base, hl)

im = base.resize((S, S), Image.LANCZOS)
im.save(out, optimize=True)
print("saved", out, im.size, im.mode)
