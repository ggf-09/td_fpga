from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent.parent
sys.path.insert(0,str(PROJECT/'doc/convert'))
from generate_music_lyrics import read_lrc
SOURCE=ROOT/'fixtures/scroll_lyrics'
font=(SOURCE/'FONT.BIN').read_bytes();bank=font[12*16384:13*16384]
raw=(SOURCE/'SONG13.LRC').read_bytes();second=(SOURCE/'SONG14.LRC').read_bytes()
entries=read_lrc(SOURCE/'SONG13.LRC',max_chars=31)
mapping={int.from_bytes(bank[8+2*i:10+2*i],'little'):i for i in range(int.from_bytes(bank[5:7],'little'))}
text=[];cues=[]
for cs,line in entries:
    cues.append((cs<<17)|(len(text)<<5)|len(line));text.extend(mapping[ord(c)] for c in line)
assert len(text)==2375 and len(entries)==132
for name,data in [('scroll_font',bank),('scroll_library_font',font),('scroll_lrc',raw),('scroll_second_lrc',second)]:
    (ROOT/f'{name}.hex').write_text(''.join(f'{v:02x}\n' for v in data),encoding='ascii')
pairs=[(bank[9216+i]<<8)|g for i,g in enumerate(text)]
(ROOT/'scroll_pairs.hex').write_text(''.join(f'{v:04x}\n' for v in pairs),encoding='ascii')
(ROOT/'scroll_cues.hex').write_text(''.join(f'{v:09x}\n' for v in cues),encoding='ascii')
(ROOT/'scroll_sizes.vh').write_text(f'`define SCR_LRC_SIZE {len(raw)}\n`define SCR_SECOND_SIZE {len(second)}\n`define SCR_CHARS {len(text)}\n',encoding='ascii')
source=(PROJECT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
assert 'scrolling_lyric_overlay #(' in source and '.KARAOKE(1),.FONT_RANGE_READ(1)) u_runtime_lyrics' in source
assert source.count('.timing_read_data(lyric_timing_data)')==2
print('Prepared real scrolling Sugar fixtures')
