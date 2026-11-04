from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parents[1]
OUTPUT=ROOT/'fixtures/long_lyrics'
sys.path.insert(0,str(PROJECT/'doc/convert'))
from prepare_music_card import normalize_card_lrc
from generate_music_lyrics import read_lrc
raw=normalize_card_lrc(OUTPUT/'SONG13.LRC')
font=(OUTPUT/'FONT.BIN').read_bytes()[12*16384:12*16384+8712]
library_font=(OUTPUT/'FONT.BIN').read_bytes()
second=normalize_card_lrc(OUTPUT/'SONG14.LRC')
count=int.from_bytes(font[5:7],'little')
mapping={int.from_bytes(font[8+2*i:10+2*i],'little'):i for i in range(count)}
entries=read_lrc(OUTPUT/'SONG13.LRC',max_chars=31)
text=[];cues=[]
for cs,line in entries:
    cues.append((cs<<17)|(len(text)<<5)|len(line))
    text.extend(mapping[ord(char)] for char in line)
assert len(entries)==132 and len(text)==2397 and len(raw)<=4096
boundary=''.join(f'[{i//60:02d}:{i%60:02d}.00]?\n' for i in range(158)).encode()
for name,payload in [('extended_lrc',raw),('extended_font',font),('extended_text',bytes(text)),
                     ('extended_boundary',boundary),('extended_library_font',library_font),('extended_second_lrc',second)]:
    (ROOT/f'{name}.hex').write_text(''.join(f'{b:02x}\n' for b in payload),encoding='ascii')
(ROOT/'extended_cues.hex').write_text(''.join(f'{cue:09x}\n' for cue in cues),encoding='ascii')
(ROOT/'extended_sizes.vh').write_text(f'`define EXT_LRC_SIZE {len(raw)}\n`define EXT_SECOND_SIZE {len(second)}\n`define EXT_BOUND_SIZE {len(boundary)}\n',encoding='ascii')
# Extract the shipped top's actual number decoder and scan wiring.
source=(PROJECT/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
assert 'wire [7:0] live_cue_count,live_cue_index;' in source
assert 'wire [11:0] live_text_addr,live_cue_base;' in source
assert '.MAX_CUES(158),.MAX_TEXT(3072),.KARAOKE(1)' in source
assert '.CUE_BITS(8),.TEXT_BITS(12),.CUE_STORAGE(160),.TEXT_DEPTH(3072)' in source
start=source.index('wire [4:0] displayed_song_number=')
end=source.index('// ===================== RGB/DE 转 AXIS',start)
fragment=source[start:end]
prefix='''module sevenseg_top_fragment(input wire clk,sys_rst_n,
 input wire [3:0] library_current_track,bmp_err_code,input wire [7:0] media_err,
 output wire [5:0] seg_sel,output wire [7:0] seg_data);
 wire [3:0] state_code;wire [6:0] seg_data_0;
'''
(ROOT/'sevenseg_top_fragment.v').write_text(prefix+fragment+'\nendmodule\n',encoding='utf-8')
print(f'Extended vectors: {len(raw)} bytes, {len(entries)} cues, {len(text)} characters')
