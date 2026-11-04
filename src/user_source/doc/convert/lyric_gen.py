# -*- coding: utf-8 -*-
# lyric_gen.py — 《反方向的钟》前100s歌词 → FPGA字形ROM(mif×4) + 行表/字索引流(lyric_table.vh)
# 用法: python lyric_gen.py
# 产物:
#   hdl_source/lyric_glyph_b0..b3.mif  (4块9K BRAM, 512×18bit, Altera标准MIF)
#   hdl_source/lyric_table.vh          (行表/字索引流 case函数, 供promax_lyric_overlay.v include)
#   doc/convert/lyric_atlas.png        (字形预览, 人工检查用)
# 字形来源: C:\Windows\Fonts\simsun.ttc 16px渲染二值化; idx0=空格(全0)
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
HDL = os.path.abspath(os.path.join(HERE, "..", "..", "..", "user_source", "hdl_source"))

# ---- 歌词(秒已按0.5四舍五入; 末项100=结束哨兵) ----
LINES = [
    (43, "迷迷蒙蒙 你给的梦"),
    (46, "出现裂缝 隐隐作痛"),
    (48, "怎么沟通你都没空"),
    (50, "说我不懂 说了没用"),
    (53, "他的笑容 有何不同"),
    (55, "在你心中 我不再受宠"),
    (58, "我的天空 是雨是风 还是彩虹"),
    (62, "你在操纵"),
    (64, "恨自己真的没用情绪激动"),
    (68, "一颗心到现在还在抽痛"),
    (72, "还为分手前那句抱歉在感动"),
    (79, "穿梭时间的画面的钟"),
    (87, "从反方向 开始移动"),
    (92, "回到当初爱你的时空"),
    (97, "停格内容 不忠"),
]
END_SEC = 100
GLYPH_W = 16
GLYPH_H = 16
BLOCK_CHARS = 32          # 每块32字 ×16行 = 512行 = 9bit地址
MAX_CHARS = BLOCK_CHARS * 4

# ---- 1. 去重字符表(idx0=空格) ----
charset = [" "]
for _, text in LINES:
    for ch in text:
        if ch not in charset:
            charset.append(ch)
n_chars = len(charset)
print(f"去重字符数(含空格): {n_chars}")
assert n_chars <= MAX_CHARS, f"超出{MAX_CHARS}字上限!"
char2idx = {ch: i for i, ch in enumerate(charset)}

# ---- 2. 渲染16×16点阵 ----
font = ImageFont.truetype("C:/Windows/Fonts/simsun.ttc", 16)
glyphs = []  # glyphs[idx][row] = 16bit, bit15=最左像素
for ch in charset:
    if ch == " ":
        glyphs.append([0] * GLYPH_H)
        continue
    # 垂直方向不裁剪: 用字体自身度量对齐基线(避免"一"等矮字掉到底部); 仅水平居中
    img = Image.new("L", (GLYPH_W, GLYPH_H), 0)
    d = ImageDraw.Draw(img)
    tb = d.textbbox((0, 0), ch, font=font)
    if tb[2] - tb[0] <= 0 or tb[3] - tb[1] <= 0:
        glyphs.append([0] * GLYPH_H)
        continue
    ox = (GLYPH_W - (tb[2] - tb[0])) // 2 - tb[0]
    d.text((ox, 0), ch, font=font, fill=255)
    canvas = img
    px = canvas.load()
    rows = []
    for y in range(GLYPH_H):
        v = 0
        for x in range(GLYPH_W):
            if px[x, y] >= 128:
                v |= 1 << (15 - x)      # bit15=最左
        rows.append(v)
    glyphs.append(rows)

