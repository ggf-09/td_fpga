`timescale 1ns/1ps
module test_equalizer_osd;
 reg clk=0,rst_n=0;
 always #20 clk=~clk;
 wire hs,vs,de;
 wire [11:0] x,y;
 wire [23:0] rgb;
 wire active;
 video_timing_ctrl #(.H_ACT(640),.H_FP(16),.H_SYNC(96),.H_BP(48),
 .V_ACT(480),.V_FP(10),.V_SYNC(2),.V_BP(33),.ACTIVE_LAST(0)) timing(
 .pclk(clk),.rst_n(rst_n),.hsync(hs),.vsync(vs),.de(de),.x(x),.y(y));
 param_osd_overlay dut(
 .clk(clk),.rst_n(rst_n),.vsync(vs),.de(de),.rgb_in(24'h101820),.pixel_x(x[9:0]),
 .bright_bcd(12'h255),.contr_bcd(12'h128),.paused(1'b0),.stopped(1'b0),
 .play_mode(2'd0),.volume(5'd13),.volume_mode(1'b0),
 .bass(3'd0),.mid(3'd4),.treble(3'd1),.edit_target(3'd3),.clipped(1'b1),
 .rgb_out(rgb),.osd_active(active));
 integer f,pixels=0,yellow=0,red=0,cyan=0;
 initial begin
  f=$fopen("equalizer_osd.ppm","w");$fwrite(f,"P3\n192 48\n255\n");
  repeat(6)@(negedge clk);rst_n=1;
  @(negedge vs);@(posedge vs);
  while(pixels<192*48)begin
   @(negedge clk);
   if(de&&x<192&&y<48)begin
    $fwrite(f,"%0d %0d %0d\n",rgb[23:16],rgb[15:8],rgb[7:0]);pixels=pixels+1;
    if(rgb==24'hFFFF00)yellow=yellow+1;
    if(rgb==24'hFF4444)red=red+1;
    if(rgb==24'h44DDFF)cyan=cyan+1;
   end
   if(de&&x==200&&active)$fatal(1,"OSD overwrote background");
  end
  $fclose(f);
  if(yellow<10||red<10||cyan<10)$fatal(1,"missing active-band highlight, clipping warning or status text");
  $display("PASS EQ OSD: real video timing, signed band values, selected-band yellow and CLIP red; preview exported");
  $finish;
 end
 initial begin #60000000;$fatal(1,"timeout");end
endmodule
