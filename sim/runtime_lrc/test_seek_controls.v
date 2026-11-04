`timescale 1ns/1ps
module test_seek_controls;
 reg clk=0,rst_n=0,kp=1,kv=1;
 reg [3:0] sw=0;
 always #5 clk=~clk;
 wire back,fwd,mode,paused,vm,ns,prev,tr,tl,tc,tt,mn;
 wire [4:0] volume;
 wire [2:0] bright,contrast,bass,mid,treble;
 wire [3:0] edit;
 playback_controls #(.CLOCK_HZ(1000)) dut(clk,rst_n,1'b1,kp,kv,1'b0,sw[0],sw[3:1],
  ns,prev,tr,tl,tc,tt,mn,paused,volume,bright,contrast,vm,bass,mid,treble,edit,back,fwd,mode, , );
 integer backs=0,fwds=0,modes=0,views=0,backs_before_single;
 always @(posedge clk)begin
  if(back)backs=backs+1;if(fwd)fwds=fwds+1;
  if(mn)modes=modes+1;if(tt)views=views+1;
 end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task click3;begin kp=0;tick(30);kp=1;tick(30);end endtask
 task click4;begin kv=0;tick(30);kv=1;tick(30);end endtask
 initial begin
  tick(4);rst_n=1;tick(80);
  // Pause normally, then preserve pause and settings through seek mode.
  click3;tick(850);if(!paused)$fatal(1,"normal pause unavailable");
  sw=3;tick(80);if(!mode||vm||edit!=5)$fatal(1,"seek combination not isolated");
  click3;click4;tick(600);
  if(backs!=1||fwds!=1||!paused||volume!=16||bass!=2||mid!=2||treble!=2||modes||views)
   $fatal(1,"seek leaked pause, double click, volume or EQ");
  kp=0;tick(1500);kp=1;tick(600);
  if(backs<=2||fwds!=1||!paused)$fatal(1,"held seek did not auto-repeat or leaked long gesture");
  // A held key crossing a mode boundary must be released before rearming.
  kv=0;tick(5);sw=0;tick(100);kv=1;tick(600);
  if(fwds!=1||views||volume!=16)$fatal(1,"held key crossed switch boundary");
  // A pending normal double-click must not become a seek on entering.
  click4;sw=3;tick(700);
  if(fwds!=1||views)$fatal(1,"pending single crossed mode boundary");
  click4;if(fwds!=2)$fatal(1,"seek did not rearm");
  sw=1;tick(80);backs_before_single=backs;click3;
  if(volume!=15||backs!=backs_before_single||!paused)$fatal(1,"single SW1 mapping broken");
  sw=2;tick(80);click4;
  if(bass!=3||fwds!=2)$fatal(1,"single SW2 mapping broken");
  sw=7;tick(80);click4;
  if(mode||volume!=16)$fatal(1,"seek must match exact combination");
  $display("PASS seek controls: exact SW1+SW2, press-once, frozen pause, settings isolation, held/pending gesture boundaries and original single switches");$finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
