"""Generate DMG background image for SnapDict installer."""

import math
from PIL import Image, ImageDraw, ImageFont

# Match window size at 1x — Finder displays background at native pixel size
WIDTH = 660
HEIGHT = 400

# Icon center positions (must match create-dmg --icon / --app-drop-link)
APP_X, APP_Y = 180, 170
DROP_X, DROP_Y = 480, 170


def draw_gradient(img: Image.Image) -> None:
    """Draw vertical gradient from light to slightly darker gray."""
    draw = ImageDraw.Draw(img)
    top = (0xF5, 0xF5, 0xF7)
    bottom = (0xE8, 0xE8, 0xED)
    for y in range(HEIGHT):
        t = y / HEIGHT
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (WIDTH, y)], fill=(r, g, b))


def draw_dashed_arrow(draw: ImageDraw.ImageDraw) -> None:
    """Draw curved dashed arrow from app icon to Applications."""
    start_x, start_y = APP_X + 50, APP_Y - 20
    end_x, end_y = DROP_X - 50, DROP_Y - 20
    mid_x = (start_x + end_x) / 2
    mid_y = start_y - 80  # arc height

    # Generate bezier curve points
    points = []
    steps = 200
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * start_x + 2 * (1 - t) * t * mid_x + t**2 * end_x
        y = (1 - t) ** 2 * start_y + 2 * (1 - t) * t * mid_y + t**2 * end_y
        points.append((x, y))

    # Draw dashed line
    dash_len = 8
    gap_len = 5
    color = (0x99, 0x99, 0x99)
    line_width = 2
    dist = 0
    drawing = True
    for i in range(len(points) - 1):
        x1, y1 = points[i]
        x2, y2 = points[i + 1]
        seg = math.hypot(x2 - x1, y2 - y1)
        if drawing:
            draw.line([(x1, y1), (x2, y2)], fill=color, width=line_width)
        dist += seg
        if drawing and dist >= dash_len:
            drawing = False
            dist = 0
        elif not drawing and dist >= gap_len:
            drawing = True
            dist = 0

    # Draw arrowhead at the end
    ax, ay = points[-1]
    bx, by = points[-10]
    angle = math.atan2(ay - by, ax - bx)
    arrow_len = 12
    arrow_angle = math.pi / 6
    left_x = ax - arrow_len * math.cos(angle - arrow_angle)
    left_y = ay - arrow_len * math.sin(angle - arrow_angle)
    right_x = ax - arrow_len * math.cos(angle + arrow_angle)
    right_y = ay - arrow_len * math.sin(angle + arrow_angle)
    draw.polygon([(ax, ay), (left_x, left_y), (right_x, right_y)], fill=color)


def draw_hint_text(draw: ImageDraw.ImageDraw) -> None:
    """Draw installation hint text at bottom."""
    try:
        font = ImageFont.truetype("/System/Library/Fonts/PingFang.ttc", 11)
    except (OSError, IOError):
        font = ImageFont.load_default()

    text = "将 SnapDict 拖入 Applications 文件夹完成安装"
    color = (0xAA, 0xAA, 0xAA)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    x = (WIDTH - tw) / 2
    y = HEIGHT - 30
    draw.text((x, y), text, fill=color, font=font)


def main() -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT))
    draw_gradient(img)
    draw = ImageDraw.Draw(img)
    draw_dashed_arrow(draw)
    draw_hint_text(draw)

    output = "scripts/dmg-background.png"
    img.save(output, "PNG")
    print(f"Background image saved to {output}")


if __name__ == "__main__":
    main()
