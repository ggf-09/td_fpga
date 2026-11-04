`timescale 1ns/1ps
module test_clip_timeout;
 reg clk=0,rst_n=0,clear=0,iv=0;
 reg signed [15:0] il=0,ir=0;
 wire ready,valid,clipped;
 wire signed [15:0] ol,orr;
 always #5 clk=~clk;
 music_equalizer dut(clk,rst_n,clear,iv,ready,il,ir,3'd4,3'd4,3'd4,5'd16,
 valid,1'b1,ol,orr,clipped);
 integer i;
 task sample;
 input signed [15:0] l,r;
 begin
  il=l;ir=r;iv=1;
  @(posedge clk);while(!ready)@(posedge clk);
  @(negedge clk);iv=0;wait(valid);@(negedge clk);
  @(negedge clk);
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  repeat(300)sample(30000,0);
  if(!clipped||ol!=32767)$fatal(1,"left clipping not detected");
  for(i=0;i<47999;i=i+1)begin
   sample(0,0);if(!clipped)$fatal(1,"CLIP expired before 48000 clean stereo frames");
  end
  repeat(500)@(negedge clk);if(!clipped)$fatal(1,"CLIP timer ran without accepted samples");
  sample(0,0);if(clipped)$fatal(1,"CLIP remained after one second of clean audio");
  sample(0,-30000);if(!clipped||orr!=-32768)$fatal(1,"right clipping not detected");
  repeat(100)sample(0,0);
  sample(30000,0);if(!clipped)$fatal(1,"new peak did not refresh timer");
  for(i=0;i<47999;i=i+1)begin sample(0,0);if(!clipped)$fatal(1,"retrigger hold shortened");end
  sample(0,0);if(clipped)$fatal(1,"retrigger hold failed to expire");
  sample(30000,0);if(!clipped)$fatal(1,"peak before reset");
  clear=1;@(negedge clk);clear=0;@(negedge clk);
  if(clipped)$fatal(1,"track reset did not clear CLIP");
  $display("PASS CLIP timeout: either stereo channel, 48000 clean frames, new-peak refresh, no-input hold and immediate track reset");
  $finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
