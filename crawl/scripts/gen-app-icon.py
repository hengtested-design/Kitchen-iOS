#!/usr/bin/env python3
"""
生成 "家厨 HomeCook" App 图标
iOS 26 风格:1024x1024,三套(标准/Dark/Tinted)
"""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1024, 1024

# 调色板
ORANGE_LIGHT = (255, 153, 51)    # #FF9933 - 浅橙
ORANGE_MID   = (242, 101, 34)    # #F26522 - 中橙
ORANGE_DARK  = (213, 64, 32)     # #D54020 - 深橙
WHITE        = (255, 255, 255)
WHITE_90     = (255, 255, 255, 230)
SHADOW       = (213, 64, 32, 100)
BOWL_LIGHT   = (255, 255, 255)
BOWL_DARK    = (240, 230, 215)   # 碗的阴影色
NOODLE       = (255, 235, 200)


def radial_gradient_bg():
    """径向渐变背景:中心橙黄 → 边缘深橙"""
    img = Image.new('RGBA', (W, H), ORANGE_DARK)
    draw = ImageDraw.Draw(img)

    # 从中心向外,颜色从浅到深
    cx, cy = W // 2, H // 2
    for r in range(W, 0, -3):
        # 计算当前半径对应的颜色(基于最大距离比例)
        ratio = r / W
        # 插值颜色
        color = (
            int(ORANGE_LIGHT[0] * (1 - ratio) + ORANGE_DARK[0] * ratio),
            int(ORANGE_LIGHT[1] * (1 - ratio) + ORANGE_DARK[1] * ratio),
            int(ORANGE_LIGHT[2] * (1 - ratio) + ORANGE_DARK[2] * ratio),
            255,
        )
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=color,
        )
    return img


def draw_steam(draw, cx, cy_base):
    """在碗上方画三股蒸汽(弯曲弧线)"""
    # 三个流线,从碗口向上袅袅升起
    for i, offset in enumerate([-90, 0, 90]):
        x = cx + offset
        y = cy_base
        # 波浪线:用 arc 画
        for j in range(4):
            arc_y = y - j * 40
            color_alpha = max(180, 255 - j * 30)
            draw.arc(
                [x - 25, arc_y - 30, x + 25, arc_y + 30],
                start=200, end=340,
                fill=(*WHITE, color_alpha),
                width=14,
            )


def draw_bowl(draw, cx, cy):
    """画一个碗 + 碗里的面条 + 筷子的简化图"""
    # 碗:椭圆(顶部) + 圆弧(底部)
    bowl_top_y = cy - 50
    bowl_w = 380
    bowl_h = 220

    # 碗体底部弧形(用 ellipse 的下半部分)
    bowl_box = [cx - bowl_w // 2, bowl_top_y, cx + bowl_w // 2, bowl_top_y + bowl_h]
    draw.ellipse(bowl_box, fill=BOWL_LIGHT, outline=BOWL_DARK, width=4)

    # 碗内面条(几条横线代表面条)
    noodle_y_start = bowl_top_y + 25
    for i in range(3):
        y = noodle_y_start + i * 14
        draw.line(
            [(cx - 150, y), (cx + 150, y)],
            fill=NOODLE,
            width=8,
        )

    # 碗口椭圆(深一点的橙红,模拟深色)
    draw.ellipse(
        bowl_box,
        outline=ORANGE_DARK,
        width=8,
    )

    # 筷子:从碗右上角斜插,露出上半截
    # 筷子 1
    ch1_x1 = cx + 90
    ch1_y1 = bowl_top_y - 60
    ch1_x2 = cx + 200
    ch1_y2 = bowl_top_y + 80
    draw.line([(ch1_x1, ch1_y1), (ch1_x2, ch1_y2)], fill=(180, 90, 30), width=12)
    draw.line([(ch1_x1, ch1_y1), (ch1_x2, ch1_y2)], fill=(220, 160, 90), width=4)

    # 筷子 2 (平行)
    ch2_x1 = cx + 130
    ch2_y1 = bowl_top_y - 70
    ch2_x2 = cx + 240
    ch2_y2 = bowl_top_y + 70
    draw.line([(ch2_x1, ch2_y1), (ch2_x2, ch2_y2)], fill=(180, 90, 30), width=12)
    draw.line([(ch2_x1, ch2_y1), (ch2_x2, ch2_y2)], fill=(220, 160, 90), width=4)


def draw_chinese_text(draw, cx, cy_bottom):
    """底部画中文 "家厨" 两字 — 用 macOS 系统字体"""
    try:
        font = ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc', 110)
    except Exception:
        try:
            font = ImageFont.truetype('/System/Library/Fonts/PingFang.ttc', 110)
        except Exception:
            font = ImageFont.load_default()

    text = "家厨"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]

    # 文字位置:底部居中,碗下方约 80px
    text_x = cx - text_w // 2 - bbox[0]
    text_y = cy_bottom - text_h // 2 - bbox[1]

    # 阴影 + 白色文字
    draw.text((text_x + 4, text_y + 4), text, font=font, fill=(0, 0, 0, 80))
    draw.text((text_x, text_y), text, font=font, fill=WHITE)


def make_icon(mode='standard'):
    """生成一个图标 mode: standard / dark / tinted"""
    img = radial_gradient_bg()
    draw = ImageDraw.Draw(img, 'RGBA')

    cx, cy = W // 2, H // 2

    # 蒸汽(碗上方)
    draw_steam(draw, cx, cy - 30)

    # 碗 + 筷子(中心略上)
    draw_bowl(draw, cx, cy + 60)

    # 中文 "家厨"(底部)
    draw_chinese_text(draw, cx, cy + 360)

    # Dark / Tinted 模式:整体调暗/调灰
    if mode == 'dark':
        # Dark 模式:背景更深,文字和图形更亮
        dark = Image.new('RGBA', (W, H), (40, 25, 15, 60))
        img = Image.alpha_composite(img, dark)
    elif mode == 'tinted':
        # Tinted 模式:去饱和
        tinted = Image.new('RGBA', (W, H), (128, 128, 128, 100))
        img = Image.alpha_composite(img, tinted)

    return img.convert('RGB')


def main():
    out_dir = '/Users/hengmintao/Desktop/Kitchen/Kitchen/Assets.xcassets/AppIcon.appiconset'
    os.makedirs(out_dir, exist_ok=True)

    for mode, suffix in [('standard', ''), ('dark', '-dark'), ('tinted', '-tinted')]:
        icon = make_icon(mode)
        filename = f'icon{suffix}.png' if suffix else 'icon.png'
        # Contents.json 期望的文件名:AppIcon-1024.png 或类似的
        # 简化为统一命名
        if mode == 'standard':
            target = os.path.join(out_dir, 'icon-1024.png')
        elif mode == 'dark':
            target = os.path.join(out_dir, 'icon-1024-dark.png')
        else:
            target = os.path.join(out_dir, 'icon-1024-tinted.png')

        icon.save(target, 'PNG', optimize=True)
        print(f'✓ {target} ({icon.size[0]}x{icon.size[1]})')

    print('\n✅ 完成')

if __name__ == '__main__':
    main()