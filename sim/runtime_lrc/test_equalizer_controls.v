`timescale 1ns/1ps
module test_equalizer_controls;
 reg clk=0,rst_n=0,kp=1,kv=1;
 reg [3:0] sw=0;
 wire ns,prev,tr,tl,tc,tt,mn,paused,vm;
 wire [4:0] volume;
 wire [2:0] bright,contrast,bass,mid,treble;
 wire [3:0] edit;
 always #5 clk=~clk;
 wire [1:0] lyric_alpha;wire [2:0] lyric_position;
 playback_controls #(.CLOCK_HZ(1000)) dut(
 .clk(clk),.rst_n(rst_n),.key_next_n(1'b1),.key_pause_n(kp),.key_view_n(kv),.thumbnail(1'b0),
 .volume_switch(sw[0]),.eq_switches(sw[3:1]),.next_song(ns),.previous_song(prev),
 .thumb_right(tr),.thumb_left(tl),.thumb_confirm(tc),.thumb_toggle(tt),.mode_next(mn),
 .paused(paused),.volume(volume),.brightness(bright),.contrast(contrast),.volume_mode(vm),
 .bass(bass),.mid(mid),.treble(treble),.edit_target(edit),.seek_backward(),.seek_forward(),
 .seek_mode(),.transition_pref(),.clean_mode(),.lyric_alpha(lyric_alpha),.lyric_position(lyric_position));
 integer i,modes=0,views=0;
 always @(posedge clk)begin if(mn)modes=modes+1;if(tt)views=views+1;end
 task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
 task select_switch;input [3:0] value;begin sw=value;tick(80);end endtask
 task down;begin kp=0;tick(30);kp=1;tick(30);end endtask
 task up;begin kv=0;tick(30);kv=1;tick(30);end endtask
 initial begin
  tick(4);rst_n=1;tick(80);
  if(bass!=2||mid!=2||treble!=2)$fatal(1,"EQ must reset neutral");
  select_switch(2);if(edit!=2||vm)$fatal(1,"SW2 bass selection");
  up();up();up();if(bass!=4||mid!=2||treble!=2||volume!=16)$fatal(1,"bass upper clamp/isolation");
  for(i=0;i<6;i=i+1)down();if(bass!=0)$fatal(1,"bass lower clamp");
  select_switch(4);down();if(mid!=1||bass!=0||treble!=2)$fatal(1,"SW3 mid isolation");
  select_switch(8);up();if(treble!=3||mid!=1)$fatal(1,"SW4 treble isolation");
  select_switch(15);down();if(edit!=1||volume!=15||bass!=0||mid!=1||treble!=3)$fatal(1,"SW1 priority");
  select_switch(14);up();if(edit!=10||lyric_position!=7||bass!=0||mid!=1||treble!=3)$fatal(1,"new position combo must preserve EQ");
  select_switch(12);up();if(edit!=9||lyric_alpha!=2||mid!=1||treble!=3)$fatal(1,"new alpha combo must preserve EQ");
  // Hold a key across a change of the selected band.
  kp=0;tick(30);sw=8;tick(80);kp=1;tick(650);
  if(mid!=1||treble!=3||paused||modes||views)$fatal(1,"held key leaked into next target");
  select_switch(0);down();tick(850);if(!paused)$fatal(1,"normal pause not restored");
  select_switch(8);up();if(!paused||treble!=4)$fatal(1,"editing EQ changed pause state");
  $display("PASS EQ switches: neutral reset, per-band adjustment/clamps, four-switch volume priority, new lyric combo isolation, held-key isolation and normal controls restoration");
  $finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
