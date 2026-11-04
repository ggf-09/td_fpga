`timescale 1ns/1ps
module test_playback_controls;
 reg clk=0,rst_n=0,kn=1,kp=1,kv=1,thumbnail=0;
 always #5 clk=~clk;
 wire ns,prev,tr,tl,tc,tt,au,paused;
 wire [4:0] volume;
 wire [2:0] bright,contrast;
 playback_controls #(.CLOCK_HZ(1000)) dut(clk,rst_n,kn,kp,kv,thumbnail,1'b0,3'b0,
 ns,prev,tr,tl,tc,tt,au,paused,volume,bright,contrast, , , , , , , , , , );
 integer nexts=0,prevs=0,toggles=0,lefts=0,rights=0,confirms=0,autos=0;
 always @(posedge clk) begin
  if(ns)nexts=nexts+1;if(prev)prevs=prevs+1;
  if(tt)toggles=toggles+1;if(tl)lefts=lefts+1;
  if(tr)rights=rights+1;if(tc)confirms=confirms+1;if(au)autos=autos+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task press;input integer key,cycles;begin
  case(key)0:kn=0;1:kp=0;2:kv=0;endcase
  tick(cycles);
  case(key)0:kn=1;1:kp=1;2:kv=1;endcase
  tick(30);
 end endtask
 initial begin
  tick(5);rst_n=1;tick(5);
  press(0,5);tick(600);if(nexts!=0)$fatal(1,"bounce accepted");
  press(0,60);if(nexts!=1)$fatal(1,"next missing");
  press(0,1300);if(prevs!=1||nexts!=1)$fatal(1,"long leaked next");
  press(1,60);tick(850);if(!paused)$fatal(1,"pause missing");
  press(1,60);tick(850);if(paused)$fatal(1,"resume missing");
  press(1,1300);if(volume!=16||paused)$fatal(1,"normal KEY3 long changed volume or pause");
  press(2,60);tick(100);press(2,60);tick(510);
  if(toggles!=1||volume!=16)$fatal(1,"double view leaked volume");
  press(2,60);tick(850);if(volume!=16)$fatal(1,"normal KEY4 single changed volume");
  press(1,60);tick(100);press(1,60);tick(510);
  if(autos!=1||paused)$fatal(1,"auto double leaked pause");
  thumbnail=1;press(0,60);press(0,1300);
  press(2,60);tick(850);
  if(rights!=1||confirms!=1||lefts!=1||nexts!=1||prevs!=1)$fatal(1,"thumbnail navigation regression");
  press(2,1300);if(bright!=1||lefts!=1)$fatal(1,"brightness leaked left");
  // 人因窗口：3.1s松手现在仍是亮度（旧设计>3s就误判成对比度），≥6s才是对比度
  press(2,3100);if(bright!=2||contrast!=0)$fatal(1,"3.1s must be brightness, not contrast");
  press(2,6100);if(contrast!=1)$fatal(1,"contrast missing");
  $display("PASS physical button debounce, short/long/double separation, pause, volume and preserved thumbnail controls");
  $finish;
 end
endmodule

module test_playback_volume;
 reg clk=0,rst_n=0,valid=0,paused=0;
 always #5 clk=~clk;
 reg [4:0] volume=16;
 reg signed [15:0] l=0,r=0;
 wire ov;
 wire signed [15:0] ol,orr;
 playback_volume dut(clk,rst_n,valid,paused,volume,l,r,ov,ol,orr);
 integer gain;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;valid=1;l=-32768;r=32767;
  for(gain=0;gain<=16;gain=gain+1)begin
   volume=gain;@(negedge clk);
   if(!ov||ol!==((-32768*gain)>>>4)||orr!==((32767*gain)>>>4))$fatal(1,"signed gain %d",gain);
  end
  paused=1;@(negedge clk);if(!ov||ol!=0||orr!=0)$fatal(1,"paused cadence");
  paused=0;valid=0;@(negedge clk);if(ov)$fatal(1,"valid pipeline");
  $display("PASS stereo volume all 17 levels, signed full scale, silence and cadence");$finish;
 end
endmodule