# ---- 3. 写4个mif(每块32字×16行, 512×18bit, 高2位补0) ----
os.makedirs(HDL, exist_ok=True)
for b in range(4):
    path = os.path.join(HDL, f"lyric_glyph_b{b}.mif")
    with open(path, "w", encoding="ascii") as f:
        f.write("WIDTH = 18;\nDEPTH = 512;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n")
        f.write("CONTENT BEGIN\n")
        for addr in range(512):
            ci = b * BLOCK_CHARS + (addr >> 4)
            row = addr & 0xF
            data = glyphs[ci][row] if ci < n_chars else 0
            f.write(f"{addr:03X} : {data:05X};\n")
        f.write("END\n")
    print(f"写出 {path}")

# ---- 4. 字索引流 + 行表 ----
stream = []
line_meta = []  # (start_sec, offset, count)
for sec, text in LINES:
    line_meta.append((sec, len(stream), len(text)))
    stream.extend(char2idx[ch] for ch in text)
print(f"字索引流长度: {len(stream)}")
assert len(stream) <= 256

# ---- 5. 写lyric_table.vh ----
vh = os.path.join(HDL, "lyric_table.vh")
with open(vh, "w", encoding="utf-8") as f:
    f.write("// lyric_table.vh — 由 doc/convert/lyric_gen.py 自动生成, 勿手改\n")
    f.write(f"// 《反方向的钟》前{END_SEC}s: {len(LINES)}行, {n_chars}字, 流长{len(stream)}\n\n")
    # 当前行查找: sec → 行号(0..N-1), 无歌词=4'hF
    f.write(f"localparam [3:0] LYRIC_NONE = 4'hF;\n")
    f.write("function [3:0] line_of_sec;\n    input [6:0] sec;\n    begin\n")
    f.write(f"        if (sec < 7'd{line_meta[0][0]}) line_of_sec = LYRIC_NONE;\n")
    for i in range(len(line_meta)):
        hi = line_meta[i + 1][0] if i + 1 < len(line_meta) else END_SEC
        f.write(f"        else if (sec < 7'd{hi}) line_of_sec = 4'd{i};\n")
    f.write("        else line_of_sec = LYRIC_NONE;\n")
    f.write("    end\nendfunction\n\n")
    # 行属性: {start已在查找用}, offset[7:0], count[4:0]
    f.write("function [12:0] line_meta;\n    input [3:0] idx;\n    begin\n        case (idx)\n")
    for i, (sec, off, cnt) in enumerate(line_meta):
        f.write(f"            4'd{i}: line_meta = {{8'd{off}, 5'd{cnt}}};\n")
    f.write("            default: line_meta = {8'd0, 5'd0};\n        endcase\n    end\nendfunction\n\n")
    # 字索引流
    f.write("function [7:0] char_at;\n    input [7:0] pos;\n    begin\n        case (pos)\n")
    for i, ci in enumerate(stream):
        f.write(f"            8'd{i}: char_at = 8'd{ci};\n")
    f.write("            default: char_at = 8'd0;\n        endcase\n    end\nendfunction\n")
print(f"写出 {vh}")

# ---- 6. 字形预览atlas ----
cols = 16
rows_n = (n_chars + cols - 1) // cols
atlas = Image.new("L", (cols * GLYPH_W, rows_n * GLYPH_H), 0)
for idx in range(n_chars):
    cell = Image.new("L", (GLYPH_W, GLYPH_H), 0)
    cpx = cell.load()
    for y in range(GLYPH_H):
        for x in range(GLYPH_W):
            if glyphs[idx][y] >> (15 - x) & 1:
                cpx[x, y] = 255
    atlas.paste(cell, ((idx % cols) * GLYPH_W, (idx // cols) * GLYPH_H))
ap = os.path.join(HERE, "lyric_atlas.png")
atlas.resize((atlas.width * 3, atlas.height * 3), Image.NEAREST).save(ap)
print(f"写出 {ap}")
with open(os.path.join(HERE, "lyric_charset.txt"), "w", encoding="utf-8") as f:
    for i, ch in enumerate(charset):
        f.write(f"{i:3d}: {ch}\n")
print("完成")
