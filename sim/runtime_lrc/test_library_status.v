`timescale 1ns/1ps
module test_library_status;
 reg sd_card_clk=0;always #5 sd_card_clk=~sd_card_clk;
 reg video_clk=0;always #20 video_clk=~video_clk;
 reg sdcard_rst=1,video_rst=1,wav_file_start=0;
 reg [1:0] selected_song=0,library_cache_page=0;
 reg [3:0] library_track_pix=0;
 reg [31:0] selected_song_size=0,sample_count=0;
 wire [31:0] ui_total_frames;
 library_ui_cdc_top_fragment cdc(.*);
 reg vsync=1,de=0,stream_active=0,wav_stream_end=0,paused=0,stopped=0;
 reg [9:0] pixel_x=0,pixel_y=48;
 wire [23:0] rgb_out;
 wire osd_active;
 playback_status_overlay #(.INDEX_WIDTH(4)) dut(
 .clk(video_clk),.rst_n(!video_rst),.vsync(vsync),.de(de),.pixel_x(pixel_x),.pixel_y(pixel_y),
 .rgb_in(24'h123456),.sample_count(sample_count),.total_frames(ui_total_frames),
 .song_index(library_track_pix),.stream_active(stream_active),.wav_stream_end(wav_stream_end),
 .paused(paused),.stopped(stopped),.play_mode(2'd0),.rgb_out(rgb_out),.osd_active(osd_active),
 .show_text(1'b1),.transition_active(2'd0));
 task start;
 begin
  @(negedge sd_card_clk);wav_file_start=1;@(negedge sd_card_clk);wav_file_start=0;
  repeat(6)@(negedge video_clk);
 end
 endtask
 task frame;
 begin
  @(negedge video_clk);vsync=0;repeat(4)@(negedge video_clk);vsync=1;
  repeat(500)@(negedge video_clk);
 end
 endtask
 task digits;
 input [7:0] tens,ones;
 begin
  pixel_x=40;#1;if(dut.character!=tens)$fatal(1,"song tens digit wrong");
  pixel_x=48;#1;if(dut.character!=ones)$fatal(1,"song units digit wrong");
 end
 endtask
 initial begin
  repeat(4)@(negedge video_clk);sdcard_rst=0;video_rst=0;
  library_cache_page=1;selected_song=0;library_track_pix=4;
  selected_song_size=44+192000*240;start();
  sample_count=48000*60;stream_active=1;frame();
  if(dut.song_display!=4||dut.elapsed_bcd!=20'h00100||dut.total_bcd!=20'h00400)
   $fatal(1,"track5 duration or identity wrong");
  digits(" ","5");
  stream_active=0;repeat(4)@(negedge video_clk);
  library_cache_page=3;selected_song=3;library_track_pix=15;sample_count=0;
  #1;if(ui_total_frames!=0)$fatal(1,"track16 reused track5 total before file start");
  selected_song_size=44+192000*300;start();stream_active=1;frame();
  if(dut.song_display!=15||dut.total_bcd!=20'h00500||dut.progress_pixels!=0)$fatal(1,"track16 status wrong");
  digits("1","6");
  stream_active=0;repeat(4)@(negedge video_clk);
  library_cache_page=0;library_track_pix=3; // Same physical slot 3, different page.
  #1;if(ui_total_frames!=0)$fatal(1,"same-slot cross-page retained stale total");
  selected_song_size=44+192000*120;start();stream_active=1;frame();
  if(dut.song_display!=3||dut.total_bcd!=20'h00200)$fatal(1,"global identity collapsed to physical slot");
  digits(" ","4");
  $display("PASS 16-track UI: actual length CDC, SONG5/16/4 decimal digits, same-slot page changes and no stale total");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
