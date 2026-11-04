from pathlib import Path
import re

top = Path('../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8-sig')
bundle = re.search(r'// Canonical 44-byte.*?(?=wire\s+fade_active;)', top, re.S)[0]
bundle = bundle.replace('wire [31:0] ui_total_frames =', 'assign ui_total_frames =')
wrapper = '''`timescale 1ns/1ps
module ui_cdc_top_fragment(
 input wire sd_card_clk,sdcard_rst,video_clk,video_rst,wav_file_start,
 input wire [1:0] selected_song,active_index_pix,
 input wire [31:0] selected_song_size,
 output wire [31:0] ui_total_frames
);
wire [31:0] wav_origin_sd=0;
wire [1:0] library_cache_page=0;
wire [3:0] library_track_pix={2'd0,active_index_pix};
'''
library_wrapper='''`timescale 1ns/1ps
module library_ui_cdc_top_fragment(
 input wire sd_card_clk,sdcard_rst,video_clk,video_rst,wav_file_start,
 input wire [1:0] selected_song,library_cache_page,
 input wire [3:0] library_track_pix,
 input wire [31:0] selected_song_size,
 output wire [31:0] ui_total_frames
);
'''
Path('ui_cdc_top_fragment.v').write_text(wrapper+bundle+'\nendmodule\n'+library_wrapper+'wire [31:0] wav_origin_sd=0;\n'+bundle+'\nendmodule\n', encoding='utf-8')
print('Extracted actual top canonical-WAV length CDC and song gating')
