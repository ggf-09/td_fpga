`timescale 1ns/1ps
module test_seek_top;
 reg sd_card_clk=0,video_clk=0,sdcard_rst=1,video_rst=1;
 always #10 sd_card_clk=~sd_card_clk;always #20 video_clk=~video_clk;
 reg [3:0] ticks=0;
 always @(posedge video_clk)ticks<=ticks+1'b1;
 wire wav_sample_tick=ticks==0;
 reg playback_paused=0,user_seek_back=0,user_seek_forward=0,transition_busy=0,sequence_replay=0;
 reg [1:0] active_idx_sd2=0;
 reg accepted_manual=0,manual_same_song=0;
 reg wav_sector_busy=0,wav_sector_valid=0,wav_sector_done=0;
 reg [7:0] wav_sector_byte=0,wav_sector_error=0;
 reg [8:0] wav_sector_byte_index=0;
 wire wav_file_sector_req,wav_sample_valid,wav_play_en,wav_file_start;
 wire [31:0] wav_file_sector_lba,wav_position;
 wire [15:0] lyric_cs;
 wire signed [15:0] wav_left_out,wav_right_out;
 wire [7:0] envelope;
 wire [3:0] transport_state;
 seek_top_fragment dut(.*);
 integer request,n,cluster,entry,file_offset,frame,byte_lane,starts=0,checked=0,request_logical;
 integer expected_origin=0;
 reg [31:0] held_position,first_candidate;
 reg [31:0] previous_count=0;
 reg monitor_audio=1;
 function [7:0] header_byte;input integer o;
 begin case(o)
  0:header_byte="R";1:header_byte="I";2,3:header_byte="F";
  8:header_byte="W";9:header_byte="A";10:header_byte="V";11:header_byte="E";
  12:header_byte="f";13:header_byte="m";14:header_byte="t";15:header_byte=" ";
  16:header_byte=16;20:header_byte=1;22:header_byte=2;
  24:header_byte=8'h80;25:header_byte=8'hbb;29:header_byte=8'hee;30:header_byte=2;
  32:header_byte=4;34:header_byte=16;
  36:header_byte="d";37:header_byte="a";38:header_byte="t";39:header_byte="a";
  default:header_byte=0;
 endcase end endfunction
 always @(posedge sd_card_clk)if(!sdcard_rst && wav_file_start)starts=starts+1;
 // Fragmented file: cluster 10 + ordinal*9, 64 sectors/cluster.
 initial forever begin
  @(negedge sd_card_clk);
  if(wav_file_sector_req && !wav_sector_busy)begin
   wav_sector_busy=1;request=wav_file_sector_lba;
   if(request>=100)begin
    cluster=(request-100)/64+2;
    if(cluster<10 || (cluster-10)%9!=0)$fatal(1,"unowned data cluster %0d",cluster);
    request_logical=(cluster-10)/9;
    file_offset=request_logical*32768+((request-100)%64)*512;
   end
   // Model a nonzero command/token wait before sector payload.
   repeat(12)@(negedge sd_card_clk);
   for(n=0;n<512;n=n+1)begin
    wav_sector_valid=1;wav_sector_byte_index=n;
    if(request<100)begin
     cluster=(request-1)*128+n/4;entry=cluster+9;
     if(cluster>=2116)entry=28'hfffffff;
     wav_sector_byte=(entry>>((n%4)*8))&255;
    end else if(file_offset+n<44)wav_sector_byte=header_byte(file_offset+n);
    else begin
     frame=(file_offset+n-44)/4;byte_lane=(file_offset+n-44)%4;
     if(byte_lane<2)wav_sector_byte=(frame>>(byte_lane*8))&255;
     else wav_sector_byte=((~frame)>>((byte_lane-2)*8))&255;
    end
    @(negedge sd_card_clk);
   end
   wav_sector_valid=0;wav_sector_done=1;@(negedge sd_card_clk);wav_sector_done=0;wav_sector_busy=0;
  end
 end
 // Check every actually consumed output frame, including the first after restart.
 always @(negedge video_clk)if(!video_rst && wav_sample_valid)begin
  if(playback_paused)begin
   if(wav_left_out!==0||wav_right_out!==0)$fatal(1,"pause not silent");
  end else if(dut.wav_sample_cnt!=0 && dut.wav_sample_cnt!=previous_count)begin
   frame=dut.wav_origin_pix+dut.wav_sample_cnt-1;
   if(wav_left_out!==frame[15:0] || wav_right_out!==~frame[15:0])
    $fatal(1,"stale/misaligned PCM after seek: source%0d L%h R%h",frame,wav_left_out,wav_right_out);
   checked=checked+1;
  end
  previous_count=dut.wav_sample_cnt;
 end
 task seek;input backward;
 begin
  @(negedge sd_card_clk);user_seek_back=backward;user_seek_forward=!backward;
  @(negedge sd_card_clk);user_seek_back=0;user_seek_forward=0;
  wait(transport_state==7);wait(dut.seek_calc==5);
  first_candidate=dut.seek_target;
  wait(transport_state==8);
  if(envelope!=0 || wav_play_en)$fatal(1,"stream reset before mute");
  wait(wav_file_start);repeat(12)@(negedge video_clk);
  if(dut.wav_origin_pix!=first_candidate)$fatal(1,"seek origin CDC mismatch");
  wait(!wav_sector_busy);
  if(first_candidate<1919990)wait(dut.u_wav_player.wr_ptr>10);
  else wait(dut.wav_file_done);
  repeat(200)@(negedge video_clk);
  if(lyric_cs!=wav_position/480)$fatal(1,"lyric clock not relocated");
 end endtask
 initial begin
  repeat(5)@(negedge sd_card_clk);sdcard_rst=0;video_rst=0;
  wait(transport_state==3);@(negedge sd_card_clk);user_seek_forward=1;
  @(negedge sd_card_clk);user_seek_forward=0;repeat(2)@(negedge sd_card_clk);
  if(transport_state!=3)$fatal(1,"seek bypassed initial header validation");
  wait(checked>100);
  seek(0);
  if(first_candidate<480000 || first_candidate>482000 || starts!=2)$fatal(1,"forward 10 seconds target/restart mismatch");
  wait(envelope==255);wait(checked>700);
  playback_paused=1;repeat(50)@(negedge video_clk);
  seek(1);
  if(first_candidate>5000||starts!=3)$fatal(1,"backward 10 seconds mismatch");
  held_position=wav_position;repeat(600)@(negedge video_clk);
  if(wav_position!=held_position||!playback_paused)$fatal(1,"paused seek resumed or drifted");
  seek(1);if(first_candidate!=0||starts!=4)$fatal(1,"beginning not clamped");
  playback_paused=0;wait(checked>800);
  // Ignore jump commands during an existing cover transition.
  transition_busy=1;@(negedge sd_card_clk);user_seek_forward=1;
  @(negedge sd_card_clk);user_seek_forward=0;repeat(100)@(negedge sd_card_clk);
  if(starts!=4||transport_state!=3)$fatal(1,"seek raced track transition");
  transition_busy=0;
  // Jumping beyond end clamps to the last valid PCM frame; natural EOF
  // still drains and reaches ENDED. Replay must clear the previous origin.
  seek(0);seek(0);seek(0);seek(0);
  if(first_candidate!=1919999 || starts!=8)$fatal(1,"end not clamped to last frame");
  wait(transport_state==6);
  if(dut.wav_start_offset!=7680040 || dut.wav_file_error)$fatal(1,"last frame offset/chain invalid");
  @(negedge sd_card_clk);sequence_replay=1;@(negedge sd_card_clk);sequence_replay=0;
  wait(wav_file_start);repeat(15)@(negedge video_clk);
  if(dut.wav_origin_pix!=0 || dut.wav_start_offset!=0 || starts!=9)$fatal(1,"normal replay retained seek origin");
  wait(dut.wav_sample_cnt>100);
  // A song change cancels an in-progress jump and starts the new song at 0.
  @(negedge sd_card_clk);user_seek_forward=1;@(negedge sd_card_clk);user_seek_forward=0;
  wait(transport_state==7);@(negedge sd_card_clk);active_idx_sd2=1;
  wait(wav_file_start);repeat(15)@(negedge video_clk);
  if(dut.wav_origin_pix!=0 || dut.wav_start_offset!=0 || dut.selected_song!=1)$fatal(1,"song change retained pending seek");
  wait(dut.wav_file_offset>=44);repeat(2)@(negedge sd_card_clk);
  // A same-song manual replay accepted during seek must survive the
  // intermediate seek restart and eventually reopen the file from its header.
  @(negedge sd_card_clk);user_seek_forward=1;@(negedge sd_card_clk);user_seek_forward=0;
  wait(transport_state==7);@(negedge sd_card_clk);accepted_manual=1;manual_same_song=1;
  @(negedge sd_card_clk);accepted_manual=0;manual_same_song=0;
  wait(wav_file_start);repeat(5)@(negedge sd_card_clk);
  if(!dut.manual_replay_pending)$fatal(1,"seek restart discarded manual replay");
  wait(transport_state==6);wait(wav_file_start);repeat(15)@(negedge video_clk);
  if(dut.wav_origin_pix!=0 || dut.wav_start_offset!=0)$fatal(1,"manual replay failed to reset seek origin");
  if(dut.wav_format_error)$fatal(1,"seek generated format error");
  $display("PASS actual top transport: fragmented FAT + asynchronous WAV FIFO, +/-10s origins, first PCM frame order, muted reset/drain, paused seek freeze, beginning clamp, lyric time, last-frame EOF/replay and transition cancellation (%0d stereo samples)",checked);$finish;
 end
 initial begin #40000000;$fatal(1,"timeout state%0d starts%0d checked%0d",transport_state,starts,checked);end
endmodule
