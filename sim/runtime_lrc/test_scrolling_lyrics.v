`timescale 1ns/1ps
`include "scroll_sizes.vh"
module test_scrolling_lyrics;
 reg clk=0,vclk=0,rst_n=0;
 always #5 clk=~clk;always #20 vclk=~vclk;
 reg start_font=0,start_lrc=0,start_timing=0,file_valid=0,file_done=0;
 reg [7:0] file_byte=0;reg [31:0] file_offset=0;
 wire font_ready,lyric_ready,parse_done,font_we,text_we,cue_we,title_we,timing_available,timing_ready;
 wire [7:0] cue_count,cue_index,text_data,title_data,timing_data;
 wire [11:0] font_addr,text_addr,cue_base,cache_addr;
 wire [15:0] font_data,cue_start;
 wire [4:0] cue_len,title_addr,title_count;
 reg allow_ready=0,probe=1;
 reg [11:0] probe_addr=0;
 reg vsync=1,de=0;reg [9:0] pixel_x=0;reg [15:0] play_cs=0;
 wire [23:0] rgb_out;wire lyric_active;
 reg [7:0] font_bytes[0:16383],lrc_bytes[0:`SCR_LRC_SIZE-1];
 reg [15:0] pairs[0:`SCR_CHARS-1];reg [32:0] cues[0:131];
 integer i,j,k,n,base,length,f,y,x,gold=0,white=0,dim=0;
 fat_lrc_loader #(.CUE_BITS(8),.TEXT_BITS(12),.MAX_CUES(158),.MAX_TEXT(3072),.KARAOKE(1)) loader(
  .clk(clk),.rst_n(rst_n),.start_font(start_font),.start_lrc(start_lrc),.start_timing(start_timing),
  .timing_clk(vclk),.timing_read_addr(probe?probe_addr:cache_addr),.timing_read_data(timing_data),
  .timing_available(timing_available),.timing_ready(timing_ready),
  .file_valid(file_valid),.file_byte(file_byte),.file_offset(file_offset),.file_done(file_done),.file_error(8'd0),
  .font_ready(font_ready),.lyric_ready(lyric_ready),.parse_done(parse_done),
  .font_we(font_we),.font_addr(font_addr),.font_data(font_data),.text_we(text_we),.text_addr(text_addr),.text_data(text_data),
  .cue_we(cue_we),.cue_count(cue_count),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
  .title_we(title_we),.title_addr(title_addr),.title_data(title_data),.title_count(title_count));
 scrolling_lyric_overlay overlay(
  .clk(vclk),.rst_n(rst_n),.vsync(vsync),.de(de),.pixel_x(pixel_x),.rgb_in(24'h204080),
  .enable(1'b1),.play_cs(play_cs),.sd_clk(clk),.ready_sd(lyric_ready&&timing_ready&&allow_ready),.cue_count_sd(cue_count),
  .cue_we(cue_we),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(cue_len),
  .text_we(text_we),.text_addr(text_addr),.text_data(text_data),.font_we(font_we),.font_addr(font_addr),.font_data(font_data),
  .title_we(title_we),.title_addr(title_addr),.title_data(title_data),.title_count_sd(title_count),.title_ready_sd(lyric_ready&&allow_ready),
  .timing_ready_sd(timing_ready),.timing_read_addr(cache_addr),.timing_read_data(timing_data),
  .rgb_out(rgb_out),.lyric_active(lyric_active));
 task font_transfer;
  begin
   for(i=0;i<16384;i=i+1)begin file_valid=1;file_offset=i;file_byte=font_bytes[i];@(negedge clk);end
   file_valid=0;file_done=1;@(negedge clk);file_done=0;wait(parse_done);@(negedge clk);
  end
 endtask
 task frame;
  begin @(negedge vclk);vsync=0;repeat(3)@(negedge vclk);vsync=1;repeat(300)@(negedge vclk);end
 endtask
 task check_current;
  input integer index;
  begin
   base=cues[index][16:5];length=cues[index][4:0];
   if(overlay.cue_cursor!==index || !overlay.cur_ok || overlay.cache_start[index%4]!==cues[index][32:17])
    $fatal(1,"cursor/metadata mismatch index=%0d cursor=%0d",index,overlay.cue_cursor);
   for(j=0;j<length;j=j+1)
    if(overlay.cache_text[(index%4)*32+j]!==pairs[base+j])
     $fatal(1,"ring-cache mismatch cue=%0d char=%0d got=%h exp=%h",index,j,overlay.cache_text[(index%4)*32+j],pairs[base+j]);
  end
 endtask
 initial begin
  $readmemh("scroll_font.hex",font_bytes);$readmemh("scroll_lrc.hex",lrc_bytes);
  $readmemh("scroll_pairs.hex",pairs);$readmemh("scroll_cues.hex",cues);
  repeat(5)@(negedge clk);rst_n=1;start_font=1;@(negedge clk);start_font=0;font_transfer;
  if(!font_ready || !timing_available)$fatal(1,"timed font header not recognized");
  start_lrc=1;@(negedge clk);start_lrc=0;
  for(i=0;i<`SCR_LRC_SIZE;i=i+1)begin file_valid=1;file_offset=i;file_byte=lrc_bytes[i];@(negedge clk);end
  file_valid=0;file_done=1;@(negedge clk);file_done=0;wait(parse_done);@(negedge clk);
  if(!lyric_ready || cue_count!=132 || timing_ready)$fatal(1,"LRC parse or premature timing ready");
  start_timing=1;@(negedge clk);start_timing=0;font_transfer;
  if(!timing_ready)$fatal(1,"reused raw RAM not ready");
  for(k=0;k<`SCR_CHARS;k=k+1)begin
   @(negedge vclk);probe_addr=k;repeat(2)@(negedge vclk);
   if(timing_data!==pairs[k][15:8])$fatal(1,"shared timing RAM mismatch %0d",k);
  end
  probe=0;allow_ready=1;repeat(400)@(negedge vclk);check_current(0);
  for(n=1;n<132;n=n+1)begin
   play_cs=cues[n][32:17]-1;repeat(1000)@(negedge vclk);
   play_cs=cues[n][32:17];frame;check_current(n);
   if(n>1 && !overlay.prev_ok)$fatal(1,"missing previous line");
   if(n<131 && !overlay.next_ok)$fatal(1,"missing next line");
   if(overlay.scroll_offset!=24)$fatal(1,"scroll did not start from prior row position");
  end
  // Nonzero backwards and large forwards seek must relocate without frame-by-frame chasing.
  play_cs=cues[4][32:17]+1;repeat(1000)@(negedge vclk);check_current(4);
  play_cs=cues[120][32:17]+1;repeat(1000)@(negedge vclk);check_current(120);
  play_cs=cues[2][32:17]+1;repeat(1000)@(negedge vclk);check_current(2);
  // Rewind, then render an early sung line with both lit and pending words.
  play_cs=0;frame;check_current(0);
  for(n=1;n<=10;n=n+1)begin play_cs=cues[n][32:17];frame;end
  play_cs=cues[10][32:17]+60;
  repeat(12)frame;
  if(overlay.scroll_offset!=0)$fatal(1,"scroll animation did not settle");
  f=$fopen("scroll_preview.rgb","wb");
  @(negedge vclk);vsync=0;repeat(3)@(negedge vclk);vsync=1;
  for(y=0;y<400;y=y+1)begin
   for(x=0;x<640;x=x+1)begin
    @(negedge vclk);de=1;pixel_x=x;#1;
    if(y>=304)begin
     $fwrite(f,"%c%c%c",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
     if(rgb_out==24'hffe000)gold=gold+1;
     if(rgb_out==24'hffffff)white=white+1;
     if(rgb_out==24'hb0b8c8)dim=dim+1;
    end
   end
   @(negedge vclk);de=0;repeat(159)@(negedge vclk);
  end
  $fclose(f);
  if(gold<10||white<10||dim<10)$fatal(1,"missing highlight/pending/context colors %0d/%0d/%0d",gold,white,dim);
  // Loading a different song must withdraw cached payload immediately.
  allow_ready=0;repeat(8)@(negedge vclk);
  if(overlay.cache_valid!=0)$fatal(1,"stale lyrics after song change");
  $display("PASS scrolling real Sugar: shared timing RAM all2375, all132 cue ring wraps, preview, smooth offsets, rewind, highlight/pending/context, invalidation");$finish;
 end
 initial begin #50000000;$fatal(1,"timeout");end
endmodule
