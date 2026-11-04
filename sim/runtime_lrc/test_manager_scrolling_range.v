`timescale 1ns/1ps
`include "scroll_sizes.vh"
module test_manager_scrolling_range;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0;reg vclk=0;always #7 vclk=~vclk;
 reg [11:0] timing_read_addr=0;
 wire [7:0] timing_read_data;wire timing_ready;
 integer font_words=0,check_i;
 reg [1:0] active_song=0;
 reg [3:0] font_bank=12;
 wire ready_for_song,lyric_visible,sector_mode,sector_req;
 wire [31:0] sector_lba;
 reg sector_busy=0,sector_valid=0,sector_done=0;
 reg [7:0] sector_byte=0;
 reg [8:0] sector_byte_index=0;
 wire [7:0] cue_count,cue_index,text_data;
 wire [11:0] font_addr,text_addr,cue_base;
 wire [15:0] font_data,cue_start;
 wire [4:0] cue_len;
 wire font_we,text_we,cue_we;
 always @(posedge clk)if(font_we)font_words=font_words+1;
 reg [7:0] font_bytes[0:262143],lrc_bytes[0:`SCR_LRC_SIZE-1],second[0:`SCR_SECOND_SIZE-1];
 integer n,offset,reads=0,cues=0,chars=0,phase=0;
 reg [31:0] req_lba;
 wire file_start,file_done,file_valid,file_partial;
 wire [31:0] file_start_offset;
 wire [7:0] file_byte,file_error;
 wire [31:0] file_cluster,file_size,file_offset;
 runtime_lyric_manager #(.LIBRARY_MODE(1),.CUE_BITS(8),.TEXT_BITS(12),.MAX_CUES(158),.MAX_TEXT(3072),.KARAOKE(1),.FONT_RANGE_READ(1)) dut(
  .timing_clk(vclk),.timing_read_addr(timing_read_addr),.timing_read_data(timing_read_data),.timing_ready(timing_ready),
  .clk(clk),.rst_n(rst_n),.sd_free(1'b1),.active_song(active_song),.font_bank(font_bank),
  .wav_play_en(1'b0),.wav_file_busy(1'b0),.wav_sector_busy(sector_busy),
  .lrc_valid(4'b0011),.lrc0_cluster(32'd6),.lrc1_cluster(32'd7),.lrc2_cluster(32'd0),.lrc3_cluster(32'd0),
  .lrc0_size(32'd`SCR_LRC_SIZE),.lrc1_size(32'd`SCR_SECOND_SIZE),.lrc2_size(32'd0),.lrc3_size(32'd0),
  .font_valid(1'b1),.font_cluster(32'd2),.font_size(32'd262144),
  .ready_for_song(ready_for_song),.lyric_visible(lyric_visible),.sector_mode(sector_mode),
  .file_start(file_start),.file_cluster(file_cluster),.file_size(file_size),
    .file_start_offset(file_start_offset),.file_partial(file_partial),
  .file_done(file_done),.file_valid(file_valid),.file_byte(file_byte),
  .file_offset(file_offset),.file_error(file_error),
  .cue_count(cue_count),.cue_we(cue_we),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
  .text_we(text_we),.text_addr(text_addr),.text_data(text_data),.font_we(font_we),.font_addr(font_addr),.font_data(font_data));
 // 鐢熶骇鐜FAT閾鹃亶鍘嗙敱sd_card_bmp鍐呭叡浜祦璇诲櫒鎵挎媴锛涜繖閲屾湰鍦板疄渚嬭ˉ鍥烇紝鎵囧尯妯″瀷淇濇寔涓嶅彉
 fat32_file_streamer #(.MAX_VISITED_CLUSTERS(8192),.SEEK_SUPPORT(1),.RANGE_SUPPORT(1)) u_lrc_file(
  .clk(clk),.rst_n(rst_n && sector_mode),.file_start(file_start),.start_offset(file_start_offset),.file_partial(file_partial),
  .first_cluster(file_cluster),.file_size(file_size),
  .sectors_per_cluster(8'd128),.fat_start_lba(32'd1),.data_start_lba(32'd100),.max_cluster(32'd1000),
  .file_busy(),.file_done(file_done),.file_valid(file_valid),
  .file_byte(file_byte),.file_byte_offset(file_offset),.fs_error(file_error),
  .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),.sector_valid(sector_valid),
  .sector_byte(sector_byte),.sector_byte_index(sector_byte_index),.sector_done(sector_done),.sector_error(8'd0));
 always @(posedge clk)begin
  if(cue_we)begin
   if(cue_index!==cues)$fatal(1,"manager cue index truncated %0d/%0d",cue_index,cues);
   cues=cues+1;
  end
  if(text_we)begin
   if(text_addr!==chars)$fatal(1,"manager text address truncated %0d/%0d",text_addr,chars);
   chars=chars+1;
  end
 end
 initial forever begin
  @(negedge clk);
  if(sector_req&&!sector_busy)begin
   sector_busy=1;req_lba=sector_lba;reads=reads+1;
   @(negedge clk);
   for(n=0;n<512;n=n+1)begin
    sector_valid=1;sector_byte_index=n;sector_byte=0;
    if(req_lba>=100&&req_lba<=611)sector_byte=font_bytes[(req_lba-100)*512+n];
    else if(req_lba>=612&&req_lba<620)begin
     offset=(req_lba-612)*512+n;
     if(offset<`SCR_LRC_SIZE)sector_byte=lrc_bytes[offset];
    end else if(req_lba>=740&&req_lba<748)begin
     offset=(req_lba-740)*512+n;
     if(offset<`SCR_SECOND_SIZE)sector_byte=second[offset];
    end else if(req_lba==1)begin
     case(n/4)
      2:sector_byte=n%4==0?3:0;
      3:sector_byte=n%4==0?4:0;
      4:sector_byte=n%4==0?5:0;
      5,6,7:sector_byte=n%4==3?8'h0f:8'hff;
     endcase
    end else $fatal(1,"unexpected LBA %0d",req_lba);
    @(negedge clk);
   end
   sector_valid=0;sector_done=1;@(negedge clk);sector_done=0;sector_busy=0;
  end
 end
 initial begin
  $readmemh("scroll_library_font.hex",font_bytes);
  $readmemh("scroll_lrc.hex",lrc_bytes);
  $readmemh("scroll_second_lrc.hex",second);
  repeat(5)@(negedge clk);rst_n=1;
  wait(ready_for_song);@(negedge clk);
  if(!lyric_visible||cue_count!=132||cues!=132||chars!=2375||reads!=39||!timing_ready||font_words!=4096)$fatal(1,"long manager failed");
  for(check_i=0;check_i<2375;check_i=check_i+1)begin
   @(negedge vclk);timing_read_addr=check_i;repeat(2)@(negedge vclk);
   if(timing_read_data!==font_bytes[12*16384+9216+check_i])$fatal(1,"manager shared timing mismatch");
  end
  phase=1;cues=0;chars=0;font_words=0;active_song=1;font_bank=13;
  wait(!ready_for_song);wait(ready_for_song);@(negedge clk);
  if(!lyric_visible||cue_count!=42||cues!=42||chars!=325||dut.font_song!=13||!timing_ready||font_words!=4096||reads!=73)$fatal(1,"short after long failed");
  // Mismatched timing metadata degrades to line highlight and still plays.
  font_bytes[12*16384+8716]=font_bytes[12*16384+8716]+1;
  cues=0;chars=0;font_words=0;active_song=0;font_bank=12;
  wait(!ready_for_song);wait(ready_for_song);@(negedge clk);
  if(!lyric_visible||timing_ready||cue_count!=132||chars!=2375)$fatal(1,"invalid timing did not degrade safely");
  $display("PASS range scrolling: 24 font/timing sectors instead of1024, real FAT font/LRC/timing pass, all2375 timings, bank12->13, no duplicate glyph/text, mismatched-count fallback");$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
