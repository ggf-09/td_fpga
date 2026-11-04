from pathlib import Path
import re
top=Path('../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
params=re.search(r'localparam \[3:0\] WAV_WAIT=.*?;',top,re.S)[0]
fsm=re.search(r'always @\(posedge sd_card_clk or posedge sdcard_rst\) begin\s*if \(sdcard_rst\) begin\s*wav_play_en.*?(?=assign wav_stream_active)',top,re.S)[0]
transport=re.search(r'// SEEK_TRANSPORT_BEGIN.*?// SEEK_TRANSPORT_END',top,re.S)[0]
bundle=re.search(r'// Canonical 44-byte.*?(?=wire\s+fade_active;)',top,re.S)[0]
position=re.search(r'assign wav_position=.*?(?=// ===================== 第16课：歌词叠加)',top,re.S)[0]
def instance(module,name):
 return re.search(r'^'+module+r'(?:\s*#\(.*?\)\s*)?\s+'+name+r'\s*\(.*?\n\);',top,re.S|re.M)[0]
header='''`timescale 1ns/1ps
module seek_top_fragment(
 input wire sd_card_clk,sdcard_rst,video_clk,video_rst,wav_sample_tick,playback_paused,
 input wire user_seek_back,user_seek_forward,transition_busy,sequence_replay,
 input wire [1:0] active_idx_sd2,
 input wire accepted_manual,manual_same_song,
 input wire wav_sector_busy,wav_sector_valid,wav_sector_done,
 input wire [7:0] wav_sector_byte,wav_sector_error,
 input wire [8:0] wav_sector_byte_index,
 output wire wav_file_sector_req,output wire [31:0] wav_file_sector_lba,
 output wire [31:0] wav_position,
 output wire [15:0] lyric_cs,
 output wire wav_sample_valid,
 output wire signed [15:0] wav_left_out,wav_right_out,
 output reg wav_play_en,wav_file_start,
 output wire [7:0] envelope,
 output wire [3:0] transport_state
);
wire sdcard_rst_n=!sdcard_rst,video_rst_n=!video_rst;
wire rst_n_video=video_rst_n;
wire sd_free=1,library_audio_allowed=1,lyric_ready_for_song=1,sel_pending=0;
wire resume_hold_audio=0,resume_apply=0;wire [31:0] checkpoint_restore_frame=0;
wire [31:0] checkpoint_restore_size=7680044,checkpoint_restore_cluster=10;

wire [3:0] song_valid=15;
reg [1:0] selected_song;
reg [3:0] wav_control_state;
reg [31:0] wav_restart_cnt;
reg wav_end_sd1,wav_end_sd2;
wire [31:0] selected_song_size=7680044,selected_song_cluster=10;
wire [7:0] media_spc=64;
wire [31:0] media_fat_start=1,media_data_start=100,media_max_cluster=3000;
wire [1:0] library_cache_page=0;
wire [3:0] library_track_pix={2'd0,active_idx_sd2};
wire wav_stream_end,wav_stream_active,wav_format_error,wav_can_read_sector;
wire wav_file_busy,wav_file_done,wav_file_valid;
wire [7:0] wav_file_byte,wav_file_error;
wire [31:0] wav_file_offset,wav_sample_cnt;
wire wav_sample_ready=1,pause_pix2=playback_paused;
reg wav_active_pix1,wav_active_pix2;

'''
active=re.search(r'assign wav_stream_active.*?(?=// ===================== 第11课新增：48kHz采样tick)',top,re.S)[0]
cancel=re.search(r'reg manual_eof_cancel,manual_replay_pending;.*?(?=playback_sequence)',top,re.S)[0]
validation=re.search(r'// RESUME_VALIDATION_BEGIN.*?// RESUME_VALIDATION_END',top,re.S)[0]
code=header+params+'\n'+validation+'\n'+transport+'\n'+cancel+'\nassign envelope=seek_gain;assign transport_state=wav_control_state;\n'+bundle+'\n'+fsm+'\n'+active
eligible=re.search(r'// SEEK_ELIGIBILITY_BEGIN.*?// SEEK_ELIGIBILITY_END',top,re.S)[0]
# u_song_streamer 已并入 sd_card_bmp 的共享流读器，顶层无法再提取；
# fragment 自包含，这里保留原实例接线的字面副本（端口名与本 fragment 头部一致）。
streamer='''fat32_file_streamer #(.MAX_VISITED_CLUSTERS(65535),.SEEK_SUPPORT(1)) u_song_streamer (
 .start_offset(wav_start_offset),.clk(sd_card_clk),.rst_n(sdcard_rst_n && wav_play_en),
 .file_start(wav_file_start),.first_cluster(selected_song_cluster),.file_size(selected_song_size),
 .sectors_per_cluster(media_spc),.fat_start_lba(media_fat_start),
 .data_start_lba(media_data_start),.max_cluster(media_max_cluster),
 .file_busy(wav_file_busy),.file_done(wav_file_done),.file_valid(wav_file_valid),
 .file_byte(wav_file_byte),.file_byte_offset(wav_file_offset),.fs_error(wav_file_error),
 .sector_req(wav_file_sector_req),.sector_lba(wav_file_sector_lba),
 .sector_busy(wav_sector_busy || !wav_can_read_sector),.sector_valid(wav_sector_valid),
 .sector_byte(wav_sector_byte),.sector_byte_index(wav_sector_byte_index),
 .sector_done(wav_sector_done),.sector_error(wav_sector_error)
);'''
code+='\n'+eligible+'\n'+streamer+'\n'+instance('fat_wav_player','u_wav_player')+'\n'+position+'\nendmodule\n'
Path('seek_top_fragment.v').write_text(code,encoding='utf-8')
print('Extracted production seek FSM, snapshot handshake, envelope, length/origin bundle, FAT/WAV instances and position clock')
