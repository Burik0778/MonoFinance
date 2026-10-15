"""Генерирует иконку MONO 1024×1024 (без прозрачности): «голосовая сфера» из трёх световых лепестков на полуночном фоне."""
import math
import sys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"

yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
cx, cy = S / 2, S / 2

# Фон: глубокий полуночный градиент с лёгким виньетированием.
top = np.array([0x0B, 0x10, 0x24], np.float32) / 255
bottom = np.array([0x03, 0x05, 0x0C], np.float32) / 255
t = (yy / S)[..., None]
img = top * (1 - t) + bottom * t
r = np.sqrt((xx - cx) ** 2 + (yy - cy * 0.95) ** 2) / (S * 0.75)
img *= (1 - 0.35 * np.clip(r, 0, 1) ** 2)[..., None]

def blob(color, ox, oy, radius, wobble_phase, strength):
    """Мягкий лепесток: искажённая окружность с гауссовым краем."""
    angle = np.arctan2(yy - (cy + oy), xx - (cx + ox))
    dist = np.sqrt((xx - (cx + ox)) ** 2 + (yy - (cy + oy)) ** 2)
    wobble = 1 + 0.07 * np.sin(3 * angle + wobble_phase) + 0.04 * np.sin(5 * angle - wobble_phase * 0.8)
    edge = radius * wobble
    falloff = np.exp(-np.clip(dist - edge * 0.42, 0, None) ** 2 / (2 * (radius * 0.24) ** 2))
    return np.array(color, np.float32)[None, None, :] / 255 * (falloff * strength)[..., None]

glow = np.zeros_like(img)
glow += blob((0x41, 0x70, 0xFF), -86, 50, 250, 0.0, 1.15)   # electric
glow += blob((0x8F, 0x63, 0xFF), 88, 44, 240, 2.1, 1.15)    # violet
glow += blob((0x33, 0xDA, 0xF5), 0, -86, 225, 4.2, 0.95)    # cyan

# Аддитивное смешение (как plusLighter) с мягким тонмаппингом.
img = img + glow
img = 1 - np.exp(-img * 1.05)

# Яркое ядро.
core_d = np.sqrt((xx - cx) ** 2 + (yy - (cy - 6)) ** 2)
core = np.exp(-(core_d ** 2) / (2 * 54 ** 2))
img = img + core[..., None] * np.array([1.0, 1.0, 1.0], np.float32) * 0.5
img = np.clip(img, 0, 1)

# Тонкие «гравированные» дуги — фирменный мотив виртуальных карт.
arcs = np.zeros((S, S), np.float32)
for k, rad in enumerate([380, 416, 452]):
    d = np.abs(np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) - rad)
    ang = np.arctan2(yy - cy, xx - cx)
    mask = ((ang > -2.6) & (ang < -0.5)).astype(np.float32)  # верхняя дуга
    arcs += np.exp(-(d ** 2) / (2 * 1.4 ** 2)) * mask * (0.34 - k * 0.09)
img = np.clip(img + arcs[..., None] * np.array([0.75, 0.82, 1.0], np.float32), 0, 1)

im = Image.fromarray((img * 255).astype(np.uint8), "RGB")
im = im.filter(ImageFilter.GaussianBlur(0.6))
im.save(out, optimize=True)
print("saved", out, im.size, im.mode)
