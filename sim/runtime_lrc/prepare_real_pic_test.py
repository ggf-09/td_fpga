"""Export the staged hi-res PIC BMPs as byte hex plus the exact 640x480
SDRAM image the FPGA scaler must produce.  The expected image uses the same
published formula as an independent integer model:
    sx = floor(ox*W/640), sy = floor(oy*H/480)  (BMP file row order)
    loader V-flip: word address (479-oy)*640+ox
"""
from pathlib import Path
import struct

root = Path(__file__).resolve().parent
staging = root / '../../doc/convert/staging_hires_pic13_20261025'

def export(bmp_path, tag):
    data = bmp_path.read_bytes()
    assert data[:2] == b'BM'
    size, off = struct.unpack_from('<II', data, 2)[0], struct.unpack_from('<I', data, 10)[0]
    w, h = struct.unpack_from('<ii', data, 18)
    bpp, comp = struct.unpack_from('<HI', data, 28)[0], struct.unpack_from('<I', data, 30)[0]
    assert size == len(data) and bpp == 24 and comp == 0 and h > 0
    stride = (w * 3 + 3) // 4 * 4
    assert off + stride * h == len(data)
    (root / f'{tag}_bytes.hex').write_text(
        ''.join(f'{b:02x}\n' for b in data), encoding='ascii')
    out = bytearray()
    for oy in range(480):
        sy = oy * h // 480
        row = off + sy * stride
        for ox in range(640):
            sx = ox * w // 640
            p = row + sx * 3
            b, g, r = data[p], data[p + 1], data[p + 2]
            out += f'{r:02x}{g:02x}{b:02x}\n'.encode()
    # Loader writes output row oy to address (479-oy)*640, so reverse row order.
    lines = out.splitlines()
    rows = [b'\n'.join(lines[r * 640:(r + 1) * 640]) for r in range(480)]
    (root / f'{tag}_expected.hex').write_bytes(b'\n'.join(reversed(rows)) + b'\n')
    print(f'{tag}: {w}x{h} size={len(data)} off={off} stride={stride}')

export(staging / 'PIC1.BMP', 'real_pic1')
export(staging / 'PIC3.BMP', 'real_pic3')
export(root / '../../doc/convert/staging_hires_pic_batch2_20261025/PIC2.BMP',
       'real_pic2')
