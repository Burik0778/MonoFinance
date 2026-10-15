"""Генерирует иконку MONO 1024×1024 (без прозрачности): графитовый фон с мягким светом сверху
и три строки выписки, от яркой к тусклой, — история операций, сведённая к сути."""
import sys
import numpy as np
from PIL import Image, ImageDraw

S = 1024
SS = 3  # суперсэмплинг для гладких краёв
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"

# Фон: радиальный графит — светлее у верхней трети, к краям почти чёрный.
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
r = np.sqrt((xx - S * 0.5) ** 2 + (yy - S * 0.28) ** 2) / (S * 0.85 * 1.414)
stops = [(0.0, (0x26, 0x27, 0x2B)), (0.55, (0x12, 0x12, 0x14)), (1.0, (0x05, 0x05, 0x06))]
bg = np.zeros((S, S, 3), np.float32)
for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
    t = np.clip((r - p0) / (p1 - p0), 0, 1)[..., None]
    inside = ((r >= p0) & (r <= p1))[..., None] if p0 > 0 else (r <= p1)[..., None]
    bg = np.where(inside, np.array(c0, np.float32) * (1 - t) + np.array(c1, np.float32) * t, bg)
bg = np.where((r > 1.0)[..., None], np.array(stops[-1][1], np.float32), bg)
base = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB").resize((S * SS, S * SS), Image.BICUBIC)

# Строки: верхняя — серебро с вертикальным градиентом, ниже — белый с прозрачностью 62% и 30%.
bars = Image.new("RGBA", base.size, (0, 0, 0, 0))
draw = ImageDraw.Draw(bars)
x, h = 282, 56
for y, width, alpha in [(352, 460, 255), (484, 340, 158), (616, 220, 77)]:
    draw.rounded_rectangle([x * SS, y * SS, (x + width) * SS, (y + h) * SS], radius=h * SS // 2, fill=(255, 255, 255, alpha))
# Серебро верхней строки: от белого к #BFC1C6.
top = np.array(bars)
y0, y1 = 352 * SS, (352 + h) * SS
shade = np.linspace([255, 255, 255], [0xBF, 0xC1, 0xC6], y1 - y0)[:, None, :]
top[y0:y1, :, :3] = np.where(top[y0:y1, :, 3:4] > 0, shade, top[y0:y1, :, :3])
bars = Image.fromarray(top.astype(np.uint8), "RGBA")

im = Image.alpha_composite(base.convert("RGBA"), bars).convert("RGB").resize((S, S), Image.LANCZOS)
im.save(out, optimize=True)
print("saved", out, im.size, im.mode)
