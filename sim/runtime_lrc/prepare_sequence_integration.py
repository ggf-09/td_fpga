from pathlib import Path
import re
top=Path('../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8-sig')
params=re.search(r'localparam \[3:0\] WAV_WAIT=.*?;',top,re.S)[0]
fsm=re.search(r'always @\(posedge sd_card_clk or posedge sdcard_rst\) begin\s*if \(sdcard_rst\) begin\s*wav_play_en.*?(?=assign wav_stream_active)',top,re.S)[0]
cancel=re.search(r'reg manual_eof_cancel,manual_replay_pending;.*?(?=playback_sequence)',top,re.S)[0]
seq=re.search(r'playback_sequence(?:\s*#\(.*?\))?\s+u_playback_sequence\(.*?\n\);',top,re.S)[0]
seq=seq.replace('.target(sequence_target)', '.target(sequence_target_global)')
wrapper='''`timescale 1ns/1ps
module sequence_top_fragment(
 input wire sd_card_clk,sdcard_rst,eos,user_mode_next,playback_paused,transition_busy,
 input wire accepted_manual,manual_same_song,
 input wire [3:0] playable_slots,
 input wire [1:0] active_idx_sd2,
 output reg wav_play_en,wav_file_start,
 output reg [1:0] selected_song,
 output wire [1:0] sequence_target,play_mode,
 output wire sequence_advance,sequence_replay,playlist_stopped
);
wire sdcard_rst_n=!sdcard_rst;
wire resume_hold_audio=0,resume_position_ok=0,resume_apply=0,resume_position_ready=1,resume_ready=1;wire [31:0] checkpoint_restore_frame=0,resume_start_offset=0;
wire library_audio_allowed=1,library_load_failed=0;
wire library_sequence_ready=!transition_busy;
wire library_nav_busy=0,library_nav_done=0;
wire [15:0] library_playable={12'd0,playable_slots};
wire [3:0] library_current_track={2'd0,selected_song};
wire [3:0] sequence_target_global;
assign sequence_target=sequence_target_global[1:0];
wire sd_free=1,lyric_ready_for_song=1,wav_sector_busy=0,wav_format_error=0;
wire [3:0] song_valid=playable_slots;
wire wav_stream_end=wav_play_en&&eos;
reg [31:0] wav_restart_cnt;
reg [3:0] wav_control_state;
reg wav_end_sd1,wav_end_sd2;
reg wav_seek_restart;
reg [31:0] wav_origin_sd,wav_start_offset,seek_position;
reg [31:0] seek_candidate,seek_target,seek_plus,seek_minus;
reg seek_under,seek_hi_gt,seek_hi_eq,seek_lo_ge;
wire [31:0] seek_sample_snapshot=0;
reg seek_back_q;reg [2:0] seek_calc;
wire [30:0] seek_delta=seek_back_q ? -31'd480000 : 31'd480000;
wire [30:0] seek_shifted={1'b0,seek_position[29:0]}+seek_delta;

wire user_seek_back=0,user_seek_forward=0;wire [31:0] consumed_seen=0,ui_frames_sd=0;
reg lyric_ready_q;wire seek_muted_s2=0,seek_stream_ready=0;wire [31:0] wav_file_offset=64;
wire sel_pending=0,ctrl_transition_req=0,user_next=0,user_previous=0,key2_dbl_pulse=0,key1_nav_confirm=0;
'''
Path('sequence_top_fragment.v').write_text(wrapper+params+'\n'+cancel+'\n'+seq+'\n'+fsm+'\nendmodule\n',encoding='utf-8')
print('Extracted actual top WAV state machine, EOF gate and sequence wiring')
