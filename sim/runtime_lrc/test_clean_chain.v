`timescale 1ns/1ps
module clean_test_spectrum(
 input wire enable,de,input wire [9:0] pixel_x,pixel_y,
 input wire [23:0] rgb_in,output wire [23:0] rgb_out
);
 assign rgb_out=enable&&de&&pixel_y==432?24'h406060:rgb_in;
endmodule
module clean_test_lyric_stage(
 input wire de,input wire [9:0] pixel_x,pixel_y,
 input wire [23:0] rgb_in,output wire [23:0] rgb_out
);
 assign rgb_out=de&&pixel_x>=96&&pixel_x<200&&pixel_y>=96&&pixel_y<104?24'hffdd33:
                de&&pixel_x>=96&&pixel_x<300&&pixel_y>=344&&pixel_y<352?24'hff55cc:rgb_in;
endmodule
module test_clean_chain;
 reg clk=0;always #20 clk=~clk;
 reg rst_n=0,vsync=1,de=0,frame_start=0,clean_frame=0,player_enable=1;
 reg [9:0] pixel_x=0,pixel_y=0;
 reg [23:0] adj_rgb=24'h112233;
 reg [31:0] sample_count=0,total_frames=0;
 reg [3:0] song_index=0;reg [1:0] play_mode=0;
 reg stream_active=0,wav_stream_end=0,paused=0,stopped=0;
 reg transition_pref=0,thumbnail=0;
 reg [4:0] volume=16;reg [2:0] bass=2,mid=2,treble=2,brightness=0,contrast=0;reg [3:0] edit_target=0;
 wire [23:0] osd_rgb_out=24'h225566;
 wire [23:0] param_rgb_out=24'h338899;
 wire [23:0] wave_rgb_out,lyric_input_rgb,lyric_rgb_out,player_ui_rgb,presentation_rgb;
 wire [23:0] resolution_rgb_out;
 wire [23:0] video_rgb;wire video_de,video_hs,video_vs,video_clk;
 wire osd_de_out=de;
 integer checks=0,f,x,y;
 resolution_osd_overlay resolution(.de(de),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .show(player_enable&&!thumbnail),.source_width_bcd(16'h1200),.source_height_bcd(16'h1200),
  .rgb_in(param_rgb_out),.rgb_out(resolution_rgb_out),.osd_active());
 clean_test_spectrum spectrum(.enable(player_enable&&!clean_frame),.de(de),
  .pixel_x(pixel_x),.pixel_y(pixel_y),.rgb_in(resolution_rgb_out),.rgb_out(wave_rgb_out));
 assign lyric_input_rgb=clean_frame?adj_rgb:wave_rgb_out;
 clean_test_lyric_stage lyric(.de(de),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .rgb_in(lyric_input_rgb),.rgb_out(lyric_rgb_out));
 playback_status_overlay #(.INDEX_WIDTH(4)) status(
  .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .rgb_in(lyric_rgb_out),.sample_count(sample_count),.total_frames(total_frames),
  .song_index(song_index),.stream_active(stream_active),.wav_stream_end(wav_stream_end),
  .paused(paused),.stopped(stopped),.play_mode(play_mode),.show_text(!clean_frame),
  .transition_active(2'd0),.rgb_out(player_ui_rgb),.osd_active());
 adjust_bar_overlay adjust(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
  .de(de),.clean_mode(clean_frame),.thumbnail(thumbnail),.transition_pref(transition_pref),
  .pixel_x(pixel_x),.pixel_y(pixel_y),.volume(volume),.bass(bass),.mid(mid),.treble(treble),
  .brightness(brightness),.contrast(contrast),.edit_target(edit_target),
  .rgb_in(player_ui_rgb),.rgb_out(presentation_rgb),.osd_active());
 rgb_video_adapter adapter(.pclk(clk),.rst_n(rst_n),.hs_in(1'b1),.vs_in(vsync),
  .de_in(osd_de_out),.rgb_in(presentation_rgb),.video_clk(video_clk),
  .video_hs(video_hs),.video_vs(video_vs),.video_de(video_de),.video_rgb(video_rgb));
 task check;input condition;input [511:0] message;begin
  if(!condition)begin $display("FAIL clean chain: %0s",message);$fatal(1);end
  checks=checks+1;
 end endtask
 task pixel;input [9:0] x,y;begin @(negedge clk);pixel_x=x;pixel_y=y;de=1;#1;end endtask
 task frame;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;frame();
  pixel(200,200);check(presentation_rgb==24'h338899,"normal chain retains diagnostic and parameter OSD");
  pixel(498,32);check(presentation_rgb==24'h44ddff,"normal chain shows real source resolution");
  pixel(100,432);check(presentation_rgb==24'h406060,"normal chain retains spectrum");
  pixel(8,48);check(presentation_rgb==24'h101018,"normal chain retains playback status text");
  pixel(100,100);check(presentation_rgb==24'hffdd33,"title stage remains downstream");
  pixel(100,350);check(presentation_rgb==24'hff55cc,"lyric stage remains downstream");
  clean_frame=1;frame();
  pixel(200,200);check(presentation_rgb==adj_rgb,"clean mode bypasses diagnostic and parameter OSD");
  pixel(498,32);check(presentation_rgb==adj_rgb,"clean mode removes source resolution OSD");
  pixel(100,432);check(presentation_rgb==adj_rgb,"clean mode removes spectrum pixels");
  pixel(8,48);check(presentation_rgb==adj_rgb,"clean mode removes status text without changing base RGB");
  pixel(100,100);check(presentation_rgb==24'hffdd33,"clean mode preserves title");
  pixel(100,350);check(presentation_rgb==24'hff55cc,"clean mode preserves three-line lyric stage");
  pixel(16,468);check(presentation_rgb==24'ha0a0a0,"clean mode preserves progress border");
  edit_target=1;frame();pixel(240,446);
  check(presentation_rgb==adj_rgb,"clean mode suppresses adjustment feedback");
  clean_frame=0;frame();pixel(240,446);
  check(presentation_rgb==24'h44ddff,"leaving clean mode restores adjustment feedback");
  thumbnail=1;pixel(498,32);
  check(presentation_rgb==24'h338899,"browser mode suppresses full-screen resolution OSD");
  thumbnail=0;pixel(498,32);
  check(presentation_rgb==24'h44ddff,"full-screen resolution OSD returns after browser");
  @(negedge clk);de=0;@(posedge clk);#1;
  check(!video_de&&video_rgb==0,"adapter keeps de low and blanks RGB during blanking");
  pixel(100,100);@(posedge clk);#1;
  check(video_de&&video_rgb==24'hffdd33,"adapter de and title RGB remain aligned");
  edit_target=0;clean_frame=0;frame();
  f=$fopen("clean_normal_preview.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");
  for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
   pixel(x,y);$fwrite(f,"%c%c%c",presentation_rgb[23:16],presentation_rgb[15:8],presentation_rgb[7:0]);
  end
  $fclose(f);clean_frame=1;frame();
  f=$fopen("clean_mode_preview.ppm","wb");$fwrite(f,"P6\n640 480\n255\n");
  for(y=0;y<480;y=y+1)for(x=0;x<640;x=x+1)begin
   pixel(x,y);$fwrite(f,"%c%c%c",presentation_rgb[23:16],presentation_rgb[15:8],presentation_rgb[7:0]);
  end
  $fclose(f);
  $display("PASS clean chain: %0d checks; bypass, title/lyrics/progress retention, adjustment gate and de alignment",checks);
  $finish;
 end
 initial begin #50000000;$fatal(1,"clean chain timeout");end
endmodule
