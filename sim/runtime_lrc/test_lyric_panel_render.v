`timescale 1ns/1ps
module test_lyric_panel_render;
 reg clk=0,rst_n=0;always #20 clk=~clk;
 reg vsync=1,de=0;reg [9:0] pixel_x=0;
 reg [1:0] alpha=1;reg [2:0] pos=7;
 reg ready=0,cue_we=0,text_we=0,font_we=0,title_we=0;
 reg [2:0] cue_index=0;reg [15:0] cue_start=0,font_data=0;
 reg [10:0] cue_base=0,text_addr=0;
 reg [7:0] text_data=1,title_data=1;reg [11:0] font_addr=0;
 reg [4:0] title_addr=0;
 wire [23:0] rgb;wire active;wire [11:0] timing_addr;
 wire visible_ready;
 lyric_visibility_fragment visibility(.sd_card_clk(clk),.sdcard_rst_n(rst_n),.lyric_visible(ready),.lyric_visible_export(visible_ready));
 scrolling_lyric_overlay #(.CUE_BITS(3),.TEXT_BITS(11),.CUE_STORAGE(8),.TEXT_DEPTH(64)) dut(
 .clk(clk),.rst_n(rst_n),.vsync(vsync),.de(de),.rgb_in(24'h80c0fc),.pixel_x(pixel_x),
 .enable(1'b1),.panel_alpha(alpha),.panel_position(pos),.play_cs(16'd150),.sd_clk(clk),.ready_sd(visible_ready),
 .cue_count_sd(3'd3),.cue_we(cue_we),.cue_index(cue_index),.cue_start(cue_start),.cue_base(cue_base),.cue_len(5'd1),
 .text_we(text_we),.text_addr(text_addr),.text_data(text_data),.font_we(font_we),.font_addr(font_addr),.font_data(font_data),
 .title_we(title_we),.title_addr(title_addr),.title_data(title_data),.title_count_sd(5'd1),.title_ready_sd(visible_ready),
 .timing_ready_sd(1'b0),.timing_read_addr(timing_addr),.timing_read_data(8'd0),.rgb_out(rgb),.lyric_active(active));
 integer a,p,y,x,i,shift,top,bottom,previous_count,current_count,next_count,title_count;
 reg [23:0] expected;
 task blank;begin
  @(negedge clk);de=0;vsync=0;repeat(4)@(negedge clk);vsync=1;repeat(100)@(negedge clk);
 end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  for(i=0;i<3;i=i+1)begin
   cue_index=i;cue_start=i*100;cue_base=i;cue_we=1;
   text_addr=i;text_we=1;@(negedge clk);
  end
  cue_we=0;text_we=0;
  for(i=0;i<16;i=i+1)begin font_addr=16+i;font_data=16'h8000;font_we=1;@(negedge clk);end
  font_we=0;title_we=1;@(negedge clk);title_we=0;ready=1;
  repeat(1000)@(negedge clk);repeat(14)blank();
  if(dut.cue_cursor!=1||!dut.prev_ok||!dut.next_ok)$fatal(1,"test cache not ready");
  for(p=7;p>=0;p=p-1)for(a=0;a<4;a=a+1)begin
   pos=p;alpha=a;blank();
   shift=(7-p)*32;top=312-shift;bottom=400-shift;
   expected=a==0?24'h000000:a==1?24'h20303f:a==2?24'h40607e:24'h80c0fc;
   previous_count=0;current_count=0;next_count=0;title_count=0;
   for(y=0;y<410;y=y+1)begin
    for(x=0;x<640;x=x+1)begin
     @(negedge clk);de=1;pixel_x=x;#1;
     if(x==40)begin
      if(rgb!==(y>=top&&y<bottom?expected:24'h80c0fc))$fatal(1,"panel mismatch pos=%0d alpha=%0d y=%0d rgb=%h",p,a,y,rgb);
     end
     if(x==311 && (rgb==24'hffe000||rgb==24'hb0b8c8))begin
      if(y>=56&&y<72)title_count=title_count+1;
      else if(y>=320-shift&&y<336-shift)previous_count=previous_count+1;
      else if(y>=344-shift&&y<360-shift)current_count=current_count+1;
      else if(y>=368-shift&&y<384-shift)next_count=next_count+1;
      else $fatal(1,"stale or detached text outside moved rows y=%0d pos=%0d",y,p);
     end
     if(y==200&&x==600)begin alpha=3-a;pos=7-p;end
    end
    @(negedge clk);de=0;repeat(159)@(negedge clk);
   end
   if(previous_count!=16||current_count!=16||next_count!=16||title_count!=16)
    $fatal(1,"glyph/row loss pos=%0d alpha=%0d counts=%0d/%0d/%0d title%0d",p,a,previous_count,current_count,next_count,title_count);
  end
  $display("PASS lyric renderer: all32 alpha/position profiles, exact RGB, all3 lyric rows move together, title fixed, no mid-frame tearing or old-row ghosts");$finish;
 end
 initial begin #1000000000;$fatal(1,"renderer timeout");end
endmodule
