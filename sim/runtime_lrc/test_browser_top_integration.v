`timescale 1ns/1ps
module test_browser_top_integration;
 reg sd_card_clk=0;always #5 sd_card_clk=~sd_card_clk;
 reg video_clk=0;always #20 video_clk=~video_clk;
 reg sdcard_rst=1,video_rst=1,user_next=0,user_previous=0,user_mode_next=0,playback_paused=0;
 reg eos=0;
 wire ctrl_transition_req,ctrl_transition_select,ctrl_view_mode;
 reg key_right=0,key_left=0,key_confirm=0,key_mode=0;
 wire [1:0] ctrl_focus_index;reg [1:0] library_cache_page=0;
 reg [15:0] library_catalog_playable=16'hffff;
 reg sd_free=0,library_page_done=0;
 reg [3:0] loader_image_complete=15,song_valid=15;
 wire wav_play_en,wav_file_start,library_page_start,library_route_busy,transition_busy,playlist_stopped,thumb_mode_sd;
 wire [1:0] selected_song,active_index_pix,library_target_page,play_mode;
 wire [3:0] library_current_track;
 reg [7:0] frame_count=0;
 always @(posedge video_clk)frame_count<=frame_count==99?0:frame_count+1'b1;
 wire frame_start_raw=frame_count==0;
 wire [3:0] ctrl_focus_track;
 assign ctrl_focus_index=ctrl_focus_track[1:0];
 library_browser_controller browser(.clk(sd_card_clk),.rst_n(!sdcard_rst),
 .key_right(key_right),.key_left(key_left),.key_confirm(key_confirm),.key_mode(key_mode),
 .frame_start(frame_start_raw),.busy(transition_busy||library_route_busy),.ready(sd_free),.menu_ready(1'b1),
 .playable(library_catalog_playable),.current_track(library_current_track),.cache_page(library_cache_page),
 .view_mode(ctrl_view_mode),.focus_track(ctrl_focus_track),.transition_req(ctrl_transition_req),.transition_select(ctrl_transition_select));
 library_top_fragment dut(.*);
 integer starts=0,reloads=0,k;
 reg [1:0] page_captured;
 always @(posedge sd_card_clk)if(wav_file_start)begin
  starts=starts+1;
  if(!sd_free || !dut.library_audio_allowed || dut.library_track_pix!={library_cache_page,selected_song})
    $fatal(1,"WAV started against stale page/slot metadata");
 end
 // Model page-cache loading. The real drain/reset controller and FAT catalog
 // are separately exercised by their dedicated tests.
 // 重载必须慢于淡出（16帧≈6400拍）：重叠加载下page_start在受理拍即发，过快完成的
 // 页模型会让WAV FSM在淡出期间用新页元数据重开旧歌——真实硬件不存在该窗口。
 initial forever begin
  @(negedge sd_card_clk);
  if(library_page_start)begin
   reloads=reloads+1;page_captured=library_target_page;sd_free=0;
   repeat(4)@(negedge sd_card_clk);
   if(wav_play_en)$fatal(1,"WAV kept running after cache ownership revoked");
   loader_image_complete=0;song_valid=0;
   repeat(8000)@(negedge sd_card_clk);
   library_cache_page=page_captured;
   song_valid=(library_catalog_playable>>(page_captured*4));loader_image_complete=song_valid;
   sd_free=1;library_page_done=1;@(negedge sd_card_clk);library_page_done=0;
  end
 end
 task tick;input integer n;begin repeat(n)@(negedge sd_card_clk);end endtask
 task settled;
 input [3:0] wanted;
 integer guard;
 begin
  guard=0;
  while(!wav_play_en || transition_busy || library_route_busy || library_current_track!=wanted || dut.library_track_pix!=wanted)begin
   tick(1);guard=guard+1;
   if(guard>100000)$fatal(1,"route stuck wanted=%d current=%d page=%d slot=%d route=%b fade=%b wavstate=%d",wanted,library_current_track,library_cache_page,active_index_pix,library_route_busy,transition_busy,dut.wav_control_state);
  end
  if({library_cache_page,selected_song}!=wanted)$fatal(1,"wrong global WAV identity");
 end
 endtask
 reg browse_guard=0;
 always @(posedge sd_card_clk)if(browse_guard&&(!wav_play_en||library_page_start))$fatal(1,"browsing interrupted audio/cache");
 initial begin
  tick(5);sdcard_rst=0;video_rst=0;tick(20);sd_free=1;
  settled(0);k=starts;
  key_mode=1;tick(1);key_mode=0;tick(8000);settled(0);
  if(!thumb_mode_sd||starts!=k||reloads!=0)$fatal(1,"opening browser restarted music");
  browse_guard=1;
  repeat(15)begin key_right=1;tick(1);key_right=0;tick(1100);end
  if(ctrl_focus_track!=15||library_current_track!=0||starts!=k||reloads!=0)$fatal(1,"browse page3 changed playback");
  // Exit without selecting: current song and cache stay at track1/page0.
  browse_guard=0;key_mode=1;tick(1);key_mode=0;tick(8000);settled(0);
  if(thumb_mode_sd||starts!=k||reloads!=0)$fatal(1,"cancel did not return to playing song");
  key_mode=1;tick(1);key_mode=0;tick(8000);settled(0);
  repeat(15)begin key_right=1;tick(1);key_right=0;tick(30);end
  if(ctrl_focus_track!=15)$fatal(1,"second browse failed");
  key_confirm=1;tick(1);key_confirm=0;tick(100);settled(15);
  if(thumb_mode_sd||reloads!=1||starts!=k+1||library_cache_page!=3||selected_song!=3)
   $fatal(1,"global16 confirmation did not load exact page/song once");
  $display("PASS actual top browser: 16-track browsing keeps WAV enabled/no reload/no restart, cancel keeps song1, confirm16 loads page3/song4 exactly once");$finish;
 end

 initial begin #12000000;$fatal(1,"timeout");end
endmodule
