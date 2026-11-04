`timescale 1ns/1ps
module test_library_top_integration;
 reg sd_card_clk=0;always #5 sd_card_clk=~sd_card_clk;
 reg video_clk=0;always #20 video_clk=~video_clk;
 reg sdcard_rst=1,video_rst=1,user_next=0,user_previous=0,user_mode_next=0,playback_paused=0;
 reg eos=0,ctrl_transition_req=0,ctrl_transition_select=0,ctrl_view_mode=0;
 reg [1:0] ctrl_focus_index=0,library_cache_page=0;
 reg [15:0] library_catalog_playable=16'h0011;
 reg sd_free=0,library_page_done=0;
 reg [3:0] loader_image_complete=1,song_valid=1;
 wire wav_play_en,wav_file_start,library_page_start,library_route_busy,transition_busy,playlist_stopped,thumb_mode_sd;
 wire [1:0] selected_song,active_index_pix,library_target_page,play_mode;
 wire [3:0] library_current_track;
 reg [7:0] frame_count=0;
 always @(posedge video_clk)frame_count<=frame_count==99?0:frame_count+1'b1;
 wire frame_start_raw=frame_count==0;
 wire [3:0] ctrl_focus_track={library_cache_page,ctrl_focus_index};
 library_top_fragment dut(.*);
 integer starts=0,reloads=0,k;
 reg [1:0] page_captured;
 always @(posedge sd_card_clk)if(wav_file_start)begin
  starts=starts+1;
  if(!sd_free || !dut.library_audio_allowed || dut.library_track_pix!={library_cache_page,selected_song})
    $fatal(1,"WAV started against stale page/slot metadata: cur=%d page=%d sel=%d tpix=%d sd_free=%d aa=%d slot=%d",library_current_track,library_cache_page,selected_song,dut.library_track_pix,sd_free,dut.library_audio_allowed,active_index_pix);
 end
 // Model page-cache loading. The real drain/reset controller and FAT catalog
 // are separately exercised by their dedicated tests.
 // 重载必须慢于淡出（16帧≈6400拍）：重叠加载下page_start在受理拍即发，若页模型
 // 在淡出完成前就sd_free=1，WAV FSM会看到sd_free&&audio_allowed并用新页元数据
 // 重开旧歌——真实硬件页加载~2s远慢于淡出0.27s，不存在该窗口，属模型造假而非RTL缺陷。
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
 initial begin
  tick(5);sdcard_rst=0;video_rst=0;tick(20);sd_free=1;
  settled(0);k=starts;
  user_next=1;tick(1);user_next=0;settled(4);
  if(reloads!=1||starts!=k+1)$fatal(1,"same-slot 1 -> 5 did not reload/restart exactly once");
  user_previous=1;tick(1);user_previous=0;settled(0);
  if(reloads!=2)$fatal(1,"reverse page route failed");
  user_next=1;tick(1);user_next=0;settled(4);
  user_mode_next=1;tick(1);user_mode_next=0;tick(3);
  eos=1;tick(8);eos=0;tick(1200);
  if(!playlist_stopped||wav_play_en||library_current_track!=4)$fatal(1,"ordered stop did not survive global identity");
  user_mode_next=1;tick(1);user_mode_next=0;settled(0);
  // View-only selection commits the same cover without restarting music.
  k=starts;ctrl_view_mode=1;ctrl_transition_req=1;tick(1);ctrl_transition_req=0;
  tick(4);settled(0);
  if(!thumb_mode_sd||starts!=k)$fatal(1,"view toggle changed music");
  // Enable additional slots on this loaded page and confirm a thumbnail.
  library_catalog_playable=16'hffff;song_valid=15;loader_image_complete=15;
  ctrl_focus_index=3;ctrl_transition_select=1;ctrl_view_mode=0;ctrl_transition_req=1;
  tick(1);ctrl_transition_req=0;ctrl_transition_select=0;tick(4);settled(3);
  if(thumb_mode_sd)$fatal(1,"confirm failed to leave thumbnail view");
  user_next=1;tick(1);user_next=0;settled(4);
  $display("PASS actual top library integration: startup/video ACK, same-slot cross-page next/previous, M2 stop/M3 resume, view-only and thumbnail confirm");$finish;
 end
 initial begin #12000000;$fatal(1,"timeout");end
endmodule
