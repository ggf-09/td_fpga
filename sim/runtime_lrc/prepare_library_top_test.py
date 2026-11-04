from pathlib import Path
import re
top=Path('../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8-sig')
def instance(name):
    return re.search(r'\w+\s*(?:#\(.*?\)\s*)?'+name+r'\s*\(.*?\n\);',top,re.S)[0]
# Match anchored declarations so a preceding module instance cannot be captured.
def inst(module,name):
    return re.search(r'^'+module+r'(?:\s*#\(.*?\)\s*)?\s+'+name+r'\s*\(.*?\n\);',top,re.S|re.M)[0]
params=re.search(r'localparam \[3:0\] WAV_WAIT=.*?;',top,re.S)[0]
fsm=re.search(r'always @\(posedge sd_card_clk or posedge sdcard_rst\) begin\s*if \(sdcard_rst\) begin\s*wav_play_en.*?(?=assign wav_stream_active)',top,re.S)[0]
cancel=re.search(r'reg manual_eof_cancel,manual_replay_pending;.*?(?=playback_sequence)',top,re.S)[0]
nav=re.search(r'assign manual_track_request=.*?\n\);',top,re.S)[0]
pixel=re.search(r'reg \[3:0\] library_track_pix;.*?(?=wire \[3:0\]\s+song_valid;)',top,re.S)[0]
route=re.search(r'assign sel_pending=library_route_busy;.*?\n\);',top,re.S)[0]
header='''`timescale 1ns/1ps
module library_top_fragment(
 input wire sd_card_clk,sdcard_rst,video_clk,video_rst,frame_start_raw,
 input wire user_next,user_previous,user_mode_next,playback_paused,
 input wire eos,ctrl_transition_req,ctrl_transition_select,ctrl_view_mode,
 input wire [1:0] ctrl_focus_index,
 input wire [3:0] ctrl_focus_track,
 input wire [15:0] library_catalog_playable,
 input wire sd_free,library_page_done,
 input wire [1:0] library_cache_page,
 input wire [3:0] loader_image_complete,song_valid,
 output reg wav_play_en,wav_file_start,
 output reg [1:0] selected_song,
 output wire [3:0] library_current_track,
 output wire [1:0] active_index_pix,library_target_page,play_mode,
 output wire library_page_start,library_route_busy,transition_busy,playlist_stopped,thumb_mode_sd
);
wire sdcard_rst_n=!sdcard_rst,video_rst_n=!video_rst;
wire resume_hold_audio=0,resume_position_ok=0,resume_apply=0,resume_position_ready=1,resume_ready=1,resume_route_request=0;wire [3:0] resume_route_target=0;wire [31:0] checkpoint_restore_frame=0,resume_start_offset=0;
wire lyric_ready_for_song=1,wav_sector_busy=0,wav_format_error=0;
wire key2_dbl_pulse=0,key1_nav_confirm=0;
wire manual_track_request,manual_found,accepted_manual,manual_same_song;
wire library_nav_busy,library_nav_done;
wire library_sequence_ready,library_audio_allowed,library_fade_request,library_cover_select;
wire library_load_failed,library_abort_toggle,library_control_busy;
wire library_keep_valid;wire [1:0] library_keep_slot;
wire [15:0] library_playable;
wire [3:0] library_pending_track,sequence_target;
wire [1:0] library_cover_slot;
wire sequence_advance,sequence_replay;
wire [1:0] sel_index;
wire sel_pending,fade_next_event,index_commit_pix;
wire [7:0] control_error;
wire auto_enabled_sd;
wire thumb_mode_frame=thumb_mode_sd;
wire [7:0] fade_alpha;
wire fade_active,wipe_active;
wire [4:0] wipe_ramp;
// The real top synchronizes transition_pref into the pixel domain; the
// fragment has no switch CDC, so hold the manual preference at FADE.
wire transition_pref_pix2=1'b0;
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
reg [1:0] active_idx_sd1,active_idx_sd2;
always @(posedge sd_card_clk or posedge sdcard_rst)begin
 if(sdcard_rst)begin active_idx_sd1<=0;active_idx_sd2<=0;end
 else begin active_idx_sd1<=active_index_pix;active_idx_sd2<=active_idx_sd1;end
end
'''
code=header+params+'\n'+pixel+'\n'+nav+'\n'+cancel+'\n'+inst('playback_sequence','u_playback_sequence')+'\n'+route
code+='\n'+inst('media_player_control','u_control')+'\n'+inst('video_fade_transition','u_fade_transition')+'\n'+fsm+'\nendmodule\n'
Path('library_top_fragment.v').write_text(code,encoding='utf8')
print('Extracted actual top global navigation/router/sequence, video commits, fade and WAV FSM')
