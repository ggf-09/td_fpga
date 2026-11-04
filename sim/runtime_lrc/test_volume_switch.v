`timescale 1ns/1ps
module test_volume_switch;
 reg clk=0,rst_n=0,kn=1,kp=1,kv=1,thumbnail=0,sw=0;
 always #5 clk=~clk;
 wire ns,prev,tr,tl,tc,tt,mode_next,paused,volume_mode;
 wire [4:0] volume;
 wire [2:0] bright,contrast;
 playback_controls #(.CLOCK_HZ(1000)) dut(clk,rst_n,kn,kp,kv,thumbnail,sw,3'b0,
 ns,prev,tr,tl,tc,tt,mode_next,paused,volume,bright,contrast,volume_mode, , , , , , , , , );
 integer mode_count=0,view_count=0,left_count=0,i;
 always @(posedge clk)begin
  if(mode_next)mode_count=mode_count+1;
  if(tt)view_count=view_count+1;
  if(tl)left_count=left_count+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task click3;begin kp=0;tick(30);kp=1;tick(30);end endtask
 task click4;begin kv=0;tick(30);kv=1;tick(30);end endtask
 initial begin
  tick(4);rst_n=1;tick(80);
  sw=1;tick(5);sw=0;tick(30);if(volume_mode)$fatal(1,"switch bounce accepted");
  sw=1;tick(80);if(!volume_mode)$fatal(1,"SW1 up not volume mode");
  kp=0;tick(30);if(volume!=15||paused)$fatal(1,"KEY3 not immediate one-step volume down");
  tick(3100);if(volume!=0||paused)$fatal(1,"hold must auto-repeat down to clamp 0");
  kp=1;tick(30);if(volume!=0)$fatal(1,"release repeated volume action");
  click3();click3();if(volume!=0||mode_count)$fatal(1,"rapid clicks became playback-mode double");
  click4();click4();if(volume!=2||view_count)$fatal(1,"rapid clicks became thumbnail double");
  for(i=0;i<20;i=i+1)click4();if(volume!=16)$fatal(1,"upper volume clamp");
  for(i=0;i<20;i=i+1)click3();if(volume!=0)$fatal(1,"lower volume clamp");
  thumbnail=1;click4();if(volume!=1||left_count||view_count||bright||contrast)$fatal(1,"volume mode changed thumbnail settings");
  kp=0;kv=0;tick(30);kp=1;kv=1;tick(30);if(volume!=1)$fatal(1,"simultaneous +/- should cancel");
  // Switching back while a key is held must not cause a pause on release.
  kp=0;tick(30);sw=0;tick(80);kp=1;tick(650);
  if(volume_mode||paused||mode_count)$fatal(1,"held key leaked normal action across switch");
  click3();tick(850);if(!paused)$fatal(1,"normal pause did not return");
  // A pending single click is discarded when entering volume mode.
  click3();sw=1;tick(650);if(!paused)$fatal(1,"pending normal click leaked across switch");
  if(mode_count||view_count||left_count)$fatal(1,"unexpected navigation during volume editing");
  $display("PASS SW1 debounce, immediate +/- clicks, hold auto-repeat, clamps, simultaneous keys, thumbnail isolation, mode-change hold and pending-click cancellation");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
