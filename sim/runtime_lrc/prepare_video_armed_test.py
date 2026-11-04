from pathlib import Path
root=Path(__file__).resolve().parent
s=(root/'../../src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8')
anchor=s.index('reg library_display_s1,library_display_s2,library_video_armed;')
a=s.index('always @(posedge video_clk or posedge video_rst)begin',anchor)
b=s.index('// sd_card_bmp首轮加载结束',a)
body=s[a:b]
header="""module video_armed_fragment(input wire video_clk,video_rst,
 input wire library_abort_toggle,library_audio_allowed,
 input wire [3:0] loader_image_complete,input wire [1:0] active_index_pix,
 input wire frame_start_raw,index_commit_pix,input wire [3:0] library_pending_track,
 output reg [3:0] library_track_pix,output reg library_abort_pulse,library_video_armed);
 reg library_abort_s1,library_abort_s2,library_abort_seen,library_abort_pending;
 reg library_display_s1,library_display_s2;
"""
(root/'video_armed_fragment.v').write_text(header+body+'\nendmodule\n',encoding='utf-8')
print('Extracted actual video-armed/track-latch always block from top')
