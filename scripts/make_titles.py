"""Generate Japanese title overlays (1080x1920, RGBA PNG) for the reel."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1920
BUILD = Path(__file__).resolve().parent.parent / "build" / "titles"
BUILD.mkdir(parents=True, exist_ok=True)

SERIF_BOLD = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc"
SERIF_REG = "/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def draw_centered(draw: ImageDraw.ImageDraw, text: str, f: ImageFont.FreeTypeFont,
                  cy: int, fill=(255, 255, 255, 255), letter_spacing: int = 0):
    if letter_spacing == 0:
        bbox = draw.textbbox((0, 0), text, font=f)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        x = (W - tw) // 2 - bbox[0]
        y = cy - th // 2 - bbox[1]
        draw.text((x, y), text, font=f, fill=fill)
        return
    widths = []
    for ch in text:
        b = draw.textbbox((0, 0), ch, font=f)
        widths.append(b[2] - b[0])
    total = sum(widths) + letter_spacing * (len(text) - 1)
    x = (W - total) // 2
    bbox = draw.textbbox((0, 0), "あ", font=f)
    th = bbox[3] - bbox[1]
    y = cy - th // 2 - bbox[1]
    for ch, w in zip(text, widths):
        b = draw.textbbox((0, 0), ch, font=f)
        draw.text((x - b[0], y), ch, font=f, fill=fill)
        x += w + letter_spacing


def hairline(draw, cy, length=180, fill=(255, 255, 255, 200)):
    x0 = (W - length) // 2
    draw.rectangle([x0, cy, x0 + length, cy + 2], fill=fill)


def draw_offset(draw, text, f, cy, offset_x=0, fill=(255, 255, 255, 255), letter_spacing=0):
    """draw_centered と同じだが、横位置に offset_x を加える。"""
    widths = []
    for ch in text:
        b = draw.textbbox((0, 0), ch, font=f)
        widths.append(b[2] - b[0])
    total = sum(widths) + letter_spacing * (len(text) - 1)
    x = (W - total) // 2 + offset_x
    bbox = draw.textbbox((0, 0), "あ", font=f)
    th = bbox[3] - bbox[1]
    y = cy - th // 2 - bbox[1]
    for ch, w in zip(text, widths):
        b = draw.textbbox((0, 0), ch, font=f)
        draw.text((x - b[0], y), ch, font=f, fill=fill)
        x += w + letter_spacing


def make_title():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f_top = font(SERIF_REG, 56)
    f_main = font(SERIF_BOLD, 80)
    f_sub = font(SERIF_REG, 44)
    draw_centered(d, "五月  月替わりコース", f_top, H // 2 - 220, letter_spacing=12)
    hairline(d, H // 2 - 130)
    draw_offset(d, "旬を、極める。", f_main, H // 2 + 20, offset_x=120, letter_spacing=18)
    hairline(d, H // 2 + 130)
    draw_centered(d, "S E A S O N A L   K A I S E K I", f_sub,
                  H // 2 + 220, fill=(220, 200, 160, 230), letter_spacing=8)
    img.save(BUILD / "01_title.png")


def make_caption(filename: str, lines: list[tuple[str, int, str]]):
    """lines: list of (text, font_size, style) where style in {bold, regular}."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    total_h = sum(sz + 24 for _, sz, _ in lines)
    y = H - 360 - total_h // 2
    for text, sz, style in lines:
        f = font(SERIF_BOLD if style == "bold" else SERIF_REG, sz)
        draw_centered(d, text, f, y + sz // 2, letter_spacing=10)
        y += sz + 24
    img.save(BUILD / filename)


def make_outro():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f_jp = font(SERIF_BOLD, 78)
    f_sub = font(SERIF_REG, 40)
    draw_centered(d, "ご予約は下記QRコードより", f_jp, 240, letter_spacing=10)
    hairline(d, 320, length=220)
    draw_centered(d, "R E S E R V A T I O N", f_sub, 380,
                  fill=(220, 200, 160, 230), letter_spacing=10)
    img.save(BUILD / "99_outro.png")


def make_brand_lower():
    """Persistent brand strip (small), top-left of every frame."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(SERIF_BOLD, 40)
    f_en = font(SERIF_REG, 24)
    d.text((60, 60), "大嵓埜", font=f, fill=(255, 255, 255, 230))
    d.text((62, 116), "O K U R A N O", font=f_en, fill=(220, 200, 160, 220))
    img.save(BUILD / "brand.png")


def make_vignette():
    """Vignette + bottom gradient overlay for legibility & luxury feel."""
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    cx, cy = W / 2, H / 2
    maxd = (cx ** 2 + cy ** 2) ** 0.5
    for y in range(H):
        for x in range(W):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd
            v = max(0, d - 0.55) / 0.45
            a = int(min(180, v * 220))
            grad_bottom = max(0, (y - H * 0.65) / (H * 0.35))
            ab = int(min(160, grad_bottom * 200))
            alpha = max(a, ab)
            if alpha:
                px[x, y] = (0, 0, 0, alpha)
    img.save(BUILD / "vignette.png")


if __name__ == "__main__":
    make_title()
    make_caption("02_cap_shun.png", [
        ("旬の鮮魚を、", 92, "bold"),
        ("確かな腕で。", 92, "bold"),
    ])
    make_caption("03_cap_zukuri.png", [
        ("造  里", 132, "bold"),
        ("S A S H I M I", 44, "regular"),
    ])
    make_caption("04_cap_chouri.png", [
        ("仕  込  み", 120, "bold"),
        ("P R E P A R A T I O N", 44, "regular"),
    ])
    make_outro()
    make_brand_lower()
    make_vignette()
    print("titles generated:", sorted(p.name for p in BUILD.iterdir()))
