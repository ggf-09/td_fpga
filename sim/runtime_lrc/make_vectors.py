from pathlib import Path
import sys
import io
import struct
import wave

ROOT = Path(__file__).resolve().parent
CONVERT = ROOT.parent.parent / "doc" / "convert"
sys.path.insert(0, str(CONVERT))
from prepare_music_card import write_card_font

lrc = "[00:01.23]HELLO\n[00:03.45]WORLD\n[00:04.00]你好\n".encode("utf-8")
(ROOT / "SONG1.LRC").write_bytes(lrc)
# Put the actual test text above glyph 127 to catch address truncation.
extra = "".join(chr(0x4e00 + i) for i in range(144))
font_source = ROOT / "FONT_SOURCE.LRC"
font_source.write_text("".join(f"[00:{i:02d}.00]{extra[i*30:(i+1)*30]}\n" for i in range(5)), encoding="utf-8")
write_card_font([font_source, ROOT / "SONG1.LRC"], ROOT / "FONT.BIN")
for name, payload in (("font.hex", (ROOT / "FONT.BIN").read_bytes()),
                      ("lrc.hex", lrc)):
    (ROOT / name).write_text("\n".join(f"{item:02x}" for item in payload) + "\n")

audio = io.BytesIO()
with wave.open(audio, 'wb') as wav:
    wav.setparams((2, 2, 48000, 0, 'NONE', 'not compressed'))
    wav.writeframes(b''.join(struct.pack('<hh', i, -i) for i in range(5000)))
(ROOT/'audio.hex').write_text(''.join(f'{b:02x}\n' for b in audio.getvalue()))

write_card_font([ROOT/'SONG1.LRC'], ROOT/'small_font.bin')
large=(ROOT/'FONT.BIN').read_bytes()
small=(ROOT/'small_font.bin').read_bytes()
banked=b''.join(slot+bytes(16384-len(slot)) for slot in [large,small,large,small])
(ROOT/'banked_font.hex').write_text(''.join(f'{b:02x}\n' for b in banked))
library_fonts=b''.join(slot+bytes(16384-len(slot)) for slot in
                       [large if i==12 else small for i in range(16)])
(ROOT/'library_font.hex').write_text(''.join(f'{b:02x}\n' for b in library_fonts))
