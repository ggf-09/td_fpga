`timescale 1ns/1ps
`include "extended_sizes.vh"
module test_long_lyrics;
 reg sd_clk=0,video_clk=0,rst_n=0;
 always #5 sd_clk=~sd_clk;
 always #7 video_clk=~video_clk;
 reg start_font=0,start_lrc=0,file_valid=0,file_done=0;
 reg [7:0] file_byte=0;
 reg [31:0] file_offset=0;
 wire font_ready,lyric_ready,parse_done,font_we,text_we,cue_we,title_we;
 wire [7:0] cue_count,cue_index,text_data,title_data;
 wire [11:0] font_addr,text_addr,cue_base;
 wire [15:0] font_data,cue_start;
 wire [4:0] cue_len,title_addr,title_count;
 reg vsync=1,de=0;
 reg [9:0] pixel_x=0;
 reg [15:0] play_cs=0;
 wire [23:0] rgb_out;
 wire lyric_active;
 reg [7:0] font_bytes[0:8711],lrc_bytes[0:`EXT_LRC_SIZE-1];
 reg [7:0] text_expected[0:2396],boundary[0:`EXT_BOUND_SIZE-1];
 reg [32:0] cue_expected[0:131];
 integer seen_cues=0,seen_chars=0,phase=0,lit=0,i,j,n,base,length;
 fat_lrc_loader #(.CUE_BITS(8),.TEXT_BITS(12),.MAX_CUES(158),.MAX_TEXT(3072)) loader(
  .clk(sd_clk),.rst_n(rst_n),.start_font(start_font),.start_lrc(start_lrc),
  .file_valid(file_valid),.file_byte(file_byte),.file_offset(file_offset),.file_done(file_done),.file_error(8'd0),
  .font_ready(font_ready),.lyric_ready(lyric_ready),.parse_done(parse_done),
  .font_we(font_we),.font_addr(font_addr),.font_data(font_data),
  .text_we(text_we),.text_addr(text_addr),.text_data(text_data),
  .cue_we(cue_we),.cue_count(cue_count),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
  .title_we(title_we),.title_addr(title_addr),.title_data(title_data),.title_count(title_count));
 runtime_lyric_overlay #(.LYRIC_Y(2),.TITLE_Y(56),.CUE_BITS(8),.TEXT_BITS(12),
  .CUE_STORAGE(160),.TEXT_DEPTH(3072)) overlay(
  .clk(video_clk),.rst_n(rst_n),.vsync(vsync),.de(de),.pixel_x(pixel_x),.rgb_in(24'h123456),
  .enable(1'b1),.play_cs(play_cs),.sd_clk(sd_clk),.ready_sd(lyric_ready),.cue_count_sd(cue_count),
  .cue_we(cue_we),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
  .text_we(text_we),.text_addr(text_addr),.text_data(text_data),
  .font_we(font_we),.font_addr(font_addr),.font_data(font_data),
  .title_we(title_we),.title_addr(title_addr),.title_data(title_data),
  .title_count_sd(title_count),.title_ready_sd(1'b0),.rgb_out(rgb_out),.lyric_active(lyric_active));
 always @(posedge sd_clk)begin
  if(cue_we)begin
   if(phase==0 && (cue_index!==seen_cues || {cue_start,cue_base,cue_len}!==cue_expected[seen_cues]))
    $fatal(1,"cue mismatch %0d index=%0d",seen_cues,cue_index);
   seen_cues=seen_cues+1;
  end
  if(text_we)begin
   if(phase==0 && (text_addr!==seen_chars || text_data!==text_expected[seen_chars]))
    $fatal(1,"text mismatch %0d addr=%0d",seen_chars,text_addr);
   seen_chars=seen_chars+1;
  end
 end
 task frame;
  begin
   @(negedge video_clk);vsync=0;
   repeat(3)@(negedge video_clk);vsync=1;
   repeat(20)@(negedge video_clk);
  end
 endtask
 task check_line;
  input integer index;
  begin
   play_cs=cue_expected[index][32:17];
   for(n=0;n<=index+1;n=n+1)frame;
   repeat(160)@(negedge video_clk);
   base=cue_expected[index][16:5];length=cue_expected[index][4:0];
   if(overlay.cue_cursor!==index || !overlay.cache_valid || overlay.cache_cursor!==index || overlay.char_offset!==base)
    $fatal(1,"overlay cursor/base mismatch index=%0d cursor=%0d base=%0d",index,overlay.cue_cursor,overlay.char_offset);
   for(j=0;j<length;j=j+1)
    if(overlay.glyph_ids[j]!==text_expected[base+j])$fatal(1,"overlay glyph %0d/%0d",index,j);
  end
 endtask
 initial begin
  $readmemh("extended_font.hex",font_bytes);
  $readmemh("extended_lrc.hex",lrc_bytes);
  $readmemh("extended_text.hex",text_expected);
  $readmemh("extended_cues.hex",cue_expected);
  $readmemh("extended_boundary.hex",boundary);
  repeat(5)@(negedge sd_clk);rst_n=1;
  @(negedge sd_clk);start_font=1;
  @(negedge sd_clk);start_font=0;
  for(i=0;i<8712;i=i+1)begin file_valid=1;file_offset=i;file_byte=font_bytes[i];@(negedge sd_clk);end
  file_valid=0;file_done=1;@(negedge sd_clk);file_done=0;
  wait(parse_done);@(negedge sd_clk);if(!font_ready)$fatal(1,"font failed");
  start_lrc=1;@(negedge sd_clk);start_lrc=0;
  for(i=0;i<`EXT_LRC_SIZE;i=i+1)begin file_valid=1;file_offset=i;file_byte=lrc_bytes[i];@(negedge sd_clk);end
  file_valid=0;file_done=1;@(negedge sd_clk);file_done=0;
  wait(parse_done);@(negedge sd_clk);
  if(!lyric_ready || cue_count!=132 || seen_cues!=132 || seen_chars!=2397)$fatal(1,"full Sugar parse mismatch");
  check_line(128);check_line(131);
  // Render the final line from the upper text bank, including actual glyph RAM.
  for(n=0;n<20;n=n+1)begin
   de=1;
   for(i=0;i<640;i=i+1)begin pixel_x=i;#1;if(lyric_active)lit=lit+1;@(negedge video_clk);end
   de=0;repeat(160)@(negedge video_clk);
  end
  if(lit==0)$fatal(1,"upper-bank subtitle did not render");
  play_cs=0;frame;repeat(160)@(negedge video_clk);
  if(overlay.cue_cursor!=0)$fatal(1,"rewind failed");
  phase=1;seen_cues=0;seen_chars=0;
  @(negedge sd_clk);start_lrc=1;@(negedge sd_clk);start_lrc=0;
  for(i=0;i<`EXT_BOUND_SIZE;i=i+1)begin file_valid=1;file_offset=i;file_byte=boundary[i];@(negedge sd_clk);end
  file_valid=0;file_done=1;@(negedge sd_clk);file_done=0;
  wait(parse_done);@(negedge sd_clk);
  if(!lyric_ready || cue_count!=158 || seen_cues!=158 || seen_chars!=158)$fatal(1,"158-cue boundary failed");
  $display("PASS complete Sugar: 132 cues,2397 glyphs; cue128/131, upper text bank, rendering, rewind and158-cue boundary");$finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
