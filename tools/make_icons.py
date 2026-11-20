#!/usr/bin/env python3
"""生成 NetCove 应用图标（原创图形：海湾 + 波形），输出 iOS 所需全部尺寸。"""
import os, math
from PIL import Image, ImageDraw, ImageFilter

OUT = "Resources/Assets.xcassets/AppIcon.appiconset"
S = 1024

def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        # 非线性插值，靠近底部更深
        t = t ** 0.85
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (size, y)], fill=c)
    return img

def main():
    os.makedirs(OUT, exist_ok=True)
    # 深海青 -> 午夜蓝
    img = gradient(S, (18, 60, 84), (8, 18, 38)).convert("RGBA")

    # 柔光
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([S*0.08, S*0.02, S*0.92, S*0.72], fill=(64, 196, 200, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img = Image.alpha_composite(img, glow)

    # 月/日
    moon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    md = ImageDraw.Draw(moon)
    md.ellipse([S*0.60, S*0.13, S*0.60+S*0.16, S*0.13+S*0.16], fill=(232, 246, 240, 235))
    moon = moon.filter(ImageFilter.GaussianBlur(2))
    img = Image.alpha_composite(img, moon)

    # 三层波浪（海湾）
    def wave(y0, amp, color, alpha):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        pts = []
        for x in range(0, S + 8, 8):
            t = x / S
            y = y0 + math.sin(t * math.pi * 1.6 + 0.4) * amp
            pts.append((x, y))
        pts += [(S, S), (0, S)]
        d.polygon(pts, fill=color + (alpha,))
        return layer

    img = Image.alpha_composite(img, wave(S*0.58, S*0.035, (86, 214, 206), 235))
    img = Image.alpha_composite(img, wave(S*0.68, S*0.045, (34, 132, 160), 240))
    img = Image.alpha_composite(img, wave(S*0.80, S*0.030, (12, 40, 66), 255))

    # 圆角（iOS 会自己裁，这里给个圆角视觉版给文档用）
    flat = img.convert("RGB")
    flat.save(os.path.join(OUT, "icon-1024.png"), "PNG")

    sizes = [(20,"2x",40),(20,"3x",60),(29,"2x",58),(29,"3x",87),
             (40,"2x",80),(40,"3x",120),(60,"2x",120),(60,"3x",180),
             (76,"1x",76),(76,"2x",152),(83.5,"2x",167),(1024,"1x",1024)]
    for base, scale, px in sizes:
        if px == 1024: continue
        name = f"icon-{px}.png"
        flat.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name), "PNG")
    print("icons written to", OUT)

main()
