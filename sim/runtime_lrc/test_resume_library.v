`timescale 1ns/1ps
module test_resume_library;
 reg sd_card_clk=0,video_clk=0;always #10 sd_card_clk=~sd_card_clk;always #20 video_clk=~video_clk;
 reg sdcard_rst=1,video_rst=1,checkpoint_boot_ready=0,checkpoint_restore_valid=1;
 reg [3:0] checkpoint_restore_track=0;
 reg [31:0] checkpoint_restore_frame=480123,checkpoint_restore_size=4000044,checkpoint_restore_cluster=10;
 reg user_next=0,user_previous=0,user_mode_next=0,playback_paused=0,eos=0;
 reg ctrl_transition_req=0,ctrl_transition_select=0,ctrl_view_mode=0;
 reg [1:0] ctrl_focus_index=0,library_cache_page=0;
 wire [3:0] ctrl_focus_track={library_cache_page,ctrl_focus_index};
 reg [15:0] library_catalog_playable=16'hffff;
 reg sd_free=0,library_page_done=0;
 reg [3:0] loader_image_complete=0,song_valid=0;
 wire wav_play_en,wav_file_start,library_page_start,library_route_busy,transition_busy,playlist_stopped,thumb_mode_sd;
 wire [1:0] selected_song,active_index_pix,library_target_page,play_mode;
 wire [3:0] library_current_track;
 reg [7:0] frame_count=0;
 always @(posedge video_clk)frame_count<=frame_count==79?0:frame_count+1'b1;
 wire frame_start_raw=frame_count==0;
 resume_library_fragment dut(.*);
 integer starts=0,reloads=0,trial,guard,wanted;

 reg [1:0] pending_page;
 always @(posedge sd_card_clk)if(!sdcard_rst&&wav_file_start)begin
  starts=starts+1;
  if(!dut.resume_ready || dut.resume_hold_audio)$fatal(1,"audio started before resume route completed");
  if(dut.wav_origin_sd!=480123 || dut.wav_start_offset!=1920536)$fatal(1,"restored position lost on first WAV start");
 end
 initial forever begin
  @(negedge sd_card_clk);
  if(!sdcard_rst&&library_page_start)begin
   pending_page=library_target_page;reloads=reloads+1;sd_free=0;
   repeat(4)@(negedge sd_card_clk);loader_image_complete=0;song_valid=0;
   repeat(15000)@(negedge sd_card_clk);
   library_cache_page=pending_page;loader_image_complete=15;song_valid=15;
   sd_free=1;library_page_done=1;@(negedge sd_card_clk);library_page_done=0;
  end
 end
 task tick;input integer n;begin repeat(n)@(negedge sd_card_clk);end endtask
 initial begin
  for(trial=0;trial<32;trial=trial+1)begin
   sdcard_rst=1;video_rst=1;checkpoint_boot_ready=0;sd_free=0;library_page_done=0;
   library_cache_page=0;loader_image_complete=0;song_valid=0;starts=0;reloads=0;
   wanted=trial%16;checkpoint_restore_track=wanted;checkpoint_restore_cluster=10+wanted;
   tick(7+trial);sdcard_rst=0;video_rst=0;
   if(trial<16)begin tick(20);checkpoint_boot_ready=1;tick(500);end
   else tick(520);
   loader_image_complete=15;song_valid=15;sd_free=1;
   if(trial>=16)begin tick(20000);checkpoint_boot_ready=1;end
   guard=0;
   while(!wav_play_en||transition_busy||library_route_busy||library_current_track!=wanted||dut.library_track_pix!=wanted)begin
    tick(1);guard=guard+1;
    if(guard>100000)$fatal(1,"startup deadlock track=%0d resume=%0d router=%0d fade=%0d wav=%0d",wanted,dut.u_resume_startup.state,dut.u_library_router.state,dut.u_fade_transition.g_fade.state,dut.wav_control_state);
   end
   tick(20);
   if(starts!=1)$fatal(1,"startup did not produce exactly one WAV start: %0d",starts);
   if(dut.resume_apply)$fatal(1,"resume offset was not consumed");
   if(reloads!=(wanted>=4?1:0))$fatal(1,"unexpected page reload count");
  end
  $display("PASS integrated resume boot: all 16 tracks, early/late records, same-track restart, page reload, real fade/video ACK and exactly one positioned WAV start");$finish;
 end
 initial begin #100000000;$fatal(1,"integrated startup timeout");end
endmodule
